<#
.SYNOPSIS
    Unit tests for CRC-FileOrganizer-ReportConflicts.ps1

.DESCRIPTION
    Tests the conflict reporting script which simulates file assignment
    and detects conflicts between multiple CSVs:
    - Conflict detection (multiple CSVs claiming same file)
    - Shared CRC handling
    - Report generation (CSV and JSON)
    - Archive functionality
    - Missing file detection vs conflicts
    
.EXAMPLE
    .\Test-ReportConflicts.ps1
#>

param(
    [string]$TestDataPath,
    [string]$ScriptPath
)

$ErrorActionPreference = 'Stop'

# Resolve paths relative to repository root (tests/ is one level down)
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $TestDataPath) {
    $TestDataPath = Join-Path $RepoRoot 'TestData' 'ConflictTests'
}
if (-not $ScriptPath) {
    $ScriptPath = Join-Path $RepoRoot 'CSV_Processing' 'CRC-FileOrganizer-ReportConflicts.ps1'
}

# Test results tracking
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Errors = @()
}

Function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )
    
    if ($Passed) {
        Write-Host "✓ PASS: $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "  $Message" -ForegroundColor Gray }
        $script:TestResults.Passed++
    }
    else {
        Write-Host "✗ FAIL: $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "  $Message" -ForegroundColor Yellow }
        $script:TestResults.Failed++
        $script:TestResults.Errors += "$TestName`: $Message"
    }
}

# Verify script exists
if (!(Test-Path $ScriptPath)) {
    throw "Script not found: $ScriptPath"
}

# Create test environment
if (Test-Path $TestDataPath) {
    Remove-Item $TestDataPath -Recurse -Force
}
New-Item -Path $TestDataPath -ItemType Directory -Force | Out-Null

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "CRC-FileOrganizer-ReportConflicts.ps1 Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Load library for creating test data
. (Join-Path $PSScriptRoot '..\Functions\CRC-FileOrganizerLib.ps1')

# ============================================
# Setup Test Data
# ============================================
Write-Host "Setting up test data..." -ForegroundColor Cyan

$sourceDir = Join-Path $TestDataPath "source"
$csvDir = Join-Path $TestDataPath "csvs"
$logsDir = Join-Path $TestDataPath "logs"

New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
New-Item -Path $csvDir -ItemType Directory -Force | Out-Null
New-Item -Path $logsDir -ItemType Directory -Force | Out-Null

# Create test files with known content
$file1 = Join-Path $sourceDir "shared.txt"
$file2 = Join-Path $sourceDir "unique_a.txt"
$file3 = Join-Path $sourceDir "unique_b.txt"
$file4 = Join-Path $sourceDir "duplicate1.txt"
$file5 = Join-Path $sourceDir "duplicate2.txt"

"Shared content" | Out-File -FilePath $file1 -Encoding UTF8 -NoNewline
"Unique A" | Out-File -FilePath $file2 -Encoding UTF8 -NoNewline
"Unique B" | Out-File -FilePath $file3 -Encoding UTF8 -NoNewline
"Duplicate" | Out-File -FilePath $file4 -Encoding UTF8 -NoNewline
"Duplicate" | Out-File -FilePath $file5 -Encoding UTF8 -NoNewline

# Get CRCs
$crc1 = Get-CRC32Hash -FilePath $file1
$size1 = (Get-Item -LiteralPath $file1).Length
$crc2 = Get-CRC32Hash -FilePath $file2
$size2 = (Get-Item -LiteralPath $file2).Length
$crc3 = Get-CRC32Hash -FilePath $file3
$size3 = (Get-Item -LiteralPath $file3).Length
$crc4 = Get-CRC32Hash -FilePath $file4
$size4 = (Get-Item -LiteralPath $file4).Length

