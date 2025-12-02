# Python Virtual Environment Setup - scanner-crc-organizer

## Overview

This repository includes Python utilities for CSV validation and repair (`CSV-Validate-Repair.py`, `CRC32-Folder-Calc.py`). A virtual environment is recommended for isolation and dependency management.

## Quick Start

### Create Virtual Environment

**Windows (PowerShell):**
```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

**Linux/macOS:**
```bash
python3 -m venv .venv
source .venv/bin/activate
```

### Install Dependencies

```powershell
pip install --upgrade pip
pip install -r requirements.txt
```

## Python Version

- **Recommended**: Python 3.12.4 or newer
- **Minimum**: Python 3.9+

## Dependencies

The main CRC workflow uses **only Python standard library**:
- `csv` - CSV file processing
- `hashlib` - CRC32 hash calculations
- `pathlib` - Cross-platform path handling

Optional testing dependency:
- `pytest==9.0.1` - For running Python test suite

## Verify Installation

```powershell
# Check Python version
python --version

# Check pip version
pip --version

# List installed packages
pip list
```

## Usage

### Run CSV Validation
```powershell
python CSV-Validate-Repair.py input.csv
```

### Run CRC32 Folder Calculator
```powershell
python CRC32-Folder-Calc.py D:\ScanFolder
```

### Run Tests
```powershell
pytest tests/
```

## Deactivate Virtual Environment

```powershell
deactivate
```

## Recreate Environment

If you need to start fresh:

```powershell
# Remove old environment
Remove-Item -Recurse -Force .venv

# Create new environment
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install --upgrade pip
pip install -r requirements.txt
```

## Troubleshooting

### "Execution Policy" Error (Windows)
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Python Not Found
Ensure Python 3.9+ is installed and in PATH:
```powershell
python --version
```

Download from: https://www.python.org/downloads/

### Module Import Errors
Ensure virtual environment is activated (prompt shows `(.venv)`):
```powershell
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```
