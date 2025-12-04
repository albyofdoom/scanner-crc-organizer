## To-Do:
## - DONE! Search for misnamed files
## - Done! Handling of duplicate names in single CSV
## - DONE! Handling of multiple files of same name, aka, pick the one with the right CRC
## - DONE! Error handler for already existing files
## - DONE! CRC32 Checking (Get-FileHash Does not support CRC32)
## - DONE! Check arrays against arrays, stop checking single files
## - DONE! Comment all your code so you know WTF you did when you look at this later
## - DONE! Add status messages and maybe a progress bar.

## Workflow:
## 1. Archive old log files to Archive subfolder (timestamped)
## 2. Calculate CRC32 hashes for all files in Source
## 3. For each CSV:
##    - Match files by CRC32
##    - If CSV is COMPLETE (all files found): move files from Source → Completed, move CSV to Completed
##    - If CSV is INCOMPLETE (some files missing): leave files in Source, CSV stays in root
## 4. Clean up empty folders in Source

## Developer Notes (workflow for future features):
## - When introducing a new feature, create a short-lived branch (e.g., feature/<short-description>)
## - Use a conventional commit message prefix (e.g., feat(csv): add ForceCSV parameter, fix(csv): handle duplicate CRCs)
## - Keep changes small and focused per branch; open a PR for review and testing
## - Run `.\CRC-FileOrganizer.ps1 -DryRun` locally to validate before merging
## - After PR review, merge into master and delete the feature branch

###############################
### Parameters and Defaults ###
###############################

[CmdletBinding()]
param(
    # This is where our CSV files are located and logs will be written
    [string]$RootFolder = 'D:\ScanSorting\_01_CSV_Source\',

    # This is where all the files we downloaded reside.
    [string]$SourceFolderCRC = 'D:\ScanSorting\_02_Image_Source\',

    # (Deprecated - kept for backward compatibility, no longer used in hybrid workflow)
    [string]$StagingFolder = 'D:\ScanSorting\_03_Staging_Folder\',

    # This is where log files are written
    [string]$LogFolder = 'D:\ScanSorting\_98_Logs\',

    # This is where csv and their completed collections of files are moved
    [string]$CompletedFolder = 'D:\ScanSorting\_99_Completed\',

    # Dry run mode: when present, the script will not create folders or move files; it will only log intended actions
    [switch]$DryRun,

    # Controls the parallelism for CRC hashing
    [int]$ThrottleLimit = 12
    ,
    # Optional override list of CSV base names or file paths to force move to Completed even if CSV is incomplete
    [string[]]$ForceCSV = @(),
    # If specified, allow forced CSVs to be moved even when zero matching files were found
    [switch]$ForceCSVMoveEmpty,
    # If specified, move matched files to CompletedFolder even if incomplete, but leave CSV in RootFolder
    [switch]$ForceMoveFiles
    ,
    # If specified, run a post-pass that compares conflicts (source vs destination) by size+CRC
    [switch]$CompareConflicts,
    # Throttle limit for conflict CRC calculations (Compare-Conflicts function)
    [int]$ConflictThrottleLimit = 8
    ,
    # Automatically confirm large conflict CRC comparisons (skip interactive prompt)
    [switch]$AutoConfirmConflicts,
    # If combined conflicts exceed this number, prompt (or skip if AutoConfirmConflicts set)
    [int]$SkipCRCIfOver = 500
)

###############################
#### End of User Parameters ###
###############################

# Set error handling preference and initialize logging
$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $LogFolder "file_moves_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Parameter validation
if (!(Test-Path $RootFolder)) {
    throw "Root folder not found: $RootFolder"
}
if (!(Test-Path $SourceFolderCRC)) {
    throw "Source folder not found: $SourceFolderCRC"
}
if (!(Test-Path $LogFolder)) {
    throw "Log folder not found: $LogFolder"
}
if (!(Test-Path $CompletedFolder)) {
    throw "Completed folder not found: $CompletedFolder"
}

# Validate parameter combinations
if ($ForceCSV -and $ForceCSV.Count -gt 0 -and $ForceMoveFiles) {
    throw "Cannot use both -ForceCSV and -ForceMoveFiles switches simultaneously. Use -ForceCSV to move files+CSV together, or -ForceMoveFiles to move only files."
}

