$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'TurtleFix.ps1')

$targetMap = @{}
foreach ($target in $script:RegistryTargets) { $targetMap[("{0}|{1}" -f $target.Path, $target.Name)] = [int]$target.Value }
$requiredTargets = @{
    'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa|LsaCfgFlags' = 0
    'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity|Enabled' = 0
    'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\SystemGuard|Enabled' = 0
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard|LsaCfgFlags' = 0
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard|ConfigureSystemGuardLaunch' = 2
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection|DeviceEnumerationPolicy' = 1
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageHealth|AllowDiskHealthModelUpdates' = 0
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security|UILockdown' = 0
}
foreach ($entry in $requiredTargets.GetEnumerator()) {
    if (-not $targetMap.ContainsKey($entry.Key) -or $targetMap[$entry.Key] -ne $entry.Value) { throw "Required registry target is missing or wrong: $($entry.Key)" }
}
if (@($script:RegistryDeleteTargets | Where-Object { $_.Name -eq 'ExploitProtectionSettings' }).Count -ne 1) { throw 'Exploit Protection policy deletion target is missing.' }
foreach ($feature in @('Microsoft-Hyper-V-All', 'Microsoft-Hyper-V-Hypervisor', 'VirtualMachinePlatform', 'Containers-DisposableClientVM', 'Windows-Defender-ApplicationGuard', 'IsolatedUserMode')) {
    if ($script:OptionalFeatureTargets -notcontains $feature) { throw "Required optional-feature target is missing: $feature" }
}
if ($script:DGReadinessZipSha256 -notmatch '^[A-F0-9]{64}$' -or $script:DGReadinessFiles.Count -ne 3) { throw 'Pinned Microsoft readiness hashes are incomplete.' }

$registry = @(($script:RegistryTargets + $script:RegistryDeleteTargets) | ForEach-Object {
    [pscustomobject]@{ Path = $_.Path; Name = $_.Name; Exists = $false; Kind = $null; Value = $null }
})
$features = @($script:OptionalFeatureTargets | ForEach-Object {
    [pscustomobject]@{ Name = $_; Present = $false; State = 'Disabled' }
})
$script:StateRoot = Join-Path $env:TEMP 'TurtleFix-Unit-State'
$testDirectory = Join-Path $script:StateRoot 'backups\unit'
$statePath = Join-Path $testDirectory 'state.json'
$valid = [pscustomobject]@{
    SchemaVersion = 2
    Strategy = 'PermanentDisable'
    SourceBootIdentifier = '{11111111-2222-3333-4444-555555555555}'
    Registry = $registry
    OptionalFeatures = $features
    BcdBackup = Join-Path $testDirectory 'bcd.bak'
    SIPolicy = [pscustomobject]@{ Existed = $false; OriginalPath = Join-Path $env:SystemRoot 'System32\CodeIntegrity\SIPolicy.p7b'; BackupPath = Join-Path $testDirectory 'SIPolicy.p7b' }
    Capabilities = [pscustomobject]@{ Existed = $false; BackupPath = Join-Path $testDirectory 'DeviceGuard-Capabilities.reg' }
    EnforcementTask = [pscustomobject]@{ Existed = $false; BackupPath = Join-Path $testDirectory 'EnforcementTask.xml' }
}

Assert-BackupState $valid $statePath

$malicious = $valid.PSObject.Copy()
$malicious.Registry = @($registry)
$malicious.Registry[0] = [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Unmanaged'; Name = 'Injected'; Exists = $true; Kind = 'DWord'; Value = 1 }
$rejected = $false
try { Assert-BackupState $malicious $statePath } catch { $rejected = $true }
if (-not $rejected) { throw 'Restore validation accepted an unmanaged registry value.' }

$rejected = $false
try { Assert-BootIdentifier -Identifier '{current}; whoami' -Label 'test' } catch { $rejected = $true }
if (-not $rejected) { throw 'Boot identifier validation accepted command text.' }

$unsafe = $valid.PSObject.Copy()
$unsafe.SIPolicy = [pscustomobject]@{ Existed = $true; OriginalPath = 'C:\Windows\System32\kernel32.dll'; BackupPath = Join-Path $testDirectory 'SIPolicy.p7b' }
$rejected = $false
try { Assert-BackupState $unsafe $statePath } catch { $rejected = $true }
if (-not $rejected) { throw 'Restore validation accepted an unsafe SIPolicy destination.' }

$rejected = $false
try { Assert-BackupState $valid (Join-Path $env:TEMP 'outside-state.json') } catch { $rejected = $true }
if (-not $rejected) { throw 'Restore validation accepted a state file outside the protected backup root.' }

Write-Host 'Unit checks passed for backup, registry and path validation.' -ForegroundColor Green
