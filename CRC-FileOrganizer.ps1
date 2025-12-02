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
    [switch]$ForceCSVMoveEmpty
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

# Initialize summary tracking variables
$ZeroMatchCSVs = @()
$PartialMatchCSVs = @()
$FullMatchCSVs = @()
# Track forced CSVs (force-moved by user)
$ForcedCSVs = @()

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
        
        if ($isCompleteCSV) {
            Write-Log "CSV $($file.Name) is COMPLETE - will move to completed folder"
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
            $missingFilesReport | Export-Csv -Path $missingFilesCsv -NoTypeInformation -Encoding UTF8 -Force

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

        # Process file moves ONLY for complete CSVs
        # Incomplete CSVs leave files in source folder
        $totalToMove = if ($isCompleteCSV) { $FoundFilesCRC.Count } else { 0 }
        $movedCount = 0
        
        if (-not $isCompleteCSV) {
            Write-Host -ForegroundColor DarkGray "  Files remain in source for incomplete CSV"
        }
        
        foreach($foundFile in $FoundFilesCRC){
            # Skip file moves for incomplete CSVs - files stay in source
            if (-not $isCompleteCSV) {
                continue
            }
            
            try {
                $movedCount++
                $movePercent = if ($totalToMove -gt 0) { [int](($movedCount / [double]$totalToMove) * 100) } else { 100 }
                Write-Progress -Id 3 -Activity "Moving Files for $($file.Name)" `
                              -Status "Moving file $movedCount of $totalToMove - $($foundFile.Filename)" `
                              -PercentComplete $movePercent
                
                # Use composite CRC:Size key to lookup the file (matches matching logic above)
                $lookupKey = "{0}:{1}" -f $foundFile.CRC32.ToString().ToUpper(), $foundFile.Size
                $matchedFiles = $CRCLookup[$lookupKey]
                Write-LogOnly "Processing file: $($foundFile.Filename) with CRC:Size key $lookupKey"
                
                # Handle case where CRCLookup contains arrays (multiple files with same CRC:Size)
                if ($matchedFiles -is [array]) {
                    $matchedFile = $matchedFiles[0]  # Use first available file
                    Write-LogOnly "Found $($matchedFiles.Count) files with key $lookupKey, using first available"
                }
                else {
                    $matchedFile = $matchedFiles
                }
                
                # Only complete CSVs move files - use CompletedFolder
                $targetFolder = $CompletedFolder
                
                $NewFileName = ($targetFolder + $file.BaseName + '\' + $foundFile.Path + '\' + $foundFile.Filename)
                $NewFileName = $NewFileName -replace '\\\\','\'
                $destFolder = (Split-Path -Parent $NewFileName)

                IF($matchedFile -and (Test-Path -LiteralPath $matchedFile.File.FullName)) {
                    # Move the file from the source folder to the new destination
                    Write-LogOnly "--Moving File to New Location--"
                    
                    # Construct proper paths with Join-Path to handle path separators correctly
                    $sourcePath = $matchedFile.File.FullName
                    $destinationPath = Join-Path $destFolder $foundFile.Filename
                    
                    Write-LogOnly "Source = $sourcePath"
                    Write-LogOnly "Destination = $destinationPath"

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
                    if ((Test-Path -LiteralPath $sourcePath) -and (Test-Path -LiteralPath $destFolder)) {
                        try {
                            if ($DryRun) {
                                Write-LogOnly "DryRun: Would move file from $sourcePath to $destinationPath"
                            }
                            else {
                                # Perform the move operation
                                Move-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
                                Write-LogOnly "Successfully moved file to destination"
                                $movedFilesCount++
                                
                                # Remove the used file from the hashtable using composite key
                                $lookupKey = "{0}:{1}" -f $foundFile.CRC32.ToString().ToUpper(), $foundFile.Size
                                if ($CRCLookup[$lookupKey] -is [array]) {
                                    # Remove just the file we used from the array
                                    $CRCLookup[$lookupKey] = @($CRCLookup[$lookupKey] | Where-Object { $_.File.FullName -ne $sourcePath })
                                    if ($CRCLookup[$lookupKey].Count -eq 0) {
                                        $CRCLookup.Remove($lookupKey)
                                        Write-LogOnly "Removed key $lookupKey from lookup table (last file)"
                                    }
                                    else {
                                        Write-LogOnly "Removed file from key $lookupKey array ($($CRCLookup[$lookupKey].Count) remaining)"
                                    }
                                }
                                else {
                                    # Single file, remove the key entirely
                                    $CRCLookup.Remove($lookupKey)
                                    Write-LogOnly "Removed key $lookupKey from lookup table"
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
        if ($isCompleteCSV) {
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
}

        # Clean up any empty folders left behind
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

Write-Host -ForegroundColor Cyan "`n========================================="

# We're done with this, bailing out
Write-Host -ForegroundColor DarkYellow "`r`n--All Actions Complete, Exiting--`r`n"