# Archive existing log files before starting new run
try {
    # Get files only from root of LogFolder, excluding Archive subfolders
    # Normalize the LogFolder path for comparison (remove trailing backslash if present)
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

# Logging function
function Write-Log {
    param($Message)
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Add-Content -Path $LogFile -Value $logEntry
    Write-Host $logEntry
}

# Dot-source shared library for CRC helpers (keeps behavior identical)
. (Join-Path $PSScriptRoot 'CRC-FileOrganizerLib.ps1')

# Write to the log file only (don't print to console)
function Write-LogOnly {
    param($Message)
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Add-Content -Path $LogFile -Value $logEntry
}

 # Reusable helper to remove empty directories under a base path
 function Remove-EmptyDirectories {
     [CmdletBinding()]
     param(
         [Parameter(Mandatory)]
         [string]$BasePath,

         # Also remove the base path itself if it ends up empty
         [switch]$IncludeBase,

         # Optional context to improve log messages
         [string]$Context
     )

     try {
         if (Test-Path -LiteralPath $BasePath) {
             if ($Context) {
                 Write-LogOnly "Cleaning up empty directories under: $BasePath ($Context)"
             }
             else {
                 Write-LogOnly "Cleaning up empty directories under: $BasePath"
             }

             # Remove deepest empty directories first
             $dirs = Get-ChildItem -LiteralPath $BasePath -Directory -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName -Descending
             foreach ($dir in $dirs) {
                 $hasEntries = Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1
                 if (-not $hasEntries) {
                     if ($DryRun) {
                         Write-LogOnly "DryRun: Would remove empty directory: $($dir.FullName)"
                     }
                     else {
                         try {
                             Remove-Item -LiteralPath $dir.FullName -Force
                             Write-LogOnly "Removed empty directory: $($dir.FullName)"
                         }
                         catch {
                             Write-LogOnly "Failed to remove directory $($dir.FullName): $_"
                         }
                     }
                 }
             }

             if ($IncludeBase) {
                 $baseHasEntries = Get-ChildItem -LiteralPath $BasePath -Force -ErrorAction SilentlyContinue | Select-Object -First 1
                 if (-not $baseHasEntries) {
                     if ($DryRun) {
                         Write-LogOnly "DryRun: Would remove empty base directory: $BasePath"
                     }
                     else {
                         try {
                             Remove-Item -LiteralPath $BasePath -Force
                             Write-LogOnly "Removed empty base directory: $BasePath"
                         }
                        catch {
                            Write-LogOnly "Failed to remove base directory $($BasePath): $_"
                        }
                     }
                 }
             }
         }
     }
    catch {
        Write-LogOnly "Error while cleaning directories under $($BasePath): $_"
    }
 }

# Function to compare conflicts by computing CRCs for source and destination files
function Compare-Conflicts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputCsv,
        [Parameter(Mandatory=$true)]
        [string]$OutputCsv,
        [int]$ThrottleLimit = 4
    )

    Write-Log "Starting conflict comparisons: $((Split-Path $InputCsv -Leaf)) -> $((Split-Path $OutputCsv -Leaf))"

    if (-not (Test-Path -LiteralPath $InputCsv)) {
        Write-Log "Compare-Conflicts: Input CSV not found: $InputCsv"
        return
    }

    $rows = Import-Csv -LiteralPath $InputCsv
    if (-not $rows -or $rows.Count -eq 0) {
        Write-LogOnly "Compare-Conflicts: No rows to process in $InputCsv"
        return
    }

    # Capture function definitions for runspaces
    $GetCRC32HashFunction = ${function:Get-CRC32Hash}.ToString()
    $AddCRC32TypeFunction = ${function:Add-CRC32Type}.ToString()

    # Run parallel comparisons as a job for controlled throttling
    $job = $rows | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        ${function:Add-CRC32Type} = $using:AddCRC32TypeFunction
        ${function:Get-CRC32Hash} = $using:GetCRC32HashFunction
        Add-CRC32Type

        $srcPath = $_.SourceFullPath
        $dstPath = $_.DestinationPath
        $srcExists = Test-Path -LiteralPath $srcPath
        $dstExists = Test-Path -LiteralPath $dstPath

        $srcSize = $null
        $dstSize = $null
        $srcCRC = ''
        $dstCRC = ''
        $sizeMatch = $false
        $crcMatch = 'NA'

        if ($srcExists) {
            try { $srcSize = (Get-Item -LiteralPath $srcPath -ErrorAction Stop).Length } catch { $srcSize = $null }
        }
        if ($dstExists) {
            try { $dstSize = (Get-Item -LiteralPath $dstPath -ErrorAction Stop).Length } catch { $dstSize = $null }
        }

        if ($null -ne $srcSize -and $null -ne $dstSize) { $sizeMatch = ($srcSize -eq $dstSize) }

        if ($srcExists) {
            try { $srcCRC = Get-CRC32Hash -FilePath $srcPath } catch { $srcCRC = '' }
        }
        if ($dstExists) {
            try { $dstCRC = Get-CRC32Hash -FilePath $dstPath } catch { $dstCRC = '' }
        }

        if ($srcCRC -ne '' -and $dstCRC -ne '') {
            $crcMatch = ($srcCRC -eq $dstCRC)
        }

        $notes = @()
        if (-not $dstExists) { $notes += 'Destination missing' }
        elseif (-not $sizeMatch) { $notes += 'Size differs' }
        elseif ($crcMatch -eq $false) { $notes += 'CRC differs' }
        else { $notes += 'Match' }

        [PSCustomObject]@{
            FileName = $_.FileName
            Size = $_.Size
            CRC32 = $_.CRC32
            Path = $_.Path
            Comment = $_.Comment
            SourceFullPath = $srcPath
            DestinationPath = $dstPath
            SourceSize = $srcSize
            DestSize = $dstSize
            SizeMatch = $sizeMatch
            SourceCRC = $srcCRC
            DestCRC = $dstCRC
            CRCMatch = $crcMatch
            Notes = ($notes -join '; ')
        }
    } -AsJob

    # Collect job output incrementally
    $collected = @()
    while ($true) {
        $new = Receive-Job -Job $job -ErrorAction SilentlyContinue
        if ($new) { $collected += $new }
        if ($job.State -eq 'Completed' -and -not $new) { break }
        if ($job.State -eq 'Failed') { break }
        Start-Sleep -Milliseconds 200
    }
    $remaining = Receive-Job -Job $job -Wait -ErrorAction SilentlyContinue
    if ($remaining) { $collected += $remaining }

    # Export a single final CSV report
    $collected | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8 -Force
    Write-Log "Compare-Conflicts: Wrote $($collected.Count) rows to: $(Split-Path $OutputCsv -Leaf)"
}

# If DryRun is enabled, print a clear banner and write to the log
if ($DryRun) {
    Write-Host -ForegroundColor Yellow "DRY RUN: No folders will be created and no files will be moved."
    Write-Log "Dry run enabled - no create/move operations will be performed"
}



# CRC32 implementation and Get-CRC32Hash are provided by the shared library
# (dot-sourced at the top of this script: Functions\CRC-FileOrganizerLib.ps1)
# We rely on `Add-CRC32Type` and `Get-CRC32Hash` from the library so parallel
# runspaces can import the function definitions instead of embedding Add-Type
# C# blobs in multiple places.

# We use this to check the encoding of the incoming CSV, since it matters for oddball characters in file names
function Get-Encoding
{
    param
    (
        [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]
        $Path
    )

    process 
    {
        $bom = New-Object -TypeName System.Byte[](4)
            
        $fileStream = New-Object System.IO.FileStream($Path, 'Open', 'Read')
        
        $null = $fileStream.Read($bom,0,4)
        $fileStream.Close()
        $fileStream.Dispose()
        
        $enc = [Text.Encoding]::ASCII
        if ($bom[0] -eq 0x2b -and $bom[1] -eq 0x2f -and $bom[2] -eq 0x76) 
            { $enc =  [Text.Encoding]::UTF7 }
        if ($bom[0] -eq 0xff -and $bom[1] -eq 0xfe) 
            { $enc =  [Text.Encoding]::Unicode }
        if ($bom[0] -eq 0xfe -and $bom[1] -eq 0xff) 
            { $enc =  [Text.Encoding]::BigEndianUnicode }
        if ($bom[0] -eq 0x00 -and $bom[1] -eq 0x00 -and $bom[2] -eq 0xfe -and $bom[3] -eq 0xff) 
            { $enc =  [Text.Encoding]::UTF32}
        if ($bom[0] -eq 0xef -and $bom[1] -eq 0xbb -and $bom[2] -eq 0xbf) 
            { $enc =  [Text.Encoding]::UTF8}
            
        [PSCustomObject]@{
            Encoding = $enc
            Path = $Path
        }
    }
}

# Move to the Unnamed Files Folder for processing
Set-Location $SourceFolderCRC

