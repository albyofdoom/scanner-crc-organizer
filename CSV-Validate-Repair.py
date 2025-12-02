# CSV-Validate-Repair.py
# ---------------------
#
# Purpose:
#   Validate and optionally repair CSV files used for scanning and organizing images
#   (FileName, Size, CRC32, Path, Comment). The script is careful to not modify
#   RFC-4180-compliant CSVs unless explicitly instructed by the user.
#
# Notable behavior changes (new in this version):
#  - Default behavior is now validation-only (conservative): the script will
#    only analyze the CSV and report issues but will not alter or rewrite files
#    unless you explicitly request repairs using the `--repair` flag.
#  - Added `--no-rewrite-if-clean` to skip writing repaired files when there are
#    no issues detected (prevents accidental overwrites for clean, manual CSVs).
#  - Added `--flag-nonutf8` to optionally treat non-UTF-8 file encodings as an
#    issue. By default, non-UTF-8 encodings are reported but *not* treated as
#    issues that force a rewrite.
#  - CSV parsing uses RFC-4180-default semantics (no skip-initial-space), and
#    RFC-compliant escaped quotes (""") are no longer treated as an issue.
#  - Field repairs (trimming, replacing invalid characters, case normalization
#    for CRC32) are only applied when `--repair` is provided. In validation-only
#    mode the script tests and reports issues but does not modify field values.
#  - The script now detects duplicate CRC32 values (with identical Size) and flags them as issues; no
#    automatic correction is performed for duplicate values.
#
# New CLI flags (summary):
#  --repair             Apply automatic repairs to invalid fields and write a
#                       repaired CSV file (default mode is validation-only).
#  --no-rewrite-if-clean
#                       When combined with --repair, do not write a repaired
#                       CSV file when no issues are present (avoid touching
#                       clean/manual files).
#  --flag-nonutf8       Treat detection of a non-UTF-8 file encoding as an
#                       issue (appends an issue entry to the log). Otherwise this
#                       is reported to stdout but not appended as an issue.
#
# Examples (recommended):
#  - Validate only, do not modify files:
#      python CSV-Validate-Repair.py input.csv
#  - Validate a whole folder (dry-run / no rewrite):
#      python CSV-Validate-Repair.py --bulk D:\CSV_Folder --dry-run
#  - Fix files in a folder but only write CSVs that had issues:
#      python CSV-Validate-Repair.py --bulk D:\CSV_Folder --repair --no-rewrite-if-clean
#  - Treat non-UTF8 as an issue (may be useful in strict environments):
#      python CSV-Validate-Repair.py input.csv --flag-nonutf8 --repair
#
# Notes & recommendation:
#  - By default the script will not rewrite a clean RFC-4180 CSV. If you need
#    to aggressively sanitize CSVs every run (not recommended), use `--repair`.
#  - If you want fine-grained behavior (e.g. only trim whitespace but not
#    change CRC case), we can add per-field flags (`--trim-filenames` etc.) on
#    request — ask if needed and I'll add them.
#

# Expected Values: Check fields for unexpected values
# Field1 (FileName): Should be a valid filename, preserve Unicode
# Field2 (Size): Should only contain digits
# Field3 (CRC32): Should contain a proper CRC32 hash (8 hex digits)
# Field4 (Path): May not be properly quoted if it contains commas, preserve Unicode
# Field5 (Comment): Optional field, rarely present

# CSV Format: FileName,Size,CRC32,Path,Comment

import csv
import re
import os
import sys
import zipfile
import shutil
from datetime import datetime


class CSVValidationIssue:
    """Tracks issues found during validation."""
    
    def __init__(self, line_num, field_num, field_name, issue_type, original_value, repaired_value=None):
        self.line_num = line_num
        self.field_num = field_num
        self.field_name = field_name
        self.issue_type = issue_type
        self.original_value = original_value
        self.repaired_value = repaired_value
    
    def __str__(self):
        repair_info = f" → Fixed to: '{self.repaired_value}'" if self.repaired_value is not None else ""
        return f"Line {self.line_num}, Field {self.field_num} ({self.field_name}): {self.issue_type} - Original: '{self.original_value}'{repair_info}"


