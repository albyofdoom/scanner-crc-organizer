import os
import importlib.util
import re


def load_module_from_path(path):
    spec = importlib.util.spec_from_file_location("csv_validate_repair", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_escaped_comma_trailing_backslash():
    # Locate the CSV-Validate-Repair.py script relative to the repo root
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    module_path = os.path.join(repo_root, 'CSV-Validate-Repair.py')
    assert os.path.exists(module_path), f"Module not found: {module_path}"

    mod = load_module_from_path(module_path)
    parse = getattr(mod, 'parse_csv_line_with_quotes')

    # Line with an escaped comma sequence (literal backslash+comma) inside the Path field
    raw = 'file.pdf,12345,ABCDEF12,\\Some\\Path\\With\\Comma\\,Comment text\n'
    issues = []
    fields = parse(raw, line_num=1, issues=issues)

    # Expect 5 fields: filename, size, crc32, path (ending with backslash), comment
    assert len(fields) == 5
    assert fields[0] == 'file.pdf'
    assert fields[1] == '12345'
    assert re.fullmatch(r'[0-9A-Fa-f]{8}', fields[2])
    assert fields[3].endswith('\\')
    assert fields[4] == 'Comment text'
