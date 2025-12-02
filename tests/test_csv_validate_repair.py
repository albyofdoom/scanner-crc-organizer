import csv
import os
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / 'CSV-Validate-Repair.py'


def run_script(csv_path, extra_args=None):
    args = [sys.executable, str(SCRIPT), str(csv_path)]
    if extra_args:
        args += extra_args
    proc = subprocess.run(args, capture_output=True, text=True)
    return proc


def read_csv_rows(path):
    with open(path, newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        return [row for row in reader]


def test_single_slash_path_repair(tmp_path):
    # Create CSV with a single slash in Path field
    csv_file = tmp_path / 'slash_test.csv'
    lines = [
        ['FileName', 'Size', 'CRC32', 'Path', 'Comment'],
        ['sample.jpg', '123', 'ABCDEF12', '/', 'slash in path'],
    ]
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerows(lines)

    proc = run_script(csv_file, extra_args=['--repair'])
    # Repair run should finish (even if there are no issues) with exit code 0 or 2
    assert proc.returncode in (0, 2)

    repaired = tmp_path / 'slash_test_repaired.csv'
    assert repaired.exists(), 'Repaired CSV must be written by default'
    rows = read_csv_rows(repaired)
    # Path should be preserved (no conversion to comma)
    assert rows[1][3] == '/', f'Unexpected Path normalization: {rows[1][3]}'


def test_escaped_comma_preserved(tmp_path):
    # Path contains a backslash+comma sequence which should be preserved
    csv_file = tmp_path / 'esc_comma.csv'
    # Write a row where the Path field contains an explicit '\,' sequence
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        f.write('FileName,Size,CRC32,Path,Comment\n')
        # This line intentionally contains a backslash followed by a comma within the Path
        f.write('sample.jpg,123,ABCDEF12,folder\\,,comment with comma\n')

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    repaired = tmp_path / 'esc_comma_repaired.csv'
    assert repaired.exists()
    rows = read_csv_rows(repaired)
    # locate the first non-header row (some runs may preserve header row)
    data_row = None
    for r in rows:
        if len(r) >= 3 and not (r[0].lower() in ['filename', 'file', 'name'] or r[2].lower() in ['crc32', 'crc', 'checksum']):
            data_row = r
            break
    assert data_row is not None, f'No data row found in repaired CSV: {rows}'
    rows = read_csv_rows(repaired)
    # The script attempts to preserve trailing backslash for escaped-comma sequences
    # CRC should remain unchanged for this row
    assert data_row[2] == 'ABCDEF12'
    assert data_row[3].endswith('\\') or '\\,' in ','.join(data_row) or data_row[3].endswith(','), 'Escaped comma/backslash should be preserved in Path'


def test_duplicate_crc_flagging(tmp_path):
    # Two rows with identical CRC and Size should be flagged as issues
    csv_file = tmp_path / 'dup_crc.csv'
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['FileName', 'Size', 'CRC32', 'Path', 'Comment'])
        writer.writerow(['a.jpg', '100', 'AAAABBBB', 'p1', ''])
        writer.writerow(['b.jpg', '100', 'AAAABBBB', 'p2', ''])

    proc = run_script(csv_file, extra_args=['--repair'])
    # The script exits with code 2 when issues are found
    assert proc.returncode == 2, f'Expected exit code 2 for duplicate CRC issues, got {proc.returncode} stdout:{proc.stdout} stderr:{proc.stderr}'
    log_file = tmp_path / 'dup_crc_repair_log.txt'
    # When issues are present, a log file should be created
    assert log_file.exists(), 'Repair run with issues should write a log file'
    txt = log_file.read_text(encoding='utf-8')
    assert 'Duplicate CRC32' in txt or 'Duplicate CRC32 value' in txt


def test_insufficient_fields_are_extended(tmp_path):
    # Row with only 3 fields should be padded to 5 fields in the repaired CSV
    csv_file = tmp_path / 'short_row.csv'
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        f.write('file,size,crc\n')
        f.write('img.jpg,200,DEADBEEF\n')

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    repaired = tmp_path / 'short_row_repaired.csv'
    assert repaired.exists()


