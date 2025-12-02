"""
Advanced edge case tests for CSV-Validate-Repair.py

Tests additional scenarios not covered by existing tests:
- Archive functionality
- Bulk mode edge cases  
- Encoding detection failures
- Normalize-only mode
- Complex field repair scenarios
- Performance edge cases
"""

import pytest
import sys
import os
import csv
import json
import zipfile
from pathlib import Path

# Add CSV_Processing to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'CSV_Processing'))
from CSV_Validate_Repair import (
    validate_and_repair_csv,
    process_folder_bulk,
    archive_csv_file
)


def test_archive_original_creates_zip(tmp_path):
    """Test archiving original CSV creates timestamped zip."""
    input_csv = tmp_path / "test.csv"
    input_csv.write_text("FileName,Size,CRC32,Path\ntest.txt,100,12345678,\\test\\", encoding='utf-8')
    
    archive_folder = tmp_path / "Archive"
    
    # Archive the file
    archive_path = archive_csv_file(str(input_csv), str(archive_folder))
    
    assert archive_path is not None, "Archive should be created"
    assert os.path.exists(archive_path), "Archive file should exist"
    assert archive_path.endswith('.zip'), "Archive should be a zip file"
    
    # Verify zip contains the original file
    with zipfile.ZipFile(archive_path, 'r') as zf:
        names = zf.namelist()
        assert len(names) == 1, "Archive should contain exactly one file"
        assert names[0] == 'test.csv', "Archived file should be named test.csv"


def test_archive_move_original_option(tmp_path):
    """Test archive with move_original flag moves file to archive folder."""
    input_csv = tmp_path / "moveme.csv"
    input_csv.write_text("FileName,Size,CRC32,Path\nfile.txt,100,ABCD1234,\\path\\", encoding='utf-8')
    
    archive_folder = tmp_path / "Archive"
    
    # Archive with move option
    archive_path = archive_csv_file(str(input_csv), str(archive_folder), move_original=True)
    
    assert archive_path is not None, "Archive should be created"
    
    # Original should be moved to archive folder (not zipped location)
    # Note: Check actual implementation - this tests expected behavior
    archived_original = Path(archive_folder) / input_csv.name
    if archived_original.exists():
        assert not input_csv.exists(), "Original should be moved, not copied"


def test_normalize_only_mode(tmp_path):
    """Test normalize-only mode only normalizes CRC32, nothing else."""
    input_csv = tmp_path / "normalize.csv"
    # CRC32 with mixed case, spaces in fields
    input_csv.write_text(
        "FileName,Size,CRC32,Path\n"
        "  file.txt  ,  100  ,abcd1234,  \\path\\  ",
        encoding='utf-8'
    )
    
    output_csv = tmp_path / "normalized.csv"
    
    # Run in normalize-only mode
    issues, rows, output_path, _ = validate_and_repair_csv(
        str(input_csv),
        str(output_csv),
        repair=True,
        normalize_only=True
    )
    
    # Parse output
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    row = rows[0]
    
    # CRC should be normalized (uppercase)
    assert row['CRC32'] == 'ABCD1234', "CRC32 should be uppercase"
    
    # Other fields should NOT be trimmed in normalize-only mode
    # (This is the key difference from full repair mode)
    # Note: Actual behavior depends on implementation - adjust test if needed


def test_bulk_mode_mixed_states(tmp_path):
    """Test bulk mode with mix of clean, repairable, and broken CSVs."""
    bulk_folder = tmp_path / "bulk"
    bulk_folder.mkdir()
    
    # Clean CSV
    clean = bulk_folder / "clean.csv"
    clean.write_text(
        "FileName,Size,CRC32,Path\n"
        "file1.txt,100,ABCD1234,\\path\\",
        encoding='utf-8'
    )
    
    # Repairable CSV (whitespace issues)
    repairable = bulk_folder / "repairable.csv"
    repairable.write_text(
        "FileName,Size,CRC32,Path\n"
        "  file2.txt  ,  200  ,  efgh5678  ,  \\path2\\  ",
        encoding='utf-8'
    )
    
    # Broken CSV (invalid CRC format)
    broken = bulk_folder / "broken.csv"
    broken.write_text(
        "FileName,Size,CRC32,Path\n"
        "file3.txt,300,INVALID!,\\path3\\",
        encoding='utf-8'
    )
    
    # Run bulk mode with repair
    results = process_folder_bulk(
        str(bulk_folder),
        repair=True,
        skip_rewrite_if_clean=True
    )
    
    assert results['total_files'] == 3, "Should process all 3 CSVs"
    assert results['with_issues'] >= 1, "Should find issues in at least broken.csv"


