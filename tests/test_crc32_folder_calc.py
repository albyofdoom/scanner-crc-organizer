"""
Unit tests for CRC32_Folder_Calc.py

Tests cover:
- CRC32 computation accuracy
- Directory scanning (recursive and non-recursive)
- CSV output format and structure
- Extra column handling
- Parent folder name extraction
- Error handling (missing files, permission issues, etc.)
- Unicode filename support
- Large file handling
"""

import pytest
import sys
import os
import csv
import tempfile
import shutil
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from CRC32_Folder_Calc import compute_crc32, scan_directory


def test_compute_crc32_known_value(tmp_path):
    """Test CRC32 computation matches known value."""
    test_file = tmp_path / "test.txt"
    test_file.write_text("Hello World!", encoding='utf-8')
    
    # Known CRC32 for "Hello World!" is 0x1C291CA3
    crc = compute_crc32(str(test_file))
    assert crc == "1C291CA3", f"Expected 1C291CA3, got {crc}"


def test_compute_crc32_empty_file(tmp_path):
    """Test CRC32 of empty file."""
    test_file = tmp_path / "empty.txt"
    test_file.write_text("", encoding='utf-8')
    
    # Known CRC32 for empty file is 0x00000000
    crc = compute_crc32(str(test_file))
    assert crc == "00000000", f"Expected 00000000 for empty file, got {crc}"


def test_compute_crc32_binary_file(tmp_path):
    """Test CRC32 of binary file."""
    test_file = tmp_path / "binary.bin"
    test_file.write_bytes(b'\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09')
    
    crc = compute_crc32(str(test_file))
    # Verify it's 8 uppercase hex characters
    assert len(crc) == 8, f"CRC should be 8 characters, got {len(crc)}"
    assert crc.isupper(), "CRC should be uppercase"
    assert all(c in '0123456789ABCDEF' for c in crc), "CRC should be hex"


def test_compute_crc32_large_file(tmp_path):
    """Test CRC32 computation on file larger than buffer size."""
    test_file = tmp_path / "large.bin"
    # Write 2MB of data (larger than 8KB buffer)
    data = b'A' * (2 * 1024 * 1024)
    test_file.write_bytes(data)
    
    crc = compute_crc32(str(test_file))
    assert len(crc) == 8, "CRC should be 8 characters"
    assert crc.isupper(), "CRC should be uppercase"


def test_compute_crc32_nonexistent_file(tmp_path):
    """Test CRC32 on non-existent file returns ERROR."""
    nonexistent = tmp_path / "doesnotexist.txt"
    crc = compute_crc32(str(nonexistent))
    
    assert crc.startswith("ERROR:"), f"Expected ERROR prefix, got {crc}"


def test_compute_crc32_unicode_filename(tmp_path):
    """Test CRC32 computation with unicode filename."""
    test_file = tmp_path / "tëst_文件.txt"
    test_file.write_text("Unicode test", encoding='utf-8')
    
    crc = compute_crc32(str(test_file))
    assert len(crc) == 8, "CRC should be 8 characters"
    assert crc.isupper(), "CRC should be uppercase"


def test_scan_directory_basic(tmp_path):
    """Test basic directory scanning produces correct CSV."""
    # Create test structure
    test_dir = tmp_path / "source"
    test_dir.mkdir()
    (test_dir / "file1.txt").write_text("Content 1", encoding='utf-8')
    (test_dir / "file2.txt").write_text("Content 2", encoding='utf-8')
    
    output_csv = tmp_path / "output.csv"
    scan_directory(str(test_dir), str(output_csv))
    
    # Verify CSV exists
    assert output_csv.exists(), "Output CSV should be created"
    
    # Parse and validate CSV
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    # Check header
    assert reader.fieldnames == ['FileName', 'Size', 'CRC32', 'Path'], \
        f"Expected standard headers, got {reader.fieldnames}"
    
    # Check row count
    assert len(rows) == 2, f"Expected 2 rows, got {len(rows)}"
    
    # Validate each row
    for row in rows:
        assert row['FileName'] in ['file1.txt', 'file2.txt']
        assert row['Size'].isdigit(), f"Size should be numeric, got {row['Size']}"
        assert len(row['CRC32']) == 8, f"CRC32 should be 8 chars, got {row['CRC32']}"
        assert row['CRC32'].isupper(), "CRC32 should be uppercase"
        assert row['Path'] == 'source', f"Path should be 'source', got {row['Path']}"


