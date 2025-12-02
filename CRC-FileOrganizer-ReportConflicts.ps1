<#
Reporting-only script: simulates file assignment and writes conflict/claim reports
Does not move files. Uses Functions\CRC-FileOrganizerLib.ps1 to compute CRCs and simulate claims.
#>

[CmdletBinding()]
param(
    [string]$RootFolder = 'D:\ScanSorting\_01_CSV_Source\Teenfuns\',
    [string]$SourceFolderCRC = 'D:\ScanSorting\_02_Image_Source\Teenfuns\',
    [string]$ReportConflictsPath = 'D:\ScanSorting\_98_Logs\',
    [switch]$DryRun,
    [int]$ThrottleLimit = 12
)

if (-not (Test-Path -LiteralPath $ReportConflictsPath)) {
    New-Item -ItemType Directory -Path $ReportConflictsPath -Force | Out-Null
}

# Initialize logging and archive existing log/CSV files in the report folder (same behavior as CRC-FileOrganizer)
$ErrorActionPreference = 'Stop'
$LogFolder = $ReportConflictsPath
$LogFile = Join-Path $LogFolder "report_conflicts_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

try {
    $normalizedLogFolder = $LogFolder.TrimEnd('\')
    $existingLogs = Get-ChildItem -LiteralPath $LogFolder -File -ErrorAction SilentlyContinue |
                    Where-Object {
                        ($_.Extension -eq '.log' -or $_.Extension -eq '.csv') -and
                        ($_.DirectoryName.TrimEnd('\') -eq $normalizedLogFolder)
                    }

    if ($existingLogs -and $existingLogs.Count -gt 0) {
        $archiveTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $archiveFolder = Join-Path $LogFolder "Archive\$archiveTimestamp"

        Write-Host -ForegroundColor Cyan "Found $($existingLogs.Count) log/CSV file(s) to archive"

        if ($DryRun) {
            Write-Host -ForegroundColor Cyan "DryRun: Would archive $($existingLogs.Count) existing log file(s) to: $archiveFolder"
        }
        else {
            $null = New-Item -ItemType Directory -Path $archiveFolder -Force
            foreach ($existingLogFile in $existingLogs) {
                Move-Item -LiteralPath $existingLogFile.FullName -Destination $archiveFolder -Force
            }
            Write-Host -ForegroundColor Cyan "Archived $($existingLogs.Count) existing log file(s) to: Archive\$archiveTimestamp"
        }
    }
    else {
        Write-Host -ForegroundColor DarkGray "No existing log files to archive"
    }
}
catch {
    Write-Host -ForegroundColor Yellow "Warning: Could not archive existing log files: $_"
}

# Simple logging helpers for this reporter
function Write-Log {
    param($Message)
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Add-Content -Path $LogFile -Value $logEntry
    Write-Host $logEntry
}

function Write-LogOnly {
    param($Message)
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Add-Content -Path $LogFile -Value $logEntry
}

# Dot-source library
. (Join-Path $PSScriptRoot '..\Functions\CRC-FileOrganizerLib.ps1')

Write-Host "Building candidate map (this will compute CRC32 for files under $SourceFolderCRC)" -ForegroundColor Cyan
$candidateMap = Get-CandidateMap -SourceFolderCRC $SourceFolderCRC -ThrottleLimit $ThrottleLimit

Write-Host "Found $($candidateMap.Keys.Count) unique CRC+Size keys" -ForegroundColor Cyan

# Initialize claim map (tracks files claimed during simulation)
$claimMap = @{}

# Find CSVs
$csvFiles = Get-ChildItem -LiteralPath $RootFolder -Filter "*.csv" | Where-Object { $_.Name -notlike "*_missing_files.csv" }

$allResults = @()

foreach ($csv in $csvFiles) {
    Write-Host "Simulating assignment for $($csv.Name)" -ForegroundColor Gray
    $res = Simulate-AssignCsvEntries -CsvPath $csv.FullName -CandidateMap $candidateMap -ClaimMap $claimMap -CompletedFolder '' -DryRun:$DryRun
    $allResults += $res
}

# Filter to interesting results (not assigned or claimed) but exclude items that are simply missing
# (Reason 'NotFound') — those are purely missing files and should not clutter the conflict report.
$conflicts = $allResults | Where-Object { $_.Reason -ne 'Assigned' -and $_.Reason -ne 'NotFound' }

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$reportFile = Join-Path $ReportConflictsPath "conflicts-$timestamp.csv"

if ($conflicts.Count -gt 0) {
    $conflicts | Select-Object CSVFile,EntryIndex,ExpectedCRC,ExpectedSize,@{Name='CandidateFiles';Expression={ $_.CandidateFiles }},AssignedFile,Reason,ClaimedBy,Timestamp,DryRun |
        Export-Csv -Path $reportFile -NoTypeInformation -Encoding UTF8 -Force

    Write-Host "Wrote conflict report: $reportFile" -ForegroundColor Yellow
    Write-Host "Conflict count: $($conflicts.Count)" -ForegroundColor Yellow
}
else {
    Write-Host "No conflicts detected in simulation" -ForegroundColor Green
}

# Also write a brief summary
$summary = [PSCustomObject]@{
    Time = (Get-Date).ToString('o')
    TotalCSVs = $csvFiles.Count
    TotalEntries = $allResults.Count
    Conflicts = $conflicts.Count
}

$summaryFile = Join-Path $ReportConflictsPath "conflicts-summary-$timestamp.json"
$summary | ConvertTo-Json | Set-Content -LiteralPath $summaryFile -Encoding UTF8
Write-Host "Wrote summary: $summaryFile" -ForegroundColor Cyan
