import csv
import subprocess
import sys
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


def test_semicolon_delimiter_flags_issue(tmp_path):
    csv_file = tmp_path / 'semi.csv'
    # Semicolon-delimited CSV (legacy) — script expects commas
    content = 'FileName;Size;CRC32;Path;Comment\nimg.jpg;10;ABCDEF01;folder;ok\n'
    csv_file.write_text(content, encoding='utf-8')

    proc = run_script(csv_file, extra_args=['--repair'])
    # Should flag issues due to insufficient fields when parsed by comma
    assert proc.returncode == 2
    log = tmp_path / 'semi_repair_log.txt'
    assert log.exists()


def test_tab_delimited_flags_issue(tmp_path):
    csv_file = tmp_path / 'tab.csv'
    content = 'FileName\tSize\tCRC32\tPath\tComment\nimg.jpg\t10\tABCDEF01\tfolder\tok\n'
    csv_file.write_text(content, encoding='utf-8')

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode == 2
    log = tmp_path / 'tab_repair_log.txt'
    assert log.exists()


def test_single_comma_path_preserved(tmp_path):
    csv_file = tmp_path / 'single_comma.csv'
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        f.write('FileName,Size,CRC32,Path,Comment\n')
        f.write('a.jpg,1,AAAABBBB,,\n')
        # explicit single-comma path value
        f.write('b.jpg,2,CCCCDDDD,",",note\n')

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    repaired = tmp_path / 'single_comma_repaired.csv'
    assert repaired.exists()
    rows = read_csv_rows(repaired)
    # find row for b.jpg and ensure Path is a single comma or quoted comma preserved
    found = False
    for r in rows:
        if r and r[0] == 'b.jpg':
            found = True
            assert r[3] in [',', '\\,', ' ,']
    assert found


def test_multiple_backslashes_before_comma(tmp_path):
    csv_file = tmp_path / 'backslashes.csv'
    # path contains multiple backslashes before a comma sequence
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        f.write('FileName,Size,CRC32,Path,Comment\n')
        f.write('x.jpg,5,ABC12345,folder\\\\,,note\n')

    proc = run_script(csv_file, extra_args=['--repair'])
    assert proc.returncode in (0, 2)
    repaired = tmp_path / 'backslashes_repaired.csv'
    assert repaired.exists()
    rows = read_csv_rows(repaired)
    # Ensure Path field contains backslashes (one or more)
    assert any('\\' in r[3] for r in rows if len(r) > 3)


def test_null_byte_in_field_reports_issue(tmp_path):
    csv_file = tmp_path / 'nullbyte.csv'
    # Null bytes are unusual in CSVs; write using bytes mode
    b = b'FileName,Size,CRC32,Path,Comment\nimg.jpg,1,ABCDEF01,folder\x00,ok\n'
    csv_file.write_bytes(b)

    proc = run_script(csv_file, extra_args=['--repair'])
    # Expect the script to error or flag the encoding/parse issue (exit 1 or 2)
    assert proc.returncode in (1, 2)
    # Ensure a log exists when issues flagged
    log = tmp_path / 'nullbyte_repair_log.txt'
    assert log.exists() or proc.returncode == 1


def test_single_quote_quoting_is_flagged(tmp_path):
    csv_file = tmp_path / 'singlequote.csv'
    # Fields quoted with single quotes are non-standard; parser should treat them as literal quotes
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        f.write("'FileName','Size','CRC32','Path','Comment'\n")
        f.write("'q.jpg','3','ABCDEF02','folder','c'\n")

    proc = run_script(csv_file, extra_args=['--repair'])
    # Likely flagged as issues due to header detection mismatch or format
    assert proc.returncode == 2
    log = tmp_path / 'singlequote_repair_log.txt'
    assert log.exists()


def test_leading_trailing_spaces_behavior(tmp_path):
    csv_file = tmp_path / 'spaces.csv'
    with open(csv_file, 'w', newline='', encoding='utf-8') as f:
        f.write('FileName,Size,CRC32,Path,Comment\n')
        f.write('  spaced.jpg  ,  10 , abcdef01 , folder , note \n')

    # Validation-only: spaces should be reported but not trimmed
    proc = run_script(csv_file, extra_args=[])
    assert proc.returncode in (0, 2)

    # Repair mode should trim spaces
    proc2 = run_script(csv_file, extra_args=['--repair'])
    assert proc2.returncode in (0, 2)
    repaired = tmp_path / 'spaces_repaired.csv'
    assert repaired.exists()
    rows = read_csv_rows(repaired)
    # filename should be trimmed
    assert rows[1][0] == 'spaced.jpg'
