<#
.SYNOPSIS
    Test that the generated `_missing_files.csv` uses the expected column order.

.DESCRIPTION
    Creates a temporary workspace, runs `CRC-FileOrganizer.ps1` with one CSV entry
    that will not be found in the source. Validates the `_missing_files.csv` header
    column order is: FileName, Size, CRC32, Path, Comment, ExpectedPath, OriginalCSV, TimeStamp
#>

param()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPath = Join-Path $scriptRoot '..\CRC-FileOrganizer.ps1' | Resolve-Path -ErrorAction Stop
$scriptPath = $scriptPath.Path

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$work = Join-Path $env:TEMP "CRCMissingColsTest_$timestamp"

# Prepare workspace
$csvDir = Join-Path $work '_01_CSV_Source'
$srcDir = Join-Path $work '_02_Image_Source'
$logDir = Join-Path $work '_98_Logs'
$completedDir = Join-Path $work '_99_Completed'

New-Item -Path $csvDir -ItemType Directory -Force | Out-Null
New-Item -Path $srcDir -ItemType Directory -Force | Out-Null
New-Item -Path $logDir -ItemType Directory -Force | Out-Null
New-Item -Path $completedDir -ItemType Directory -Force | Out-Null

# Create a file that WILL be found and one entry that will be missing so the script
# generates a partial-match _missing_files.csv report (report only created for partial matches)
$csvName = 'missing_cols_test.csv'
$csvPath = Join-Path $csvDir $csvName

# Create a sample file in source that the script should match by CRC
$sampleFileName = 'found.jpg'
$sampleFilePath = Join-Path $srcDir $sampleFileName
[System.IO.File]::WriteAllText($sampleFilePath, 'sample-data-for-crc')

# Dot-source the CRC helper library to compute the CRC for our sample file
$libPath = Join-Path (Split-Path -Parent $scriptPath) '..\CRC-FileOrganizerLib.ps1' | Resolve-Path -ErrorAction SilentlyContinue
if ($libPath) { . $libPath }
else { Write-Host "Warning: CRC library not found at expected location; test may fail" -ForegroundColor Yellow }

# Ensure CRC type available and compute CRC for sample file
try {
    Add-CRC32Type
    $sampleCRC = Get-CRC32Hash -FilePath $sampleFilePath
    $sampleSize = (Get-Item -LiteralPath $sampleFilePath).Length
}
catch {
    Write-Host "Warning: Could not compute CRC for sample file: $_" -ForegroundColor Yellow
    # Fallback: use placeholder CRC (may cause test to fail)
    $sampleCRC = '00000000'
    $sampleSize = (Get-Item -LiteralPath $sampleFilePath).Length
}

# CSV header and two entries: one that will be matched, one that will be missing
"FileName,Size,CRC32,Path,Comment" | Out-File -FilePath $csvPath -Encoding utf8
"$sampleFileName,$sampleSize,$sampleCRC,subfolder,found-entry" | Out-File -FilePath $csvPath -Encoding utf8 -Append
"notfound.jpg,1234,DEADBEEF,subfolder,reason" | Out-File -FilePath $csvPath -Encoding utf8 -Append

Write-Host "Running CRC-FileOrganizer to generate missing-files report" -ForegroundColor Cyan
& $scriptPath -RootFolder ("$csvDir\") -SourceFolderCRC ("$srcDir\") -LogFolder ("$logDir\") -CompletedFolder ("$completedDir") -ThrottleLimit 1

# Find generated missing-files CSV
$missing = Get-ChildItem -Path $logDir -Filter "*_missing_files.csv" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $missing) {
    Write-Host "FAIL: Missing-files report not created" -ForegroundColor Red
    exit 2
}

# Import the CSV and inspect header/property order
$rows = Import-Csv -Path $missing.FullName -Encoding UTF8
if ($rows.Count -eq 0) {
    Write-Host "FAIL: Missing-files CSV contains no rows" -ForegroundColor Red
    exit 3
}

$headerNames = $rows[0].PSObject.Properties | ForEach-Object { $_.Name }
$expected = @('FileName','Size','CRC32','Path','Comment','ExpectedPath','OriginalCSV','TimeStamp')

if ($headerNames.Count -ne $expected.Count) {
    Write-Host "FAIL: Header column count mismatch. Found: $($headerNames -join ', ')" -ForegroundColor Red
    exit 4
}

for ($i=0; $i -lt $expected.Count; $i++) {
    if ($headerNames[$i] -ne $expected[$i]) {
        Write-Host "FAIL: Header mismatch at position $i. Expected '$($expected[$i])' but found '$($headerNames[$i])'" -ForegroundColor Red
        exit 5
    }
}

Write-Host "PASS: Missing-files CSV header columns in expected order: $($expected -join ', ')" -ForegroundColor Green
exit 0