def test_scan_directory_recursive(tmp_path):
    """Test recursive directory scanning."""
    # Create nested structure
    test_dir = tmp_path / "root"
    test_dir.mkdir()
    (test_dir / "file1.txt").write_text("Root file", encoding='utf-8')
    
    subdir = test_dir / "subfolder"
    subdir.mkdir()
    (subdir / "file2.txt").write_text("Subfolder file", encoding='utf-8')
    
    deep_dir = subdir / "deep"
    deep_dir.mkdir()
    (deep_dir / "file3.txt").write_text("Deep file", encoding='utf-8')
    
    output_csv = tmp_path / "recursive.csv"
    scan_directory(str(test_dir), str(output_csv))
    
    # Parse CSV
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    # Should find all 3 files
    assert len(rows) == 3, f"Expected 3 files recursively, got {len(rows)}"
    
    # Check Path field reflects parent folder
    filenames = {row['FileName']: row['Path'] for row in rows}
    assert filenames['file1.txt'] == 'root', "Root file should have 'root' path"
    assert filenames['file2.txt'] == 'subfolder', "Subfolder file should have 'subfolder' path"
    assert filenames['file3.txt'] == 'deep', "Deep file should have 'deep' path"


def test_scan_directory_extra_columns(tmp_path):
    """Test adding extra columns to CSV."""
    test_dir = tmp_path / "source"
    test_dir.mkdir()
    (test_dir / "file.txt").write_text("Test", encoding='utf-8')
    
    output_csv = tmp_path / "extra_cols.csv"
    scan_directory(str(test_dir), str(output_csv), extra_columns=['Comment', 'Tags'])
    
    # Parse CSV
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    # Check headers include extra columns
    expected_headers = ['FileName', 'Size', 'CRC32', 'Path', 'Comment', 'Tags']
    assert reader.fieldnames == expected_headers, \
        f"Expected {expected_headers}, got {reader.fieldnames}"
    
    # Check extra columns are empty
    row = rows[0]
    assert row['Comment'] == '', "Extra column 'Comment' should be empty"
    assert row['Tags'] == '', "Extra column 'Tags' should be empty"


def test_scan_directory_multiple_extra_columns(tmp_path):
    """Test multiple extra columns with various names."""
    test_dir = tmp_path / "source"
    test_dir.mkdir()
    (test_dir / "test.txt").write_text("Test", encoding='utf-8')
    
    output_csv = tmp_path / "multi_cols.csv"
    extra = ['Col1', 'Col2', 'Col3', 'Col4']
    scan_directory(str(test_dir), str(output_csv), extra_columns=extra)
    
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    expected = ['FileName', 'Size', 'CRC32', 'Path'] + extra
    assert reader.fieldnames == expected
    
    # All extra columns should be empty
    row = rows[0]
    for col in extra:
        assert row[col] == '', f"Extra column '{col}' should be empty"


def test_scan_directory_parent_folder_extraction(tmp_path):
    """Test parent folder name extraction from various paths."""
    # Create multiple levels
    root = tmp_path / "level1" / "level2" / "level3"
    root.mkdir(parents=True)
    (root / "file.txt").write_text("Test", encoding='utf-8')
    
    output_csv = tmp_path / "paths.csv"
    scan_directory(str(root), str(output_csv))
    
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    # Path should be the immediate parent folder name
    assert rows[0]['Path'] == 'level3', f"Expected 'level3', got {rows[0]['Path']}"


def test_scan_directory_unicode_filenames(tmp_path):
    """Test scanning files with unicode characters."""
    test_dir = tmp_path / "unicode"
    test_dir.mkdir()
    
    # Create files with various unicode characters
    files = [
        "tëst_äöü.txt",
        "日本語.txt",
        "файл.txt",
        "émilie_café.txt"
    ]
    
    for filename in files:
        (test_dir / filename).write_text("Unicode content", encoding='utf-8')
    
    output_csv = tmp_path / "unicode.csv"
    scan_directory(str(test_dir), str(output_csv))
    
    # Parse CSV with UTF-8 encoding
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    assert len(rows) == len(files), f"Expected {len(files)} files, got {len(rows)}"
    
    # Verify all filenames preserved correctly
    found_names = {row['FileName'] for row in rows}
    expected_names = set(files)
    assert found_names == expected_names, f"Unicode filenames not preserved correctly"


def test_scan_directory_special_chars_in_filenames(tmp_path):
    """Test files with special characters like brackets, ampersands."""
    test_dir = tmp_path / "special"
    test_dir.mkdir()
    
    files = [
        "file[2024].txt",
        "item{with}braces.txt",
        "name & value.txt",
        "comma,separated.txt"
    ]
    
    for filename in files:
        (test_dir / filename).write_text("Content", encoding='utf-8')
    
    output_csv = tmp_path / "special.csv"
    scan_directory(str(test_dir), str(output_csv))
    
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    found_names = {row['FileName'] for row in rows}
    expected_names = set(files)
    assert found_names == expected_names, "Special characters not preserved"