Write-Host "  Created test files:" -ForegroundColor Gray
Write-Host "    shared.txt: $crc1 ($size1 bytes)" -ForegroundColor Gray
Write-Host "    unique_a.txt: $crc2 ($size2 bytes)" -ForegroundColor Gray
Write-Host "    unique_b.txt: $crc3 ($size3 bytes)" -ForegroundColor Gray
Write-Host "    duplicate1.txt: $crc4 ($size4 bytes)" -ForegroundColor Gray
Write-Host "    duplicate2.txt: $crc4 ($size4 bytes)" -ForegroundColor Gray

# ============================================
# TEST SCENARIO 1: No Conflicts
# ============================================
Write-Host "`n--- Test 1: No Conflicts (Each CSV claims unique files) ---" -ForegroundColor Magenta

$csv1 = Join-Path $csvDir "setA.csv"
@"
FileName,Size,CRC32,Path
unique_a.txt,$size2,$crc2,\test\
"@ | Out-File -FilePath $csv1 -Encoding UTF8

$csv2 = Join-Path $csvDir "setB.csv"
@"
FileName,Size,CRC32,Path
unique_b.txt,$size3,$crc3,\test\
"@ | Out-File -FilePath $csv2 -Encoding UTF8

# Run script
& $ScriptPath -RootFolder $csvDir -SourceFolderCRC $sourceDir -ReportConflictsPath $logsDir -ThrottleLimit 2

# Test 1: No conflict CSV should be created (or empty)
$conflictFiles = Get-ChildItem -Path $logsDir -Filter "conflicts-*.csv" -ErrorAction SilentlyContinue
if ($conflictFiles) {
    $conflictData = Import-Csv $conflictFiles[0].FullName
    $conflictCount = $conflictData.Count
}
else {
    $conflictCount = 0
}

Write-TestResult -TestName "No conflicts detected" `
    -Passed ($conflictCount -eq 0) `
    -Message "Conflict count: $conflictCount (expected 0)"

# Test 2: Summary JSON created
$summaryFiles = Get-ChildItem -Path $logsDir -Filter "conflicts-summary-*.json" -ErrorAction SilentlyContinue
Write-TestResult -TestName "Summary JSON created" `
    -Passed ($null -ne $summaryFiles) `
    -Message "Found summary file: $($summaryFiles[0].Name)"

if ($summaryFiles) {
    $summary = Get-Content $summaryFiles[0].FullName -Raw | ConvertFrom-Json
    Write-TestResult -TestName "Summary contains correct CSV count" `
        -Passed ($summary.TotalCSVs -eq 2) `
        -Message "TotalCSVs: $($summary.TotalCSVs)"
}

# Clean logs for next test
Get-ChildItem -Path $logsDir -File | Remove-Item -Force

# ============================================
# TEST SCENARIO 2: Conflicts (Both CSVs claim same file)
# ============================================
Write-Host "`n--- Test 2: Conflicts (Multiple CSVs claim same file) ---" -ForegroundColor Magenta

$csv3 = Join-Path $csvDir "setC.csv"
@"
FileName,Size,CRC32,Path
shared_c.txt,$size1,$crc1,\test\
"@ | Out-File -FilePath $csv3 -Encoding UTF8

$csv4 = Join-Path $csvDir "setD.csv"
@"
FileName,Size,CRC32,Path
shared_d.txt,$size1,$crc1,\test\
"@ | Out-File -FilePath $csv4 -Encoding UTF8

# Run script
& $ScriptPath -RootFolder $csvDir -SourceFolderCRC $sourceDir -ReportConflictsPath $logsDir -ThrottleLimit 2

# Test 3: Conflict detected
$conflictFiles = Get-ChildItem -Path $logsDir -Filter "conflicts-*.csv" -ErrorAction SilentlyContinue
if ($conflictFiles) {
    $conflictData = Import-Csv $conflictFiles[0].FullName
    $conflictCount = $conflictData.Count
}
else {
    $conflictCount = 0
}

Write-TestResult -TestName "Conflict detected" `
    -Passed ($conflictCount -ge 1) `
    -Message "Conflict count: $conflictCount (expected at least 1)"

