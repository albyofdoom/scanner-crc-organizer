<#
.SYNOPSIS
    Simple tests for ForceCSV behavior (safe mode)

.DESCRIPTION
    Creates a temporary workspace, runs `CRC-FileOrganizer.ps1` with -ForceCSV and validates
    that by default a CSV with zero matches is NOT moved, and that when run with
    -ForceCSVMoveEmpty the CSV is moved to Completed. Missing-file report should always be generated.
#>

param()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPath = Join-Path $scriptRoot '..\CSV_Processing\CRC-FileOrganizer.ps1' | Resolve-Path -ErrorAction Stop
$scriptPath = $scriptPath.Path

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$work = Join-Path $env:TEMP "CRCForceTest_$timestamp"

# Prepare workspace
$csvDir = Join-Path $work '_01_CSV_Source'
$srcDir = Join-Path $work '_02_Image_Source'
$logDir = Join-Path $work '_98_Logs'
$completedDir = Join-Path $work '_99_Completed'

New-Item -Path $csvDir -ItemType Directory -Force | Out-Null
New-Item -Path $srcDir -ItemType Directory -Force | Out-Null
New-Item -Path $logDir -ItemType Directory -Force | Out-Null
New-Item -Path $completedDir -ItemType Directory -Force | Out-Null

# Create a CSV with a CRC that won't be found
$csvName = 'force_test.csv'
$csvPath = Join-Path $csvDir $csvName
# CSV header and one entry: Filename,Size,CRC32,Path
"FileName,Size,CRC32,Path" | Out-File -FilePath $csvPath -Encoding utf8
"notfound.jpg,1234,DEADBEEF00112233,subfolder" | Out-File -FilePath $csvPath -Encoding utf8 -Append

Write-Host "Running test: ForceCSV default (should NOT move empty CSV)" -ForegroundColor Cyan
& $scriptPath -RootFolder ("$csvDir\") -SourceFolderCRC ("$srcDir\") -LogFolder ("$logDir\") -CompletedFolder ("$completedDir\") -ThrottleLimit 1 -ForceCSV @('force_test')

# Check CSV still in source
$csvStillThere = Test-Path -LiteralPath $csvPath
if (-not $csvStillThere) {
    Write-Host "FAIL: CSV was moved when it should not have been" -ForegroundColor Red
    exit 2
}
else {
    Write-Host "PASS: CSV remained in source as expected" -ForegroundColor Green
}

# Check missing-files report created
$missing = Get-ChildItem -Path $logDir -Filter "*_missing_files.csv" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $missing) {
    Write-Host "FAIL: Missing-files report not created" -ForegroundColor Red
    exit 3
}
else {
    Write-Host "PASS: Missing-files report created: $($missing.Name)" -ForegroundColor Green
}

# Now run with ForceCSVMoveEmpty to force moving empty CSVs
Write-Host "Running test: ForceCSVMoveEmpty (should move CSV even with zero matches)" -ForegroundColor Cyan
& $scriptPath -RootFolder ("$csvDir\") -SourceFolderCRC ("$srcDir\") -LogFolder ("$logDir\") -CompletedFolder ("$completedDir\") -ThrottleLimit 1 -ForceCSV @('force_test') -ForceCSVMoveEmpty

# Check CSV moved to completed
$csvDest = Join-Path (Join-Path $completedDir 'force_test') $csvName
if (Test-Path -LiteralPath $csvDest) {
    Write-Host "PASS: CSV moved to completed when -ForceCSVMoveEmpty supplied" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "FAIL: CSV was not moved to completed despite -ForceCSVMoveEmpty" -ForegroundColor Red
    exit 4
}
