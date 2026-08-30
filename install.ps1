[CmdletBinding()]
param(
    [ValidateSet('PermanentDisable')]
    [string]$Strategy = 'PermanentDisable',
    [switch]$SkipReboot,
    [switch]$Force,
    [switch]$DiagnoseOnly,
    [string]$InstallDirectory = "$env:ProgramFiles\TurtleFix"
)

$ErrorActionPreference = 'Stop'
$installerVersion = '2026.08.30.1'
$rawScriptUrl = 'https://raw.githubusercontent.com/Krex381/TurtleRemove-OracleVM/main/TurtleFix.ps1'
$expectedSha256 = 'D819404188656B6A30EC0ED3FE4718E51F8734D031CD8CC1EBFE5401966DC455'
$script:InvocationParameters = @{}
foreach ($parameterName in $PSBoundParameters.Keys) { $script:InvocationParameters[$parameterName] = $PSBoundParameters[$parameterName] }

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedInstaller {
    if (-not $PSCommandPath) {
        throw 'Automatic elevation is unavailable when install.ps1 is piped into Invoke-Expression. Download install.ps1 first, then run it.'
    }
    foreach ($value in @($PSCommandPath, $InstallDirectory)) {
        if ($value -match '["\r\n]') { throw 'An installer process argument contains an unsafe quote or newline.' }
    }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath), '-Strategy', $Strategy, '-InstallDirectory', ('"{0}"' -f $InstallDirectory))
    foreach ($name in @('SkipReboot', 'Force', 'DiagnoseOnly')) {
        if ($script:InvocationParameters.ContainsKey($name) -and $script:InvocationParameters[$name]) { $arguments += "-$name" }
    }
    $process = Start-Process -FilePath 'PowerShell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}

Write-Host "TurtleFix installer $installerVersion" -ForegroundColor Cyan
if (-not (Test-Administrator)) { Invoke-ElevatedInstaller }

New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
$destination = Join-Path $InstallDirectory 'TurtleFix.ps1'
$localSource = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'TurtleFix.ps1' } else { $null }

if ($localSource -and (Test-Path -LiteralPath $localSource)) {
    Copy-Item -LiteralPath $localSource -Destination $destination -Force
} else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $temporary = Join-Path $env:TEMP ("TurtleFix-{0}.ps1" -f [guid]::NewGuid().ToString('N'))
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $rawScriptUrl -OutFile $temporary
        $actualSha256 = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
        if ($actualSha256 -ine $expectedSha256) {
            throw "Downloaded TurtleFix.ps1 failed SHA-256 verification. Expected $expectedSha256, received $actualSha256."
        }
        Move-Item -LiteralPath $temporary -Destination $destination -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

& icacls.exe $InstallDirectory /inheritance:r | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to remove inherited ACLs from the TurtleFix install directory.' }
& icacls.exe $InstallDirectory /grant:r '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' '*S-1-5-32-545:(OI)(CI)(RX)' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to apply the TurtleFix install-directory ACL.' }

$action = if ($DiagnoseOnly) { 'Diagnose' } else { 'Fix' }
$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $destination, '-Action', $action, '-Strategy', $Strategy)
if ($SkipReboot) { $arguments += '-SkipReboot' }
if ($Force) { $arguments += '-Force' }
& PowerShell.exe @arguments
exit $LASTEXITCODE
