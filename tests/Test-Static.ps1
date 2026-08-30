$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scripts = @('TurtleFix.ps1', 'install.ps1', 'Disable-VirtualBoxTurtle-Full.ps1')
$failures = New-Object System.Collections.Generic.List[string]

foreach ($name in $scripts) {
    $path = Join-Path $root $name
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($error in $errors) { $failures.Add("$name parser error: $($error.Message)") }
}

$core = Get-Content -LiteralPath (Join-Path $root 'TurtleFix.ps1') -Raw
$required = @(
    'DeployConfigCIPolicy',
    'DeviceEnumerationPolicy',
    'AllowDiskHealthModelUpdates',
    'ExploitProtectionSettings',
    'SIPolicy.p7b',
    "@('/reset')",
    'TurtleFix-Enforce-Hypervisor-Off',
    'DG_Readiness_Tool_v3.6.ps1',
    'dgreadiness_v3.6.zip',
    'hypervisorlaunchtype',
    'vsmlaunchtype',
    'Update-DeviceGuardCapabilities',
    'Windows Defender Security Center',
    "LatestKnownVirtualBoxVersion = [version]'7.2.16'"
)
foreach ($needle in $required) {
    if ($core -notmatch [regex]::Escape($needle)) { $failures.Add("Required permanent-disable mechanism is missing: $needle") }
}

foreach ($policy in @('DefaultWindows_Audit_sipolicy.p7b', 'DefaultWindows_Enforced_sipolicy.p7b')) {
    if (Test-Path -LiteralPath (Join-Path $root $policy)) { $failures.Add("Unpinned repository binary should not be vendored: $policy") }
}

if ($core -match 'BootProfile|FullDisable') { $failures.Add('A legacy fallback strategy remains in TurtleFix.ps1.') }
if ($core -match "'/copy'|'hypervisorlaunchtype',\s*'auto'") { $failures.Add('Core still contains a Hyper-V fallback boot creation or enable path.') }

$installer = Get-Content -LiteralPath (Join-Path $root 'install.ps1') -Raw
$hashMatch = [regex]::Match($installer, 'expectedSha256\s*=\s*''([A-Fa-f0-9]{64})''')
if (-not $hashMatch.Success) {
    $failures.Add('Installer does not contain a finalized SHA-256 value.')
} else {
    $actualHash = (Get-FileHash -LiteralPath (Join-Path $root 'TurtleFix.ps1') -Algorithm SHA256).Hash
    if ($actualHash -ine $hashMatch.Groups[1].Value) { $failures.Add('Installer SHA-256 does not match TurtleFix.ps1.') }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Static checks passed for $($scripts.Count) PowerShell scripts." -ForegroundColor Green