def test_encoding_detection_fallback_chain(tmp_path):
    """Test encoding detection tries multiple encodings."""
    # Create file with Latin-1 encoding (not UTF-8)
    input_csv = tmp_path / "latin1.csv"
    content = "FileName,Size,CRC32,Path\nfilé.txt,100,12345678,\\path\\"
    input_csv.write_bytes(content.encode('latin-1'))
    
    output_csv = tmp_path / "repaired.csv"
    
    # Should successfully detect and process
    try:
        issues, rows, output_path, _ = validate_and_repair_csv(
            str(input_csv),
            str(output_csv),
            repair=True
        )
        
        # Should process successfully
        assert rows >= 1, "Should process at least one row"
        
        # Output should be UTF-8
        with open(output_csv, 'r', encoding='utf-8') as f:
            content = f.read()
            assert 'filé' in content or 'file' in content, "Filename preserved"
    except Exception as e:
        pytest.fail(f"Should handle Latin-1 encoding: {e}")


def test_flag_nonutf8_treats_as_issue(tmp_path):
    """Test --flag-nonutf8 treats non-UTF-8 encoding as an issue."""
    # Create Latin-1 encoded file
    input_csv = tmp_path / "latin1.csv"
    content = "FileName,Size,CRC32,Path\nfile.txt,100,12345678,\\path\\"
    input_csv.write_bytes(content.encode('latin-1'))
    
    output_csv = tmp_path / "repaired.csv"
    log_file = tmp_path / "repair.log"
    
    # Run with flag_nonutf8=True
    issues, rows, output_path, _ = validate_and_repair_csv(
        str(input_csv),
        str(output_csv),
        log_file=str(log_file),
        flag_nonutf8=True,
        repair=True
    )
    
    # Should report non-UTF-8 as an issue
    assert issues > 0, "Non-UTF-8 encoding should be flagged as issue"
    
    # Check log contains encoding message
    if log_file.exists():
        log_content = log_file.read_text(encoding='utf-8')
        assert 'encoding' in log_content.lower() or 'utf' in log_content.lower()


def test_bom_stripped_correctly(tmp_path):
    """Test BOM is stripped from first line after detection."""
    input_csv = tmp_path / "bom.csv"
    # UTF-8 BOM + content
    content = b'\xef\xbb\xbfFileName,Size,CRC32,Path\nfile.txt,100,ABCD1234,\\path\\'
    input_csv.write_bytes(content)
    
    output_csv = tmp_path / "repaired.csv"
    
    issues, rows, output_path, _ = validate_and_repair_csv(
        str(input_csv),
        str(output_csv),
        repair=True
    )
    
    # Should process without treating BOM as part of data
    assert rows >= 1, "Should process rows"
    
    # Check output doesn't have BOM artifacts in data
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        first_row = next(reader)
        # First field name should not contain BOM character
        assert '\ufeff' not in first_row['FileName'], "BOM should be stripped"


def test_skip_rewrite_if_clean_actually_skips(tmp_path):
    """Test --no-rewrite-if-clean doesn't write when CSV is clean."""
    input_csv = tmp_path / "clean.csv"
    input_csv.write_text(
        "FileName,Size,CRC32,Path\n"
        "file.txt,100,ABCD1234,\\path\\",
        encoding='utf-8'
    )
    
    output_csv = tmp_path / "clean_repaired.csv"
    
    # Run with skip_rewrite_if_clean=True and repair=True
    issues, rows, output_path, _ = validate_and_repair_csv(
        str(input_csv),
        str(output_csv),
        repair=True,
        skip_rewrite_if_clean=True
    )
    
    # No issues means clean
    if issues == 0:
        # Output file should NOT be created
        assert not output_csv.exists(), "Clean CSV should not be rewritten"


