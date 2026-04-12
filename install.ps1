$ErrorActionPreference = 'Stop'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InstallUrlFromInvocation {
    $line = $MyInvocation.Line
    if (-not $line) { return $null }

    $pattern = 'https://raw\.githubusercontent\.com/[^\s''"]+/[^\s''"]+/[^\s''"]+/install\.ps1'
    $m = [regex]::Match($line, $pattern)
    if ($m.Success) { return $m.Value }
    return $null
}

function Get-MainScriptUrl {
    param([string]$InstallUrl)

    if ($InstallUrl -match '^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/install\.ps1$') {
        $owner = $matches[1]
        $repo = $matches[2]
        $branch = $matches[3]
        return "https://raw.githubusercontent.com/$owner/$repo/$branch/Disable-VirtualBoxTurtle-Full.ps1"
    }

    throw 'Could not determine main script URL from invocation. Use raw GitHub URL format for install.ps1.'
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
}

$installUrl = Get-InstallUrlFromInvocation
if (-not $installUrl) {
    throw 'Run this installer via: iwr -useb https://raw.githubusercontent.com/<owner>/<repo>/<branch>/install.ps1 | iex'
}

if (-not (Test-Admin)) {
    $cmd = "iwr -useb '$installUrl' | iex"
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd)
    return
}

$mainScriptUrl = Get-MainScriptUrl -InstallUrl $installUrl
$tmpScript = Join-Path $env:TEMP 'Disable-VirtualBoxTurtle-Full.ps1'

Invoke-WebRequest -UseBasicParsing -Uri $mainScriptUrl -OutFile $tmpScript

if ($env:SCHILDKROTE_SKIP_REBOOT -eq '1') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmpScript -SkipReboot
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmpScript
}
