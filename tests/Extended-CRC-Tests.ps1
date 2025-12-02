<#
.SYNOPSIS
    Extended test suite for `CRC-FileOrganizer.ps1` covering multiple edge cases.

.DESCRIPTION
    Creates a disposable working area from the bundled TestSourceData.zip, injects
    several CSV/file scenarios (header rows, quoted filenames, duplicate CRCs,
    cross-CSV conflicts, empty CSVs, unicode/special characters) and runs the
    `CRC-FileOrganizer.ps1` script. Validates expected behavior and emits a
    concise report.

.PARAMETER KeepData
    If specified, preserves the working directory for manual inspection.
#>

param([switch]$KeepData)

$ErrorActionPreference = 'Stop'
$ScriptPath = Join-Path $PSScriptRoot '..\CSV_Processing\CRC-FileOrganizer.ps1'
$TestZip = Join-Path $PSScriptRoot '..\TestData\TestSourceData.zip'
$WorkRoot = Join-Path $PSScriptRoot '..\TestData\ExtendedWorking'

function Assert-True { param($cond,$msg) if (-not $cond) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 2 } else { Write-Host "PASS: $msg" -ForegroundColor Green } }
function Assert-FileExists { param($p,$msg) Assert-True (Test-Path -LiteralPath $p) $msg }

Write-Host "Preparing extended test workspace: $WorkRoot" -ForegroundColor Cyan
if (Test-Path $WorkRoot) { Remove-Item $WorkRoot -Recurse -Force }
New-Item -Path $WorkRoot -ItemType Directory -Force | Out-Null
Expand-Archive -Path $TestZip -DestinationPath $WorkRoot -Force

# Ensure log/completed dirs exist
@('_98_Logs','_99_Completed') | ForEach-Object { $d = Join-Path $WorkRoot $_; if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }

# Dot-source CRC helper to compute CRCs for synthetic CSV rows
. (Join-Path $PSScriptRoot '..\Functions\CRC-FileOrganizerLib.ps1')

$csvDir = Join-Path $WorkRoot '_01_CSV_Source'
$srcDir = Join-Path $WorkRoot '_02_Image_Source'
$logDir = Join-Path $WorkRoot '_98_Logs'
$completed = Join-Path $WorkRoot '_99_Completed'

Write-Host "Injecting test scenarios..." -ForegroundColor Cyan

# 1) Header row CSV (should be handled)
$hdrCsv = Join-Path $csvDir 'HeaderRow_Test.csv'
$sample = Get-ChildItem -Path $csvDir -Filter '*.csv' | Select-Object -First 1
if ($sample) { $sampleLines = Get-Content -LiteralPath $sample.FullName -Encoding UTF8; $first = $sampleLines[0]; $rest = $sampleLines | Select-Object -Skip 1; }
"FileName,Size,CRC32,Path,Comment" | Out-File -FilePath $hdrCsv -Encoding UTF8
if ($rest) { $rest[0..([math]::Min(4,$rest.Count-1))] | Out-File -FilePath $hdrCsv -Append -Encoding UTF8 }