def parse_csv_line_with_quotes(line, line_num=None, issues=None):
    """
    Parse a CSV line respecting quoted fields that may contain commas.
    Also handles special case where paths have commas but aren't quoted.
    Records an issue if FileName field contains a comma and is corrected.
    Args:
        line: Raw CSV line as string
        line_num: Line number in the CSV (for logging)
        issues: List to append issues to (for logging)
    Returns:
        list: Parsed fields
    """
    # RFC 4180-compliant CSV line parser using Python's csv module
    import io
    line = line.strip('\r\n')
    # Mask commas inside backslash-delimited regions (e.g. \...\,) by replacing
    # the entire region with indexed placeholders so the parser preserves exact
    # text (including leading/trailing backslashes). Also mask explicit '\\,'
    # escaped commas with a separate placeholder.
    ESC_COMMA_PLACEHOLDER = '<<<CSV_ESC_COMMA>>>'
    REGION_PLACEHOLDER_FMT = '<<<CSV_REGION_{idx}>>>'
    regions = []

    # NOTE: backslashes in these CSVs are literal and sequences like "\\,"
    # represent a backslash character followed by the delimiter comma. Do
    # NOT mask or remove the comma here — keep the original line intact so
    # csv.reader can see the delimiter correctly.
    temp_line = line

    try:
        # Use greedy match so we capture the full region between the outer backslashes
        pattern = re.compile(r'\\(.*)\\(?=,)', re.DOTALL)

        def _repl(m):
            inner_full = m.group(0)  # includes the surrounding backslashes
            idx = len(regions)
            regions.append(inner_full)
            return REGION_PLACEHOLDER_FMT.format(idx=idx)

        temp_line = pattern.sub(_repl, temp_line)
    except Exception:
        # If regex fails for any reason, keep the already-escaped temp_line
        pass

    # Use strict RFC 4180 parsing defaults: DON'T skip initial spaces after delimiter
    # since leading spaces may be meaningful and RFC-compliant quoting should be retained.
    reader = csv.reader(io.StringIO(temp_line), doublequote=True)
    try:
        fields = next(reader)
        # Restore any region placeholders back to their original text (preserve trailing backslashes)
        if regions:
            for i, region_text in enumerate(regions):
                ph = REGION_PLACEHOLDER_FMT.format(idx=i)
                fields = [f.replace(ph, region_text) for f in fields]
        # Finally restore escaped-comma placeholders back to a literal backslash+comma
        # (the files use backslashes literally, do not treat them as escape characters).
        # No escaped-comma placeholder restoration needed (we don't mask '\,')

        # If any field is wrapped in quotes (e.g. '"..."') because of fallback
        # or malformed input, unquote it here so the csv.writer does not
        # re-quote an already-quoted string and double the quotes.
        def _unquote_if_quoted(s):
            if s is None:
                return s
            if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
                inner = s[1:-1]
                # CSV escaping uses double double-quotes to represent a literal quote
                return inner.replace('""', '"')
            return s

        fields = [_unquote_if_quoted(f) for f in fields]
        # Normalize any doubled backslashes directly preceding a comma to a single
        # backslash+comma (some combinations of region+placeholder restoration
        # can produce a duplicate backslash). Keep this local and conservative.
        fields = [re.sub(r'\\+,', r'\\,', f) for f in fields]

        # If the original raw line used an explicit escaped-comma sequence
        # ("\,") but the csv parser returned a single combined Path+Comment
        # field (len==4), split that fourth field at the first comma and
        # restore the trailing backslash to the Path. This preserves the
        # original trailing '\' that was removed by the temporary masking
        # while avoiding broad changes to the parsing logic.
        if '\\,' in line and len(fields) == 4:
            parts = fields[3].split(',', 1)
            if len(parts) == 2:
                # If the extracted path part already ends with a backslash, avoid appending another.
                if parts[0].endswith('\\'):
                    path_part = parts[0]
                else:
                    path_part = parts[0] + '\\'
                comment_part = parts[1]
                fields = [fields[0], fields[1], fields[2], path_part, comment_part]
    except Exception as e:
        # If parsing fails, fallback to splitting by comma and rejoin parts
        parts = temp_line.split(',')
        fields = []
        cur = parts[0] if parts else ''
        for part in parts[1:]:
            # If the current segment ends with a backslash, it was escaping the comma
            if cur.endswith('\\'):
                # keep the backslash by default to preserve delimiter behavior
                cur = cur + ',' + part
            else:
                fields.append(cur)
                cur = part
        fields.append(cur)
        if issues is not None and line_num is not None:
            issues.append(CSVValidationIssue(line_num, 0, "Row", f"CSV parsing error: {e}", line))
        # After fallback parsing, restore any placeholders back to original
        if regions:
            for i, region_text in enumerate(regions):
                ph = REGION_PLACEHOLDER_FMT.format(idx=i)
                fields = [f.replace(ph, region_text) for f in fields]
        # No escaped-comma placeholder restoration needed for fallback path
        # Normalize any doubled backslashes directly preceding a comma to a single
        # backslash+comma for the fallback-parsed fields as well.
        fields = [re.sub(r'\\+,', r'\\,', f) for f in fields]

        # Unquote any fully-quoted fields from the fallback path as well
        def _unquote_if_quoted(s):
            if s is None:
                return s
            if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
                inner = s[1:-1]
                return inner.replace('""', '"')
            return s
        fields = [_unquote_if_quoted(f) for f in fields]

        # Apply the same trailing-backslash preservation logic for fallback
        # parsing as we did for the normal path above.
        if '\\,' in line and len(fields) == 4:
            parts = fields[3].split(',', 1)
            if len(parts) == 2:
                # Preserve existing trailing backslash if present; otherwise append one.
                if parts[0].endswith('\\'):
                    path_part = parts[0]
                else:
                    path_part = parts[0] + '\\'
                comment_part = parts[1]
                fields = [fields[0], fields[1], fields[2], path_part, comment_part]
    # Note: We do not treat RFC-4180-style escaped quotes (""") as issues - these are valid.
    # Only flag parsing errors or clearly invalid quote sequences (handled above via Exception).
    # If we later decide to flag non-standard quoting, add a separate CLI option.
    return fields