# Calculate CRC32 hashes for all files and store in array
Write-Log "Starting CRC32 hash calculations"
Write-Host -ForegroundColor DarkYellow "`r`n--Calculating CRC32 Hashes--"
$FileSearchCRC = Get-ChildItem -LiteralPath $SourceFolderCRC -Recurse -att !H -File
$totalFiles = $FileSearchCRC.Count

    try {
        # Get the function definitions to pass to parallel context
        $GetCRC32HashFunction = ${function:Get-CRC32Hash}.ToString()
        $AddCRC32TypeFunction = ${function:Add-CRC32Type}.ToString()

        # Create the job for parallel processing (each runspace emits a PSCustomObject)
            $job = $FileSearchCRC | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            # Import helper functions into this runspace
            ${function:Add-CRC32Type} = $using:AddCRC32TypeFunction
            ${function:Get-CRC32Hash} = $using:GetCRC32HashFunction

            # Ensure CRC32 type is available in the runspace
            Add-CRC32Type

            $CRC32Hash = Get-CRC32Hash -FilePath $_.FullName

            [PSCustomObject]@{
                File = $_
                FullName = $_.Name
                CRC32 = $CRC32Hash
                Size = $_.Length
            }
        } -AsJob

        # Monitor progress while the job produces output incrementally
        $received = @()
        while ($true) {
            # Pull any completed results from the job (consumes them)
            $newResults = Receive-Job -Job $job -ErrorAction SilentlyContinue
            if ($newResults) { $received += $newResults }

            $hashCount = $received.Count
            $hashPercent = if ($totalFiles -gt 0) { [int](($hashCount / [double]$totalFiles) * 100) } else { 100 }
            $currentHashFile = if ($hashCount -gt 0) { $received[-1].File.Name } else { "" }

            # Use a stable progress Id so this progress doesn't conflict with other Write-Progress calls
            Write-Progress -Id 1 -Activity "Calculating CRC32 Hashes" -Status "Processing $hashCount of $totalFiles files - Current: $currentHashFile" -PercentComplete $hashPercent

            # Exit when the job has completed and there are no more results to receive
            if ($job.State -eq 'Completed' -and -not $newResults) { break }
            if ($job.State -eq 'Failed') { break }

            Start-Sleep -Milliseconds 200
        }

        # Receive any remaining results (if any) and combine
        $remaining = Receive-Job -Job $job -Wait -ErrorAction SilentlyContinue
        if ($remaining) { $received += $remaining }
        $FileHashes = $received

    # Create hashtable for O(1) lookups using composite CRC:Size keys
    # This matches the strategy used by Get-CandidateMap in the simulation
    $CRCLookup = @{}
    $duplicateKeys = 0
    $FileHashes | ForEach-Object {
        $key = "{0}:{1}" -f $_.CRC32, $_.Size  # Composite key: CRC:Size
        if (-not $CRCLookup.ContainsKey($key)) {
            $CRCLookup[$key] = @($_)  # Initialize as array
        }
        else {
            $CRCLookup[$key] += $_  # Add to existing array
            $duplicateKeys++
        }
    }

    if ($duplicateKeys -gt 0) {
        Write-Log "Found $duplicateKeys duplicate CRC32:Size combinations across $($FileHashes.Count) files"
        Write-Host -ForegroundColor Yellow "Note: Found $duplicateKeys files with duplicate CRC32:Size values (will use first available match)"
    }

    Write-Progress -Id 1 -Activity "Calculating CRC32 Hashes" -Completed
    Write-Log "Completed CRC32 calculations for $($FileHashes.Count) files"
}
catch {
    Write-Log "Error during CRC32 calculations: $_"
    throw
}

Write-Host "Calculated CRC32 hashes for $($FileHashes.Count) files"

# Get list of CSV files to process
$CRC_CSV_Files = Get-ChildItem -LiteralPath $RootFolder -Filter "*.csv" | Where-Object { $_.Name -notlike "*_missing_files.csv" }

$AllConflictTempFiles = @()
# Initialize summary tracking variables
$ZeroMatchCSVs = @()
$PartialMatchCSVs = @()
$FullMatchCSVs = @()
# Track forced CSVs (force-moved by user)
$ForcedCSVs = @()
# Track CSVs where files were force-moved but CSV left behind
$ForceMoveFilesCSVs = @()
# NOTE: conflict records are collected per-CSV and flushed to per-CSV temp files.

# Normalize ForceCSV list into exact base-names and wildcard patterns (case-insensitive)
$ForceCSVBaseNames = @()
$ForceCSVPatterns = @()
if ($ForceCSV -and $ForceCSV.Count -gt 0) {
    foreach ($entry in $ForceCSV) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $base = [IO.Path]::GetFileNameWithoutExtension($entry)
        if ($base -match '[\*\?]') {
            # keep wildcard patterns as-lower
            $ForceCSVPatterns += $base.ToLower()
        }
        else {
            $ForceCSVBaseNames += $base.ToLower()
        }
    }
    $ForceCSVBaseNames = $ForceCSVBaseNames | Sort-Object -Unique
    $ForceCSVPatterns = $ForceCSVPatterns | Sort-Object -Unique
}

# Warn if any ForceCSV exact entries were not found among CSV files, and check patterns for matches
if (($ForceCSVBaseNames.Count -gt 0) -or ($ForceCSVPatterns.Count -gt 0)) {
    $foundCSVBaseNames = $CRC_CSV_Files | ForEach-Object { $_.BaseName.ToLower() }

    # exact missing
    $missingExact = @()
    if ($ForceCSVBaseNames.Count -gt 0) {
        $missingExact = $ForceCSVBaseNames | Where-Object { -not ($foundCSVBaseNames -contains $_) }
    }

    # patterns that match nothing
    $missingPatterns = @()
    if ($ForceCSVPatterns.Count -gt 0) {
        foreach ($pat in $ForceCSVPatterns) {
            $matched = $foundCSVBaseNames | Where-Object { $_ -like $pat }
            if (-not $matched) { $missingPatterns += $pat }
        }
    }

    if (($missingExact.Count -gt 0) -or ($missingPatterns.Count -gt 0)) {
        foreach ($m in $missingExact) {
            Write-LogOnly "Warning: ForceCSV specified as '$m' but no CSV with that base name was found in Root folder"
            Write-Host -ForegroundColor Yellow "Warning: ForceCSV specified as '$m' but no CSV with that base name was found in Root folder"
        }
        foreach ($p in $missingPatterns) {
            Write-LogOnly "Warning: ForceCSV pattern '$p' did not match any CSV base names in Root folder"
            Write-Host -ForegroundColor Yellow "Warning: ForceCSV pattern '$p' did not match any CSV base names in Root folder"
        }
    }
    else {
        $active = @()
        if ($ForceCSVBaseNames.Count -gt 0) { $active += $ForceCSVBaseNames }
        if ($ForceCSVPatterns.Count -gt 0) { $active += $ForceCSVPatterns }
        Write-Log "ForceCSV override active for: $($active -join ', ')"
        Write-Host -ForegroundColor Cyan "ForceCSV override active for: $($active -join ', ')"
    }
}