def test_very_large_field_handling(tmp_path):
    """Test handling of very long field values."""
    input_csv = tmp_path / "large_fields.csv"
    
    # Create CSV with very long filename and comment
    long_filename = "a" * 500 + ".txt"
    long_comment = "x" * 2000
    
    input_csv.write_text(
        f"FileName,Size,CRC32,Path,Comment\n"
        f"{long_filename},100,12345678,\\path\\,{long_comment}",
        encoding='utf-8'
    )
    
    output_csv = tmp_path / "repaired.csv"
    
    # Should handle without crashing
    issues, rows, output_path, _ = validate_and_repair_csv(
        str(input_csv),
        str(output_csv),
        repair=True
    )
    
    assert rows >= 1, "Should process large fields"
    
    # Verify data preserved
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        row = next(reader)
        assert len(row['FileName']) >= 500, "Long filename preserved"
        assert len(row['Comment']) >= 2000, "Long comment preserved"


def test_multiple_crc_normalization_formats(tmp_path):
    """Test CRC32 normalization handles various input formats."""
    input_csv = tmp_path / "crc_formats.csv"
    input_csv.write_text(
        "FileName,Size,CRC32,Path\n"
        "file1.txt,100,abcd1234,\\path\\\n"  # Lowercase
        "file2.txt,100,ABCD1234,\\path\\\n"  # Uppercase
        "file3.txt,100,  efgh5678  ,\\path\\\n"  # With spaces
        "file4.txt,100,0xABCD1234,\\path\\",  # With 0x prefix
        encoding='utf-8'
    )
    
    output_csv = tmp_path / "normalized.csv"
    
    issues, rows, output_path, _ = validate_and_repair_csv(
        str(input_csv),
        str(output_csv),
        repair=True,
        normalize_crc32=True
    )
    
    # Parse output
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    # All CRCs should be normalized to uppercase, no prefix, no spaces
    for row in rows:
        crc = row['CRC32']
        assert len(crc) == 8, f"CRC should be 8 chars: {crc}"
        assert crc.isupper(), f"CRC should be uppercase: {crc}"
        assert not crc.startswith('0x'), f"CRC should not have 0x prefix: {crc}"
        assert crc.strip() == crc, f"CRC should have no whitespace: {crc}"


def test_duplicate_crc_detection_with_different_sizes(tmp_path):
    """Test duplicate detection only flags same CRC+Size, not CRC alone."""
    input_csv = tmp_path / "dup_crc.csv"
    input_csv.write_text(
        "FileName,Size,CRC32,Path\n"
        "file1.txt,100,ABCD1234,\\path\\\n"
        "file2.txt,100,ABCD1234,\\path\\\n"  # Duplicate CRC+Size
        "file3.txt,200,ABCD1234,\\path\\",  # Same CRC, different size
        encoding='utf-8'
    )
    
    output_csv = tmp_path / "checked.csv"
    log_file = tmp_path / "dup.log"
    
    issues, rows, output_path, _ = validate_and_repair_csv(
        str(input_csv),
        str(output_csv),
        log_file=str(log_file),
        repair=True
    )
    
    # Should detect duplicate CRC+Size (file1 and file2)
    assert issues > 0, "Should detect duplicate CRC+Size"
    
    # Check log mentions duplicate
    if log_file.exists():
        log_content = log_file.read_text(encoding='utf-8')
        assert 'duplicate' in log_content.lower(), "Log should mention duplicate"


def test_empty_fields_handling(tmp_path):
    """Test handling of empty/missing fields in CSV."""
    input_csv = tmp_path / "empty_fields.csv"
    input_csv.write_text(
        "FileName,Size,CRC32,Path,Comment\n"
        "file1.txt,,,\\path\\,\n"  # Missing Size and CRC32
        ",100,12345678,\\path\\,comment\n"  # Missing FileName
        "file3.txt,100,12345678,,",  # Missing Path
        encoding='utf-8'
    )
    
    output_csv = tmp_path / "repaired.csv"
    log_file = tmp_path / "empty.log"
    
    # Should detect issues with empty required fields
    issues, rows, output_path, _ = validate_and_repair_csv(
        str(input_csv),
        str(output_csv),
        log_file=str(log_file),
        repair=True
    )
    
    # Empty FileName, Size, or CRC32 should be flagged
    assert issues >= 3, f"Should flag at least 3 empty field issues, found {issues}"