# 2) Quoted filename with comma
$quotedFolder = Join-Path $srcDir 'quoted_test'
New-Item -ItemType Directory -Path $quotedFolder -Force | Out-Null
$quotedName = 'file,with,comma.jpg'
$quotedPath = Join-Path $quotedFolder $quotedName
[System.IO.File]::WriteAllBytes($quotedPath,[byte[]](1..10))
$crc = Get-CRC32Hash -FilePath $quotedPath
$size = (Get-Item -LiteralPath $quotedPath).Length
"`"$quotedName`",$size,$crc,quoted_test,quoted comma file" | Out-File -FilePath (Join-Path $csvDir 'QuotedComma_Test.csv') -Encoding UTF8

# 3) Duplicate CRCs in a CSV (same CRC line repeated)
$dupFolder = Join-Path $srcDir 'dup_test'
New-Item -ItemType Directory -Path $dupFolder -Force | Out-Null
$dupFile = Join-Path $dupFolder 'dupA.jpg'
[System.IO.File]::WriteAllBytes($dupFile,[byte[]](2..20))
$crcDup = Get-CRC32Hash -FilePath $dupFile
$sizeDup = (Get-Item -LiteralPath $dupFile).Length
$dupCsv = Join-Path $csvDir 'DuplicateCRC_Test.csv'
1..3 | ForEach-Object { "dupA.jpg,$sizeDup,$crcDup,dup_test,duplicate $_" | Out-File -FilePath $dupCsv -Append -Encoding UTF8 }

# 4) Cross-CSV conflict: two CSVs reference same CRC (claiming)
$confFolder = Join-Path $srcDir 'conf_test'
New-Item -ItemType Directory -Path $confFolder -Force | Out-Null
$confFile = Join-Path $confFolder 'shared.jpg'
[System.IO.File]::WriteAllBytes($confFile,[byte[]](3..30))
$crcConf = Get-CRC32Hash -FilePath $confFile
$sizeConf = (Get-Item -LiteralPath $confFile).Length
"shared.jpg,$sizeConf,$crcConf,conf_test,first csv" | Out-File -FilePath (Join-Path $csvDir 'ConflictA.csv') -Encoding UTF8
"shared.jpg,$sizeConf,$crcConf,conf_test,second csv" | Out-File -FilePath (Join-Path $csvDir 'ConflictB.csv') -Encoding UTF8

# 5) Empty CSV
New-Item -ItemType File -Path (Join-Path $csvDir 'Empty_Test.csv') -Force | Out-Null

# 6) Unicode / special characters filename
$uniFolder = Join-Path $srcDir 'unicode_test'
New-Item -ItemType Directory -Path $uniFolder -Force | Out-Null
$uniName = 'Ménage & Friends [第1].jpg'
$uniPath = Join-Path $uniFolder $uniName
[System.IO.File]::WriteAllBytes($uniPath,[byte[]](4..40))
$crcUni = Get-CRC32Hash -FilePath $uniPath
$sizeUni = (Get-Item -LiteralPath $uniPath).Length
"$uniName,$sizeUni,$crcUni,unicode_test,unicode name" | Out-File -FilePath (Join-Path $csvDir 'Unicode_Test.csv') -Encoding UTF8

# --- Additional legacy/edge-case CSV scenarios ---

# 7) Semicolon-delimited CSV (legacy regional exports)
$semiFolder = Join-Path $srcDir 'semi_test'
New-Item -ItemType Directory -Path $semiFolder -Force | Out-Null
$semiFile = Join-Path $semiFolder 'semi.jpg'
[System.IO.File]::WriteAllBytes($semiFile,[byte[]](5..50))
$crcSemi = Get-CRC32Hash -FilePath $semiFile
$sizeSemi = (Get-Item -LiteralPath $semiFile).Length
"semi.jpg;$sizeSemi;$crcSemi;semi_test;semicolon delimiter" | Out-File -FilePath (Join-Path $csvDir 'Semicolon_Test.csv') -Encoding UTF8

# 8) Tab-delimited CSV (some old tools export TSV)
$tabFolder = Join-Path $srcDir 'tab_test'
New-Item -ItemType Directory -Path $tabFolder -Force | Out-Null
$tabFile = Join-Path $tabFolder 'tabfile.jpg'
[System.IO.File]::WriteAllBytes($tabFile,[byte[]](6..60))
$crcTab = Get-CRC32Hash -FilePath $tabFile
$sizeTab = (Get-Item -LiteralPath $tabFile).Length
[System.Text.Encoding]::UTF8.GetBytes("tabfile`t$sizeTab`t$crcTab`t tab_test`t tab-delim") | Set-Content -Path (Join-Path $csvDir 'Tab_Test.csv') -Encoding Byte

# 9) UTF-8 BOM + header present (older Excel saves)
$bomFolder = Join-Path $srcDir 'bom_test'
New-Item -ItemType Directory -Path $bomFolder -Force | Out-Null
$bomFile = Join-Path $bomFolder 'bom.jpg'
[System.IO.File]::WriteAllBytes($bomFile,[byte[]](7..70))
$crcBom = Get-CRC32Hash -FilePath $bomFile
$sizeBom = (Get-Item -LiteralPath $bomFile).Length
[System.Text.Encoding]::UTF8.GetPreamble() + [System.Text.Encoding]::UTF8.GetBytes("FileName,Size,CRC32,Path,Comment`n") | Set-Content -Path (Join-Path $csvDir 'BOM_Test.csv') -Encoding Byte
[System.Text.Encoding]::UTF8.GetBytes("bom.jpg,$sizeBom,$crcBom,bom_test,BOM header row") | Add-Content -Path (Join-Path $csvDir 'BOM_Test.csv') -Encoding Byte

