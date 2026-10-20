#requires -Version 5.1
[CmdletBinding()]
param([switch]$Check,[switch]$SmokeTest,[string]$Screenshot,[string]$Theme,[string]$Mood)
& (Join-Path $PSScriptRoot 'src\main.ps1') @PSBoundParameters
if (-not $?) { exit 1 }
