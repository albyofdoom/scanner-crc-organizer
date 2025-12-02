"""
Test suite for CSV comment field preservation and quoting.

This test file ensures that the CSV-Validate-Repair script properly:
- Preserves comment fields with commas
- Handles embedded quotes in comments
- Doesn't truncate comment content
- Uses proper quoting (QUOTE_ALL) to avoid parsing issues
"""

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
    """Read CSV with QUOTE_ALL to match output format."""
    with open(path, newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        return [row for row in reader]


def test_comment_with_single_comma(tmp_path):
    """Test that comments with a single comma are preserved."""
    csv_file = tmp_path / 'single_comma.csv'
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['file1.jpg', '1000', 'ABCD1234', '\\path\\', 'This is a comment, with one comma'])

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    
    repaired = tmp_path / 'single_comma_repaired.csv'
    assert repaired.exists()
    
    rows = read_csv_rows(repaired)
    assert len(rows) == 1
    assert rows[0][4] == 'This is a comment, with one comma'


def test_comment_with_multiple_commas(tmp_path):
    """Test that comments with multiple commas are preserved."""
    csv_file = tmp_path / 'multi_comma.csv'
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['file2.jpg', '2000', 'DEADBEEF', '\\path\\', 'Comment with, multiple, commas, here'])

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    
    repaired = tmp_path / 'multi_comma_repaired.csv'
    assert repaired.exists()
    
    rows = read_csv_rows(repaired)
    assert len(rows) == 1
    assert rows[0][4] == 'Comment with, multiple, commas, here'


def test_comment_with_embedded_quotes(tmp_path):
    """Test that comments with embedded double quotes are preserved."""
    csv_file = tmp_path / 'quoted_comment.csv'
    comment_text = 'Comment with "quoted" text inside'
    
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['file3.jpg', '3000', 'CAFEBABE', '\\path\\', comment_text])

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    
    repaired = tmp_path / 'quoted_comment_repaired.csv'
    assert repaired.exists()
    
    rows = read_csv_rows(repaired)
    assert len(rows) == 1
    assert rows[0][4] == comment_text


def test_comment_with_quotes_and_commas(tmp_path):
    """Test the complex case: comments with both quotes and commas."""
    csv_file = tmp_path / 'complex_comment.csv'
    comment_text = 'In the "2006-09-16" folder, check files'
    
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['file4.jpg', '4000', '12345678', '\\path\\', comment_text])

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    
    repaired = tmp_path / 'complex_comment_repaired.csv'
    assert repaired.exists()
    
    rows = read_csv_rows(repaired)
    assert len(rows) == 1
    assert rows[0][4] == comment_text


def test_long_comment_not_truncated(tmp_path):
    """Test that long comments are not truncated."""
    csv_file = tmp_path / 'long_comment.csv'
    long_comment = 'This is a very long comment with many words, multiple commas, and "quotes" to test that the entire content is preserved without any truncation or data loss even when it spans many characters and contains special CSV characters like commas and quotes.'
    
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['file5.jpg', '5000', '9ABCDEF0', '\\path\\', long_comment])

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    
    repaired = tmp_path / 'long_comment_repaired.csv'
    assert repaired.exists()
    
    rows = read_csv_rows(repaired)
    assert len(rows) == 1
    assert rows[0][4] == long_comment


def test_empty_comment_preserved(tmp_path):
    """Test that empty comments remain empty."""
    csv_file = tmp_path / 'empty_comment.csv'
    
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['file6.jpg', '6000', 'FEDCBA98', '\\path\\', ''])

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    
    repaired = tmp_path / 'empty_comment_repaired.csv'
    assert repaired.exists()
    
    rows = read_csv_rows(repaired)
    assert len(rows) == 1
    assert rows[0][4] == ''


def test_comment_with_whitespace(tmp_path):
    """Test that comments with leading/trailing whitespace are trimmed."""
    csv_file = tmp_path / 'whitespace_comment.csv'
    
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['file7.jpg', '7000', '11223344', '\\path\\', '  Comment with spaces  '])

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    
    repaired = tmp_path / 'whitespace_comment_repaired.csv'
    assert repaired.exists()
    
    rows = read_csv_rows(repaired)
    assert len(rows) == 1
    # validate_comment() trims whitespace
    assert rows[0][4] == 'Comment with spaces'