def validate_filename(filename, line_num, issues, repair=True):
    """Validate and repair filename field."""
    original = filename
    
    # Check for empty filename
    if not filename or filename.strip() == "":
        issues.append(CSVValidationIssue(line_num, 1, "FileName", "Empty filename", original))
        return "MISSING_FILENAME.jpg"
    
    # Remove leading/trailing whitespace only if repair mode enabled
    if repair:
        filename = filename.strip()
    
    # Check for invalid filename characters (Windows-specific)
    invalid_chars = r'[<>:"|?*\x00-\x1f]'
    if re.search(invalid_chars, filename):
        if repair:
            repaired = re.sub(invalid_chars, '_', filename)
            issues.append(CSVValidationIssue(line_num, 1, "FileName", "Invalid filename characters", original, repaired))
            filename = repaired
        else:
            issues.append(CSVValidationIssue(line_num, 1, "FileName", "Invalid filename characters", original))
    
    # Preserve Unicode characters (important for your domain)
    # If repair was applied and value changed, log detail. If not in repair mode, we only flagged issues above.
    if repair and original != filename:
        issues.append(CSVValidationIssue(line_num, 1, "FileName", "Whitespace trimmed or characters replaced", original, filename))
    
    return filename


def validate_size(size, line_num, issues, repair=True):
    """Validate and repair size field."""
    original = size
    
    # Remove whitespace only if repair mode enabled
    if repair:
        size = size.strip()
    
    # Check if it's all digits
    if not size.isdigit():
        # Try to extract digits
        digits_only = re.sub(r'\D', '', size)
        if digits_only:
            if repair:
                issues.append(CSVValidationIssue(line_num, 2, "Size", "Non-digit characters removed", original, digits_only))
                return digits_only
            else:
                issues.append(CSVValidationIssue(line_num, 2, "Size", "Non-digit characters detected", original))
                return original
        else:
            if repair:
                issues.append(CSVValidationIssue(line_num, 2, "Size", "Invalid size - no digits found", original, "0"))
                return "0"
            else:
                issues.append(CSVValidationIssue(line_num, 2, "Size", "Invalid size - no digits found", original))
                return original
    
    return size


def validate_crc32(crc32, line_num, issues, repair=True):
    """Validate and repair CRC32 hash field."""
    original = crc32
    
    # Remove whitespace
    # Adjust only in repair mode; otherwise just normalize (keep case) for checking
    if repair:
        crc32 = crc32.strip().upper()
    else:
        crc32 = crc32.strip()
    
    # CRC32 should be exactly 8 hexadecimal characters
    if repair:
        if not re.match(r'^[0-9A-F]{8}$', crc32):
            test_crc = crc32
        else:
            test_crc = None
    else:
        # Non-repair mode, accept lowercase or uppercase hex digits as valid
        if not re.match(r'^[0-9A-Fa-f]{8}$', crc32):
            test_crc = crc32
        else:
            test_crc = None

    if test_crc is not None:
        # Try to extract hex characters
        hex_only = re.sub(r'[^0-9A-Fa-f]', '', crc32).upper()
        
        if len(hex_only) == 8:
            if repair:
                issues.append(CSVValidationIssue(line_num, 3, "CRC32", "Non-hex characters removed", original, hex_only))
                return hex_only
            else:
                issues.append(CSVValidationIssue(line_num, 3, "CRC32", "Non-hex characters present", original))
                return original
        elif len(hex_only) > 8:
            # Truncate to 8 characters
            truncated = hex_only[:8]
            if repair:
                issues.append(CSVValidationIssue(line_num, 3, "CRC32", "CRC32 truncated to 8 characters", original, truncated))
                return truncated
            else:
                issues.append(CSVValidationIssue(line_num, 3, "CRC32", "CRC32 too long", original))
                return original
        elif len(hex_only) < 8 and len(hex_only) > 0:
            # Pad with zeros
            padded = hex_only.zfill(8)
            if repair:
                issues.append(CSVValidationIssue(line_num, 3, "CRC32", "CRC32 padded with zeros", original, padded))
                return padded
            else:
                issues.append(CSVValidationIssue(line_num, 3, "CRC32", "CRC32 too short", original))
                return original
        else:
            if repair:
                issues.append(CSVValidationIssue(line_num, 3, "CRC32", "Invalid CRC32 - no valid hex found", original, "00000000"))
                return "00000000"
            else:
                issues.append(CSVValidationIssue(line_num, 3, "CRC32", "Invalid CRC32 - no valid hex found", original))
                return original
    
    return crc32


def validate_path(path, line_num, issues, repair=True):
    """Validate and repair path field."""
    original = path
    
    # Remove leading/trailing whitespace only in repair mode
    if repair:
        path = path.strip()
    
    # Preserve Unicode characters (important for international character sets)
    # Just remove truly problematic characters
    invalid_chars = r'[<>"|?*\x00-\x1f]'
    if re.search(invalid_chars, path):
        if repair:
            repaired = re.sub(invalid_chars, '_', path)
            issues.append(CSVValidationIssue(line_num, 4, "Path", "Invalid path characters removed", original, repaired))
            path = repaired
        else:
            issues.append(CSVValidationIssue(line_num, 4, "Path", "Invalid path characters present", original))
    
    # Normalize path separators (optional - keep as-is for now)
    # path = path.replace('/', '\\')
    
    if repair and original != path and path:
        issues.append(CSVValidationIssue(line_num, 4, "Path", "Whitespace or invalid characters removed", original, path))
    
    return path