# Here is where the magic happens for the Unnamed Files
ForEach($File in $CRC_CSV_Files){
    # Commence CSV Actions
    Write-Host -ForegroundColor Blue "`r`n--Processing" $File.Name "--"

    # Per-CSV in-memory conflict accumulator (flushed to temp per CSV to bound memory)
    $ConflictRecords = @()


    # RFC 4180-compliant CSV line parser
    function Parse-CSVLineRFC4180 {
        param([string]$line)
        $fields = @()
        $field = ""
        $inQuotes = $false
        $i = 0
        while ($i -lt $line.Length) {
            $char = $line[$i]
            if ($inQuotes) {
                if ($char -eq '"') {
                    if (($i + 1) -lt $line.Length -and $line[$i + 1] -eq '"') {
                        $field += '"'
                        $i++
                    } else {
                        $inQuotes = $false
                    }
                } else {
                    $field += $char
                }
            } else {
                if ($char -eq ',') {
                    $fields += $field
                    $field = ""
                } elseif ($char -eq '"') {
                    $inQuotes = $true
                } else {
                    $field += $char
                }
            }
            $i++
        }
        $fields += $field
        return $fields
    }

    Write-Host "--Importing CSV--"
    $rawLines = Get-Content -LiteralPath $File.FullName -Encoding UTF8
    $list = @()
    foreach ($line in $rawLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = Parse-CSVLineRFC4180 $line
        if ($parts.Count -ge 4) {
            $list += [PSCustomObject]@{
                FileName = $parts[0].Trim()
                Size     = $parts[1].Trim()
                CRC32    = $parts[2].Trim()
                Path     = $parts[3].Trim()
                Comment  = if ($parts.Count -ge 5) { $parts[4].Trim() } else { "" }
            }
        }
    }
    
    Write-LogOnly "Imported $($list.Count) entries from CSV"

    # Normalize Path fields to be defensive against malformed CSVs
    foreach ($entry in $list) {
        if ($null -ne $entry.Path) {
            # Trim whitespace
            $entry.Path = $entry.Path.Trim()

            # Convert forward slashes to backslashes (consistent with Windows paths)
            $entry.Path = $entry.Path -replace '/','\\'

            # If path was a single comma (malformed), normalize to empty and log warning
            if ($entry.Path -eq ',') {
                Write-Log "Warning: CSV $($File.Name) contained a path value of ',' - normalizing to empty path"
                Write-Host -ForegroundColor Yellow "Warning: CSV $($File.Name) contained a path value of ',' - normalizing to empty path"
                $entry.Path = ''
            }
        }
    }
    
    # Check if the first row is a header row (contains text like "FileName" or "CRC32") and skip it if so
    if ($list.Count -gt 0 -and ($list[0].FileName -match '^(FileName|File|Name)$' -or $list[0].CRC32 -match '^(CRC32|CRC|Checksum)$')) {
        Write-Log "Detected header row in CSV, skipping first row"
        $list = $list | Select-Object -Skip 1
    }

    # Check for duplicate CRCs within this CSV file
    Write-Host "--Checking for Duplicate CRCs in CSV--"
    $csvCRCCheck = @{}
    $duplicatesFound = @()
    
    foreach ($csvRow in $list) {
        # Only consider duplicates if CRC and Size both match (avoid false positives where CRC collides but sizes differ)
        $crcValue = "{0}:{1}" -f $csvRow.CRC32.ToString().ToUpper(), $csvRow.Size
        if ($csvCRCCheck.ContainsKey($crcValue)) {
            $duplicatesFound += [PSCustomObject]@{
                CRC32 = $crcValue
                FirstFile = $csvCRCCheck[$crcValue]
                DuplicateFile = $csvRow.FileName
            }
        }
        else {
            $csvCRCCheck[$crcValue] = $csvRow.FileName
        }
    }
    
    if ($duplicatesFound.Count -gt 0) {
        $warnMsg = "WARNING: CSV $($File.Name) contains $($duplicatesFound.Count) duplicate CRC32 value(s) (CRC+Size match). Processing will continue."
        Write-Log $warnMsg
        Write-Host -ForegroundColor Yellow $warnMsg
        Write-Host -ForegroundColor Red "Duplicate CRC32 values found (CRC | Size):"
        
        foreach ($dup in $duplicatesFound) {
            # $dup.CRC32 holds "CRC:Size" so split for separate display
            $parts = $dup.CRC32 -split ':'
            $crcOnly = $parts[0]
            $sizeOnly = if ($parts.Count -gt 1) { $parts[1] } else { '' }
            $dupMsg = "  CRC: $crcOnly | Size: $sizeOnly - First: '$($dup.FirstFile)' | Duplicate: '$($dup.DuplicateFile)'"
            Write-Host -ForegroundColor Red $dupMsg
            Write-Log $dupMsg
        }
        
        Write-Host -ForegroundColor Yellow "Note: Continuing processing for $($File.Name) despite duplicate CRC32 entries. Please review and correct collisions as needed."
        Write-Log "Continuing processing of $($File.Name) despite duplicate CRCs"
        
        # Track as CSV with duplicates (new category for reporting)
        if (-not (Test-Path -LiteralPath (Join-Path $LogFolder 'CSV_With_Duplicate_CRCs.txt'))) {
            # create a small file for tracking (append-only)
            Add-Content -Path (Join-Path $LogFolder 'CSV_With_Duplicate_CRCs.txt') -Value "CSV duplicates found: $($File.Name) - timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        }
        else {
            Add-Content -Path (Join-Path $LogFolder 'CSV_With_Duplicate_CRCs.txt') -Value "CSV duplicates found: $($File.Name) - timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        }
    }
    else {
        Write-Host -ForegroundColor DarkGray "No duplicate CRCs found in CSV"
    }

    # Trim CSV down to only files found in Source
    # We do this by only retaining filenames that exist in the source folders
    Write-Host "--Checking Source for Matched Files--"
    
    try {
        Write-Log "Processing CSV entries for matching files"
        
        # Pre-calculate all destination folders
        $allDestFolders = $list | ForEach-Object {
            $NewFileName = ($CompletedFolder + $file.BaseName + '\' + $_.Path)
            $NewFileName = $NewFileName -replace '\\\\','\'
            Split-Path -Parent $NewFileName
        } | Sort-Object -Unique

        # Create all required folders in one go
        Write-LogOnly "Creating destination folders"
        foreach ($destFolder in $allDestFolders) {
            if (!(Test-Path -LiteralPath $destFolder)) {
                if ($DryRun) {
                    Write-LogOnly "DryRun: Would create folder: $destFolder"
                }
                else {
                    $null = New-Item -ItemType Directory -Path $destFolder -Force
                    Write-LogOnly "Created folder: $destFolder"
                }
            }
        }

        # Find matches using hashtable lookup (O(1) operation)
        $totalEntries = $list.Count
        $processedEntries = 0
        $matchedEntries = 0
        $movedFilesCount = 0
        $FoundFilesCRC = @()
        $NotFoundFiles = @()
        $AlreadyInDestinationOrCompleted = @()
        
        foreach ($csvEntry in $list) {
            $processedEntries++
            $csvCRC = $csvEntry.CRC32.ToString().ToUpper()
            $csvSize = [int64]$csvEntry.Size

            $matchPercent = if ($totalEntries -gt 0) { [int](($processedEntries / [double]$totalEntries) * 100) } else { 100 }
            Write-Progress -Id 2 -Activity "Matching Files" `
                          -Status "Processed $processedEntries of $totalEntries (Found: $matchedEntries)" `
                          -PercentComplete $matchPercent

            # Check if file exists in source folder (needs to be moved)
            # Use composite CRC:Size key for direct lookup (matches simulation strategy)
            $lookupKey = "{0}:{1}" -f $csvCRC, $csvSize
            $foundMatch = $false
            if ($CRCLookup.ContainsKey($lookupKey)) {
                # Found at least one file with matching CRC and Size
                $matchedEntries++
                $FoundFilesCRC += $csvEntry
                $foundMatch = $true
            }
            if (-not $foundMatch) {
                # Check if file already exists in completed folder
                $expectedCompletedPath = ($CompletedFolder + $file.BaseName + '\' + $csvEntry.Path + '\' + $csvEntry.Filename)
                $expectedCompletedPath = $expectedCompletedPath -replace '\\','\'

                if (Test-Path -LiteralPath $expectedCompletedPath) {
                    $matchedEntries++
                    $AlreadyInDestinationOrCompleted += $csvEntry
                    Write-LogOnly "File already in completed folder: $($csvEntry.Filename)"
                }
                else {
                    $NotFoundFiles += [PSCustomObject]@{
                        FileName = $csvEntry.FileName
                        Size     = $csvSize
                        CRC32    = $csvCRC
                        Path     = $csvEntry.Path
                        Comment  = if ($null -ne $csvEntry.Comment) { $csvEntry.Comment } else { '' }
                    }
                }
            }
        }
        Write-Progress -Id 2 -Activity "Matching Files" -Completed

    Write-LogOnly "Found $($FoundFilesCRC.Count) files in source, $($AlreadyInDestinationOrCompleted.Count) already in completed folder, $($NotFoundFiles.Count) missing"
        
        # Determine if this CSV is complete (all files accounted for)
        $isCompleteCSV = ($FoundFilesCRC.Count + $AlreadyInDestinationOrCompleted.Count) -eq $totalEntries -and $totalEntries -gt 0

                # Honor ForceCSV override: if this CSV's base name matches any exact entries or wildcard patterns,
                # only mark it complete when at least one file was matched OR when the explicit -ForceCSVMoveEmpty switch is provided.
                $csvBaseLower = $File.BaseName.ToLower()
                $forcedMatch = $false
                if ($ForceCSVBaseNames -and ($ForceCSVBaseNames -contains $csvBaseLower)) { $forcedMatch = $true }
                elseif ($ForceCSVPatterns -and $ForceCSVPatterns.Count -gt 0) {
                    foreach ($pat in $ForceCSVPatterns) {
                        if ($csvBaseLower -like $pat) { $forcedMatch = $true; break }
                    }
                }

                if ($forcedMatch) {
                    $ForcedCSVs += $File.Name
                    if ((($FoundFilesCRC.Count + $AlreadyInDestinationOrCompleted.Count) -gt 0) -or $ForceCSVMoveEmpty) {
                        Write-Log "Force-move override active for CSV $($File.Name) - marking as complete to move found files and CSV"
                        $isCompleteCSV = $true
                    }
                    else {
                        Write-Log "Force-move specified for $($File.Name) but no matching files were found; CSV will NOT be moved unless -ForceCSVMoveEmpty is supplied"
                        Write-Host -ForegroundColor Yellow "Force-move specified for $($File.Name) but no matching files were found; CSV will NOT be moved unless -ForceCSVMoveEmpty is supplied"
                    }
                }
        
        # Handle -ForceMoveFiles: move matched files even if incomplete, but leave CSV behind
        $forceMoveFilesActive = $ForceMoveFiles -and ($FoundFilesCRC.Count -gt 0)
        if ($forceMoveFilesActive) {
            $ForceMoveFilesCSVs += $File.Name
            Write-Log "ForceMoveFiles active for CSV $($File.Name) - will move $($FoundFilesCRC.Count) matched file(s) but leave CSV in RootFolder"
            Write-Host -ForegroundColor Cyan "ForceMoveFiles: Moving $($FoundFilesCRC.Count) file(s) for $($File.Name), CSV stays in RootFolder"
            # Set flag to enable file moves without marking CSV complete
            $moveFilesOnly = $true
        }
        else {
            $moveFilesOnly = $false
        }
        
        if ($isCompleteCSV) {
            Write-Log "CSV $($file.Name) is COMPLETE - will move to completed folder"
        }
        elseif ($moveFilesOnly) {
            Write-LogOnly "CSV $($file.Name) is INCOMPLETE - ForceMoveFiles will move matched files only, CSV stays in RootFolder"
        }
        else {
            Write-LogOnly "CSV $($file.Name) is INCOMPLETE - files will remain in source folder"
        }
        
        # Log files that weren't found.
        # Only create a missing-files CSV when there are missing entries AND at least one file
        # from the CSV was matched (partial match). If zero files were found for this CSV,
        # skip creating the missing-files CSV (even when -ForceCSV is present). This avoids
        # generating large numbers of empty/audit CSVs for CSVs that matched nothing.
        if (($NotFoundFiles.Count -gt 0) -and (($FoundFilesCRC.Count + $AlreadyInDestinationOrCompleted.Count) -gt 0)) {
            Write-Log "The following $($NotFoundFiles.Count) files from CSV were not found in source directory:"

            # Create a fast, single-write CSV report for this CSV's missing files
            $currentCSVBaseName = $file.BaseName
            $currentCSVName = $file.Name
            $missingFilesCsv = Join-Path $LogFolder ($currentCSVBaseName + "_" + $($NotFoundFiles.Count) + "_missing_files.csv")
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            
            Write-LogOnly "Creating missing files report: $(Split-Path $missingFilesCsv -Leaf)"

            # Preserve original CSV columns first, then append our additional metadata columns
            $missingFilesReport = $NotFoundFiles | ForEach-Object {
            [PSCustomObject]@{
                FileName     = $_.FileName
                Size         = $_.Size
                CRC32        = $_.CRC32
                Path         = $_.Path
                Comment      = if ($_.PSObject.Properties.Match('Comment')) { $_.Comment } else { '' }
                ExpectedPath = $_.Path
                OriginalCSV  = $currentCSVName
                TimeStamp    = $timestamp
            }
            }

            # Single output operation for speed - Force overwrites any existing file
            $missingFilesReport | Export-Csv -LiteralPath $missingFilesCsv -NoTypeInformation -Encoding UTF8 -Force

            # Concise console warning (no per-file prints) and a summary line to main log
            Write-Host -ForegroundColor Red "WARNING: $($NotFoundFiles.Count) files from CSV were not found. See $(Split-Path $missingFilesCsv -Leaf) for details."
            Write-LogOnly "Detailed missing files report written to: $(Split-Path $missingFilesCsv -Leaf)"
            
            # Track partial match
            $PartialMatchCSVs += $currentCSVName
        }
        elseif (($FoundFilesCRC.Count + $AlreadyInDestinationOrCompleted.Count) -eq 0) {
            # No files matched at all - log warning but don't create missing files CSV
            Write-Log "No files from CSV $($file.Name) were found in source or destination directories"
            Write-Host -ForegroundColor Red "WARNING: No files from CSV $($file.Name) were found in source or destination directories"
            
            # Track zero match
            $ZeroMatchCSVs += $file.Name
        }
        else {
            # All files in this CSV were found (either in source or already in destination)
            $completeMsg = "Complete CSV: $($file.Name) - All $totalEntries files accounted for ($($FoundFilesCRC.Count) to move, $($AlreadyInDestinationOrCompleted.Count) already in place)"
            Write-Log $completeMsg
            Write-Host -ForegroundColor Green $completeMsg
            
            # Track full match (CSV will be moved after file operations complete)
            $FullMatchCSVs += $file.Name
        }

                        # One-line green summary for this CSV (always show counts)
                        $summaryMsg = "CSV: $($file.Name) — Total: $totalEntries | In Source: $($FoundFilesCRC.Count) | In Destination: $($AlreadyInDestinationOrCompleted.Count) | Missing: $($NotFoundFiles.Count)"
                        # Print concise green summary to console and record to main log (log-only)
                        Write-Host -ForegroundColor Green $summaryMsg
                        Write-LogOnly $summaryMsg

            # If no files were found for this CSV (neither in source nor completed folder), remove any empty destination directories created for it 
            if (($FoundFilesCRC.Count + $AlreadyInDestinationOrCompleted.Count) -eq 0) {
                Remove-EmptyDirectories -BasePath (Join-Path $CompletedFolder $file.BaseName) -IncludeBase -Context "empty destination directories for CSV: $($file.Name)"
            }

        # Process file moves for complete CSVs OR when ForceMoveFiles is active
        # Incomplete CSVs leave files in source folder (unless ForceMoveFiles is specified)
        $shouldMoveFiles = $isCompleteCSV -or $moveFilesOnly
        $totalToMove = if ($shouldMoveFiles) { $FoundFilesCRC.Count } else { 0 }
        $movedCount = 0
        
        if (-not $shouldMoveFiles) {
            Write-Host -ForegroundColor DarkGray "  Files remain in source for incomplete CSV"
        }
        
        foreach($foundFile in $FoundFilesCRC){
            # Skip file moves for incomplete CSVs unless ForceMoveFiles is active
            if (-not $shouldMoveFiles) {
                continue
            }
            
            try {
                $movedCount++
                # Update progress every 25 files or on first/last to reduce overhead
                if (($movedCount % 25) -eq 1 -or $movedCount -eq $totalToMove) {
                    $movePercent = if ($totalToMove -gt 0) { [int](($movedCount / [double]$totalToMove) * 100) } else { 100 }
                    Write-Progress -Id 3 -Activity "Moving Files for $($file.Name)" `
                                  -Status "Moving file $movedCount of $totalToMove - $($foundFile.Filename)" `
                                  -PercentComplete $movePercent
                }
                
                # Use composite CRC:Size key to lookup the file (matches matching logic above)
                $lookupKey = "{0}:{1}" -f $foundFile.CRC32.ToString().ToUpper(), $foundFile.Size
                $matchedFiles = $CRCLookup[$lookupKey]
                
                # Handle case where CRCLookup contains arrays (multiple files with same CRC:Size)
                if ($matchedFiles -is [array]) {
                    $matchedFile = $matchedFiles[0]  # Use first available file
                }
                else {
                    $matchedFile = $matchedFiles
                }
                
                # Pre-calculate destination path
                $csvBaseFolder = Join-Path $CompletedFolder $file.BaseName
                if ([string]::IsNullOrWhiteSpace($foundFile.Path)) {
                    $NewFileName = Join-Path $csvBaseFolder $foundFile.Filename
                }
                else {
                    $NewFileName = Join-Path (Join-Path $csvBaseFolder $foundFile.Path) $foundFile.Filename
                }
                $destFolder = Split-Path -Parent $NewFileName
                $sourcePath = $matchedFile.File.FullName
                $destinationPath = $NewFileName

                IF($matchedFile) {

                    # Create parent directory if it doesn't exist
                    if (!(Test-Path -LiteralPath $destFolder)) {
                        if ($DryRun) {
                            Write-LogOnly "DryRun: Would create destination directory: $destFolder"
                        }
                        else {
                            try {
                                $null = New-Item -ItemType Directory -Path $destFolder -Force -ErrorAction Stop
                                Write-LogOnly "Created destination directory: $destFolder"
                            }
                            catch {
                                throw "Failed to create destination directory $destFolder : $_"
                            }
                        }
                    }

                    # Verify paths and move file
                    # Skip destination verification in DryRun mode since folders aren't created
                    $pathsValid = if ($DryRun) { 
                        (Test-Path -LiteralPath $sourcePath) 
                    } else { 
                        (Test-Path -LiteralPath $sourcePath) -and (Test-Path -LiteralPath $destFolder) 
                    }
                    
                    if ($pathsValid) {
                        try {
                            # If destination already exists, record conflict and skip moving now
                            $destExists = Test-Path -LiteralPath $destinationPath
                            if ($destExists) {
                                # Record conflict information mirroring first 5 CSV columns plus paths
                                $ConflictRecords += [PSCustomObject]@{
                                    FileName = $foundFile.FileName
                                    Size = $foundFile.Size
                                    CRC32 = $foundFile.CRC32
                                    Path = $foundFile.Path
                                    Comment = if ($foundFile.PSObject.Properties.Match('Comment')) { $foundFile.Comment } else { '' }
                                    SourceFullPath = $sourcePath
                                    DestinationPath = $destinationPath
                                }
                                # Recorded in-memory for later batch processing (per-CSV summary will be logged)
                                continue
                            }

                            if ($DryRun) {
                                Write-LogOnly "DryRun: Would move file from $sourcePath to $destinationPath"
                            }
                            else {
                                # Perform the move operation
                                Move-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
                                $movedFilesCount++

                                # Remove the used file from the hashtable using composite key
                                $lookupKey = "{0}:{1}" -f $foundFile.CRC32.ToString().ToUpper(), $foundFile.Size
                                if ($CRCLookup[$lookupKey] -is [array]) {
                                    # Remove just the file we used from the array
                                    $CRCLookup[$lookupKey] = @($CRCLookup[$lookupKey] | Where-Object { $_.File.FullName -ne $sourcePath })
                                    if ($CRCLookup[$lookupKey].Count -eq 0) {
                                        $CRCLookup.Remove($lookupKey)
                                    }
                                }
                                else {
                                    # Single file, remove the key entirely
                                    $CRCLookup.Remove($lookupKey)
                                }
                            }
                        }
                        catch {
                            throw "Failed to move file: $_"
                        }
                    }
                    else {
                        throw "Source or destination path verification failed - Source exists: $((Test-Path -LiteralPath $sourcePath)), Destination parent exists: $((Test-Path -LiteralPath $destFolder))"
                    }
                }
                ELSE {
                    $errorMsg = "File with CRC $($foundFile.CRC32) not found in source folder!"
                    Write-Log $errorMsg
                    Write-Host -ForegroundColor Red "ERROR: $errorMsg"
                }
            }
            catch {
                Write-Log "Error processing file $($foundFile.Filename): $_"
                Write-Host -ForegroundColor Red "Error processing file: $($foundFile.Filename)"
            }
        }
        Write-Progress -Id 3 -Activity "Moving Files" -Completed
        
        # Show summary of moves for this CSV
        if ($movedFilesCount -gt 0) {
            Write-Host -ForegroundColor Cyan "  → Moved $movedFilesCount file(s) for $($file.Name)"
        }
        
        # Move CSV to completed folder only after ALL file operations are done successfully
        # Skip CSV move if ForceMoveFiles is active (files moved but CSV stays for tracking)
        if ($isCompleteCSV -and -not $moveFilesOnly) {
            try {
                $csvDestPath = Join-Path (Join-Path $CompletedFolder $file.BaseName) $file.Name
                $csvDestFolder = Split-Path -Parent $csvDestPath
                
                # Create the destination folder if it doesn't exist
                if (!(Test-Path -LiteralPath $csvDestFolder)) {
                    if ($DryRun) {
                        Write-LogOnly "DryRun: Would create CSV destination folder: $csvDestFolder"
                    }
                    else {
                        $null = New-Item -ItemType Directory -Path $csvDestFolder -Force
                        Write-LogOnly "Created CSV destination folder: $csvDestFolder"
                    }
                }
                
                if ($DryRun) {
                    Write-LogOnly "DryRun: Would move completed CSV from $($file.FullName) to $csvDestPath"
                }
                else {
                    Move-Item -LiteralPath $file.FullName -Destination $csvDestPath -Force
                    Write-Log "Moved completed CSV to completed folder: $csvDestPath"
                    Write-Host -ForegroundColor Cyan "  ✓ CSV $($file.Name) moved to completed folder"
                }
            }
            catch {
                Write-Log "Warning: Failed to move completed CSV $($file.Name): $_"
                Write-Host -ForegroundColor Yellow "Warning: Could not move CSV to completed folder: $_"
            }
        }
    }
    catch {
        Write-Log "Error processing CSV file $($File.Name): $_"
        Write-Host -ForegroundColor Red "Error processing CSV file: $($File.Name)"
    }

    # Per-CSV conflict flush: if any conflicts were recorded for this CSV, write a per-CSV temp CSV and record it
    try {
        if ($ConflictRecords -and $ConflictRecords.Count -gt 0) {
            $confTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $confTempCsv = Join-Path $LogFolder ("conflicts_$($File.BaseName)_$confTimestamp.csv")
            $ConflictRecords | Select-Object FileName,Size,CRC32,Path,Comment,SourceFullPath,DestinationPath | Export-Csv -LiteralPath $confTempCsv -NoTypeInformation -Encoding UTF8 -Force
            $AllConflictTempFiles += $confTempCsv
            Write-LogOnly "Recorded $($ConflictRecords.Count) conflict(s) for CSV $($File.Name) to: $(Split-Path $confTempCsv -Leaf)"
            Write-Host -ForegroundColor Magenta "  → Recorded $($ConflictRecords.Count) conflict(s) for $($File.Name) to $(Split-Path $confTempCsv -Leaf)"
        }
    }
    catch {
        Write-LogOnly "Error while flushing conflicts for CSV $($File.Name): $_"
    }
}

        # Clean up any empty folders left behind
        # If any per-CSV conflict temp files were created, consolidate into a single combined CSV
        if ($AllConflictTempFiles -and $AllConflictTempFiles.Count -gt 0) {
            $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
            $combinedTemp = Join-Path $LogFolder ("conflicts_combined_$ts.csv")

            try {
                # Combine all per-CSV temp files into one consolidated CSV (single write)
                $AllConflictTempFiles | ForEach-Object { Import-Csv -LiteralPath $_ } | Export-Csv -LiteralPath $combinedTemp -NoTypeInformation -Encoding UTF8 -Force
                Write-Log "Combined $($AllConflictTempFiles.Count) per-CSV conflict files into: $(Split-Path $combinedTemp -Leaf)"
                Write-Host -ForegroundColor Magenta "Combined $($AllConflictTempFiles.Count) conflict files -> $(Split-Path $combinedTemp -Leaf)"

                # Remove per-CSV temp files now that they are consolidated
                foreach ($t in $AllConflictTempFiles) {
                    try {
                        Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue
                        Write-LogOnly "Removed per-CSV temp file: $(Split-Path $t -Leaf)"
                    }
                    catch {
                        Write-LogOnly "Failed to remove temp file $(Split-Path $t -Leaf): $_"
                    }
                }

                # Clear the list now that temp files are removed
                $AllConflictTempFiles = @()

                if ($CompareConflicts) {
                    if ($DryRun) {
                        Write-Log "DryRun: Skipping conflict CRC comparisons. Consolidated temp conflicts CSV: $(Split-Path $combinedTemp -Leaf)"
                        Write-Host -ForegroundColor Yellow "DryRun: Skipping conflict CRC comparisons. Consolidated temp file: $(Split-Path $combinedTemp -Leaf)"
                    }
                    else {
                        # Count rows in combined CSV to decide whether to prompt
                        try {
                            $combinedCount = (Import-Csv -LiteralPath $combinedTemp | Measure-Object).Count
                        }
                        catch {
                            Write-Log "Failed to read combined conflicts CSV for counting: $_"
                            $combinedCount = 0
                        }

                        $finalReport = Join-Path $LogFolder ("conflict_report_$ts.csv")

                        if ($combinedCount -gt $SkipCRCIfOver) {
                            # If auto-confirm is requested, proceed without prompting
                            if ($AutoConfirmConflicts) {
                                Compare-Conflicts -InputCsv $combinedTemp -OutputCsv $finalReport -ThrottleLimit $ConflictThrottleLimit
                                Write-Log "Conflict comparison written to: $(Split-Path $finalReport -Leaf)"
                                Write-Host -ForegroundColor Magenta "Conflict comparison done: $(Split-Path $finalReport -Leaf)"
                            }
                            else {
                                # Prompt the user for confirmation
                                $ans = Read-Host "Conflict comparison will process $combinedCount files (this may take time). Continue with full CRC comparisons? (Y/N)"
                                if ($ans -match '^[Yy](es)?$') {
                                    Compare-Conflicts -InputCsv $combinedTemp -OutputCsv $finalReport -ThrottleLimit $ConflictThrottleLimit
                                    Write-Log "Conflict comparison written to: $(Split-Path $finalReport -Leaf)"
                                    Write-Host -ForegroundColor Magenta "Conflict comparison done: $(Split-Path $finalReport -Leaf)"
                                }
                                else {
                                    # User declined: generate final report without CRC values (size-based only)
                                    try {
                                        $rows = Import-Csv -LiteralPath $combinedTemp
                                        $out = foreach ($r in $rows) {
                                            $src = $r.SourceFullPath
                                            $dst = $r.DestinationPath
                                            $srcSize = $null; $dstSize = $null; $sizeMatch = $false
                                            if (Test-Path -LiteralPath $src) { try { $srcSize = (Get-Item -LiteralPath $src).Length } catch { $srcSize = $null } }
                                            if (Test-Path -LiteralPath $dst) { try { $dstSize = (Get-Item -LiteralPath $dst).Length } catch { $dstSize = $null } }
                                            if ($null -ne $srcSize -and $null -ne $dstSize) { $sizeMatch = ($srcSize -eq $dstSize) }

                                            [PSCustomObject]@{
                                                FileName = $r.FileName
                                                Size = $r.Size
                                                CRC32 = $r.CRC32
                                                Path = $r.Path
                                                Comment = $r.Comment
                                                SourceFullPath = $src
                                                DestinationPath = $dst
                                                SourceSize = $srcSize
                                                DestSize = $dstSize
                                                SizeMatch = $sizeMatch
                                                SourceCRC = ''
                                                DestCRC = ''
                                                CRCMatch = 'NA'
                                                Notes = (if (-not (Test-Path -LiteralPath $dst)) { 'Destination missing' } elseif (-not $sizeMatch) { 'Size differs' } else { 'Size matches (CRC skipped)' })
                                            }
                                        }
                                        $out | Export-Csv -LiteralPath $finalReport -NoTypeInformation -Encoding UTF8 -Force
                                        Write-Log "Size-only conflict report written to: $(Split-Path $finalReport -Leaf) (CRC values omitted by user choice)"
                                        Write-Host -ForegroundColor Magenta "Size-only conflict report written: $(Split-Path $finalReport -Leaf)"
                                    }
                                    catch {
                                        Write-Log "Failed to write size-only conflict report: $_"
                                        Write-Host -ForegroundColor Yellow "Warning: Could not write size-only conflict report: $_"
                                    }
                                }
                            }
                        }
                        else {
                            # Small enough to run full comparison without prompting
                            Compare-Conflicts -InputCsv $combinedTemp -OutputCsv $finalReport -ThrottleLimit $ConflictThrottleLimit
                            Write-Log "Conflict comparison written to: $(Split-Path $finalReport -Leaf)"
                            Write-Host -ForegroundColor Magenta "Conflict comparison done: $(Split-Path $finalReport -Leaf)"
                        }
                    }
                }
            }
            catch {
                Write-Log "Error consolidating conflict temp files: $_"
                Write-Host -ForegroundColor Yellow "Warning: Could not consolidate conflict temp files: $_"
            }
        }

        Write-LogOnly "Starting cleanup of empty folders"
        Remove-EmptyDirectories -BasePath $SourceFolderCRC -Context "source tree empty folder cleanup"

        # Also clean up empty folders under the CompletedFolder (remove per-CSV created empty directories)
        Write-LogOnly "Starting cleanup of empty folders under CompletedFolder: $CompletedFolder"
        Remove-EmptyDirectories -BasePath $CompletedFolder -Context "completed folder empty folder cleanup"


# Drop us back to the home folder
Set-Location $RootFolder

# Display final summary
Write-Host -ForegroundColor Cyan "`r`n========================================="
Write-Host -ForegroundColor Cyan "           FINAL SUMMARY"
Write-Host -ForegroundColor Cyan "========================================="
Write-Log "Processing Summary:"

Write-Host "`nTotal CSVs Processed: $($CRC_CSV_Files.Count)"
Write-Log "Total CSVs Processed: $($CRC_CSV_Files.Count)"

# Zero matches
Write-Host -ForegroundColor Red "`nCSVs with ZERO matches: $($ZeroMatchCSVs.Count)"
Write-Log "CSVs with ZERO matches: $($ZeroMatchCSVs.Count)"
if ($ZeroMatchCSVs.Count -gt 0) {
    foreach ($csv in $ZeroMatchCSVs) {
        Write-Host "  - $csv" -ForegroundColor Red
        Write-LogOnly "  - $csv"
    }
}

# Partial matches
Write-Host -ForegroundColor Yellow "`nCSVs with PARTIAL matches: $($PartialMatchCSVs.Count)"
Write-Log "CSVs with PARTIAL matches: $($PartialMatchCSVs.Count)"
if ($PartialMatchCSVs.Count -gt 0) {
    foreach ($csv in $PartialMatchCSVs) {
        Write-Host "  - $csv" -ForegroundColor Yellow
        Write-LogOnly "  - $csv"
    }
}

# Full matches
Write-Host -ForegroundColor Green "`nCSVs with ALL files matched: $($FullMatchCSVs.Count)"
Write-Log "CSVs with ALL files matched: $($FullMatchCSVs.Count)"
if ($FullMatchCSVs.Count -gt 0) {
    foreach ($csv in $FullMatchCSVs) {
        Write-Host "  - $csv" -ForegroundColor Green
        Write-LogOnly "  - $csv"
    }
}

# Forced CSVs
Write-Host -ForegroundColor Cyan "`nCSVs forced to move regardless of completeness: $($ForcedCSVs.Count)"
Write-Log "CSVs forced to move regardless of completeness: $($ForcedCSVs.Count)"
if ($ForcedCSVs.Count -gt 0) {
    foreach ($csv in $ForcedCSVs) {
        Write-Host "  - $csv"
        Write-LogOnly "  - $csv"
    }
}

# Force-moved files (CSV left behind)
Write-Host -ForegroundColor Magenta "`nCSVs where files were moved but CSV left in RootFolder (ForceMoveFiles): $($ForceMoveFilesCSVs.Count)"
Write-Log "CSVs where files were moved but CSV left in RootFolder (ForceMoveFiles): $($ForceMoveFilesCSVs.Count)"
if ($ForceMoveFilesCSVs.Count -gt 0) {
    foreach ($csv in $ForceMoveFilesCSVs) {
        Write-Host "  - $csv" -ForegroundColor Magenta
        Write-LogOnly "  - $csv"
    }
}

Write-Host -ForegroundColor Cyan "`n========================================="

# We're done with this, bailing out
Write-Host -ForegroundColor DarkYellow "`r`n--All Actions Complete, Exiting--`r`n"
