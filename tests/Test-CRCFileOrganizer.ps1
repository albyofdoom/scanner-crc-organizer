<#
.SYNOPSIS
    Automated test suite for CRC-FileOrganizer.ps1

.DESCRIPTION
    Extracts test data, runs CRC-FileOrganizer.ps1, and validates all expected outcomes
    against the test scenarios documented in TestData\TestingData.md

.PARAMETER TestDataPath
    Path to the TestData folder containing TestSourceData.zip

.PARAMETER WorkingPath
    Path where test files will be extracted and processed (will be cleaned each run)

.PARAMETER ScriptPath
    Path to the CRC-FileOrganizer.ps1 script to test

.PARAMETER KeepTestData
    If specified, test data will not be cleaned up after test run (for debugging)

.EXAMPLE
    .\Test-CRCFileOrganizer.ps1
    
.EXAMPLE
    .\Test-CRCFileOrganizer.ps1 -KeepTestData
#>

param(
    [string]$TestDataPath,
    [string]$WorkingPath,
    [string]$ScriptPath,
    [switch]$KeepTestData
)

# Resolve paths relative to repository root (tests/ is one level down)
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $TestDataPath) {
    $TestDataPath = Join-Path $RepoRoot 'TestData'
}
if (-not $WorkingPath) {
    $WorkingPath = Join-Path $RepoRoot 'TestData' 'TestWorking'
}
if (-not $ScriptPath) {
    $ScriptPath = Join-Path $RepoRoot 'CSV_Processing' 'CRC-FileOrganizer.ps1'
}

$ErrorActionPreference = 'Stop'

# Test results tracking
$script:TestResults = @{
    Passed = @()
    Failed = @()
    Warnings = @()
    StartTime = Get-Date
}

Function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
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
        $script:TestResults.Passed += $TestName
    }
    else {
        Write-Host "✗ FAIL: $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "  $Message" -ForegroundColor Yellow }
        $script:TestResults.Failed += $TestName
    }
}

Function Write-TestWarning {
    param([string]$Message)
    Write-Host "⚠ WARNING: $Message" -ForegroundColor Yellow
    $script:TestResults.Warnings += $Message
}

Function Test-PathExists {
    param(
        [string]$Path,
        [string]$Description,
        [switch]$ShouldNotExist
    )
    
    $exists = Test-Path -LiteralPath $Path
    if ($ShouldNotExist) {
        Test-TestResult -TestName $Description -Passed (-not $exists) -Message "Path: $Path"
    }
    else {
        Test-TestResult -TestName $Description -Passed $exists -Message "Path: $Path"
    }
    return $exists
}

Function Test-FileCount {
    param(
        [string]$Path,
        [int]$ExpectedCount,
        [string]$Description,
        [string]$Filter = "*"
    )
    
    if (Test-Path -LiteralPath $Path) {
        $actualCount = (Get-ChildItem -LiteralPath $Path -Filter $Filter -Recurse -File).Count
        $passed = $actualCount -eq $ExpectedCount
        Write-TestResult -TestName $Description -Passed $passed -Message "Expected: $ExpectedCount, Actual: $actualCount"
        return $actualCount
    }
    else {
        Write-TestResult -TestName $Description -Passed $false -Message "Path does not exist: $Path"
        return 0
    }
}

Function Test-LogContains {
    param(
        [string]$LogPath,
        [string]$Pattern,
        [string]$Description
    )
    
    if (Test-Path -LiteralPath $LogPath) {
        $content = Get-Content -LiteralPath $LogPath -Raw
        $found = $content -match $Pattern
        Write-TestResult -TestName $Description -Passed $found -Message "Pattern: $Pattern"
        return $found
    }
    else {
        Write-TestResult -TestName $Description -Passed $false -Message "Log file not found: $LogPath"
        return $false
    }
}

# ============================================
# Main Test Execution
# ============================================

Write-TestHeader "CRC-FileOrganizer.ps1 Automated Test Suite"

# Validate prerequisites
Write-Host "Validating prerequisites..." -ForegroundColor Cyan
if (!(Test-Path $ScriptPath)) {
    throw "Script not found: $ScriptPath"
}
Write-Host "✓ Script found: $ScriptPath" -ForegroundColor Green

if (!(Test-Path "$TestDataPath\TestSourceData.zip")) {
    throw "Test data zip not found: $TestDataPath\TestSourceData.zip"
}
Write-Host "✓ Test data found: $TestDataPath\TestSourceData.zip" -ForegroundColor Green

