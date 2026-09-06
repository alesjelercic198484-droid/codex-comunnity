<#  Razvojni zagon z samodejnim ponovnim zagonom ob spremembi datotek (node --watch). #>
[CmdletBinding()] param([int]$Port = 3000, [string]$DataDir = './dev-data')
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSScriptRoot
Push-Location $here
try { $env:PORT = "$Port"; $env:DATA_DIR = $DataDir; & node --watch server.js } finally { Pop-Location }
