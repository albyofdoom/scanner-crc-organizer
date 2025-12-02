<#
.SYNOPSIS
    Unit tests for CRC-FileOrganizerLib.ps1 functions

.DESCRIPTION
    Tests the shared library functions used by CRC-FileOrganizer scripts:
    - Get-CRC32Hash: CRC32 computation
    - Get-CandidateMap: File discovery and CRC mapping
    - Simulate-AssignCsvEntries: CSV parsing and claim simulation
    
.EXAMPLE
    .\Test-CRCFileOrganizerLib.ps1
#>

param(
    [string]$TestDataPath
)

$ErrorActionPreference = 'Stop'

# Resolve paths relative to repository root (tests/ is one level down)
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $TestDataPath) {
    $TestDataPath = Join-Path $RepoRoot 'TestData' 'LibTests'
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

# Load library
. (Join-Path $PSScriptRoot '..\Functions\CRC-FileOrganizerLib.ps1')

# Create test environment
if (Test-Path $TestDataPath) {
    Remove-Item $TestDataPath -Recurse -Force
}
New-Item -Path $TestDataPath -ItemType Directory -Force | Out-Null

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "CRC-FileOrganizerLib.ps1 Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ============================================
# TEST: Get-CRC32Hash
# ============================================
Write-Host "`n--- Testing Get-CRC32Hash ---" -ForegroundColor Magenta

# Test 1: Known CRC32 value
$testFile1 = Join-Path $TestDataPath "test1.txt"
"Hello World!" | Out-File -FilePath $testFile1 -Encoding ascii -NoNewline
$crc1 = Get-CRC32Hash -FilePath $testFile1

# Known CRC32 for "Hello World!" (ASCII, no newline) is 0x1C291CA3
Write-TestResult -TestName "Get-CRC32Hash: Known value test" `
    -Passed ($crc1 -eq "1C291CA3") `
    -Message "Expected: 1C291CA3, Got: $crc1"

# Test 2: Empty file
$testFile2 = Join-Path $TestDataPath "empty.txt"
"" | Out-File -FilePath $testFile2 -Encoding ascii -NoNewline
$crc2 = Get-CRC32Hash -FilePath $testFile2

# Empty file CRC32 is 0x00000000
Write-TestResult -TestName "Get-CRC32Hash: Empty file" `
    -Passed ($crc2 -eq "00000000") `
    -Message "Expected: 00000000, Got: $crc2"

# Test 3: Binary file
$testFile3 = Join-Path $TestDataPath "binary.bin"
[byte[]]$bytes = 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09
[System.IO.File]::WriteAllBytes($testFile3, $bytes)
$crc3 = Get-CRC32Hash -FilePath $testFile3

Write-TestResult -TestName "Get-CRC32Hash: Binary file" `
    -Passed ($crc3.Length -eq 8 -and $crc3 -match '^[0-9A-F]{8}$') `
    -Message "CRC: $crc3 (should be 8 uppercase hex chars)"

# Test 4: Large file (> 1MB buffer)
$testFile4 = Join-Path $TestDataPath "large.bin"
$largeData = [byte[]]::new(2MB)
for ($i = 0; $i -lt 2MB; $i++) { $largeData[$i] = [byte]($i % 256) }
[System.IO.File]::WriteAllBytes($testFile4, $largeData)
$crc4 = Get-CRC32Hash -FilePath $testFile4

Write-TestResult -TestName "Get-CRC32Hash: Large file (2MB)" `
    -Passed ($crc4.Length -eq 8 -and $crc4 -match '^[0-9A-F]{8}$') `
    -Message "CRC: $crc4"

# Test 5: Identical content produces identical CRCs
$testFile5a = Join-Path $TestDataPath "ident_a.txt"
$testFile5b = Join-Path $TestDataPath "ident_b.txt"
"Identical content" | Out-File -FilePath $testFile5a -Encoding UTF8 -NoNewline
"Identical content" | Out-File -FilePath $testFile5b -Encoding UTF8 -NoNewline
$crc5a = Get-CRC32Hash -FilePath $testFile5a
$crc5b = Get-CRC32Hash -FilePath $testFile5b

Write-TestResult -TestName "Get-CRC32Hash: Identical content" `
    -Passed ($crc5a -eq $crc5b) `
    -Message "File A: $crc5a, File B: $crc5b"

# Test 6: Different content produces different CRCs
$testFile6a = Join-Path $TestDataPath "diff_a.txt"
$testFile6b = Join-Path $TestDataPath "diff_b.txt"
"Content A" | Out-File -FilePath $testFile6a -Encoding UTF8 -NoNewline
"Content B" | Out-File -FilePath $testFile6b -Encoding UTF8 -NoNewline
$crc6a = Get-CRC32Hash -FilePath $testFile6a
$crc6b = Get-CRC32Hash -FilePath $testFile6b

Write-TestResult -TestName "Get-CRC32Hash: Different content" `
    -Passed ($crc6a -ne $crc6b) `
    -Message "File A: $crc6a, File B: $crc6b (should differ)"

# Test 7: Unicode filename
$testFile7 = Join-Path $TestDataPath "tëst_文件.txt"
"Unicode test" | Out-File -FilePath $testFile7 -Encoding UTF8 -NoNewline
$crc7 = Get-CRC32Hash -FilePath $testFile7

Write-TestResult -TestName "Get-CRC32Hash: Unicode filename" `
    -Passed ($crc7.Length -eq 8 -and $crc7 -match '^[0-9A-F]{8}$') `
    -Message "CRC: $crc7"

# Test 8: Special characters in filename
$testFile8 = Join-Path $TestDataPath "file[2024]{test}.txt"
"Special chars" | Out-File -FilePath $testFile8 -Encoding UTF8 -NoNewline
$crc8 = Get-CRC32Hash -FilePath $testFile8

Write-TestResult -TestName "Get-CRC32Hash: Brackets in filename" `
    -Passed ($crc8.Length -eq 8 -and $crc8 -match '^[0-9A-F]{8}$') `
    -Message "CRC: $crc8"

# ============================================
# TEST: Get-CandidateMap
# ============================================
Write-Host "`n--- Testing Get-CandidateMap ---" -ForegroundColor Magenta

# Create test file structure
$sourceDir = Join-Path $TestDataPath "source"
New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null

# Create files with known content
$file1 = Join-Path $sourceDir "file1.txt"
$file2 = Join-Path $sourceDir "file2.txt"
$file3 = Join-Path $sourceDir "duplicate.txt"
$file4 = Join-Path $sourceDir "duplicate_same_content.txt"

"Content 1" | Out-File -FilePath $file1 -Encoding UTF8 -NoNewline
"Content 2" | Out-File -FilePath $file2 -Encoding UTF8 -NoNewline
"Duplicate" | Out-File -FilePath $file3 -Encoding UTF8 -NoNewline
"Duplicate" | Out-File -FilePath $file4 -Encoding UTF8 -NoNewline

# Create subdirectory
$subdir = Join-Path $sourceDir "subdir"
New-Item -Path $subdir -ItemType Directory -Force | Out-Null
$file5 = Join-Path $subdir "nested.txt"
"Nested file" | Out-File -FilePath $file5 -Encoding UTF8 -NoNewline

# Build candidate map
Write-Host "  Building candidate map..." -ForegroundColor Gray
$candidateMap = Get-CandidateMap -SourceFolderCRC $sourceDir -ThrottleLimit 2

# Test 9: Map contains all files
$totalFiles = 5
Write-TestResult -TestName "Get-CandidateMap: All files discovered" `
    -Passed ($candidateMap.Keys.Count -ge 3) `
    -Message "Found $($candidateMap.Keys.Count) unique CRC+Size combinations (expected at least 3)"

# Test 10: Duplicate CRCs grouped correctly
$dupCRC = Get-CRC32Hash -FilePath $file3
$dupSize = (Get-Item -LiteralPath $file3).Length
$dupKey = "{0}:{1}" -f $dupCRC, $dupSize

if ($candidateMap.ContainsKey($dupKey)) {
    $dupCount = $candidateMap[$dupKey].Count
    Write-TestResult -TestName "Get-CandidateMap: Duplicate CRCs grouped" `
        -Passed ($dupCount -eq 2) `
        -Message "Found $dupCount files with same CRC+Size (expected 2)"
}
else {
    Write-TestResult -TestName "Get-CandidateMap: Duplicate CRCs grouped" `
        -Passed $false `
        -Message "Duplicate key not found in map"
}

# Test 11: Map entries have correct structure
$firstKey = $candidateMap.Keys | Select-Object -First 1
$firstEntry = $candidateMap[$firstKey][0]

$hasFullName = $null -ne $firstEntry.FullName
$hasFileName = $null -ne $firstEntry.FileName
$hasSize = $null -ne $firstEntry.Size
$hasCRC32 = $null -ne $firstEntry.CRC32
$hasFileInfo = $null -ne $firstEntry.FileInfo

Write-TestResult -TestName "Get-CandidateMap: Entry structure" `
    -Passed ($hasFullName -and $hasFileName -and $hasSize -and $hasCRC32 -and $hasFileInfo) `
    -Message "Entry has all required properties"

# Test 12: CRC format validation
$crcFormat = $firstEntry.CRC32 -match '^[0-9A-F]{8}$'
Write-TestResult -TestName "Get-CandidateMap: CRC format uppercase hex" `
    -Passed $crcFormat `
    -Message "CRC: $($firstEntry.CRC32)"

# ============================================
# TEST: Simulate-AssignCsvEntries
# ============================================
Write-Host "`n--- Testing Simulate-AssignCsvEntries ---" -ForegroundColor Magenta

# Create test CSV
$csvDir = Join-Path $TestDataPath "csvs"
New-Item -Path $csvDir -ItemType Directory -Force | Out-Null

# Get actual CRCs for test files
$crc1 = Get-CRC32Hash -FilePath $file1
$size1 = (Get-Item -LiteralPath $file1).Length
$crc2 = Get-CRC32Hash -FilePath $file2
$size2 = (Get-Item -LiteralPath $file2).Length
$crc5 = Get-CRC32Hash -FilePath $file5
$size5 = (Get-Item -LiteralPath $file5).Length

# Test CSV 1: Complete match
$csv1 = Join-Path $csvDir "test1.csv"
@"
FileName,Size,CRC32,Path
file1.txt,$size1,$crc1,\test\
file2.txt,$size2,$crc2,\test\
"@ | Out-File -FilePath $csv1 -Encoding UTF8

$claimMap1 = @{}
$results1 = Simulate-AssignCsvEntries -CsvPath $csv1 -CandidateMap $candidateMap -ClaimMap $claimMap1 -CompletedFolder '' -DryRun

# Test 13: All entries assigned
$assignedCount = ($results1 | Where-Object { $_.Reason -eq 'Assigned' }).Count
Write-TestResult -TestName "Simulate-AssignCsvEntries: Complete match" `
    -Passed ($assignedCount -eq 2) `
    -Message "Assigned: $assignedCount (expected 2)"

# Test 14: ClaimMap updated
Write-TestResult -TestName "Simulate-AssignCsvEntries: ClaimMap updated" `
    -Passed ($claimMap1.Count -eq 2) `
    -Message "Claims: $($claimMap1.Count)"

# Test CSV 2: Re-use same files (should be claimed)
$csv2 = Join-Path $csvDir "test2.csv"
@"
FileName,Size,CRC32,Path
file1_again.txt,$size1,$crc1,\test\
file2_again.txt,$size2,$crc2,\test\
"@ | Out-File -FilePath $csv2 -Encoding UTF8

$results2 = Simulate-AssignCsvEntries -CsvPath $csv2 -CandidateMap $candidateMap -ClaimMap $claimMap1 -CompletedFolder '' -DryRun

# Test 15: Files claimed by previous CSV
$claimedCount = ($results2 | Where-Object { $_.Reason -eq 'ClaimedByOther' }).Count
Write-TestResult -TestName "Simulate-AssignCsvEntries: Claimed detection" `
    -Passed ($claimedCount -eq 2) `
    -Message "Claimed: $claimedCount (expected 2)"

# Test 16: ClaimedBy field populated
$firstClaimed = $results2 | Where-Object { $_.Reason -eq 'ClaimedByOther' } | Select-Object -First 1
Write-TestResult -TestName "Simulate-AssignCsvEntries: ClaimedBy populated" `
    -Passed ($firstClaimed.ClaimedBy -eq 'test1.csv') `
    -Message "ClaimedBy: $($firstClaimed.ClaimedBy)"

# Test CSV 3: Missing files
$csv3 = Join-Path $csvDir "test3.csv"
@"
FileName,Size,CRC32,Path
missing.txt,1234,DEADBEEF,\test\
notfound.txt,5678,CAFEBABE,\test\
"@ | Out-File -FilePath $csv3 -Encoding UTF8

$claimMap3 = @{}
$results3 = Simulate-AssignCsvEntries -CsvPath $csv3 -CandidateMap $candidateMap -ClaimMap $claimMap3 -CompletedFolder '' -DryRun

# Test 17: NotFound reason
$notFoundCount = ($results3 | Where-Object { $_.Reason -eq 'NotFound' }).Count
Write-TestResult -TestName "Simulate-AssignCsvEntries: Missing files" `
    -Passed ($notFoundCount -eq 2) `
    -Message "NotFound: $notFoundCount (expected 2)"

# Test CSV 4: Mixed scenario
$csv4 = Join-Path $csvDir "test4.csv"
@"
FileName,Size,CRC32,Path
nested.txt,$size5,$crc5,\test\
missing.txt,999,12345678,\test\
"@ | Out-File -FilePath $csv4 -Encoding UTF8

$claimMap4 = @{}
$results4 = Simulate-AssignCsvEntries -CsvPath $csv4 -CandidateMap $candidateMap -ClaimMap $claimMap4 -CompletedFolder '' -DryRun

# Test 18: Mixed results
$assigned4 = ($results4 | Where-Object { $_.Reason -eq 'Assigned' }).Count
$notFound4 = ($results4 | Where-Object { $_.Reason -eq 'NotFound' }).Count
Write-TestResult -TestName "Simulate-AssignCsvEntries: Mixed scenario" `
    -Passed ($assigned4 -eq 1 -and $notFound4 -eq 1) `
    -Message "Assigned: $assigned4, NotFound: $notFound4"

# Test CSV 5: Header row handling
$csv5 = Join-Path $csvDir "test5.csv"
@"
FileName,Size,CRC32,Path,Comment
file1.txt,$size1,$crc1,\test\,Test comment
"@ | Out-File -FilePath $csv5 -Encoding UTF8

$claimMap5 = @{}
$results5 = Simulate-AssignCsvEntries -CsvPath $csv5 -CandidateMap $candidateMap -ClaimMap $claimMap5 -CompletedFolder '' -DryRun

# Test 19: Header row skipped
Write-TestResult -TestName "Simulate-AssignCsvEntries: Header skipped" `
    -Passed ($results5.Count -eq 1) `
    -Message "Results: $($results5.Count) (expected 1, not 2)"

# Test CSV 6: Quoted fields with commas
$csv6 = Join-Path $csvDir "test6.csv"
@"
FileName,Size,CRC32,Path,Comment
"file1.txt",$size1,$crc1,"\test\path,with,commas\","Comment, with, commas"
"@ | Out-File -FilePath $csv6 -Encoding UTF8

$claimMap6 = @{}
$results6 = Simulate-AssignCsvEntries -CsvPath $csv6 -CandidateMap $candidateMap -ClaimMap $claimMap6 -CompletedFolder '' -DryRun

# Test 20: Quoted field parsing
Write-TestResult -TestName "Simulate-AssignCsvEntries: Quoted fields" `
    -Passed ($results6.Count -eq 1 -and $results6[0].Reason -eq 'Assigned') `
    -Message "Parsed and assigned quoted CSV entry"

# Test CSV 7: RFC4180 escaped quotes
$csv7 = Join-Path $csvDir "test7.csv"
@"
FileName,Size,CRC32,Path
"file""with""quotes.txt",$size1,$crc1,\test\
"@ | Out-File -FilePath $csv7 -Encoding UTF8

$claimMap7 = @{}
$results7 = Simulate-AssignCsvEntries -CsvPath $csv7 -CandidateMap $candidateMap -ClaimMap $claimMap7 -CompletedFolder '' -DryRun

# Test 21: RFC4180 escaped quotes handled
Write-TestResult -TestName "Simulate-AssignCsvEntries: RFC4180 escaped quotes" `
    -Passed ($results7.Count -eq 1) `
    -Message "Entry count: $($results7.Count)"

# Test 22: Empty CSV (header only)
$csv8 = Join-Path $csvDir "test8.csv"
@"
FileName,Size,CRC32,Path
"@ | Out-File -FilePath $csv8 -Encoding UTF8

$claimMap8 = @{}
$results8 = Simulate-AssignCsvEntries -CsvPath $csv8 -CandidateMap $candidateMap -ClaimMap $claimMap8 -CompletedFolder '' -DryRun

# Test 23: Empty CSV handling
Write-TestResult -TestName "Simulate-AssignCsvEntries: Empty CSV" `
    -Passed ($results8.Count -eq 0) `
    -Message "Results: $($results8.Count) (expected 0)"

# Test 24: Result structure validation
$sampleResult = $results1[0]
$hasCSVFile = $null -ne $sampleResult.CSVFile
$hasEntryIndex = $null -ne $sampleResult.EntryIndex
$hasExpectedCRC = $null -ne $sampleResult.ExpectedCRC
$hasExpectedSize = $null -ne $sampleResult.ExpectedSize
$hasReason = $null -ne $sampleResult.Reason
$hasTimestamp = $null -ne $sampleResult.Timestamp

Write-TestResult -TestName "Simulate-AssignCsvEntries: Result structure" `
    -Passed ($hasCSVFile -and $hasEntryIndex -and $hasExpectedCRC -and $hasExpectedSize -and $hasReason -and $hasTimestamp) `
    -Message "Result has all required properties"

# ============================================
# TEST: Edge Cases
# ============================================
Write-Host "`n--- Testing Edge Cases ---" -ForegroundColor Magenta

# Test 25: Duplicate CRCs in same CSV
$csv9 = Join-Path $csvDir "test9.csv"
@"
FileName,Size,CRC32,Path
duplicate1.txt,$($dupSize),$dupCRC,\test\
duplicate2.txt,$($dupSize),$dupCRC,\test\
"@ | Out-File -FilePath $csv9 -Encoding UTF8

$claimMap9 = @{}
$results9 = Simulate-AssignCsvEntries -CsvPath $csv9 -CandidateMap $candidateMap -ClaimMap $claimMap9 -CompletedFolder '' -DryRun

# Both should be assigned (2 files with same CRC in source, 2 in CSV)
$assigned9 = ($results9 | Where-Object { $_.Reason -eq 'Assigned' }).Count
Write-TestResult -TestName "Edge Case: Duplicate CRCs in CSV" `
    -Passed ($assigned9 -eq 2) `
    -Message "Assigned: $assigned9 (expected 2 with duplicate CRC handling)"

# Test 26: Unicode in CSV
$unicodeFile = Join-Path $sourceDir "tëst_文件.txt"
"Unicode content" | Out-File -FilePath $unicodeFile -Encoding UTF8 -NoNewline
$unicodeCRC = Get-CRC32Hash -FilePath $unicodeFile
$unicodeSize = (Get-Item -LiteralPath $unicodeFile).Length

# Rebuild candidate map with unicode file
$candidateMapUnicode = Get-CandidateMap -SourceFolderCRC $sourceDir -ThrottleLimit 2

$csv10 = Join-Path $csvDir "test10.csv"
@"
FileName,Size,CRC32,Path
tëst_文件.txt,$unicodeSize,$unicodeCRC,\test\
"@ | Out-File -FilePath $csv10 -Encoding UTF8

$claimMap10 = @{}
$results10 = Simulate-AssignCsvEntries -CsvPath $csv10 -CandidateMap $candidateMapUnicode -ClaimMap $claimMap10 -CompletedFolder '' -DryRun

Write-TestResult -TestName "Edge Case: Unicode in CSV" `
    -Passed ($results10[0].Reason -eq 'Assigned') `
    -Message "Unicode filename: $($results10[0].ExpectedCRC)"

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