# Clean and prepare working directory
Write-TestHeader "Preparing Test Environment"
if (Test-Path $WorkingPath) {
    Write-Host "Cleaning existing test directory..." -ForegroundColor Yellow
    Remove-Item -Path $WorkingPath -Recurse -Force
}
New-Item -Path $WorkingPath -ItemType Directory -Force | Out-Null
Write-Host "✓ Created working directory: $WorkingPath" -ForegroundColor Green

# Extract test data
Write-Host "Extracting test data..." -ForegroundColor Cyan
Expand-Archive -Path "$TestDataPath\TestSourceData.zip" -DestinationPath $WorkingPath -Force
Write-Host "✓ Test data extracted" -ForegroundColor Green

# Ensure required folders exist (in case zip doesn't include empty folders)
@('_98_Logs', '_99_Completed') | ForEach-Object {
    $folder = Join-Path $WorkingPath $_
    if (-not (Test-Path $folder)) { 
        New-Item $folder -ItemType Directory -Force | Out-Null
        Write-Host "  Created missing folder: $_" -ForegroundColor Gray
    }
}

# Verify extraction structure
$sourceDir = "$WorkingPath\_02_Image_Source"
$csvDir = "$WorkingPath\_01_CSV_Source"
$logDir = "$WorkingPath\_98_Logs"
$completedDir = "$WorkingPath\_99_Completed"

if (!(Test-Path $csvDir)) {
    throw "CSV directory not found after extraction: $csvDir"
}
Write-Host "✓ Test structure validated" -ForegroundColor Green

# Count initial files
$initialDVD31Count = (Get-ChildItem "$sourceDir\DVD31" -Recurse -File).Count
$initialDVD34Count = (Get-ChildItem "$sourceDir\DVD34" -Recurse -File).Count
$initialDVD33Count = (Get-ChildItem "$sourceDir\TEST_MetArt-DVD033(Final)_5923" -Recurse -File).Count
$initialDVD36Count = (Get-ChildItem "$sourceDir\DVD36_Brackets" -Recurse -File -ErrorAction SilentlyContinue).Count
$initialDVD39Count = (Get-ChildItem "$sourceDir\DVD39_Conflicts" -Recurse -File -ErrorAction SilentlyContinue).Count
$initialDVD40Count = (Get-ChildItem "$sourceDir\DVD40_EmptyFolders" -Recurse -File -ErrorAction SilentlyContinue).Count
$initialCompletedDVD32Count = (Get-ChildItem "$completedDir\MetArt-DVD032(Final)_5090" -Recurse -File).Count

Write-Host "`nInitial file counts:" -ForegroundColor Cyan
Write-Host "  DVD31: $initialDVD31Count files" -ForegroundColor Gray
Write-Host "  DVD33: $initialDVD33Count files" -ForegroundColor Gray
Write-Host "  DVD34: $initialDVD34Count files" -ForegroundColor Gray
Write-Host "  DVD36: $initialDVD36Count files" -ForegroundColor Gray
Write-Host "  DVD39: $initialDVD39Count files" -ForegroundColor Gray
Write-Host "  DVD40: $initialDVD40Count files" -ForegroundColor Gray
Write-Host "  DVD32 (Completed): $initialCompletedDVD32Count files" -ForegroundColor Gray

# Run the script
Write-TestHeader "Running CRC-FileOrganizer.ps1"
Write-Host "Executing script with test parameters..." -ForegroundColor Cyan

$scriptParams = @{
    RootFolder = $csvDir + '\'
    SourceFolderCRC = $sourceDir + '\'
    LogFolder = $logDir + '\'
    CompletedFolder = $completedDir + '\'
    ThrottleLimit = 4  # Lower for faster test execution
}

try {
    & $ScriptPath @scriptParams
    Write-Host "✓ Script execution completed" -ForegroundColor Green
}
catch {
    Write-Host "✗ Script execution failed: $_" -ForegroundColor Red
    throw
}

# Get log file
$logFile = Get-ChildItem -Path $logDir -Filter "file_moves_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (!$logFile) {
    Write-TestWarning "Log file not found in $logDir"
}
else {
    Write-Host "✓ Log file created: $($logFile.Name)" -ForegroundColor Green
}

# ============================================
# Validation Tests
# ============================================

Write-TestHeader "Validating Test Results"

# --- TEST 1: DVD031 (Duplicate CRCs) ---
Write-Host "`n--- DVD031: Duplicate CRC Handling ---" -ForegroundColor Magenta

