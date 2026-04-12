$ErrorActionPreference = 'Stop'

$InstallerVersion = '2026.04.12.3'
$DefaultInstallUrl = 'https://raw.githubusercontent.com/Krex381/TurtleRemove-OracleVM/main/install.ps1'
$DefaultMainScriptUrl = 'https://raw.githubusercontent.com/Krex381/TurtleRemove-OracleVM/main/Disable-VirtualBoxTurtle-Full.ps1'
$DefaultAuditPolicyUrl = 'https://raw.githubusercontent.com/Krex381/TurtleRemove-OracleVM/main/DefaultWindows_Audit_sipolicy.p7b'
$DefaultEnforcedPolicyUrl = 'https://raw.githubusercontent.com/Krex381/TurtleRemove-OracleVM/main/DefaultWindows_Enforced_sipolicy.p7b'

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

# Optional parity policy files from GitHub (best effort)
$tmpAuditPolicy = Join-Path $env:TEMP 'DefaultWindows_Audit_sipolicy.p7b'
$tmpEnforcedPolicy = Join-Path $env:TEMP 'DefaultWindows_Enforced_sipolicy.p7b'
try {
    Invoke-WebRequest -UseBasicParsing -Uri $DefaultAuditPolicyUrl -OutFile $tmpAuditPolicy
    Write-Host 'Downloaded DefaultWindows_Audit_sipolicy.p7b'
} catch {
    Write-Host 'Audit SIPolicy not found on GitHub (continuing without it)'
}

try {
    Invoke-WebRequest -UseBasicParsing -Uri $DefaultEnforcedPolicyUrl -OutFile $tmpEnforcedPolicy
    Write-Host 'Downloaded DefaultWindows_Enforced_sipolicy.p7b'
} catch {
    Write-Host 'Enforced SIPolicy not found on GitHub (continuing without it)'
}

if ($env:SCHILDKROTE_SKIP_REBOOT -eq '1') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmpScript -SkipReboot
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmpScript
}
