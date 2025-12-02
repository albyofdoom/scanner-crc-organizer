# scanner-crc-organizer

Production-grade CRC32-based file organization workflow for managing downloaded scanner sets with CSV metadata.

## Overview

This tool automates the workflow of:
1. Reading CSV files containing expected filenames with CRC32 hashes
2. Calculating CRC32 hashes for downloaded files in parallel
3. Matching files to CSV entries by CRC32 (handles duplicates, renames, etc.)
4. Organizing complete sets into structured folders
5. Generating detailed logs and conflict reports

## Features

- **CRC32-based matching**: Finds files even if renamed, handles duplicates intelligently
- **Parallel hash calculation**: Multi-threaded CRC computation with configurable throttling
- **CSV validation**: Repair malformed CSVs, handle exotic encodings, preserve comments
- **Dry-run mode**: Preview all actions before making changes
- **Comprehensive logging**: Timestamped logs with archiving, detailed conflict reports
- **Staging workflow**: Hybrid direct-move + staging folder for complex cases

## Quick Start

### Prerequisites

- **PowerShell**: PowerShell Core 7.0+ or Windows PowerShell 5.1+
- **Python**: 3.9+ (for CSV utilities)
- **Virtual Environment**: Recommended (see `venv_readme.md`)

### Installation

```powershell
# Clone or extract repository
cd scanner-crc-organizer

# Set up Python environment (optional)
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### Basic Usage

```powershell
# Dry run (preview actions without making changes)
.\CRC-FileOrganizer.ps1 -DryRun

# Production run with custom paths
.\CRC-FileOrganizer.ps1 `
    -RootFolder "D:\CSVs" `
    -SourceFolderCRC "D:\Downloads" `
    -CompletedFolder "D:\Completed"

# Control parallelism (default: 4 threads)
.\CRC-FileOrganizer.ps1 -ThrottleLimit 8
```

## Folder Structure

```
RootFolder/          # CSV files and logs
  ├── *.csv          # CSV metadata files
  ├── _98_Logs/      # Timestamped logs
  └── Archive/       # Archived logs

SourceFolderCRC/     # Downloaded files to organize
  └── [files]

CompletedFolder/     # Organized complete sets
  ├── SetName1/
  │   ├── SetName1.csv
  │   └── [matched files]
  └── SetName2/
```

## CSV Format

Expected CSV format (5 columns, no header row):

```
FileName,Size,CRC32,Path,Comment
image001.jpg,1234567,ABCD1234,optional/path,Optional comment
image002.jpg,2345678,EFGH5678,,
```

**Column details:**
- **FileName**: Expected filename (used for reference only, matching is by CRC)
- **Size**: File size in bytes (informational)
- **CRC32**: 8-character hexadecimal CRC32 hash (case-insensitive)
- **Path**: Optional subdirectory path (rarely used)
- **Comment**: Optional notes (preserved during repairs)

## Scripts

### Main Scripts

- **CRC-FileOrganizer.ps1** (966 lines) - Main workflow orchestrator
- **CRC-FileOrganizerLib.ps1** (226 lines) - Shared CRC calculation functions
- **CRC-FileOrganizer-ReportConflicts.ps1** - Detailed conflict analysis tool

### Python Utilities

- **CSV-Validate-Repair.py** - Repairs malformed CSVs, handles exotic encodings
-- **CRC32_Folder_Calc.py** - Standalone CRC32 calculator for folders
- **ExtractModelID.ps1** - HTML parsing for model IDs (optional utility)

## Testing

Comprehensive test suite with 85% coverage:

```powershell
# Run all PowerShell CRC tests
.\tests\run-crc-tests.ps1

# Quick validation test (runs in seconds)
.\tests\Quick-Test-CRC.ps1

# Extended test scenarios
.\tests\Extended-CRC-Tests.ps1

# Python CSV tests (requires pytest)
pytest tests/
```

### Test Files

**PowerShell tests:**
- `Test-CRCFileOrganizer.ps1` - Main workflow tests
- `Test-CRCFileOrganizerLib.ps1` - Library function tests
- `Test-ReportConflicts.ps1` - Conflict reporting tests
- `Test-ForceCSV-Safe.ps1` - ForceCSV parameter validation
- `Test-MissingFiles-Columns.ps1` - Missing file column tests

**Python tests:**
- `test_csv_validate_repair.py` - CSV repair functionality
- `test_csv_escaped_comma.py` - Escaped comma handling
- `test_csv_comment_preservation.py` - Comment preservation
- `test_csv_quoted_comment.py` - Quoted comment edge cases
- `test_crc32_folder_calc.py` - Folder calculator tests
- 5 additional exotic CSV scenario tests

