param([Parameter(Mandatory=$true)][string]$Compiler)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Compiler -PathType Leaf)) { throw 'Specify the installed Inno Setup ISCC.exe path.' }
& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "$PSScriptRoot\app\WaterReminder.ps1" -SelfTest
if ($LASTEXITCODE -ne 0) { throw 'Schedule tests failed.' }
& $Compiler "$PSScriptRoot\installer\WaterBuddy.iss"
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }
Get-FileHash "$PSScriptRoot\artifacts\Water-Buddy-Setup.exe" -Algorithm SHA256