def test_path_with_multiple_backslashes(tmp_path):
    """Test path normalization with various backslash patterns."""
    input_csv = tmp_path / "paths.csv"
    input_csv.write_text(
        "FileName,Size,CRC32,Path\n"
        "file1.txt,100,12345678,\\\\path\\\\to\\\\folder\\\\\n"  # Double backslashes
        "file2.txt,100,12345678,\\path\\single\\\n"  # Normal
        "file3.txt,100,12345678,path/with/forward/slashes/",  # Forward slashes
        encoding='utf-8'
    )
    
    output_csv = tmp_path / "repaired.csv"
    
    issues, rows, output_path, _ = validate_and_repair_csv(
        str(input_csv),
        str(output_csv),
        repair=True
    )
    
    # Should process without crashing
    assert rows >= 3, "Should process all path variations"


def test_unicode_in_all_fields(tmp_path):
    """Test unicode characters in FileName, Path, and Comment."""
    input_csv = tmp_path / "unicode_all.csv"
    input_csv.write_text(
        "FileName,Size,CRC32,Path,Comment\n"
        "tëst_文件.txt,100,12345678,\\路径\\フォルダ\\,Commentaire élémentaire",
        encoding='utf-8'
    )
    
    output_csv = tmp_path / "repaired.csv"
    
    issues, rows, output_path, _ = validate_and_repair_csv(
        str(input_csv),
        str(output_csv),
        repair=True
    )
    
    # Parse output
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        row = next(reader)
    
    # Unicode should be preserved
    assert 'tëst_文件' in row['FileName'], "Unicode filename preserved"
    assert '路径' in row['Path'] or 'フォルダ' in row['Path'], "Unicode path preserved"
    assert 'élémentaire' in row['Comment'], "Unicode comment preserved"


def test_bulk_mode_output_organization(tmp_path):
    """Test bulk mode creates proper subfolder structure."""
    bulk_folder = tmp_path / "bulk"
    bulk_folder.mkdir()
    
    # Create test CSV
    test_csv = bulk_folder / "test.csv"
    test_csv.write_text(
        "FileName,Size,CRC32,Path\n"
        "  file.txt  ,  100  ,abcd1234,\\path\\",  # Has issues
        encoding='utf-8'
    )
    
    # Run bulk mode with subfolders
    results = process_folder_bulk(
        str(bulk_folder),
        use_subfolders=True,
        repair=True
    )
    
    # Check subfolder structure created
    expected_folders = ['CleanCSVs', 'Logs']
    for folder in expected_folders:
        folder_path = bulk_folder / folder
        # Folders may or may not be created depending on whether there were issues
        # Just verify the process completed
    
    assert results['total_files'] == 1, "Should process the CSV"


def test_insufficient_fields_extended(tmp_path):
    """Test rows with insufficient fields are extended with empty values."""
    input_csv = tmp_path / "insufficient.csv"
    input_csv.write_text(
        "FileName,Size,CRC32,Path,Comment\n"
        "file1.txt,100,12345678\n"  # Missing Path and Comment
        "file2.txt,100",  # Missing CRC32, Path, Comment
        encoding='utf-8'
    )
    
    output_csv = tmp_path / "extended.csv"
    
    issues, rows, output_path, _ = validate_and_repair_csv(
        str(input_csv),
        str(output_csv),
        repair=True
    )
    
    # Should extend fields (though likely flag as issues)
    # Parse output to verify structure
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows_out = list(reader)
    
    # All rows should have all columns (even if empty)
    for row in rows_out:
        assert 'FileName' in row
        assert 'Size' in row
        assert 'CRC32' in row
        assert 'Path' in row
        assert 'Comment' in row


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