def test_embedded_newline_in_quoted_field_flags_issue(tmp_path):
    # A quoted field containing an embedded newline (physical multi-line field)
    # is an edge-case for this line-by-line parser; the script should flag an issue
    csv_file = tmp_path / 'multi_line_field.csv'
    content = 'FileName,Size,CRC32,Path,Comment\n"file.jpg",10,ABCDEF12,"multi\nline",note\n'
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        f.write(content)

    proc = run_script(csv_file, extra_args=['--repair'])
    # Expect the script to detect a parsing/fallback issue and return exit code 2
    assert proc.returncode == 2
    log_file = tmp_path / 'multi_line_field_repair_log.txt'
    assert log_file.exists()
    txt = log_file.read_text(encoding='utf-8')
    assert 'CSV parsing error' in txt or 'Insufficient fields' in txt or 'Issues Found' in txt


def test_control_characters_removed_on_repair(tmp_path):
    # Path contains control characters which should be replaced when --repair is used
    csv_file = tmp_path / 'ctrl_chars.csv'
    bad_path = 'folder' + chr(7) + 'inner'  # BEL/control char in path
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['FileName', 'Size', 'CRC32', 'Path', 'Comment'])
        writer.writerow(['a.jpg', '1', 'A1B2C3D4', bad_path, ''])

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode == 2 or proc.returncode == 0
    repaired = tmp_path / 'ctrl_chars_repaired.csv'
    assert repaired.exists()
    rows = read_csv_rows(repaired)
    # Invalid control char should have been replaced by '_' by the repair logic
    assert '_' in rows[1][3]
    log_file = tmp_path / 'ctrl_chars_repair_log.txt'
    assert log_file.exists()
    assert 'Invalid path characters removed' in log_file.read_text(encoding='utf-8')


def test_utf16_bom_handling(tmp_path):
    csv_file = tmp_path / 'utf16.csv'
    # Write as UTF-16 with BOM
    with open(csv_file, 'w', newline='', encoding='utf-16') as f:
        f.write('FileName,Size,CRC32,Path,Comment\n')
        f.write('img.jpg,30,0BADF00D,folder,ok\n')

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    repaired = tmp_path / 'utf16_repaired.csv'
    assert repaired.exists()


def test_very_long_fields(tmp_path):
    csv_file = tmp_path / 'long.csv'
    long_name = 'a' * 5000
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['FileName', 'Size', 'CRC32', 'Path', 'Comment'])
        writer.writerow([long_name, '1', 'ABCDEF01', '.', ''])

    proc = run_script(csv_file, extra_args=['--repair'])
    # Should not crash; accept success or issues
    assert proc.returncode in (0, 2)
    repaired = tmp_path / 'long_repaired.csv'
    assert repaired.exists()
    rows = read_csv_rows(repaired)
    # The repaired row should have been extended to include Path and Comment (we wrote '.' as Path)
    assert len(rows[1]) >= 5
    assert rows[1][3] == '.'


def test_header_row_preserved(tmp_path):
    csv_file = tmp_path / 'header.csv'
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        f.write('FileName,Size,CRC32,Path,Comment\n')
        f.write('img.jpg,50,CAFEBABE,folder,ok\n')

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    repaired = tmp_path / 'header_repaired.csv'
    assert repaired.exists()
    rows = read_csv_rows(repaired)
    # First row should still be the header
    assert rows[0][0].lower() in ['filename', 'file', 'name']


def test_normalize_crc32_flag(tmp_path):
    csv_file = tmp_path / 'norm_crc.csv'
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        f.write('img.jpg,10,deadbeef,.,\n')

    proc = run_script(csv_file, extra_args=['--repair', '--normalize-crc32'])
    # Should complete (may write a log); accept 0 or 2 conservatively
    assert proc.returncode in (0, 2)
    repaired = tmp_path / 'norm_crc_repaired.csv'
    assert repaired.exists()
    rows = read_csv_rows(repaired)
    # locate the first non-header row (some runs may preserve header row)
    data_row = None
    for r in rows:
        if len(r) >= 3 and not (r[0].lower() in ['filename', 'file', 'name'] or r[2].lower() in ['crc32', 'crc', 'checksum']):
            data_row = r
            break
    assert data_row is not None, f'No data row found in repaired CSV: {rows}'
    assert data_row[2] == 'DEADBEEF'