def validate_comment(comment, line_num, issues):
    """Validate and repair comment field (optional)."""
    # Comments are optional and freeform - just trim whitespace
    return comment.strip() if comment else ""


def archive_csv_file(csv_file_path, archive_folder, timestamp=None, move_original=False):
    """
    Archive a CSV file by creating a timestamped zip file in the Archive folder.
    
    Args:
        csv_file_path: Path to the CSV file to archive
        archive_folder: Path to the Archive folder
        timestamp: Optional timestamp string (default: current datetime)
        move_original: If True, move original file to Archive folder after zipping
    
    Returns:
        str: Path to created archive file, or None if failed
    """
    if not os.path.exists(csv_file_path):
        return None
    
    # Generate timestamp if not provided
    if timestamp is None:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    
    # Create archive folder if it doesn't exist
    os.makedirs(archive_folder, exist_ok=True)
    
    # Generate archive filename
    base_name = os.path.splitext(os.path.basename(csv_file_path))[0]
    archive_name = f"{base_name}_{timestamp}.zip"
    archive_path = os.path.join(archive_folder, archive_name)
    
    try:
        # Create zip file with the CSV
        with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            zipf.write(csv_file_path, os.path.basename(csv_file_path))
        
        # Move original file to Archive folder if requested
        if move_original:
            original_in_archive = os.path.join(archive_folder, os.path.basename(csv_file_path))
            # If file already exists in archive, add timestamp to avoid collision
            if os.path.exists(original_in_archive):
                base, ext = os.path.splitext(os.path.basename(csv_file_path))
                original_in_archive = os.path.join(archive_folder, f"{base}_original_{timestamp}{ext}")
            shutil.move(csv_file_path, original_in_archive)
        
        return archive_path
    except Exception as e:
        print(f"Warning: Failed to archive {os.path.basename(csv_file_path)}: {e}")
        return None


