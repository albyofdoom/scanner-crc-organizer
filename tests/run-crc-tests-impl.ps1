#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Implementation copy of CRC test runner.

.This file is the concrete implementation that runs Quick or Full CRC
.tests. It is invoked by the consolidated runner (`run-all-tests.ps1`) to
.avoid recursive delegation.
#>

param(
    [switch]$Quick,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'
$TestsPath = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($Quick) {
    Write-Host "Running Quick Test..." -ForegroundColor Cyan
    if ($Keep) {
        & "$TestsPath\Quick-Test-CRC.ps1" -KeepData
    }
    else {
        & "$TestsPath\Quick-Test-CRC.ps1"
    }
}
else {
    Write-Host "Running Full Test Suite..." -ForegroundColor Cyan
    if ($Keep) {
        & "$TestsPath\Test-CRCFileOrganizer.ps1" -KeepTestData
    }
    else {
        & "$TestsPath\Test-CRCFileOrganizer.ps1"
    }
}

exit $LASTEXITCODE
