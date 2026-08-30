[CmdletBinding()]
param([switch]$SkipReboot, [switch]$Force)

$replacement = Join-Path $PSScriptRoot 'TurtleFix.ps1'
if (-not (Test-Path -LiteralPath $replacement)) { throw 'TurtleFix.ps1 was not found next to this compatibility wrapper.' }
Write-Warning 'This compatibility entry point now forwards to TurtleFix PermanentDisable.'
& $replacement -Action Fix -Strategy PermanentDisable -SkipReboot:$SkipReboot -Force:$Force
exit $LASTEXITCODE