# 10) Different column order but with headers (CRC first)
$reorderFolder = Join-Path $srcDir 'reorder_test'
New-Item -ItemType Directory -Path $reorderFolder -Force | Out-Null
$reFile = Join-Path $reorderFolder 'reorder.jpg'
[System.IO.File]::WriteAllBytes($reFile,[byte[]](8..80))
$crcRe = Get-CRC32Hash -FilePath $reFile
$sizeRe = (Get-Item -LiteralPath $reFile).Length
"CRC32,Size,FileName,Path,Comment" | Out-File -FilePath (Join-Path $csvDir 'Reorder_Test.csv') -Encoding UTF8
"$crcRe,$sizeRe,reorder.jpg,reorder_test,reordered header" | Out-File -FilePath (Join-Path $csvDir 'Reorder_Test.csv') -Append -Encoding UTF8

# 11) Filename with embedded quotes (CSV-escaped by doubling quotes)
$qFolder = Join-Path $srcDir 'qtest'
New-Item -ItemType Directory -Path $qFolder -Force | Out-Null
$qName = 'quote"inner".jpg'
$qPath = Join-Path $qFolder $qName
[System.IO.File]::WriteAllBytes($qPath,[byte[]](9..90))
$crcQ = Get-CRC32Hash -FilePath $qPath
$sizeQ = (Get-Item -LiteralPath $qPath).Length
"""quote""""inner""".jpg",$sizeQ,$crcQ,qtest,embedded quotes" | Out-File -FilePath (Join-Path $csvDir 'EmbeddedQuotes_Test.csv') -Encoding UTF8