# New behavior: duplicate CRCs no longer prevent processing. Expect CSV moved to completed
$dvd31CompletedCsv = Join-Path $completedDir 'TEST_MetArt-DVD031(Final)_42\TEST_MetArt-DVD031(Final)_42.csv'
Write-TestResult -TestName "DVD031 CSV moved to Completed" `
    -Passed (Test-Path $dvd31CompletedCsv) `
    -Message "CSV should be processed and moved to Completed when duplicates are present"

# Verify files were moved into completed folder (expect at least one file moved)
$dvd31CompletedFolder = Join-Path $completedDir 'TEST_MetArt-DVD031(Final)_42'
$dvd31MovedCount = if (Test-Path $dvd31CompletedFolder) { (Get-ChildItem -LiteralPath $dvd31CompletedFolder -Recurse -File -Exclude "*.csv").Count } else { 0 }
Write-TestResult -TestName "DVD031 files moved to Completed" `
    -Passed ($dvd31MovedCount -ge 1) `
    -Message "Expected files moved to completed, Actual moved: $dvd31MovedCount"

if ($logFile) {
    Test-LogContains -LogPath $logFile.FullName `
        -Pattern "duplicate CRC|Duplicate CRC" `
        -Description "DVD031 log shows duplicate detection"
}

# --- TEST 2: DVD033 (Incomplete - Missing Files) ---
Write-Host "`n--- DVD033: Incomplete CSV with Missing Files ---" -ForegroundColor Magenta

Write-TestResult -TestName "DVD033 CSV remains in source" `
    -Passed (Test-Path "$csvDir\TEST_MetArt-DVD033(Final)_35.csv") `
    -Message "Incomplete CSV should stay in source"

Write-TestResult -TestName "DVD033 CSV not in Completed" `
    -Passed (!(Test-Path "$completedDir\TEST_MetArt-DVD033(Final)_35\TEST_MetArt-DVD033(Final)_35.csv")) `
    -Message "Incomplete CSV should not move to completed"

$dvd33FilesRemain = (Get-ChildItem "$sourceDir\TEST_MetArt-DVD033(Final)_5923" -Recurse -File -ErrorAction SilentlyContinue).Count
Write-TestResult -TestName "DVD033 files remain in source (hybrid workflow)" `
    -Passed ($dvd33FilesRemain -eq $initialDVD33Count) `
    -Message "Expected: $initialDVD33Count, Actual: $dvd33FilesRemain"

$missingCSV = Get-ChildItem "$logDir\TEST_MetArt-DVD033(Final)_35*missing*.csv" -ErrorAction SilentlyContinue
Write-TestResult -TestName "DVD033 missing files CSV created" `
    -Passed ($null -ne $missingCSV) `
    -Message "Should log 4 missing files"

if ($missingCSV) {
    $missingCount = (Import-Csv $missingCSV.FullName).Count
    Write-TestResult -TestName "DVD033 missing CSV has 4 entries" `
        -Passed ($missingCount -eq 4) `
        -Message "Expected: 4, Actual: $missingCount"
}

if ($logFile) {
    Test-LogContains -LogPath $logFile.FullName `
        -Pattern "INCOMPLETE.*remain in source" `
        -Description "DVD033 log shows incomplete status"
        
    Test-LogContains -LogPath $logFile.FullName `
        -Pattern "Found 31 files.*4 missing" `
        -Description "DVD033 log shows correct file counts"
}

# --- TEST 3: DVD034 (Complete - All Edge Cases) ---
Write-Host "`n--- DVD034: Complete CSV with Edge Cases ---" -ForegroundColor Magenta

Write-TestResult -TestName "DVD034 CSV moved to Completed" `
    -Passed (Test-Path "$completedDir\TEST_MetArt-DVD034(Final)_35\TEST_MetArt-DVD034(Final)_35.csv") `
    -Message "Complete CSV should move with files"

Write-TestResult -TestName "DVD034 CSV removed from source" `
    -Passed (!(Test-Path "$csvDir\TEST_MetArt-DVD034(Final)_35.csv")) `
    -Message "CSV should be moved, not copied"