# Test 4: ClaimedBy field populated
if ($conflictData) {
    $firstConflict = $conflictData[0]
    $hasClaimedBy = -not [string]::IsNullOrWhiteSpace($firstConflict.ClaimedBy)
    Write-TestResult -TestName "ClaimedBy field populated" `
        -Passed $hasClaimedBy `
        -Message "ClaimedBy: $($firstConflict.ClaimedBy)"
}

# Test 5: Summary reflects conflict count
$summaryFiles = Get-ChildItem -Path $logsDir -Filter "conflicts-summary-*.json" -ErrorAction SilentlyContinue
if ($summaryFiles) {
    $summary = Get-Content $summaryFiles[0].FullName -Raw | ConvertFrom-Json
    Write-TestResult -TestName "Summary shows conflicts" `
        -Passed ($summary.Conflicts -ge 1) `
        -Message "Conflicts: $($summary.Conflicts)"
}

# Clean logs
Get-ChildItem -Path $logsDir -File | Remove-Item -Force

# ============================================
# TEST SCENARIO 3: Missing Files (Not Conflicts)
# ============================================
Write-Host "`n--- Test 3: Missing Files (Should not appear in conflict report) ---" -ForegroundColor Magenta

$csv5 = Join-Path $csvDir "setE.csv"
@"
FileName,Size,CRC32,Path
missing1.txt,999,DEADBEEF,\test\
missing2.txt,888,CAFEBABE,\test\
"@ | Out-File -FilePath $csv5 -Encoding UTF8

# Run script
& $ScriptPath -RootFolder $csvDir -SourceFolderCRC $sourceDir -ReportConflictsPath $logsDir -ThrottleLimit 2

# Test 6: Missing files excluded from conflict report
$conflictFiles = Get-ChildItem -Path $logsDir -Filter "conflicts-*.csv" -ErrorAction SilentlyContinue
if ($conflictFiles) {
    $conflictData = Import-Csv $conflictFiles[0].FullName
    # Filter for NotFound reason - these should not be in conflict report
    $notFoundInReport = $conflictData | Where-Object { $_.Reason -eq 'NotFound' }
    Write-TestResult -TestName "Missing files excluded from conflicts" `
        -Passed ($null -eq $notFoundInReport -or $notFoundInReport.Count -eq 0) `
        -Message "NotFound entries in report: $($notFoundInReport.Count) (expected 0)"
}
else {
    # No conflicts = correct behavior
    Write-TestResult -TestName "Missing files excluded from conflicts" `
        -Passed $true `
        -Message "No conflict report (correct - missing files don't create conflicts)"
}

# Clean logs
Get-ChildItem -Path $logsDir -File | Remove-Item -Force

# ============================================
# TEST SCENARIO 4: Duplicate CRCs (Two files, two CSVs)
# ============================================
Write-Host "`n--- Test 4: Duplicate CRCs (Multiple candidates available) ---" -ForegroundColor Magenta

$csv6 = Join-Path $csvDir "setF.csv"
@"
FileName,Size,CRC32,Path
dup_f.txt,$size4,$crc4,\test\
"@ | Out-File -FilePath $csv6 -Encoding UTF8

$csv7 = Join-Path $csvDir "setG.csv"
@"
FileName,Size,CRC32,Path
dup_g.txt,$size4,$crc4,\test\
"@ | Out-File -FilePath $csv7 -Encoding UTF8

# Run script
& $ScriptPath -RootFolder $csvDir -SourceFolderCRC $sourceDir -ReportConflictsPath $logsDir -ThrottleLimit 2

# Test 7: Both files assigned (2 candidates, 2 CSVs)
$conflictFiles = Get-ChildItem -Path $logsDir -Filter "conflicts-*.csv" -ErrorAction SilentlyContinue
if ($conflictFiles) {
    $conflictData = Import-Csv $conflictFiles[0].FullName
    $conflictCount = $conflictData.Count
}
else {
    $conflictCount = 0
}

Write-TestResult -TestName "Duplicate CRCs handled (no conflict)" `
    -Passed ($conflictCount -eq 0) `
    -Message "Conflict count: $conflictCount (2 files available, 2 CSVs = no conflict)"

# Clean logs
Get-ChildItem -Path $logsDir -File | Remove-Item -Force

