#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test runner for CRC-FileOrganizer tests

.DESCRIPTION
    Run different test suites for CRC-FileOrganizer

.EXAMPLE
    .\run-crc-tests.ps1           # Run full test suite
    .\run-crc-tests.ps1 -Quick     # Run quick test
    .\run-crc-tests.ps1 -Keep      # Run and keep test data
    .\run-crc-tests.ps1 -Extended  # Run extended tests
    .\run-crc-tests.ps1 -All       # Run all tests
#>

param(
    [switch]$Quick,
    [switch]$Keep,
    [switch]$Extended,
    [switch]$All
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$TestsPath = $PSScriptRoot

# Helper to set CWD back to repo root after tests
function Set-RepoRoot {
    $repoRoot = Split-Path -Parent $TestsPath
    Set-Location -LiteralPath $repoRoot
    Write-Host "Working directory set to: $repoRoot" -ForegroundColor Gray
}

try {
    if ($All) {
        # Run all test suites
        Write-Host "`n=== Running ALL Tests ===" -ForegroundColor Cyan
        
        Write-Host "`n--- Quick Test ---" -ForegroundColor Yellow
        & "$TestsPath\Quick-Test-CRC.ps1" $(if ($Keep) { '-KeepData' })
        
        Write-Host "`n--- Full Test Suite ---" -ForegroundColor Yellow
        & "$TestsPath\Test-CRCFileOrganizer.ps1" $(if ($Keep) { '-KeepTestData' })
        
        Write-Host "`n--- Extended Tests ---" -ForegroundColor Yellow
        & "$TestsPath\Extended-CRC-Tests.ps1" $(if ($Keep) { '-KeepData' })
        
        Write-Host "`n--- Library Tests ---" -ForegroundColor Yellow
        & "$TestsPath\Test-CRCFileOrganizerLib.ps1"
        
        Write-Host "`n--- Focused Tests ---" -ForegroundColor Yellow
        & "$TestsPath\Test-ForceCSV-Safe.ps1"
        & "$TestsPath\Test-MissingFiles-Columns.ps1"
        & "$TestsPath\Test-ReportConflicts.ps1"
        
        # Run Pester tests if available
        $pesterTest = Join-Path $TestsPath 'Test-ConflictCompareAndForceMove.ps1'
        if (Test-Path $pesterTest) {
            Write-Host "`n--- Pester Tests ---" -ForegroundColor Yellow
            try {
                pwsh -NoProfile -Command "Import-Module Pester -ErrorAction Stop; Invoke-Pester -Script '$pesterTest' -Verbose"
            }
            catch {
                Write-Host "Warning: Pester tests failed or Pester not available: $_" -ForegroundColor Yellow
            }
        }
    }
    elseif ($Quick) {
        Write-Host "Running Quick Test..." -ForegroundColor Cyan
        if ($Keep) {
            & "$TestsPath\Quick-Test-CRC.ps1" -KeepData
        }
        else {
            & "$TestsPath\Quick-Test-CRC.ps1"
        }
    }
    elseif ($Extended) {
        Write-Host "Running Extended Tests..." -ForegroundColor Cyan
        if ($Keep) {
            & "$TestsPath\Extended-CRC-Tests.ps1" -KeepData
        }
        else {
            & "$TestsPath\Extended-CRC-Tests.ps1"
        }
    }
    else {
        # Default: run full test suite
        Write-Host "Running Full Test Suite..." -ForegroundColor Cyan
        if ($Keep) {
            & "$TestsPath\Test-CRCFileOrganizer.ps1" -KeepTestData
        }
        else {
            & "$TestsPath\Test-CRCFileOrganizer.ps1"
        }

        # Run additional focused Pester tests for conflict-compare and force-move
        $conflictTest = Join-Path $TestsPath 'Test-ConflictCompareAndForceMove.ps1'
        if (Test-Path $conflictTest) {
            Write-Host "Running conflict/force-move Pester tests..." -ForegroundColor Cyan
            try {
                pwsh -NoProfile -Command "Import-Module Pester -ErrorAction Stop; Invoke-Pester -Script '$conflictTest' -Verbose"
            }
            catch {
                Write-Host "Warning: Pester tests failed or Pester not available: $_" -ForegroundColor Yellow
            }
        }
    }
    
    $exitCode = $LASTEXITCODE
}
finally {
    # Always return to repo root after tests
    Set-RepoRoot
}

exit $exitCode
