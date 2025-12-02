#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test runner dispatcher for CRC-FileOrganizer tests

.DESCRIPTION
    Convenient wrapper to run different test types

.EXAMPLE
    .\run-crc-tests.ps1           # Run full test suite
    .\run-crc-tests.ps1 -Quick     # Run quick test
    .\run-crc-tests.ps1 -Keep      # Run and keep test data
#>

param(
    [switch]$Quick,
    [switch]$Keep
)

Set-StrictMode -Version Latest

# Delegate to consolidated runner so all test entrypoints go through
# `run-all-tests.ps1`. Use -Which crc to request CRC tests.
$runner = Join-Path $PSScriptRoot 'run-all-tests.ps1'

if (-not (Test-Path $runner)) {
    Write-Error "Consolidated runner not found: $runner"
    exit 2
}

$argsToPass = @()
if ($Quick) { $argsToPass += '-Quick' }
if ($Keep)  { $argsToPass += '-Keep' }

& $runner -Which crc @argsToPass
exit $LASTEXITCODE