# ============================================
# TEST SCENARIO 5: Three CSVs, One File (Definite Conflict)
# ============================================
Write-Host "`n--- Test 5: Three CSVs claiming same file (definite conflict) ---" -ForegroundColor Magenta

$csv8 = Join-Path $csvDir "setH.csv"
@"
FileName,Size,CRC32,Path
shared_h.txt,$size1,$crc1,\test\
"@ | Out-File -FilePath $csv8 -Encoding UTF8

$csv9 = Join-Path $csvDir "setI.csv"
@"
FileName,Size,CRC32,Path
shared_i.txt,$size1,$crc1,\test\
"@ | Out-File -FilePath $csv9 -Encoding UTF8

$csv10 = Join-Path $csvDir "setJ.csv"
@"
FileName,Size,CRC32,Path
shared_j.txt,$size1,$crc1,\test\
"@ | Out-File -FilePath $csv10 -Encoding UTF8

# Run script
& $ScriptPath -RootFolder $csvDir -SourceFolderCRC $sourceDir -ReportConflictsPath $logsDir -ThrottleLimit 2

# Test 8: Multiple conflicts detected
$conflictFiles = Get-ChildItem -Path $logsDir -Filter "conflicts-*.csv" -ErrorAction SilentlyContinue
if ($conflictFiles) {
    $conflictData = Import-Csv $conflictFiles[0].FullName
    $conflictCount = $conflictData.Count
}
else {
    $conflictCount = 0
}

Write-TestResult -TestName "Multiple conflicts detected" `
    -Passed ($conflictCount -ge 2) `
    -Message "Conflict count: $conflictCount (expected at least 2 from 3 CSVs, 1 file)"

# Clean logs
Get-ChildItem -Path $logsDir -File | Remove-Item -Force

# ============================================
# TEST SCENARIO 6: Archive Existing Logs
# ============================================
Write-Host "`n--- Test 6: Archive existing log files ---" -ForegroundColor Magenta

# Create dummy existing log files
$dummyLog1 = Join-Path $logsDir "old_report.log"
$dummyLog2 = Join-Path $logsDir "old_conflicts.csv"
"Old log" | Out-File -FilePath $dummyLog1 -Encoding UTF8
"Old CSV" | Out-File -FilePath $dummyLog2 -Encoding UTF8

# Run script (should archive existing files)
& $ScriptPath -RootFolder $csvDir -SourceFolderCRC $sourceDir -ReportConflictsPath $logsDir -ThrottleLimit 2

# Test 9: Archive folder created
$archiveFolders = Get-ChildItem -Path $logsDir -Directory -Filter "Archive" -ErrorAction SilentlyContinue
Write-TestResult -TestName "Archive folder created" `
    -Passed ($null -ne $archiveFolders) `
    -Message "Archive folder exists"

# Test 10: Old files moved to archive
if ($archiveFolders) {
    $archivedFiles = Get-ChildItem -Path $archiveFolders[0].FullName -Recurse -File
    $hasOldLog = $archivedFiles | Where-Object { $_.Name -eq 'old_report.log' }
    $hasOldCSV = $archivedFiles | Where-Object { $_.Name -eq 'old_conflicts.csv' }
    
    Write-TestResult -TestName "Old files archived" `
        -Passed ($null -ne $hasOldLog -and $null -ne $hasOldCSV) `
        -Message "Found archived files: $($archivedFiles.Count)"
}

# Clean logs
Get-ChildItem -Path $logsDir -File | Remove-Item -Force

# ============================================
# TEST SCENARIO 7: DryRun Mode
# ============================================
Write-Host "`n--- Test 7: DryRun mode ---" -ForegroundColor Magenta

# Create simple CSV
$csv11 = Join-Path $csvDir "dryrun.csv"
@"
FileName,Size,CRC32,Path
unique_a.txt,$size2,$crc2,\test\
"@ | Out-File -FilePath $csv11 -Encoding UTF8