$dvd34Completed = "$completedDir\TEST_MetArt-DVD034(Final)_35"
if (Test-Path $dvd34Completed) {
    $completedFileCount = (Get-ChildItem $dvd34Completed -Recurse -File -Exclude "*.csv").Count
    Write-TestResult -TestName "DVD034 all 42 files in Completed" `
        -Passed ($completedFileCount -eq 42) `
        -Message "Expected: 42, Actual: $completedFileCount"
    
    # Check specific folders with edge cases
    Write-TestResult -TestName "DVD034 diacriticals preserved (Ménage)" `
        -Passed (Test-Path "$dvd34Completed\sg_09255 - Anna & Anna - Ménage") `
        -Message "Folder with 'é' character"
    
    Write-TestResult -TestName "DVD034 commas handled (vol_10025)" `
        -Passed (Test-Path "$dvd34Completed\vol_10025 - Alena") `
        -Message "Path with commas should be handled"
    
    Write-TestResult -TestName "DVD034 ampersands handled" `
        -Passed (Test-Path "$dvd34Completed\tad_11025 - Carolina & Yalim - Atacama") `
        -Message "Folder with '&' character"
    
    # Check that source folders are empty or removed
    # Note: DVD31 and DVD034 share files, so DVD34 folder may still exist with DVD31's remaining files
    $dvd34SourceRemaining = 0
    if (Test-Path "$sourceDir\DVD34") {
        $dvd34SourceRemaining = (Get-ChildItem "$sourceDir\DVD34" -Recurse -File -ErrorAction SilentlyContinue).Count
    }
    Write-TestResult -TestName "DVD034 source folder empty or has shared files" `
        -Passed ($dvd34SourceRemaining -le 21) `
        -Message "Expected: 0-21 (may contain DVD31 shared files), Actual: $dvd34SourceRemaining"
}

if ($logFile) {
    Test-LogContains -LogPath $logFile.FullName `
        -Pattern "DVD034.*COMPLETE" `
        -Description "DVD034 log shows complete status"
}

# --- TEST 4: DVD035 (Incomplete - Zero Matches) ---
Write-Host "`n--- DVD035: Zero Matches ---" -ForegroundColor Magenta

Write-TestResult -TestName "DVD035 CSV remains in source" `
    -Passed (Test-Path "$csvDir\TEST_MetArt-DVD035(Final)_5154.csv") `
    -Message "Zero-match CSV should stay in source"

Write-TestResult -TestName "DVD035 CSV not in Completed" `
    -Passed (!(Test-Path "$completedDir\TEST_MetArt-DVD035(Final)_5154\TEST_MetArt-DVD035(Final)_5154.csv")) `
    -Message "CSV should not move to completed"

if ($logFile) {
    Test-LogContains -LogPath $logFile.FullName `
        -Pattern "TEST_MetArt-DVD035.*No files from CSV|No files from CSV.*TEST_MetArt-DVD035" `
        -Description "DVD035 log shows zero matches"
}

# --- TEST 5: DVD032 (Pre-existing Completed) ---
Write-Host "`n--- DVD032: Pre-existing Completed Set ---" -ForegroundColor Magenta

$dvd32CompletedCount = (Get-ChildItem "$completedDir\MetArt-DVD032(Final)_5090" -Recurse -File).Count
Write-TestResult -TestName "DVD032 unchanged in Completed" `
    -Passed ($dvd32CompletedCount -eq $initialCompletedDVD32Count) `
    -Message "Pre-existing set should be untouched"

Write-TestResult -TestName "DVD032 CSV present in Completed folder" `
    -Passed (Test-Path "$completedDir\MetArt-DVD032(Final)_5090\TEST_MetArt-DVD032(Final)_5090.csv") `
    -Message "CSV should remain with completed files"

# --- Hybrid Workflow Validation ---
Write-Host "`n--- Hybrid Workflow Validation ---" -ForegroundColor Magenta

if ($logFile) {
    $logContent = Get-Content $logFile.FullName -Raw
    
    # Should NOT have staging folder references
    $hasStagingRefs = $logContent -match "staging folder|moved to staging"
    Write-TestResult -TestName "No staging folder references in log" `
        -Passed (-not $hasStagingRefs) `
        -Message "Hybrid workflow should not use staging"
    
    # Should have hybrid workflow messages
    Test-LogContains -LogPath $logFile.FullName `
        -Pattern "remain in source" `
        -Description "Log shows hybrid workflow messages"
}

# --- TEST 6: DVD036 (Square Brackets in Filenames) ---
Write-Host "`n--- DVD036: Square Brackets and Braces in Filenames ---" -ForegroundColor Magenta

Write-TestResult -TestName "DVD036 CSV moved to Completed" `
    -Passed (Test-Path "$completedDir\TEST_MetArt-DVD036_Brackets\TEST_MetArt-DVD036_Brackets.csv") `
    -Message "Complete CSV with bracket filenames should move"

