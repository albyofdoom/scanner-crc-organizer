# Pester tests for Compare-Conflicts and ForceMoveFiles features
# Requires PowerShell and Pester to run

Describe "CRC-FileOrganizer conflict and force-move tests" {

    BeforeAll {
        $root = Join-Path $env:TEMP "crc_test_root_$(Get-Random)"
        $source = Join-Path $env:TEMP "crc_test_source_$(Get-Random)"
        $completed = Join-Path $env:TEMP "crc_test_completed_$(Get-Random)"
        $log = Join-Path $env:TEMP "crc_test_logs_$(Get-Random)"

        New-Item -ItemType Directory -Path $root -Force | Out-Null
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        New-Item -ItemType Directory -Path $completed -Force | Out-Null
        New-Item -ItemType Directory -Path $log -Force | Out-Null

        $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..\CRC-FileOrganizer.ps1')).Path
        $libPath = (Resolve-Path (Join-Path $PSScriptRoot '..\CRC-FileOrganizerLib.ps1')).Path

        # Dot-source library so we can compute CRCs for CSV entries
        . $libPath

        Set-Variable -Name TestRoot -Value $root -Scope Script
        Set-Variable -Name TestSource -Value $source -Scope Script
        Set-Variable -Name TestCompleted -Value $completed -Scope Script
        Set-Variable -Name TestLog -Value $log -Scope Script
        Set-Variable -Name ScriptPath -Value $scriptPath -Scope Script
    }

    AfterAll {
        # Cleanup everything we created
        Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $TestSource -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $TestCompleted -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $TestLog -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "ForceMoveFiles moves matched files but leaves CSV in RootFolder" {
        # Create a sample file in source
        $fileName = 'sample1.bin'
        $sourceFile = Join-Path $TestSource $fileName
        [System.IO.File]::WriteAllText($sourceFile, 'force-move-test')

        # Compute CRC and Size using library
        $crc = Get-CRC32Hash -FilePath $sourceFile
        $size = (Get-Item -LiteralPath $sourceFile).Length

        # Create CSV in Root (no header)
        $csvName = 'TestPack-001.csv'
        $csvPath = Join-Path $TestRoot $csvName
        [PSCustomObject]@{
            FileName = $fileName
            Size = $size
            CRC32 = $crc
            Path = ''
            Comment = ''
        } | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Force

        # Run the organizer with ForceMoveFiles
        & pwsh -NoProfile -File $ScriptPath -RootFolder $TestRoot -SourceFolderCRC $TestSource -CompletedFolder $TestCompleted -LogFolder $TestLog -ThrottleLimit 1 -ForceMoveFiles

        # Expect the file to be moved into Completed/<CSVBase>/fileName
        $dest = Join-Path $TestCompleted (([IO.Path]::GetFileNameWithoutExtension($csvName)))
        $destFile = Join-Path $dest $fileName
        Test-Path $destFile | Should Be $true

        # CSV should still exist in RootFolder
        Test-Path $csvPath | Should Be $true
    }

    It "Compare-Conflicts produces a report and detects CRC mismatch when destination differs" {
        # Create a sample file in source and a different file already in destination to cause a conflict
        $fileName = 'conflict1.bin'
        $sourceFile = Join-Path $TestSource $fileName
        [System.IO.File]::WriteAllText($sourceFile, 'original-content')

        $csvName = 'ConflictPack-001.csv'
        $csvPath = Join-Path $TestRoot $csvName

        # Create destination file (different content)
        $destDir = Join-Path $TestCompleted ([IO.Path]::GetFileNameWithoutExtension($csvName))
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        $destFile = Join-Path $destDir $fileName
        [System.IO.File]::WriteAllText($destFile, 'different-content')

        # Compute CRC for source file
        $crc = Get-CRC32Hash -FilePath $sourceFile
        $size = (Get-Item -LiteralPath $sourceFile).Length

        # Create CSV entry (no header)
        [PSCustomObject]@{
            FileName = $fileName
            Size = $size
            CRC32 = $crc
            Path = ''
            Comment = ''
        } | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Force

        # Run organizer with CompareConflicts and AutoConfirmConflicts to avoid interactive prompt
        & pwsh -NoProfile -File $ScriptPath -RootFolder $TestRoot -SourceFolderCRC $TestSource -CompletedFolder $TestCompleted -LogFolder $TestLog -ThrottleLimit 1 -ForceMoveFiles -CompareConflicts -AutoConfirmConflicts

        # Find the latest conflict_report_*.csv in the log folder
        $report = Get-ChildItem -Path $TestLog -Filter 'conflict_report_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $report | Should Not BeNullOrEmpty

        $rows = Import-Csv -Path $report.FullName
        $rows.Count | Should BeGreaterThan 0

        # CRCMatch should be False for the differing destination
        ($rows | Where-Object { $_.FileName -eq $fileName }).CRCMatch | Should Be 'False'
    }
}
