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

# Call the implementation script directly
$runner = Join-Path $PSScriptRoot 'run-crc-tests-impl.ps1'

if (-not (Test-Path $runner)) {
    Write-Error "Test implementation not found: $runner"
    exit 2
}

$argsToPass = @()
if ($Quick) { $argsToPass += '-Quick' }
if ($Keep)  { $argsToPass += '-Keep' }

& $runner @argsToPass
exit $LASTEXITCODE
