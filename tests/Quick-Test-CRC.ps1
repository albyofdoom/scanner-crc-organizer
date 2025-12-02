<#
.SYNOPSIS
    Quick validation test for CRC-FileOrganizer.ps1 - runs in seconds

.DESCRIPTION
    Performs essential validation without full test suite overhead.
    Perfect for rapid iteration during development.

.PARAMETER KeepData
    Keep test data after run (for inspection)

.EXAMPLE
    .\Quick-Test-CRC.ps1
    
.EXAMPLE
    .\Quick-Test-CRC.ps1 -KeepData
#>

param([switch]$KeepData)

$ErrorActionPreference = 'Stop'

# Resolve paths relative to repository root (tests/ is one level down)
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TestPath = Join-Path $RepoRoot 'TestData' 'TestWorking'
$ScriptPath = Join-Path $RepoRoot 'CRC-FileOrganizer.ps1'
$TestDataZip = Join-Path $RepoRoot 'TestData' 'TestSourceData.zip'

Write-Host "`n=== Quick Test: CRC-FileOrganizer ===" -ForegroundColor Cyan
Write-Host "Test Path: $TestPath`n" -ForegroundColor Gray

# Setup
if (Test-Path $TestPath) { Remove-Item $TestPath -Recurse -Force }
New-Item $TestPath -ItemType Directory -Force | Out-Null
Expand-Archive $TestDataZip -DestinationPath $TestPath -Force

# Ensure required folders exist (in case zip doesn't include empty folders)
@('_98_Logs', '_99_Completed') | ForEach-Object {
    $folder = Join-Path $TestPath $_
    if (-not (Test-Path $folder)) { New-Item $folder -ItemType Directory -Force | Out-Null }
}

