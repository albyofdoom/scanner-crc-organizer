$root=Join-Path $env:TEMP ('crc_manual_root_'+[System.Guid]::NewGuid().ToString())
$source=Join-Path $env:TEMP ('crc_manual_src_'+[System.Guid]::NewGuid().ToString())
$completed=Join-Path $env:TEMP ('crc_manual_completed_'+[System.Guid]::NewGuid().ToString())
$log=Join-Path $env:TEMP ('crc_manual_log_'+[System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $root,$source,$completed,$log -Force | Out-Null
Write-Host "Root:$root"
Write-Host "Source:$source"
Write-Host "Completed:$completed"
Write-Host "Log:$log"
[System.IO.File]::WriteAllText((Join-Path $source 'sample_manual.bin'),'manual')
. (Resolve-Path $PSScriptRoot\..\CRC-FileOrganizerLib.ps1).Path
$srcFile = Join-Path $source 'sample_manual.bin'
$crc = Get-CRC32Hash -FilePath $srcFile
$size = (Get-Item $srcFile).Length
$csvPath = Join-Path $root 'manual.csv'
[PSCustomObject]@{ FileName='sample_manual.bin'; Size=$size; CRC32=$crc; Path=''; Comment=''} | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Force
Write-Host "CSV created: $csvPath"
$script = (Resolve-Path $PSScriptRoot\..\CRC-FileOrganizer.ps1).Path
Write-Host "Running organizer: $script"
& pwsh -NoProfile -File $script -RootFolder $root -SourceFolderCRC $source -CompletedFolder $completed -LogFolder $log -ThrottleLimit 1 -ForceMoveFiles -CompareConflicts -AutoConfirmConflicts
Write-Host "Organizer exit code: $LASTEXITCODE"
Write-Host "Completed directory listing:"
Get-ChildItem -Path $completed -Recurse | ForEach-Object { Write-Host $_.FullName }
Write-Host "Log files:"
Get-ChildItem -Path $log -Recurse | ForEach-Object { Write-Host $_.FullName }
