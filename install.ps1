$ErrorActionPreference = 'Stop'

$InstallerVersion = '2026.04.12.2'
$DefaultInstallUrl = 'https://raw.githubusercontent.com/Krex381/TurtleRemove-OracleVM/main/install.ps1'
$DefaultMainScriptUrl = 'https://raw.githubusercontent.com/Krex381/TurtleRemove-OracleVM/main/Disable-VirtualBoxTurtle-Full.ps1'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
}

Write-Host "Schildkrote installer v$InstallerVersion"
$installUrl = $DefaultInstallUrl

if (-not (Test-Admin)) {
    $cmd = "iwr -useb '$installUrl' | iex"
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd)
    return
}

$mainScriptUrl = $DefaultMainScriptUrl
$tmpScript = Join-Path $env:TEMP 'Disable-VirtualBoxTurtle-Full.ps1'

Invoke-WebRequest -UseBasicParsing -Uri $mainScriptUrl -OutFile $tmpScript

if ($env:SCHILDKROTE_SKIP_REBOOT -eq '1') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmpScript -SkipReboot
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmpScript
}
