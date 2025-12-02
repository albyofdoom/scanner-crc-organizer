<#
Shared helper library for CRC-FileOrganizer scripts.
Provides functions to build a candidate map of files by CRC+Size
and to simulate assigning CSV entries to candidate files for reporting.
#>

function Add-CRC32Type {
    if (-not ('System.Security.Cryptography.CRC32' -as [type])) {
        Add-Type @'
using System.Security.Cryptography;

namespace System.Security.Cryptography {
    public class CRC32 : HashAlgorithm {
        private uint _crc32;
        private static uint[] _lookup;
        
        static CRC32() {
            _lookup = new uint[256];
            for (uint i = 0; i < 256; i++) {
                uint value = i;
                for (int j = 0; j < 8; j++)
                    value = ((value & 1) == 1) ? (value >> 1) ^ 0xEDB88320 : value >> 1;
                _lookup[i] = value;
            }
        }
        
        public override void Initialize() {
            _crc32 = 0xFFFFFFFF;
        }
        
        protected override void HashCore(byte[] array, int ibStart, int cbSize) {
            for (int i = ibStart; i < ibStart + cbSize; i++)
                _crc32 = (_crc32 >> 8) ^ _lookup[array[i] ^ (_crc32 & 0xFF)];
        }
        
        protected override byte[] HashFinal() {
            byte[] hashBytes = BitConverter.GetBytes(~_crc32);
            Array.Reverse(hashBytes);
            return hashBytes;
        }
    }
}
'@
    }
}

function Get-CRC32Hash {
    param([Parameter(Mandatory)][string]$FilePath)

    Add-CRC32Type

    $bufferSize = 1MB
    $crc32 = New-Object -TypeName System.Security.Cryptography.CRC32
    $crc32.Initialize()

    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        $buffer = New-Object byte[] $bufferSize
        $bytesRead = 0
        while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $crc32.TransformBlock($buffer, 0, $bytesRead, $buffer, 0) | Out-Null
        }
        $crc32.TransformFinalBlock($buffer, 0, 0) | Out-Null
        $hash = $crc32.Hash
        $hashString = [System.BitConverter]::ToString($hash).Replace("-", "")
        return $hashString
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $crc32) { $crc32.Dispose() }
    }
}

function Get-CandidateMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceFolderCRC,
        [int]$ThrottleLimit = 4
    )

    # Discover files and calculate CRCs (single-process for reliability)
    $files = Get-ChildItem -LiteralPath $SourceFolderCRC -Recurse -File -ErrorAction SilentlyContinue
    $candidateMap = @{}

    $total = $files.Count
    $i = 0
    foreach ($f in $files) {
        $i++
        # Update progress every 50 files to reduce overhead
        if (($i -eq 1) -or (($i % 50) -eq 0) -or ($i -eq $total)) {
            $percent = [int](($i / [double]$total) * 100)
            $status = ("Processing {0} of {1}: {2}" -f $i, $total, $f.Name)
            Write-Progress -Activity "Computing CRC32 for files" -Status $status -PercentComplete $percent
        }

        try {
            $crc = Get-CRC32Hash -FilePath $f.FullName
            $size = $f.Length
            $key = "{0}:{1}" -f $crc.ToUpper(), $size
            $entry = [PSCustomObject]@{
                FullName = $f.FullName
                FileName = $f.Name
                Size = $size
                CRC32 = $crc.ToUpper()
                FileInfo = $f
            }

            if (-not $candidateMap.ContainsKey($key)) { $candidateMap[$key] = @() }
            $candidateMap[$key] += $entry
        }
        catch {
            Write-Verbose "Failed to hash file $($f.FullName): $_"
        }
    }
    # Clear progress bar on completion
    Write-Progress -Activity "Computing CRC32 for files" -Completed

    return $candidateMap
}

function Simulate-AssignCsvEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter(Mandatory)]$CandidateMap,
        [Parameter(Mandatory)] [hashtable]$ClaimMap,
        [string]$CompletedFolder = '',
        [switch]$DryRun
    )

    # Parse CSV (RFC4180 minimal parser)
    function Parse-CSVLineRFC4180_Internal {
        param([string]$line)
        $fields = @(); $field = ""; $inQuotes = $false; $i=0
        while ($i -lt $line.Length) {
            $char = $line[$i]
            if ($inQuotes) {
                if ($char -eq '"') {
                    if (($i+1) -lt $line.Length -and $line[$i+1] -eq '"') { $field += '"'; $i++ }
                    else { $inQuotes = $false }
                } else { $field += $char }
            } else {
                if ($char -eq ',') { $fields += $field; $field = "" }
                elseif ($char -eq '"') { $inQuotes = $true }
                else { $field += $char }
            }
            $i++
        }
        $fields += $field
        return $fields
    }

    $rawLines = Get-Content -LiteralPath $CsvPath -Encoding UTF8 -ErrorAction Stop
    $entries = @()
    foreach ($line in $rawLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = Parse-CSVLineRFC4180_Internal $line
        if ($parts.Count -ge 3) {
            $entries += [PSCustomObject]@{
                FileName = $parts[0].Trim()
                Size = $parts[1].Trim()
                CRC32 = $parts[2].Trim().ToUpper()
                RawLine = $line
            }
        }
    }

    # Skip header if present
    if ($entries.Count -gt 0 -and ($entries[0].FileName -match '^(FileName|File|Name)$' -or $entries[0].CRC32 -match '^(CRC32|CRC|Checksum)$')) {
        $entries = $entries | Select-Object -Skip 1
    }

    $results = @()
    $idx = 0
    foreach ($e in $entries) {
        $idx++
        $key = "{0}:{1}" -f $e.CRC32, $([int64]$e.Size)
        $candidates = @()
        if ($CandidateMap.ContainsKey($key)) { $candidates = $CandidateMap[$key] }

        $assigned = $null
        $reason = ''
        $claimedBy = ''

        if ($candidates.Count -eq 0) {
            # No candidates at all
            $reason = 'NotFound'
        }
        else {
            # Try to find an unclaimed candidate
            foreach ($c in $candidates) {
                if (-not $ClaimMap.ContainsKey($c.FullName)) {
                    # claim it
                    $ClaimMap[$c.FullName] = [PSCustomObject]@{ ClaimedBy = (Split-Path -Leaf $CsvPath); ClaimedFor = $idx; Time = (Get-Date).ToString('o') }
                    $assigned = $c.FullName
                    $reason = 'Assigned'
                    break
                }
            }

            if (-not $assigned) {
                # All candidates already claimed
                $reason = 'ClaimedByOther'
                # Pick first claimant to report
                $first = $candidates[0]
                if ($ClaimMap.ContainsKey($first.FullName)) { $claimedBy = $ClaimMap[$first.FullName].ClaimedBy }
            }
        }

        $results += [PSCustomObject]@{
            CSVFile = (Split-Path -Leaf $CsvPath)
            EntryIndex = $idx
            ExpectedCRC = $e.CRC32
            ExpectedSize = $e.Size
            CandidateFiles = ($candidates | ForEach-Object { $_.FullName }) -join ';'
            AssignedFile = $assigned
            Reason = $reason
            ClaimedBy = $claimedBy
            Timestamp = (Get-Date).ToString('o')
            DryRun = $DryRun.IsPresent
        }
    }

    return $results
}