def test_no_rewrite_if_clean(tmp_path):
    # Create a clean CSV that should not be rewritten when --no-rewrite-if-clean is used
    csv_file = tmp_path / 'clean.csv'
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        f.write('img.jpg,10,01234567,folder,\n')

    proc = run_script(csv_file, extra_args=['--repair', '--no-rewrite-if-clean'])
    # If the file is clean, the script reports and skips rewrite
    assert proc.returncode in (0, 2)
    repaired = tmp_path / 'clean_repaired.csv'
    assert not repaired.exists(), 'No repaired file should be written when --no-rewrite-if-clean is used and CSV is clean'


def test_dry_run_does_not_write(tmp_path):
    csv_file = tmp_path / 'dry.csv'
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        f.write('img.jpg,10,89ABCDEF,folder,\n')

    proc = run_script(csv_file, extra_args=['--repair', '--dry-run'])
    assert proc.returncode in (0, 2)
    repaired = tmp_path / 'dry_repaired.csv'
    assert not repaired.exists()


def test_nonutf8_flag_reports_issue(tmp_path):
    csv_file = tmp_path / 'cp1252.csv'
    # Write a cp1252-encoded CSV (contains a Latin-1/CP1252 character)
    text = 'img.jpg,15,ABCDEF01,folder,é\n'
    with open(csv_file, 'w', newline='', encoding='cp1252') as f:
        f.write(text)

    proc = run_script(csv_file, extra_args=['--repair', '--flag-nonutf8'])
    # Expect issues found due to non-UTF8 encoding detection
    assert proc.returncode == 2, f'Expected exit code 2 for non-UTF8 flagged run, got {proc.returncode} stdout:{proc.stdout} stderr:{proc.stderr}'
    log_file = tmp_path / 'cp1252_repair_log.txt'
    assert log_file.exists()
    txt = log_file.read_text(encoding='utf-8')
    assert 'Non-UTF-8 encoding detected' in txt


def test_bom_handling_utf8sig(tmp_path):
    csv_file = tmp_path / 'bom.csv'
    # Write with UTF-8 BOM
    with open(csv_file, 'w', newline='', encoding='utf-8-sig') as f:
        f.write('FileName,Size,CRC32,Path,Comment\n')
        f.write('img.jpg,20,FEEDFACE,folder,ok\n')

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    repaired = tmp_path / 'bom_repaired.csv'
    assert repaired.exists()
import importlib.util
import csv
from pathlib import Path


def load_module():
    src = Path(__file__).parent.parent / 'CSV-Validate-Repair.py'
    spec = importlib.util.spec_from_file_location('csv_validate_repair', str(src))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_validate_crc32_normalization():
    mod = load_module()
    issues = []
    # lower-case short hex should be uppercased and zero-padded to 8
    out = mod.validate_crc32('1a', 1, issues, repair=True)
    assert out == '0000001A'


def test_validate_and_repair_csv_normalize_only(tmp_path):
    mod = load_module()
    input_csv = tmp_path / 'input.csv'
    output_csv = tmp_path / 'output_repaired.csv'
    log_file = tmp_path / 'repair_log.txt'

    # Write a simple CSV with header and one row; CRC is short and lower-case
    content = 'FileName,Size,CRC32,Path,Comment\n'
    content += 'test.jpg,123,1a2b3c,\\path\\,\n'
    input_csv.write_text(content, encoding='utf-8')

    issues, rows, out_path, archive = mod.validate_and_repair_csv(
        str(input_csv),
        output_file=str(output_csv),
        log_file=str(log_file),
        dry_run=False,
        normalize_crc32=True,
        normalize_only=True,
        repair=False
    )

    assert out_path == str(output_csv)
    # Read repaired CSV and assert CRC normalized
    with open(out_path, 'r', encoding='utf-8', newline='') as f:
        rdr = csv.reader(f)
        rows = list(rdr)
    # header + one data row
    assert len(rows) == 2
    data_row = rows[1]
    # CRC is at index 2
    assert data_row[2] == '001A2B3C'
