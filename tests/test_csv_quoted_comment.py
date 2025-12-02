import os
import importlib.util
import csv
import io


def load_module_from_path(path):
    spec = importlib.util.spec_from_file_location("csv_validate_repair", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_quoted_comment_not_double_quoted():
    # Use the exact raw line from the AmourAngels sample where the comment is
    # already correctly quoted in the CSV. The parser should return an
    # unquoted Python string and csv.writer should not produce tripled quotes.
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    module_path = os.path.join(repo_root, 'CSV-Validate-Repair.py')
    assert os.path.exists(module_path), f"Module not found: {module_path}"

    mod = load_module_from_path(module_path)
    parse = getattr(mod, 'parse_csv_line_with_quotes')

    raw = 'bp_009.jpg,1978743,956820FA,\\2006-09-02__BeautyAngel-by-Rasputin\\,"in the ""2006-09-16__Krasa-kama-by-Rasputin"" zip file from"\n'
    issues = []
    fields = parse(raw, line_num=9, issues=issues)

    # The comment field should be unquoted and should contain a single pair
    # of internal quotes around the date (as a normal Python string).
    expected_comment = 'in the "2006-09-16__Krasa-kama-by-Rasputin" zip file from'
    assert fields[4] == expected_comment

    # Now write the row back to CSV using csv.writer and ensure that the
    # output does not contain triple/doubled-up quotes like '"""' or '""""'.
    buf = io.StringIO()
    writer = csv.writer(buf, quoting=csv.QUOTE_MINIMAL)
    writer.writerow(fields)
    out = buf.getvalue()

    assert '"""' not in out
    assert '""""' not in out
    # Also assert the date piece is present and correctly escaped once
    assert '2006-09-16__Krasa-kama-by-Rasputin' in out