def test_scan_directory_empty_directory(tmp_path):
    """Test scanning empty directory produces header-only CSV."""
    test_dir = tmp_path / "empty"
    test_dir.mkdir()
    
    output_csv = tmp_path / "empty.csv"
    scan_directory(str(test_dir), str(output_csv))
    
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    # Should have header but no data rows
    assert reader.fieldnames == ['FileName', 'Size', 'CRC32', 'Path']
    assert len(rows) == 0, "Empty directory should produce no data rows"


def test_scan_directory_size_accuracy(tmp_path):
    """Test file size is accurately reported."""
    test_dir = tmp_path / "sizes"
    test_dir.mkdir()
    
    # Create files of known sizes
    sizes = {
        "small.txt": 10,
        "medium.txt": 1000,
        "large.txt": 100000
    }
    
    for filename, size in sizes.items():
        (test_dir / filename).write_bytes(b'X' * size)
    
    output_csv = tmp_path / "sizes.csv"
    scan_directory(str(test_dir), str(output_csv))
    
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    # Verify sizes match
    for row in rows:
        expected_size = sizes[row['FileName']]
        actual_size = int(row['Size'])
        assert actual_size == expected_size, \
            f"{row['FileName']}: expected {expected_size}, got {actual_size}"


def test_scan_directory_csv_compatibility(tmp_path):
    """Test CSV output is compatible with CRC-FileOrganizer expectations."""
    test_dir = tmp_path / "compat"
    test_dir.mkdir()
    (test_dir / "test.jpg").write_bytes(b'\xFF\xD8\xFF\xE0' * 100)  # Fake JPEG
    
    output_csv = tmp_path / "compat.csv"
    scan_directory(str(test_dir), str(output_csv))
    
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    row = rows[0]
    
    # Validate format matches CRC-FileOrganizer expectations
    assert 'FileName' in reader.fieldnames, "Must have FileName column"
    assert 'Size' in reader.fieldnames, "Must have Size column"
    assert 'CRC32' in reader.fieldnames, "Must have CRC32 column"
    assert 'Path' in reader.fieldnames, "Must have Path column"
    
    # CRC32 format: 8 uppercase hex
    assert len(row['CRC32']) == 8, "CRC32 must be 8 characters"
    assert row['CRC32'].isupper(), "CRC32 must be uppercase"
    assert all(c in '0123456789ABCDEF' for c in row['CRC32']), "CRC32 must be hex"
    
    # Size format: numeric string
    assert row['Size'].isdigit(), "Size must be numeric"


def test_scan_directory_path_normalization(tmp_path):
    """Test path normalization handles trailing slashes correctly."""
    test_dir = tmp_path / "normalize"
    test_dir.mkdir()
    (test_dir / "file.txt").write_text("Test", encoding='utf-8')
    
    output_csv = tmp_path / "norm.csv"
    # Test with trailing slash
    scan_directory(str(test_dir) + os.sep, str(output_csv))
    
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    # Should still extract folder name correctly
    assert rows[0]['Path'] == 'normalize', \
        f"Path normalization failed: got {rows[0]['Path']}"


def test_scan_directory_mixed_file_types(tmp_path):
    """Test scanning directory with various file types."""
    test_dir = tmp_path / "mixed"
    test_dir.mkdir()
    
    # Create different file types
    (test_dir / "text.txt").write_text("Text", encoding='utf-8')
    (test_dir / "image.jpg").write_bytes(b'\xFF\xD8\xFF\xE0')
    (test_dir / "data.bin").write_bytes(b'\x00\x01\x02\x03')
    (test_dir / "script.ps1").write_text("Write-Host 'Test'", encoding='utf-8')
    
    output_csv = tmp_path / "mixed.csv"
    scan_directory(str(test_dir), str(output_csv))
    
    with open(output_csv, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    # All file types should be included
    assert len(rows) == 4, f"Expected 4 files, got {len(rows)}"
    
    # Verify each has valid CRC
    for row in rows:
        assert len(row['CRC32']) == 8, f"Invalid CRC for {row['FileName']}"


def test_compute_crc32_identical_content(tmp_path):
    """Test identical content produces identical CRCs."""
    content = "Identical content for CRC testing"
    
    file1 = tmp_path / "file1.txt"
    file2 = tmp_path / "file2.txt"
    
    file1.write_text(content, encoding='utf-8')
    file2.write_text(content, encoding='utf-8')
    
    crc1 = compute_crc32(str(file1))
    crc2 = compute_crc32(str(file2))
    
    assert crc1 == crc2, "Identical content should produce identical CRCs"


def test_compute_crc32_different_content(tmp_path):
    """Test different content produces different CRCs."""
    file1 = tmp_path / "file1.txt"
    file2 = tmp_path / "file2.txt"
    
    file1.write_text("Content A", encoding='utf-8')
    file2.write_text("Content B", encoding='utf-8')
    
    crc1 = compute_crc32(str(file1))
    crc2 = compute_crc32(str(file2))
    
    assert crc1 != crc2, "Different content should produce different CRCs"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