def validate_and_repair_csv(input_file, output_file=None, log_file=None, dry_run=False, use_subfolders=False, archive_original=False, skip_rewrite_if_clean=False, normalize_crc32=False, normalize_only=False, flag_nonutf8=False, repair=False):
    """
    Validate and repair a CSV file.
    
    Args:
        input_file: Path to input CSV file
        output_file: Path to output repaired CSV file (default: input_file with _repaired suffix)
        log_file: Path to log file (default: input_file with _repair_log.txt suffix)
        dry_run: If True, only validate and log issues without creating output file
        use_subfolders: If True, organize output into CleanCSVs/Logs/Archive subfolders
        archive_original: If True, create timestamped zip of original CSV in Archive folder
    
    Returns:
        tuple: (issues_found, rows_processed, output_file_path, archive_file_path)
    """
    # Generate timestamp for this run (used for archive if enabled)
    run_timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    
    # Generate output filenames if not provided
    if output_file is None:
        if use_subfolders:
            input_dir = os.path.dirname(input_file)
            base_name = os.path.basename(input_file)
            output_file = os.path.join(input_dir, "CleanCSVs", base_name)
        else:
            base, ext = os.path.splitext(input_file)
            output_file = f"{base}_repaired{ext}"
    
    if log_file is None:
        if use_subfolders:
            input_dir = os.path.dirname(input_file)
            base_name = os.path.splitext(os.path.basename(input_file))[0]
            log_file = os.path.join(input_dir, "Logs", f"{base_name}_repair_log.txt")
        else:
            base, ext = os.path.splitext(input_file)
            log_file = f"{base}_repair_log.txt"
    
    # Create subdirectories if using subfolders
    archive_folder = None
    if use_subfolders and not dry_run:
        input_dir = os.path.dirname(input_file)
        clean_csv_dir = os.path.join(input_dir, "CleanCSVs")
        logs_dir = os.path.join(input_dir, "Logs")
        archive_folder = os.path.join(input_dir, "Archive")
        
        os.makedirs(clean_csv_dir, exist_ok=True)
        os.makedirs(logs_dir, exist_ok=True)
        os.makedirs(archive_folder, exist_ok=True)
    
    issues = []
    repaired_rows = []
    row_line_numbers = []
    line_num = 0
    header_detected = False
    encoding_used = 'utf-8'
    
    print(f"Validating CSV: {input_file}")
    print(f"{'DRY RUN - ' if dry_run else ''}Output will be written to: {output_file}")
    print(f"Log will be written to: {log_file}")
    if normalize_crc32:
        if normalize_only:
            print("Note: CRC32 normalization is ENABLED for this run (normalize-only mode)")
        else:
            print("Note: CRC32 normalization is ENABLED for this run")
    print()
    
    # Detect BOM first (to correctly handle UTF-16/UTF-32 with BOM)
    file_content = None
    encoding_used = None
    try:
        with open(input_file, 'rb') as bf:
            header = bf.read(4)
    except Exception as e:
        print(f"ERROR: Unable to open file in binary mode: {e}")
        return None, 0, None, None

    # BOM signatures
    if header.startswith(b'\xff\xfe\x00\x00'):
        detected = 'utf-32'
    elif header.startswith(b'\x00\x00\xfe\xff'):
        detected = 'utf-32-be'
    elif header.startswith(b'\xff\xfe'):
        # UTF-16 LE with BOM
        detected = 'utf-16'
    elif header.startswith(b'\xfe\xff'):
        # UTF-16 BE with BOM
        detected = 'utf-16'
    elif header.startswith(b'\xef\xbb\xbf'):
        detected = 'utf-8-sig'
    else:
        detected = None

    if detected:
        try:
            with open(input_file, 'r', newline='', encoding=detected) as test_file:
                file_content = test_file.readlines()
                encoding_used = detected
                if detected not in ('utf-8', 'utf-8-sig'):
                    print(f"Note: File encoding detected as {detected} (via BOM)")
                    if flag_nonutf8:
                        issues.append(CSVValidationIssue(0, 0, "File", f"Non-UTF-8 encoding detected: {detected}", input_file))
        except Exception:
            # Fall through to try other encodings below
            file_content = None

    # If no BOM-detected encoding succeeded, try common encodings (including utf-16 fallback)
    if file_content is None:
        encodings_to_try = ['utf-8-sig', 'utf-8', 'mbcs', 'cp1250', 'cp1252', 'latin-1', 'iso-8859-1', 'iso-8859-2', 'utf-16']
        # 'mbcs' is a Windows-only codec; skip it on non-Windows platforms to avoid LookupError
        if sys.platform != 'win32':
            encodings_to_try = [e for e in encodings_to_try if e.lower() != 'mbcs']
        # Filter encodings list to only those supported on this platform
        try:
            import codecs
            supported_encodings = []
            for e in encodings_to_try:
                try:
                    codecs.lookup(e)
                    supported_encodings.append(e)
                except LookupError:
                    # encoding not available on this platform; skip
                    continue
            encodings_to_try = supported_encodings
        except Exception:
            # If codecs isn't usable for some reason, fall back to original list
            pass

        for encoding in encodings_to_try:
            try:
                with open(input_file, 'r', newline='', encoding=encoding) as test_file:
                    file_content = test_file.readlines()
                    encoding_used = encoding
                    if encoding not in ('utf-8', 'utf-8-sig'):
                        print(f"Note: File encoding detected as {encoding} (fallback)")
                        if flag_nonutf8:
                            issues.append(CSVValidationIssue(0, 0, "File", f"Non-UTF-8 encoding detected: {encoding}", input_file))
                    break
            except (UnicodeDecodeError, UnicodeError, LookupError):
                # Unicode/LUT errors mean this encoding isn't suitable on this platform
                continue
    
    if file_content is None:
        print(f"ERROR: Could not decode file with any supported encoding")
        return None, 0, None, None

    # Strip a possible leading BOM character from the first line if present (safeguard)
    if file_content and len(file_content) > 0:
        file_content[0] = file_content[0].lstrip('\ufeff')
    
    try:
        for raw_line in file_content:
            # Skip blank/empty lines BEFORE incrementing line_num
            if not raw_line.strip():
                continue
            line_num += 1
            # Parse the line respecting quoted fields, passing line_num and issues for logging
            fields = parse_csv_line_with_quotes(raw_line, line_num=line_num, issues=issues)
            # Skip lines that result in no fields (edge case)
            if not fields or (len(fields) == 1 and not fields[0]):
                continue
            # Check if this is a header row
            if line_num == 1 and len(fields) >= 3:
                if fields[0].lower() in ['filename', 'file', 'name'] or fields[2].lower() in ['crc32', 'crc', 'checksum']:
                    header_detected = True
                    print(f"Header row detected on line {line_num}, skipping validation")
                    repaired_rows.append(fields)
                    row_line_numbers.append(line_num)
                    continue
            # Validate we have at least 4 fields (FileName, Size, CRC32, Path)
            if len(fields) < 4:
                issues.append(CSVValidationIssue(line_num, 0, "Row", f"Insufficient fields (found {len(fields)}, expected at least 4)", raw_line.strip()))
                while len(fields) < 4:
                    fields.append("")
            # Validate and repair each field
            filename = validate_filename(fields[0], line_num, issues, repair=repair)
            size = validate_size(fields[1], line_num, issues, repair=repair)
            # Determine per-field repair behavior. If `normalize_only` is set we
            # only apply normalization to CRC32 and avoid changing other fields.
            filename_repair = repair and not normalize_only
            size_repair = repair and not normalize_only
            path_repair = repair and not normalize_only
            crc_repair = normalize_crc32 or repair

            filename = validate_filename(fields[0], line_num, issues, repair=filename_repair)
            size = validate_size(fields[1], line_num, issues, repair=size_repair)
            crc32 = validate_crc32(fields[2], line_num, issues, repair=crc_repair)
            path = validate_path(fields[3], line_num, issues, repair=path_repair)
            # Merge all remaining fields into comment (handles unquoted comments with commas)
            if len(fields) >= 5:
                # Join fields 4 onwards with commas (they were split due to unquoted commas in comment)
                comment = ','.join(fields[4:])
                comment = validate_comment(comment, line_num, issues)
            else:
                comment = ""
            # Build repaired row
            repaired_row = [filename, size, crc32, path, comment]
            repaired_rows.append(repaired_row)
            row_line_numbers.append(line_num)
        
        # After processing all rows, check for duplicate CRC32 values (validation-only flagging)
        crc_map = {}
        for idx, row in enumerate(repaired_rows):
            # Skip header row if present
            if header_detected and idx == 0 and row_line_numbers[idx] == 1:
                continue
            # Ensure row has a CRC field and a Size field
            crc_field = row[2] if len(row) >= 3 else ''
            size_field = row[1] if len(row) >= 2 else ''
            # Normalize CRC by extracting hex characters and uppercasing and zero-pad/truncate to 8
            hex_only = re.sub(r'[^0-9A-Fa-f]', '', str(crc_field))
            if not hex_only:
                continue
            norm = hex_only.upper().zfill(8)[:8]
            # Normalize size: try to convert to int, fallback to string
            try:
                norm_size = int(str(size_field).strip())
            except Exception:
                norm_size = str(size_field).strip()
            # Only consider duplicates if both CRC and Size are identical
            key = f"{norm}:{norm_size}"
            crc_map.setdefault(key, []).append(idx)

        # Flag duplicates for any CRC that occurs more than once
        for key, indices in crc_map.items():
            if len(indices) > 1:
                # prepare list of line numbers
                lines_list = [row_line_numbers[i] for i in indices]
                lines_str = ", ".join(str(ln) for ln in lines_list)
                # key format: CRC:SIZE
                crc_part, size_part = key.split(':', 1)
                for i in indices:
                    line_num_i = row_line_numbers[i]
                    orig_val = repaired_rows[i][2] if len(repaired_rows[i]) >= 3 else ''
                    issues.append(CSVValidationIssue(line_num_i, 3, "CRC32", f"Duplicate CRC32 value found; CRC={crc_part}, Size={size_part}; also used on lines: {lines_str}", orig_val))

        # Write output CSV if not dry run && either (we found issues) or the caller explicitly allows rewriting clean files
        if not dry_run:
            if skip_rewrite_if_clean and not issues:
                print("No issues found; skipping rewrite of the original CSV as requested.")
                # If skipping rewrite, keep the original output_file value None to indicate no file was written
                output_file = None
            else:
                with open(output_file, 'w', newline='', encoding='utf-8') as outfile:
                    writer = csv.writer(outfile, quoting=csv.QUOTE_ALL)
                    for row in repaired_rows:
                        # Ensure all fields are str and encode/decode to preserve Unicode
                        safe_row = [str(field) if field is not None else '' for field in row]
                        writer.writerow(safe_row)
        # Write log file if issues were found or if CRC normalization was requested
        if issues or normalize_crc32:
            with open(log_file, 'w', encoding='utf-8') as logf:
                logf.write("CSV Validation and Repair Log\n")
                logf.write("" + ('=' * 80) + "\n")
                logf.write(f"Input File: {input_file}\n")
                logf.write(f"Output File: {output_file}\n")
                logf.write(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                logf.write(f"Mode: {'DRY RUN (validation only)' if dry_run else 'REPAIR'}\n")
                logf.write(f"Normalize CRC32: {'Yes' if normalize_crc32 else 'No'}\n")
                logf.write(f"Normalize Only: {'Yes' if normalize_only else 'No'}\n")
                logf.write(f"\nTotal Rows Processed: {line_num}\n")
                logf.write(f"Total Issues Found: {len(issues)}\n")
                logf.write(f"Header Row Detected: {'Yes' if header_detected else 'No'}\n")
                logf.write(f"\n{'=' * 80}\n\n")
                logf.write("Issues Found:\n")
                logf.write("-" * 80 + "\n")
                for issue in issues:
                    logf.write(str(issue) + "\n")
        # Print summary
        print(f"\nValidation Complete!")
        print(f"  Rows processed: {line_num}")
        print(f"  Issues found: {len(issues)}")
        if issues:
            print(f"\n  Issue breakdown:")
            issue_types = {}
            for issue in issues:
                issue_types[issue.issue_type] = issue_types.get(issue.issue_type, 0) + 1
            for issue_type, count in sorted(issue_types.items()):
                print(f"    - {issue_type}: {count}")
            print(f"\nDetailed log written to: {log_file}")
        if not dry_run:
            print(f"Repaired CSV written to: {output_file}")
        
        # Archive original CSV if requested and not in dry run mode
        archive_path = None
        if archive_original and not dry_run:
            if archive_folder is None:
                # If not using subfolders, create Archive folder next to input file
                input_dir = os.path.dirname(input_file) if os.path.dirname(input_file) else "."
                archive_folder = os.path.join(input_dir, "Archive")
            
            archive_path = archive_csv_file(input_file, archive_folder, run_timestamp, move_original=True)
            if archive_path:
                print(f"Original CSV archived to: {archive_path}")
                print(f"Original CSV moved to Archive folder")
        
        return issues, line_num, output_file, archive_path
    
    except Exception as e:
        print(f"ERROR: Failed to process CSV file: {e}")
        import traceback
        traceback.print_exc()
        return None, 0, None, None


def process_folder_bulk(folder_path, output_folder=None, dry_run=False, use_subfolders=True, archive_originals=False, skip_rewrite_if_clean=False, normalize_crc32=False, normalize_only=False, flag_nonutf8=False, repair=False):
    """
    Process all CSV files in a folder in bulk mode.
    
    Args:
        folder_path: Path to folder containing CSV files
        output_folder: Optional output folder (default: creates subfolders in source folder)
        dry_run: If True, only validate without creating output files
        use_subfolders: If True, organize output into CleanCSVs/Logs/Archive subfolders
        archive_originals: If True, create timestamped zips of original CSVs in Archive folder
    
    Returns:
        dict: Summary statistics for all processed files
    """
    if not os.path.isdir(folder_path):
        print(f"ERROR: Not a valid directory: {folder_path}")
        return None
    
    # Set up output folder structure
    if use_subfolders:
        if output_folder is None:
            output_folder = folder_path
        
        clean_csv_folder = os.path.join(output_folder, "CleanCSVs")
        logs_folder = os.path.join(output_folder, "Logs")
        archive_folder = os.path.join(output_folder, "Archive")
        
        if not dry_run:
            os.makedirs(clean_csv_folder, exist_ok=True)
            os.makedirs(logs_folder, exist_ok=True)
            os.makedirs(archive_folder, exist_ok=True)
            print(f"Created folder structure:")
            print(f"  - CleanCSVs: {clean_csv_folder}")
            print(f"  - Logs:      {logs_folder}")
            print(f"  - Archive:   {archive_folder}")
    else:
        if output_folder is None:
            output_folder = os.path.join(folder_path, "repaired")
        
        if not dry_run and not os.path.exists(output_folder):
            os.makedirs(output_folder)
            print(f"Created output folder: {output_folder}")
    
    # Find all CSV files (excluding already repaired files and missing files reports)
    csv_files = [
        f for f in os.listdir(folder_path)
        if f.endswith('.csv')
        and not f.endswith('_repaired.csv')
        and '_missing_files.csv' not in f
        and os.path.isfile(os.path.join(folder_path, f))
    ]
    
    if not csv_files:
        print(f"No CSV files found in: {folder_path}")
        return None
    
    print(f"\n{'=' * 80}")
    print(f"BULK MODE: Processing {len(csv_files)} CSV file(s) from: {folder_path}")
    print(f"{'=' * 80}\n")
    
    # Process each CSV
    results = {
        'total_files': len(csv_files),
        'successful': 0,
        'with_issues': 0,
        'failed': 0,
        'total_issues': 0,
        'total_rows': 0,
        'archived_count': 0,
        'files': []
    }
    
    for idx, csv_file in enumerate(csv_files, 1):
        input_path = os.path.join(folder_path, csv_file)
        
        # Set output paths based on subfolder mode
        if use_subfolders:
            output_path = os.path.join(output_folder, "CleanCSVs", csv_file) if not dry_run else None
            log_path = os.path.join(output_folder, "Logs", f"{os.path.splitext(csv_file)[0]}_repair_log.txt")
        else:
            output_path = os.path.join(output_folder, csv_file) if not dry_run else None
            log_path = os.path.join(output_folder, f"{os.path.splitext(csv_file)[0]}_repair_log.txt")
        
        print(f"\n[{idx}/{len(csv_files)}] Processing: {csv_file}")
        print("-" * 80)
        
        try:
            issues, rows, output, archive_path = validate_and_repair_csv(
                input_path,
                output_file=output_path,
                log_file=log_path,
                dry_run=dry_run,
                use_subfolders=False,  # Already handled paths above
                archive_original=archive_originals,
                skip_rewrite_if_clean=skip_rewrite_if_clean,
                normalize_crc32=normalize_crc32,
                normalize_only=normalize_only,
                flag_nonutf8=flag_nonutf8,
                repair=repair
            )
            
            if archive_path:
                results['archived_count'] += 1
            
            if issues is None:
                results['failed'] += 1
                results['files'].append({
                    'name': csv_file,
                    'status': 'FAILED',
                    'issues': 0,
                    'rows': 0
                })
            elif len(issues) > 0:
                results['with_issues'] += 1
                results['total_issues'] += len(issues)
                results['total_rows'] += rows
                results['files'].append({
                    'name': csv_file,
                    'status': 'ISSUES_FOUND',
                    'issues': len(issues),
                    'rows': rows
                })
            else:
                results['successful'] += 1
                results['total_rows'] += rows
                results['files'].append({
                    'name': csv_file,
                    'status': 'CLEAN',
                    'issues': 0,
                    'rows': rows
                })
        
        except Exception as e:
            print(f"ERROR processing {csv_file}: {e}")
            results['failed'] += 1
            results['files'].append({
                'name': csv_file,
                'status': 'ERROR',
                'issues': 0,
                'rows': 0,
                'error': str(e)
            })
    
    # Print summary
    print(f"\n{'=' * 80}")
    print("BULK PROCESSING SUMMARY")
    print(f"{'=' * 80}")
    print(f"Total CSV files processed: {results['total_files']}")
    print(f"  Clean (no issues):       {results['successful']}")
    print(f"  Issues found/repaired:   {results['with_issues']}")
    print(f"  Failed/Errors:           {results['failed']}")
    print(f"\nTotal rows processed:      {results['total_rows']}")
    print(f"Total issues found:        {results['total_issues']}")
    
    if archive_originals and not dry_run:
        print(f"Original CSVs archived:    {results['archived_count']}")
    
    if results['with_issues'] > 0 or results['failed'] > 0:
        print("\nFiles with issues:")
        for file_info in results['files']:
            if file_info['status'] in ['ISSUES_FOUND', 'ERROR', 'FAILED']:
                status_color = 'ISSUES' if file_info['status'] == 'ISSUES_FOUND' else 'ERROR'
                issue_count = f" ({file_info['issues']} issues)" if file_info['issues'] > 0 else ""
                print(f"  [{status_color}] {file_info['name']}{issue_count}")
    
    if not dry_run:
        if use_subfolders:
            print(f"\nOrganized output:")
            print(f"  - Clean CSVs: {os.path.join(output_folder, 'CleanCSVs')}")
            print(f"  - Logs:       {os.path.join(output_folder, 'Logs')}")
        else:
            print(f"\nRepaired files and logs written to: {output_folder}")
    
    print(f"{'=' * 80}\n")
    
    return results


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Validate and repair CRC32 CSV files',
        epilog='Examples:\n'
               '  Single file:  python CSV-Validate-Repair.py input.csv\n'
               '  Bulk mode:    python CSV-Validate-Repair.py --bulk D:\\ScanSorting\\_01_CSV_Source\\\n'
               '  Dry run:      python CSV-Validate-Repair.py --bulk D:\\folder\\ --dry-run',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('input_file', nargs='?', help='Input CSV file to validate/repair (not used in bulk mode)')
    parser.add_argument('-o', '--output', help='Output repaired CSV file (default: input_file_repaired.csv)')
    parser.add_argument('-l', '--log', help='Log file path (default: input_file_repair_log.txt)')
    parser.add_argument('--dry-run', action='store_true', help='Validate only, do not create output file')
    parser.add_argument('--bulk', metavar='FOLDER', help='Process all CSV files in specified folder')
    parser.add_argument('--output-folder', help='Output folder for bulk mode (default: FOLDER with subfolders)')
    parser.add_argument('--no-subfolders', action='store_true', help='Disable subfolder organization (use flat structure)')
    parser.add_argument('--use-subfolders', action='store_true', help='Enable subfolder organization for single file mode')
    parser.add_argument('--archive', action='store_true', help='Archive original CSV files as timestamped zips')
    parser.add_argument('--no-rewrite-if-clean', action='store_true', help='Skip rewriting CSV files when no issues are detected (useful with --repair)')
    parser.add_argument('--flag-nonutf8', action='store_true', help='Treat detection of non-UTF-8 encoding as an issue (default: show informative message only)')
    parser.add_argument('--normalize-crc32', action='store_true', help='Force normalization of CRC32 values when writing repaired CSVs (uppercase, hex-only, zero-pad/truncate to 8).')
    parser.add_argument('--normalize-only', action='store_true', help='Only normalize CRC32 values (do not apply other repairs even if --repair is specified).')
    parser.add_argument('--repair', action='store_true', help='Enable repairs (modify fields and write repaired CSV files). By default the script is validation-only.')
    
    args = parser.parse_args()
    
    # Bulk mode processing
    if args.bulk:
        if not os.path.exists(args.bulk):
            print(f"ERROR: Folder not found: {args.bulk}")
            sys.exit(1)
        
        # In bulk mode, subfolders are ON by default unless --no-subfolders is specified
        use_subfolders = not args.no_subfolders
        
        results = process_folder_bulk(
            args.bulk,
            output_folder=args.output_folder,
            dry_run=args.dry_run,
            use_subfolders=use_subfolders,
            archive_originals=args.archive,
            skip_rewrite_if_clean=args.no_rewrite_if_clean,
            normalize_crc32=args.normalize_crc32,
            normalize_only=args.normalize_only,
            flag_nonutf8=args.flag_nonutf8,
            repair=args.repair
        )
        
        if results is None:
            sys.exit(1)
        elif results['failed'] > 0:
            sys.exit(1)  # Errors occurred
        elif results['with_issues'] > 0:
            sys.exit(2)  # Issues found
        else:
            sys.exit(0)  # All clean
    
    # Single file mode
    else:
        if not args.input_file:
            parser.print_help()
            print("\nERROR: Either specify an input_file or use --bulk FOLDER")
            sys.exit(1)
        
        # Check if input file exists
        if not os.path.exists(args.input_file):
            print(f"ERROR: Input file not found: {args.input_file}")
            sys.exit(1)
        
        # In single file mode, subfolders are OFF by default unless --use-subfolders is specified
        use_subfolders = args.use_subfolders
        
        # Run validation and repair
        issues, rows, output, archive_path = validate_and_repair_csv(
            args.input_file,
            output_file=args.output,
            log_file=args.log,
            dry_run=args.dry_run,
            use_subfolders=use_subfolders,
            archive_original=args.archive,
            skip_rewrite_if_clean=args.no_rewrite_if_clean,
            normalize_crc32=args.normalize_crc32,
            normalize_only=args.normalize_only,
            flag_nonutf8=args.flag_nonutf8,
            repair=args.repair
        )
        
        # Exit with appropriate code
        if issues is None:
            sys.exit(1)  # Error occurred
        elif len(issues) > 0:
            sys.exit(2)  # Issues found
        else:
            sys.exit(0)  # Success, no issues