## Workflow Details

### Phase 1: Archive Old Logs
- Moves previous logs to `Archive/` subfolder with timestamps
- Prevents log directory clutter

### Phase 2: Calculate CRC32 Hashes
- Scans all files in `SourceFolderCRC` recursively
- Parallel processing with configurable throttle limit
- Creates `CRC:Size` candidate map for fast lookups

### Phase 3: Process Each CSV
- Reads CSV entries (expected files)
- Matches entries to candidates by CRC32
- Handles edge cases:
  - Multiple files with same CRC (picks best match by filename similarity)
  - Duplicate CRC entries in CSV (all variants must be found)
  - Files already in destination (skips gracefully)
  - Missing files (logs incomplete CSVs)

### Phase 4: Move Complete Sets
- If CSV is **COMPLETE** (all files found):
  - Creates folder named after CSV
  - Moves all matched files to folder
  - Moves CSV to folder
  - Moves folder to `CompletedFolder`
- If CSV is **INCOMPLETE**:
  - Leaves files in `SourceFolderCRC`
  - Leaves CSV in `RootFolder`
  - Logs missing files for manual review

### Phase 5: Cleanup
- Removes empty folders from `SourceFolderCRC`
- Final log summary

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-RootFolder` | `D:\ScanSorting\_01_CSV_Source\` | CSV files and logs location |
| `-SourceFolderCRC` | `D:\ScanSorting\_02_Image_Source\` | Downloaded files location |
| `-CompletedFolder` | `D:\ScanSorting\_99_Completed\` | Final destination for complete sets |
| `-LogFolder` | `D:\ScanSorting\_98_Logs\` | Log file directory |
| `-ThrottleLimit` | `4` | Parallel CRC threads (1-32) |
| `-DryRun` | (switch) | Preview mode - no file moves |

**Deprecated (kept for compatibility):**
- `-StagingFolder` - No longer used in current workflow

## Troubleshooting

### Files Not Matching Despite Correct CRC
- Check CSV encoding (must be UTF-8)
- Verify CRC values are 8 hex characters
- Run `CSV-Validate-Repair.py` on the CSV

### Slow CRC Calculation
- Increase `-ThrottleLimit` (try 8 or 16 for fast SSDs)
- Move files to faster storage
- Check disk I/O in Task Manager

### "Access Denied" Errors
- Ensure files aren't open in other programs
- Check folder permissions
- Run PowerShell as Administrator if needed

### CSV Parse Errors
```powershell
# Repair CSV automatically
python CSV-Validate-Repair.py broken.csv
```

## Advanced Usage

### Custom Conflict Analysis
```powershell
# Generate detailed conflict report
.\CRC-FileOrganizer-ReportConflicts.ps1 `
    -CsvPath "SetName.csv" `
    -SourceFolderCRC "D:\Downloads"
```

### Calculate CRC for Existing Files
```powershell
# Python utility for any folder
python CRC32_Folder_Calc.py "D:\MyFiles"
```

### Preview Mode for Testing
```powershell
# See exactly what would happen
.\CRC-FileOrganizer.ps1 -DryRun | Out-File preview.txt
```

## Performance

**Typical benchmarks:**
- CRC32 calculation: ~500 MB/s per thread on SSD
- 1000 files (~2 GB): ~30 seconds with `-ThrottleLimit 4`
- 10,000 files (~20 GB): ~5 minutes with `-ThrottleLimit 8`

## Architecture

### Dependencies
- **PowerShell**: Native cmdlets only (`Get-ChildItem`, `Move-Item`, `ForEach-Object -Parallel`)
- **Python**: Standard library only (`csv`, `hashlib`, `pathlib`)
- **No external binaries** required

### Key Design Decisions
1. **CRC32 over SHA256**: Faster, sufficient for filename matching (not security)
2. **Parallel processing**: Modern multi-core CPUs benefit from parallel hashing
3. **Self-contained scripts**: No external module dependencies for portability
4. **Dry-run by default**: Prevents accidental file operations

## Contributing

This repository is part of a larger PowerShell-Scripts collection that has been split for maintainability. For the original context:
- Original repo: [PowerShell-Scripts](https://github.com/albyofdoom/PowerShell-Scripts)

## License

Personal utility scripts - use at your own risk. No warranty provided.

## See Also

- `venv_readme.md` - Python virtual environment setup
- `Samples/` - Example CSV files
- `TestData/` - Test fixtures for automated tests
- Related repos:
  - `model-metadata-toolkit` - Model metadata gathering and web scraping
  - `brainbooks-organizer` - eBook metadata extraction and organization