def test_all_fields_quoted_in_output(tmp_path):
    """Test that ALL fields are quoted in the output (QUOTE_ALL behavior)."""
    csv_file = tmp_path / 'quote_all.csv'
    
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['simple.jpg', '8000', 'AABBCCDD', '\\path\\', 'Simple comment'])

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    
    repaired = tmp_path / 'quote_all_repaired.csv'
    assert repaired.exists()
    
    # Read raw content to verify all fields are quoted
    with open(repaired, 'r', encoding='utf-8') as f:
        raw_content = f.read()
    
    # All fields should be wrapped in quotes (QUOTE_ALL)
    assert '"simple.jpg"' in raw_content
    assert '"8000"' in raw_content  # Even numeric fields should be quoted
    assert '"AABBCCDD"' in raw_content
    assert '"\\path\\"' in raw_content or '"\\\\path\\\\"' in raw_content  # May have escaped backslashes
    assert '"Simple comment"' in raw_content


def test_multiple_rows_with_varied_comments(tmp_path):
    """Test multiple rows with different comment patterns."""
    csv_file = tmp_path / 'multi_rows.csv'
    
    rows_data = [
        ['file1.jpg', '1000', 'AAAAAAAA', '\\path1\\', 'Simple'],
        ['file2.jpg', '2000', 'BBBBBBBB', '\\path2\\', 'With, comma'],
        ['file3.jpg', '3000', 'CCCCCCCC', '\\path3\\', 'With "quotes"'],
        ['file4.jpg', '4000', 'DDDDDDDD', '\\path4\\', ''],
    ]
    
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerows(rows_data)

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    
    repaired = tmp_path / 'multi_rows_repaired.csv'
    assert repaired.exists()
    
    rows = read_csv_rows(repaired)
    assert len(rows) == 4
    assert rows[0][4] == 'Simple'
    assert rows[1][4] == 'With, comma'
    assert rows[2][4] == 'With "quotes"'
    assert rows[3][4] == ''


def test_comment_preservation_with_header(tmp_path):
    """Test comment preservation when CSV has a header row."""
    csv_file = tmp_path / 'with_header.csv'
    
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['FileName', 'Size', 'CRC32', 'Path', 'Comment'])
        writer.writerow(['data.jpg', '9000', 'EEFFAABB', '\\data\\', 'Important, note, here'])

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    
    repaired = tmp_path / 'with_header_repaired.csv'
    assert repaired.exists()
    
    rows = read_csv_rows(repaired)
    assert len(rows) == 2
    # Header row
    assert rows[0][4].lower() == 'comment'
    # Data row - comment should be preserved
    assert rows[1][4] == 'Important, note, here'


def test_unquoted_comment_with_commas(tmp_path):
    """Test that unquoted comments with commas in the input CSV are properly merged and preserved."""
    csv_file = tmp_path / 'unquoted_commas.csv'
    
    # Write CSV with unquoted comment fields that contain commas
    # This simulates the real-world case where input CSVs aren't properly quoted
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        # Note: Using raw write instead of csv.writer to create truly unquoted fields
        f.write('ccde_MediaMarkt_35.jpg,100167,1CACA5EE,\\Specials\\MediaMarkt\\,Isabell Etz, Media Markt Plauen\n')
        f.write('ccde_MediaMarkt_36.jpg,98322,FA74C41F,\\Specials\\MediaMarkt\\,Janine Menzel, Media Markt Stuttgart\n')

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    
    repaired = tmp_path / 'unquoted_commas_repaired.csv'
    assert repaired.exists()
    
    rows = read_csv_rows(repaired)
    assert len(rows) == 2
    
    # The comment fields should be merged back together (fields 4 and 5+ joined by comma)
    assert rows[0][4] == 'Isabell Etz, Media Markt Plauen'
    assert rows[1][4] == 'Janine Menzel, Media Markt Stuttgart'
    
    # Verify other fields are intact
    assert rows[0][0] == 'ccde_MediaMarkt_35.jpg'
    assert rows[0][2] == '1CACA5EE'
    assert rows[1][0] == 'ccde_MediaMarkt_36.jpg'
    assert rows[1][2] == 'FA74C41F'


if __name__ == '__main__':
    # Run tests with pytest
    import pytest
    pytest.main([__file__, '-v'])