Write-TestResult -TestName "DVD036 CSV removed from source" `
    -Passed (!(Test-Path "$csvDir\TEST_MetArt-DVD036_Brackets.csv")) `
    -Message "CSV should be moved, not copied"

$dvd36Completed = "$completedDir\TEST_MetArt-DVD036_Brackets"
if (Test-Path $dvd36Completed) {
    $dvd36FileCount = (Get-ChildItem $dvd36Completed -Recurse -File -Exclude "*.csv").Count
    Write-TestResult -TestName "DVD036 all 10 files in Completed" `
        -Passed ($dvd36FileCount -eq 10) `
        -Message "Expected: 10, Actual: $dvd36FileCount (tests -LiteralPath fix)"
    
    # Check specific bracket files exist
    Write-TestResult -TestName "DVD036 bracket file [2024] exists" `
        -Passed (Test-Path -LiteralPath "$dvd36Completed\TEST_[2024] Preview.jpg") `
        -Message "File with square brackets handled"
    
    Write-TestResult -TestName "DVD036 bracket file {Types} exists" `
        -Passed (Test-Path -LiteralPath "$dvd36Completed\TEST_Mixed[Bracket]{Types}.jpg") `
        -Message "File with mixed brackets handled"
}

if ($logFile) {
    Test-LogContains -LogPath $logFile.FullName `
        -Pattern "DVD036.*COMPLETE" `
        -Description "DVD036 log shows complete status"
}

# --- TEST 7: DVD038 (Shared CRCs - Script Limitation) ---
Write-Host "`n--- DVD038: Shared CRCs with DVD034 (Expected Incomplete) ---" -ForegroundColor Magenta

Write-TestResult -TestName "DVD038 CSV remains in source" `
    -Passed (Test-Path "$csvDir\TEST_MetArt-DVD038_SharedCRC.csv") `
    -Message "CSV stays in source (files in DVD034, script limitation)"

Write-TestResult -TestName "DVD038 CSV not in Completed" `
    -Passed (!(Test-Path "$completedDir\TEST_MetArt-DVD038_SharedCRC\TEST_MetArt-DVD038_SharedCRC.csv")) `
    -Message "Script only checks current CSV's completed folder"

if ($logFile) {
    Test-LogContains -LogPath $logFile.FullName `
        -Pattern "TEST_MetArt-DVD038.*No files from CSV|No files from CSV.*TEST_MetArt-DVD038" `
        -Description "DVD038 log shows no files found (expected behavior)"
}

Write-TestWarning "DVD038: Cross-CSV duplicate detection is a known limitation. Files exist in DVD034's completed folder."

# --- TEST 8: DVD039 (CRC Conflicts) ---
Write-Host "`n--- DVD039: CRC Conflicts (Wrong CRC Values) ---" -ForegroundColor Magenta

Write-TestResult -TestName "DVD039 CSV remains in source" `
    -Passed (Test-Path "$csvDir\TEST_MetArt-DVD039_Conflicts.csv") `
    -Message "CSV with CRC mismatches should stay in source"

Write-TestResult -TestName "DVD039 CSV not in Completed" `
    -Passed (!(Test-Path "$completedDir\TEST_MetArt-DVD039_Conflicts\TEST_MetArt-DVD039_Conflicts.csv")) `
    -Message "Incomplete set should not move"

$dvd39FilesRemain = 0
if (Test-Path "$sourceDir\DVD39_Conflicts") {
    $dvd39FilesRemain = (Get-ChildItem "$sourceDir\DVD39_Conflicts" -Recurse -File -ErrorAction SilentlyContinue).Count
}
Write-TestResult -TestName "DVD039 files remain in source" `
    -Passed ($dvd39FilesRemain -eq $initialDVD39Count) `
    -Message "Expected: $initialDVD39Count, Actual: $dvd39FilesRemain"

$missingCSV = Get-ChildItem "$logDir\TEST_MetArt-DVD039_Conflicts*missing*.csv" -ErrorAction SilentlyContinue
Write-TestResult -TestName "DVD039 missing files CSV created" `
    -Passed ($null -ne $missingCSV) `
    -Message "Should log 3 CRC mismatches as missing"

if ($missingCSV) {
    $missingCount = (Import-Csv $missingCSV.FullName).Count
    Write-TestResult -TestName "DVD039 missing CSV has 3 entries" `
        -Passed ($missingCount -eq 3) `
        -Message "Expected: 3, Actual: $missingCount"
}

