# scanner-crc-organizer

Production-grade CRC32-based file organization workflow for managing downloaded scanner sets with CSV metadata. This project originated as a modernized command line replacement for the functionality found in Hunter (aka HunterCSV).

Historical note: Most scanner csvs pre-date creation or wide adoption of csv standards in [RFC4180](https://datatracker.ietf.org/doc/html/rfc4180) which wasn't published until 2005, and the expansion and further defining of CSV standards by the [W3C in 2013](https://www.w3.org/TR/sparql11-results-csv-tsv/). The height of scanning as an internet sub-culture occurred during the late 1990s and early 2000s, though thre were pre-cursors and there are some remnants remaining to this day.

This context helps explain the heavy amount of CSV validation and repair tool included in this repo, as the CSVs follow a lot of different ad-hoc standards from that timeframe and a wide variety of text encoding types. It is strongly encouraged to use those tools to validate and repair CSVs before using them in the main workflow.

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

``` plaintext
Workspace Folder
  └── CSVFolder/         # CSV files and logs (aka RootFolder)
      └── *.csv          # CSV metadata files

  └── LogFolder/         # Timestamped Logs
      └── Archive/       # Archived logs

  └── SourceFolderCRC/   # Downloaded files to organize
      └── [files]

  └── CompletedFolder/   # Organized complete sets
      ├── SetName1/
      │   ├── SetName1.csv
      │   └── [matched files]
      └── SetName2/
```

## CSV Format

Expected CSV format (5 columns, no header row):

``` CSV
FileName,Size,CRC32,Path,Comment
image001.jpg,1234567,ABCD1234,optional/path,Optional comment
image002.jpg,2345678,EFGH5678,,
```

**Column details:**

- **FileName**: Expected filename (used for reference only, matching is by CRC and size)
- **Size**: File size in bytes (for matching validation in addition to CRC32)
- **CRC32**: 8-character hexadecimal CRC32 hash (case-insensitive)
- **Path**: Optional subdirectory path (often used)
- **Comment**: Optional notes (Uncommon, but preserved during repairs)

## Scripts

### Main Scripts

- **CRC-FileOrganizer.ps1** - Main workflow orchestrator
- **CRC-FileOrganizerLib.ps1** - Shared CRC calculation functions
- **CRC-FileOrganizer-ReportConflicts.ps1** - Detailed conflict analysis tool

### Python Utilities

- **CSV-Validate-Repair.py** - Repairs malformed CSVs, handles exotic encodings
-- **CRC32_Folder_Calc.py** - Standalone CRC32 calculator for folders

## Testing

Comprehensive test suite with 85% coverage:

```powershell
# Run full PowerShell test suite (default)
.\tests\run-crc-tests.ps1

# Quick validation (runs in seconds)
.\tests\run-crc-tests.ps1 -Quick

# Extended test scenarios
.\tests\run-crc-tests.ps1 -Extended

# Run ALL tests (Quick + Full + Extended + Library + Focused)
.\tests\run-crc-tests.ps1 -All

# Keep test data after run for inspection
.\tests\run-crc-tests.ps1 -Keep

# Or run individual test scripts directly
.\tests\Quick-Test-CRC.ps1
.\tests\Extended-CRC-Tests.ps1
.\tests\Test-CRCFileOrganizer.ps1

# Python CSV tests (requires pytest)
pytest tests/
```

**Note:** All test commands automatically return to the repo root directory after completion.

### Test Files

**PowerShell tests:**

- `Test-CRCFileOrganizer.ps1` - Main workflow tests
- `Test-CRCFileOrganizerLib.ps1` - Library function tests
- `Test-ReportConflicts.ps1` - Conflict reporting tests
- `Test-ForceCSV-Safe.ps1` - ForceCSV parameter validation
- `Test-MissingFiles-Columns.ps1` - Missing file column tests

New / updated tests:

- `Test-ConflictCompareAndForceMove.ps1` - Pester tests that validate `-ForceMoveFiles` behavior and `Compare-Conflicts` report generation (included in the full test runner).
- CI-friendly flags: `-AutoConfirmConflicts` and `-SkipCRCIfOver` were added to allow non-interactive runs when conflict CRC comparisons may be expensive.

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
 - Archive includes `.log`, `.csv`, `.json`, and `.txt` files from the `LogFolder` root (excluding Archive subfolders)

### Phase 2: Calculate CRC32 Hashes

- Scans all files in `SourceFolderCRC` recursively
- Parallel processing with configurable throttle limit
- Creates `CRC:Size` candidate map for fast lookups

### Phase 3: Process Each CSV

- Reads CSV entries (expected files)
- Matches entries to candidates by CRC32 and Size
- Handles edge cases:
  - Multiple files with same CRC (Matches both Size and CRC32)
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

### Conflict Handling (hybrid workflow)

- During file moves, when a destination file already exists for a matched entry the script records a conflict rather than overwriting. Conflicts are collected per-CSV and flushed to small per-CSV temp CSV files in `LogFolder` named `conflicts_<CSVBase>_<timestamp>.csv`.
- After processing all CSVs the script consolidates per-CSV conflict files into a single combined CSV `conflicts_combined_<timestamp>.csv`. If `-CompareConflicts` is specified the script runs a single `Compare-Conflicts` pass over the combined CSV and produces a final `conflict_report_<timestamp>.csv` that includes:
  - Original CSV columns (`FileName,Size,CRC32,Path,Comment`) plus
  - `SourceFullPath`, `DestinationPath`, `SourceSize`, `DestSize`, `SizeMatch`, `SourceCRC`, `DestCRC`, `CRCMatch`, and `Notes` (human-friendly summary).
- The compare pass computes CRCs in parallel with a configurable throttle (`-ConflictThrottleLimit`). If the combined row count exceeds `-SkipCRCIfOver` the script will prompt before running full CRC comparisons unless `-AutoConfirmConflicts` is set.

### DryRun and Conflict Behavior

- When `-DryRun` is set the script will still create consolidated conflict CSVs but will skip running the CRC comparisons; logs will note the consolidated temp file location. This lets you inspect potential conflicts without performing expensive CRC calculations.

### ForceCSV and ForceMoveFiles interaction

- `-ForceCSV` moves both files and CSVs even when incomplete (accepts exact base names and wildcard patterns). `-ForceMoveFiles` instead moves matched files but intentionally leaves the CSV in `RootFolder` so you can track incomplete sets. These two switches are mutually exclusive — the script will error if both are supplied.

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
| `-ThrottleLimit` | `12` | Parallel CRC threads (1-32) |
| `-DryRun` | (switch) | Preview mode - no file moves |

Additional parameters (new):

| `-ForceMoveFiles` | (switch) | Move matched files to `CompletedFolder` even if the CSV is incomplete; the CSV remains in `RootFolder` for tracking. When `-ForceMoveFiles` is used and a missing-files report is generated, the missing-files CSV will be written into the per-CSV folder under `CompletedFolder` (so it travels with the moved files) instead of being left in the `LogFolder`. |
| `-CompareConflicts` | (switch) | Consolidate per-CSV conflict entries and run a single pass to compare source vs destination (Size+CRC). Produces `conflict_report_*.csv` in `LogFolder`. |
| `-ConflictThrottleLimit` | `4` | Throttle limit for CRC calculations run by the `Compare-Conflicts` routine. |
| `-AutoConfirmConflicts` | (switch) | Bypass interactive confirmation when the combined conflict rows exceed `-SkipCRCIfOver` (useful for CI). |
| `-SkipCRCIfOver` | `500` | Threshold of combined conflict rows above which the script prompts before running full CRC comparisons. |

**Deprecated (kept for compatibility):**

- `-StagingFolder` - No longer used in current workflow

## Troubleshooting

### Files Not Matching Despite Correct CRC

- Check CSV encoding (must be UTF-8)
- Verify CRC values are 8 hex characters (repair script optionally converts to uppercase)
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
# Generate detailed conflict report to determine if a file is used either multiple times within a csv or across multiple csvs (overlaps)
.\CRC-FileOrganizer-ReportConflicts.ps1 `
    -CsvPath "SetName.csv" `
    -SourceFolderCRC "D:\Downloads"
```

### Calculate CRC for Existing Files

```powershell
# Python utility for any folder used for fater manual matching or logging
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

This repository is part of a larger PowerShell-Scripts collection that has been split for maintainability.

## License

Personal utility scripts - use at your own risk. No warranty provided.

## See Also

- `venv_readme.md` - Python virtual environment setup
- `Samples/` - Example CSV files
- `TestData/` - Test fixtures for automated tests