# Run script
Write-Host "Running script..." -ForegroundColor Yellow
$params = @{
    RootFolder = "$TestPath\_01_CSV_Source\"
    SourceFolderCRC = "$TestPath\_02_Image_Source\"
    LogFolder = "$TestPath\_98_Logs\"
    CompletedFolder = "$TestPath\_99_Completed\"
    ThrottleLimit = 4
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $ScriptPath @params
$sw.Stop()

Write-Host "`n✓ Script completed in $($sw.Elapsed.TotalSeconds)s" -ForegroundColor Green

# Quick checks
Write-Host "`nQuick Validation:" -ForegroundColor Cyan
$results = @()

# DVD031 (duplicates) - new behavior: duplicates do not cause skip, expect processed
$dvd031CsvInCompleted = Test-Path "$TestPath\_99_Completed\TEST_MetArt-DVD031(Final)_42\TEST_MetArt-DVD031(Final)_42.csv"
$dvd031CompletedCount = if ($dvd031CsvInCompleted) { (Get-ChildItem "$TestPath\_99_Completed\TEST_MetArt-DVD031(Final)_42" -Recurse -File -Exclude "*.csv").Count } else { 0 }
$results += [PSCustomObject]@{ Test = "DVD031 processed (duplicates allowed)"; Pass = ($dvd031CsvInCompleted -and $dvd031CompletedCount -ge 1) }

# DVD033 (incomplete) - should stay in source
$dvd033InSource = Test-Path "$TestPath\_01_CSV_Source\TEST_MetArt-DVD033(Final)_35.csv"
$dvd033FilesInSource = (Get-ChildItem "$TestPath\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923" -Recurse -File -ErrorAction SilentlyContinue).Count -eq 31
$dvd033CSVInCompleted = Test-Path "$TestPath\_99_Completed\TEST_MetArt-DVD033(Final)_35\TEST_MetArt-DVD033(Final)_35.csv"
$results += [PSCustomObject]@{ Test = "DVD033 incomplete (stays in source)"; Pass = ($dvd033InSource -and $dvd033FilesInSource -and !$dvd033CSVInCompleted) }

# DVD034 (complete) - should move to completed
$dvd034InCompleted = Test-Path "$TestPath\_99_Completed\TEST_MetArt-DVD034(Final)_35\TEST_MetArt-DVD034(Final)_35.csv"
$dvd034FileCount = if ($dvd034InCompleted) { (Get-ChildItem "$TestPath\_99_Completed\TEST_MetArt-DVD034(Final)_35" -Recurse -File -Exclude "*.csv").Count } else { 0 }
$results += [PSCustomObject]@{ Test = "DVD034 complete (moved to completed)"; Pass = ($dvd034InCompleted -and $dvd034FileCount -eq 42) }

# DVD035 (zero matches) - should stay in source
$dvd035InSource = Test-Path "$TestPath\_01_CSV_Source\TEST_MetArt-DVD035(Final)_5154.csv"
$dvd035InCompleted = Test-Path "$TestPath\_99_Completed\TEST_MetArt-DVD035(Final)_5154"
$results += [PSCustomObject]@{ Test = "DVD035 zero matches (stays in source)"; Pass = ($dvd035InSource -and !$dvd035InCompleted) }

# DVD032 (pre-existing) - should be untouched
$dvd032Files = (Get-ChildItem "$TestPath\_99_Completed\MetArt-DVD032(Final)_5090" -Recurse -File).Count
$results += [PSCustomObject]@{ Test = "DVD032 pre-existing (untouched)"; Pass = ($dvd032Files -eq 22) }

# DVD036 (brackets/special chars) - should move to completed
$dvd036InCompleted = Test-Path "$TestPath\_99_Completed\TEST_MetArt-DVD036_Brackets\TEST_MetArt-DVD036_Brackets.csv"
$dvd036FileCount = if ($dvd036InCompleted) { (Get-ChildItem "$TestPath\_99_Completed\TEST_MetArt-DVD036_Brackets" -Recurse -File -Exclude "*.csv").Count } else { 0 }
$results += [PSCustomObject]@{ Test = "DVD036 brackets (all files matched)"; Pass = ($dvd036InCompleted -and $dvd036FileCount -eq 10) }

# DVD038 (shared CRC) - files in DVD034's folder, not found by current script logic
# Current behavior: CSV stays in source because script only checks current CSV's completed folder
$dvd038InSource = Test-Path "$TestPath\_01_CSV_Source\TEST_MetArt-DVD038_SharedCRC.csv"
$dvd038NotInCompleted = -not (Test-Path "$TestPath\_99_Completed\TEST_MetArt-DVD038_SharedCRC")
$results += [PSCustomObject]@{ Test = "DVD038 shared CRC (stays incomplete)"; Pass = ($dvd038InSource -and $dvd038NotInCompleted) }

# DVD039 (CRC conflicts) - should stay in source (mismatches)
$dvd039InSource = Test-Path "$TestPath\_01_CSV_Source\TEST_MetArt-DVD039_Conflicts.csv"
$dvd039FilesInSource = (Get-ChildItem "$TestPath\_02_Image_Source\DVD39_Conflicts" -Recurse -File -ErrorAction SilentlyContinue).Count -eq 4
$dvd039InCompleted = Test-Path "$TestPath\_99_Completed\TEST_MetArt-DVD039_Conflicts"
$results += [PSCustomObject]@{ Test = "DVD039 CRC conflicts (stays incomplete)"; Pass = ($dvd039InSource -and $dvd039FilesInSource -and !$dvd039InCompleted) }

# DVD040 (empty folders) - should move to completed and clean up folders
$dvd040InCompleted = Test-Path "$TestPath\_99_Completed\TEST_MetArt-DVD040_EmptyFolders\TEST_MetArt-DVD040_EmptyFolders.csv"
$dvd040EmptyFoldersRemoved = !(Test-Path "$TestPath\_02_Image_Source\DVD40_EmptyFolders")
$results += [PSCustomObject]@{ Test = "DVD040 empty folders (removed)"; Pass = ($dvd040InCompleted -and $dvd040EmptyFoldersRemoved) }

# Display results
$results | ForEach-Object {
    $symbol = if ($_.Pass) { "✓" } else { "✗" }
    $color = if ($_.Pass) { "Green" } else { "Red" }
    Write-Host "$symbol $($_.Test)" -ForegroundColor $color
}

$passed = ($results | Where-Object { $_.Pass }).Count
$total = $results.Count

Write-Host "`nResult: $passed/$total tests passed" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Red" })
Write-Host "  (5 original + 4 new scenarios)" -ForegroundColor Gray

# Show log location
$logFile = Get-ChildItem "$TestPath\_98_Logs\file_moves_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($logFile) {
    Write-Host "`nLog: $($logFile.FullName)" -ForegroundColor Gray
}

# Cleanup
if (!$KeepData) {
    # Change directory away from TestPath to allow deletion
    Set-Location (Split-Path $TestPath -Parent)
    Start-Sleep -Seconds 1
    
    try {
        Remove-Item $TestPath -Recurse -Force -ErrorAction Stop
        Write-Host "`n✓ Test data cleaned" -ForegroundColor Gray
    }
    catch {
        Write-Host "`n⚠ Could not clean test data: $_" -ForegroundColor Yellow
        Write-Host "  Manual cleanup: Remove-Item '$TestPath' -Recurse -Force" -ForegroundColor Gray
    }
}
else {
    Write-Host "`n📁 Test data kept at: $TestPath" -ForegroundColor Cyan
}

exit $(if ($passed -eq $total) { 0 } else { 1 })