# --- TEST 9: DVD040 (Empty Folder Cleanup) ---
Write-Host "`n--- DVD040: Empty Folder Cleanup ---" -ForegroundColor Magenta

Write-TestResult -TestName "DVD040 CSV moved to Completed" `
    -Passed (Test-Path "$completedDir\TEST_MetArt-DVD040_EmptyFolders\TEST_MetArt-DVD040_EmptyFolders.csv") `
    -Message "Complete CSV should move"

$dvd40Completed = "$completedDir\TEST_MetArt-DVD040_EmptyFolders"
if (Test-Path $dvd40Completed) {
    $dvd40FileCount = (Get-ChildItem $dvd40Completed -Recurse -File -Exclude "*.csv").Count
    Write-TestResult -TestName "DVD040 all 4 files in Completed" `
        -Passed ($dvd40FileCount -eq 4) `
        -Message "Expected: 4, Actual: $dvd40FileCount"
}

# Check that empty source folders were removed
$dvd40SourceExists = Test-Path "$sourceDir\DVD40_EmptyFolders"
if ($dvd40SourceExists) {
    $dvd40Remaining = (Get-ChildItem "$sourceDir\DVD40_EmptyFolders" -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-TestResult -TestName "DVD040 source folder empty or removed" `
        -Passed ($dvd40Remaining -eq 0) `
        -Message "Empty folders should be cleaned up"
} else {
    Write-TestResult -TestName "DVD040 source folder removed" `
        -Passed $true `
        -Message "Empty parent folder removed successfully"
}

if ($logFile) {
    Test-LogContains -LogPath $logFile.FullName `
        -Pattern "DVD040.*COMPLETE" `
        -Description "DVD040 log shows complete status"
}

# ============================================
# Generate Test Report
# ============================================

Write-TestHeader "Test Summary"

$endTime = Get-Date
$duration = $endTime - $script:TestResults.StartTime

Write-Host "Test Execution Time: $($duration.TotalSeconds) seconds" -ForegroundColor Cyan
Write-Host "`nResults:" -ForegroundColor Cyan
Write-Host "  PASSED: $($script:TestResults.Passed.Count)" -ForegroundColor Green
Write-Host "  FAILED: $($script:TestResults.Failed.Count)" -ForegroundColor $(if ($script:TestResults.Failed.Count -eq 0) { "Green" } else { "Red" })
Write-Host "  WARNINGS: $($script:TestResults.Warnings.Count)" -ForegroundColor Yellow

if ($script:TestResults.Failed.Count -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $script:TestResults.Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

if ($script:TestResults.Warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    $script:TestResults.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

# Save detailed report
$reportPath = "$WorkingPath\TestReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$report = @"
CRC-FileOrganizer.ps1 Test Report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Script: $ScriptPath
Test Data: $TestDataPath
Duration: $($duration.TotalSeconds) seconds

RESULTS SUMMARY
===============
Passed: $($script:TestResults.Passed.Count)
Failed: $($script:TestResults.Failed.Count)
Warnings: $($script:TestResults.Warnings.Count)

PASSED TESTS
============
$($script:TestResults.Passed -join "`n")

FAILED TESTS
============
$($script:TestResults.Failed -join "`n")

WARNINGS
========
$($script:TestResults.Warnings -join "`n")

LOG FILE LOCATION
=================
$($logFile.FullName)
"@

$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`n✓ Detailed report saved: $reportPath" -ForegroundColor Green

# Cleanup
if (!$KeepTestData) {
    Write-Host "`nCleaning up test data..." -ForegroundColor Yellow
    
    # Change directory away from WorkingPath to allow deletion
    Set-Location (Split-Path $WorkingPath -Parent)
    Start-Sleep -Seconds 1
    
    try {
        Remove-Item -Path $WorkingPath -Recurse -Force -ErrorAction Stop
        Write-Host "✓ Test data cleaned up" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠ Could not clean test data: $_" -ForegroundColor Yellow
        Write-Host "  Manual cleanup: Remove-Item '$WorkingPath' -Recurse -Force" -ForegroundColor Gray
    }
}
else {
    Write-Host "`nTest data preserved at: $WorkingPath" -ForegroundColor Cyan
    Write-Host "Log file: $($logFile.FullName)" -ForegroundColor Cyan
}

# Exit with appropriate code
if ($script:TestResults.Failed.Count -eq 0) {
    Write-Host "`n✓ ALL TESTS PASSED!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n✗ SOME TESTS FAILED!" -ForegroundColor Red
    exit 1
}