# Run in DryRun mode
& $ScriptPath -RootFolder $csvDir -SourceFolderCRC $sourceDir -ReportConflictsPath $logsDir -DryRun -ThrottleLimit 2

# Test 11: Reports still generated in DryRun
$reportFiles = Get-ChildItem -Path $logsDir -Filter "conflicts-*.csv" -ErrorAction SilentlyContinue
$summaryFiles = Get-ChildItem -Path $logsDir -Filter "conflicts-summary-*.json" -ErrorAction SilentlyContinue

Write-TestResult -TestName "DryRun mode generates reports" `
    -Passed ($summaryFiles.Count -gt 0) `
    -Message "Summary files: $($summaryFiles.Count)"

# Test 12: DryRun flag set in results
if ($reportFiles -and $reportFiles.Count -gt 0) {
    $reportData = Import-Csv $reportFiles[0].FullName
    if ($reportData.Count -gt 0) {
        $dryRunFlag = $reportData[0].DryRun
        Write-TestResult -TestName "DryRun flag set in report" `
            -Passed ($dryRunFlag -eq 'True') `
            -Message "DryRun: $dryRunFlag"
    }
}

# Clean logs
Get-ChildItem -Path $logsDir -File | Remove-Item -Force

# ============================================
# TEST SCENARIO 8: CSV Output Structure
# ============================================
Write-Host "`n--- Test 8: Conflict CSV output structure ---" -ForegroundColor Magenta

# Create conflict scenario
$csv12 = Join-Path $csvDir "struct1.csv"
$csv13 = Join-Path $csvDir "struct2.csv"

@"
FileName,Size,CRC32,Path
shared_struct.txt,$size1,$crc1,\test\
"@ | Out-File -FilePath $csv12 -Encoding UTF8

@"
FileName,Size,CRC32,Path
shared_struct2.txt,$size1,$crc1,\test\
"@ | Out-File -FilePath $csv13 -Encoding UTF8

# Run script
& $ScriptPath -RootFolder $csvDir -SourceFolderCRC $sourceDir -ReportConflictsPath $logsDir -ThrottleLimit 2

# Test 13: Check CSV structure
$conflictFiles = Get-ChildItem -Path $logsDir -Filter "conflicts-*.csv" -ErrorAction SilentlyContinue
if ($conflictFiles) {
    $conflictCSV = Import-Csv $conflictFiles[0].FullName
    $firstEntry = $conflictCSV[0]
    
    $hasCSVFile = $null -ne $firstEntry.CSVFile
    $hasEntryIndex = $null -ne $firstEntry.EntryIndex
    $hasExpectedCRC = $null -ne $firstEntry.ExpectedCRC
    $hasExpectedSize = $null -ne $firstEntry.ExpectedSize
    $hasReason = $null -ne $firstEntry.Reason
    $hasClaimedBy = $null -ne $firstEntry.ClaimedBy
    
    Write-TestResult -TestName "Conflict CSV has required columns" `
        -Passed ($hasCSVFile -and $hasEntryIndex -and $hasExpectedCRC -and $hasExpectedSize -and $hasReason -and $hasClaimedBy) `
        -Message "All required columns present"
}

# ============================================
# Test Summary
# ============================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed: $($script:TestResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($script:TestResults.Failed)" -ForegroundColor $(if ($script:TestResults.Failed -eq 0) { "Green" } else { "Red" })

if ($script:TestResults.Failed -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $script:TestResults.Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

# Cleanup
Write-Host "`nCleaning up test data..." -ForegroundColor Yellow
try {
    Set-Location (Split-Path $TestDataPath -Parent)
    Start-Sleep -Milliseconds 500
    Remove-Item $TestDataPath -Recurse -Force -ErrorAction Stop
    Write-Host "✓ Test data cleaned up" -ForegroundColor Green
}
catch {
    Write-Host "⚠ Could not clean test data: $_" -ForegroundColor Yellow
}

if ($script:TestResults.Failed -eq 0) {
    Write-Host "`n✓ ALL TESTS PASSED!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n✗ SOME TESTS FAILED!" -ForegroundColor Red
    exit 1
}