# 12) Filename with leading and trailing spaces (quoted to preserve)
$spFolder = Join-Path $srcDir 'sp_test'
New-Item -ItemType Directory -Path $spFolder -Force | Out-Null
$spName = ' leading and trailing .jpg'
$spPath = Join-Path $spFolder $spName
[System.IO.File]::WriteAllBytes($spPath,[byte[]](10..100))
$crcSp = Get-CRC32Hash -FilePath $spPath
$sizeSp = (Get-Item -LiteralPath $spPath).Length
"`"$spName`",$sizeSp,$crcSp,sp_test,leading/trailing spaces" | Out-File -FilePath (Join-Path $csvDir 'Spaces_Test.csv') -Encoding UTF8

# 13) CSV with blank lines interspersed
$blankCsv = Join-Path $csvDir 'BlankLines_Test.csv'
"FileName,Size,CRC32,Path,Comment" | Out-File -FilePath $blankCsv -Encoding UTF8
"blank1.jpg,10,DEADBEEF,blank_test,first" | Out-File -FilePath $blankCsv -Append -Encoding UTF8
"" | Out-File -FilePath $blankCsv -Append -Encoding UTF8
"blank2.jpg,11,FEEDBEEF,blank_test,second" | Out-File -FilePath $blankCsv -Append -Encoding UTF8

# create the actual blank-case files and use correct CRCs
$b1 = Join-Path (Join-Path $srcDir 'blank_test') 'blank1.jpg'
New-Item -ItemType Directory -Path (Join-Path $srcDir 'blank_test') -Force | Out-Null
[System.IO.File]::WriteAllBytes($b1,[byte[]](11..20))
$crcB1 = Get-CRC32Hash -FilePath $b1
(Get-Content -LiteralPath $blankCsv) -replace 'DEADBEEF',$crcB1 | Set-Content -LiteralPath $blankCsv -Encoding UTF8
$b2 = Join-Path (Join-Path $srcDir 'blank_test') 'blank2.jpg'
[System.IO.File]::WriteAllBytes($b2,[byte[]](12..22))
$crcB2 = Get-CRC32Hash -FilePath $b2
(Get-Content -LiteralPath $blankCsv) -replace 'FEEDBEEF',$crcB2 | Set-Content -LiteralPath $blankCsv -Encoding UTF8

# End additional legacy scenarios

Write-Host "Running `CRC-FileOrganizer.ps1` against extended workspace..." -ForegroundColor Cyan
$params = @{
    RootFolder = $csvDir + '\'
    SourceFolderCRC = $srcDir + '\'
    LogFolder = $logDir + '\'
    CompletedFolder = $completed + '\'
    ThrottleLimit = 4
}

$start = Get-Date
& $ScriptPath @params
$elapsed = (Get-Date) - $start
Write-Host "Script completed in $($elapsed.TotalSeconds) seconds" -ForegroundColor Cyan

Write-Host "Validating extended scenarios..." -ForegroundColor Cyan

# Header CSV should have been processed and moved to completed
$hdrCompletedFound = Get-ChildItem -LiteralPath $completed -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'HeaderRow_Test.csv' }
Assert-True ($hdrCompletedFound) "Header CSV moved to completed and processed"

# Stricter: verify HeaderRow moved file count matches CSV data rows (skip header)
$hdrCsvRows = @(Get-Content -LiteralPath $hdrCsv -Encoding UTF8 | Where-Object { $_ -ne '' })
$expectedHdrFiles = if ($hdrCsvRows.Count -gt 0) { ($hdrCsvRows | Select-Object -Skip 1).Count } else { 0 }
$hdrMovedFiles = (Get-ChildItem -LiteralPath (Join-Path $completed 'HeaderRow_Test') -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'HeaderRow_Test.csv' }).Count
Assert-True ($hdrMovedFiles -eq $expectedHdrFiles) "HeaderRow moved files count matches CSV data rows (expected $expectedHdrFiles, got $hdrMovedFiles)"

# Quoted comma file should be moved to completed
Assert-True (Get-ChildItem -LiteralPath $completed -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $quotedName }) "Quoted-comma filename moved to completed"

# Stricter: QuotedComma completed folder contains exactly one non-CSV file
$quotedCompletedFolder = Join-Path $completed 'QuotedComma_Test'
$quotedMovedCount = (Get-ChildItem -LiteralPath $quotedCompletedFolder -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ne '.csv' }).Count
Assert-True ($quotedMovedCount -eq 1) "QuotedComma completed folder contains exactly 1 moved file (got $quotedMovedCount)"

# Duplicate CRC CSV: should be processed (duplicates no longer skip)
Assert-True (Test-Path (Join-Path $completed 'DuplicateCRC_Test\DuplicateCRC_Test.csv')) "Duplicate CRC CSV moved to completed or processed"

# Stricter: DuplicateCSV rows refer to the same source file; expect exactly 1 moved file (we only created one physical file 'dupA.jpg')
$dupCompletedFolder = Join-Path $completed 'DuplicateCRC_Test'
$dupMovedFiles = (Get-ChildItem -LiteralPath $dupCompletedFolder -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'DuplicateCRC_Test.csv' }).Count
Assert-True ($dupMovedFiles -eq 1) "DuplicateCRC moved file count should be 1 (got $dupMovedFiles)"

# Conflict claiming: only one CSV should have claimed the shared file (so file moved once)
$confAPath = Join-Path $completed 'ConflictA'
$confBPath = Join-Path $completed 'ConflictB'
$confAHas = Test-Path (Join-Path $confAPath 'shared.jpg')
$confBHas = Test-Path (Join-Path $confBPath 'shared.jpg')
Assert-True ((($confAHas -xor $confBHas))) "Cross-CSV conflict: shared file claimed by only one CSV (A xor B)"

# Empty CSV should be left in source (no action)
Assert-True (Test-Path (Join-Path $csvDir 'Empty_Test.csv')) "Empty CSV remains in source"

# Stricter: no completed folder should have been created for Empty_Test
Assert-True (-not (Test-Path (Join-Path $completed 'Empty_Test'))) "Empty CSV did not create a completed folder"

# Unicode filename moved
Assert-True (Get-ChildItem -LiteralPath $completed -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $uniName }) "Unicode filename moved to completed"

# Stricter: Unicode completed folder contains exactly one non-CSV file and exact filename preserved
$uniCompletedFolder = Join-Path $completed 'Unicode_Test'
$uniMovedFiles = (Get-ChildItem -LiteralPath $uniCompletedFolder -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'Unicode_Test.csv' })
Assert-True ($uniMovedFiles.Count -eq 1) "Unicode completed folder contains exactly 1 moved file (got $($uniMovedFiles.Count))"
Assert-True ($uniMovedFiles[0].Name -eq $uniName) "Unicode filename preserved in completed (expected '$uniName', got '$($uniMovedFiles[0].Name)')"

# --- Assertions for additional legacy scenarios ---

# Semicolon-delimited CSV: either processed (preferred) or left in source (acceptable)
$semiCompleted = Join-Path $completed 'Semicolon_Test'
$semiCsvInCompleted = Test-Path (Join-Path $semiCompleted 'Semicolon_Test.csv')
$semiFileMoved = Test-Path (Join-Path $semiCompleted 'semi.jpg')
if ($semiCsvInCompleted) {
    $movedCrc = Get-CRC32Hash -FilePath (Join-Path $semiCompleted 'semi.jpg')
    Assert-True ($movedCrc -eq $crcSemi) "Semicolon file moved and CRC matches"
} else {
    Assert-True (Test-Path (Join-Path $csvDir 'Semicolon_Test.csv')) "Semicolon CSV left in source (parser did not accept semicolons)"
}

# Tab-delimited CSV: accept either behavior as legacy tools differ
$tabCompleted = Join-Path $completed 'Tab_Test'
if (Test-Path (Join-Path $tabCompleted 'Tab_Test.csv')) {
    $movedCrc = Get-CRC32Hash -FilePath (Join-Path $tabCompleted 'tabfile.jpg')
    Assert-True ($movedCrc -eq $crcTab) "Tab-delimited file moved and CRC matches"
} else {
    Assert-True (Test-Path (Join-Path $csvDir 'Tab_Test.csv')) "Tab-delimited CSV left in source (parser did not accept tabs)"
}

# BOM header CSV should be parsed and moved
$bomCompleted = Join-Path $completed 'BOM_Test'
Assert-True (Test-Path (Join-Path $bomCompleted 'bom.jpg')) "BOM CSV parsed and file moved"
Assert-True ((Get-CRC32Hash -FilePath (Join-Path $bomCompleted 'bom.jpg')) -eq $crcBom) "BOM file CRC matches"

# Reordered header CSV (CRC first) should be parsed and file moved
$reCompleted = Join-Path $completed 'Reorder_Test'
Assert-True (Test-Path (Join-Path $reCompleted 'reorder.jpg')) "Reorder CSV parsed and file moved"
Assert-True ((Get-CRC32Hash -FilePath (Join-Path $reCompleted 'reorder.jpg')) -eq $crcRe) "Reorder file CRC matches"

# Embedded quotes filename should be handled and preserved
$eqCompleted = Join-Path $completed 'EmbeddedQuotes_Test'
Assert-True (Test-Path (Join-Path $eqCompleted $qName)) "Embedded-quote filename moved to completed"
Assert-True ((Get-CRC32Hash -FilePath (Join-Path $eqCompleted $qName)) -eq $crcQ) "Embedded-quote file CRC matches"

# Leading/trailing spaces: file should be moved and name preserved (quoting handled)
$spCompleted = Join-Path $completed 'Spaces_Test'
Assert-True (Test-Path (Join-Path $spCompleted $spName)) "Spaces filename moved to completed"
Assert-True ((Get-CRC32Hash -FilePath (Join-Path $spCompleted $spName)) -eq $crcSp) "Spaces file CRC matches"

# Blank-lines CSV: both entries should be processed and files moved
$blankCompleted = Join-Path $completed 'BlankLines_Test'
Assert-True (Test-Path (Join-Path $blankCompleted 'blank1.jpg')) "BlankLines first file moved"
Assert-True (Test-Path (Join-Path $blankCompleted 'blank2.jpg')) "BlankLines second file moved"
Assert-True ((Get-CRC32Hash -FilePath (Join-Path $blankCompleted 'blank1.jpg')) -eq $crcB1) "BlankLines blank1 CRC matches"
Assert-True ((Get-CRC32Hash -FilePath (Join-Path $blankCompleted 'blank2.jpg')) -eq $crcB2) "BlankLines blank2 CRC matches"

Write-Host "Extended tests passed" -ForegroundColor Green

if (-not $KeepData) {
    Write-Host "Cleaning up extended test workspace..." -ForegroundColor Gray
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned" -ForegroundColor Gray
}
else {
    Write-Host "Preserved test data at: $WorkRoot" -ForegroundColor Cyan
}

exit 0
