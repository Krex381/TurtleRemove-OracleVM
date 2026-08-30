[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Diagnose', 'Fix', 'Verify', 'Restore', 'Enforce')]
    [string]$Action = 'Fix',
    [ValidateSet('PermanentDisable')]
    [string]$Strategy = 'PermanentDisable',
    [switch]$SkipReboot,
    [switch]$NonInteractive,
    [switch]$Force,
    [switch]$NoBitLockerSuspend,
    [string]$BackupPath,
    [switch]$Json
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:TurtleFixVersion = '2026.08.30.1'
$script:LatestKnownVirtualBoxVersion = [version]'7.2.16'
$script:InvocationParameters = @{}
foreach ($parameterName in $PSBoundParameters.Keys) { $script:InvocationParameters[$parameterName] = $PSBoundParameters[$parameterName] }
$script:StateRoot = Join-Path $env:ProgramData 'TurtleFix'
$script:LogRoot = Join-Path $env:TEMP 'TurtleFix'
$script:LogFile = $null
$script:PostRebootTaskName = 'TurtleFix-PostReboot-Verify'
$script:EnforcementTaskName = 'TurtleFix-Enforce-Hypervisor-Off'
$script:DGReadinessUrl = 'https://download.microsoft.com/download/b/d/8/bd821b1f-05f2-4a7e-aa03-df6c4f687b07/dgreadiness_v3.6.zip'
$script:DGReadinessZipSha256 = 'B351BE8E77C8D7994D97B8B9E60EF310EA5873A336FB8D3B5B009379F29BC6FC'
$script:DGReadinessFiles = @{
    'DG_Readiness_Tool_v3.6.ps1' = 'C248C7EECF637E9CFEC4353B55336542A1AC13FBB5E58EBD622E4717CFFC09C7'
    'DefaultWindows_Audit_sipolicy.p7b' = '40B975DA6D6745FFD735C8D0D9644311B099E3458AA07823F505DA109582A13A'
    'DefaultWindows_Enforced_sipolicy.p7b' = '5835059E0FED0F7DBE7AD482A5033E3726586366D9B27D908B6670AB116D7C0C'
}

$script:RegistryTargets = @(
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'EnableVirtualizationBasedSecurity'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'RequirePlatformSecurityFeatures'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'Locked'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; Name = 'Enabled'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; Name = 'Locked'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard'; Name = 'Enabled'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\DmaGuard'; Name = 'Enabled'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\SystemGuard'; Name = 'Enabled'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'LsaCfgFlags'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'EnableVirtualizationBasedSecurity'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'DeployConfigCIPolicy'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'RequirePlatformSecurityFeatures'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'HypervisorEnforcedCodeIntegrity'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'LsaCfgFlags'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'ConfigureSystemGuardLaunch'; Value = 2 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'MachineIdentityIsolation'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection'; Name = 'DeviceEnumerationPolicy'; Value = 1 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageHealth'; Name = 'AllowDiskHealthModelUpdates'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device performance and health'; Name = 'UILockdown'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security'; Name = 'DisableClearTpmButton'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security'; Name = 'DisableTpmFirmwareUpdateWarning'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security'; Name = 'HideSecureBoot'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security'; Name = 'HideTPMTroubleshooting'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security'; Name = 'UILockdown'; Value = 0 }
)

$script:RegistryDeleteTargets = @(
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender ExploitGuard\Exploit Protection'; Name = 'ExploitProtectionSettings' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender ExploitGuard\Exploit Protection'; Name = '' }
)

$script:OptionalFeatureTargets = @(
    'Microsoft-Hyper-V-All',
    'Microsoft-Hyper-V-Hypervisor',
    'HypervisorPlatform',
    'WindowsHypervisorPlatform',
    'VirtualMachinePlatform',
    'Containers-DisposableClientVM',
    'Windows-Defender-ApplicationGuard',
    'IsolatedUserMode'
)

function Initialize-Logging {
    param([switch]$MachineScope)
    if ($MachineScope) { $script:LogRoot = Join-Path $script:StateRoot 'logs' }
    if (-not (Test-Path -LiteralPath $script:LogRoot)) {
        New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
    }
    $script:LogFile = Join-Path $script:LogRoot ("turtlefix-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

function Write-Log {
    param(
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}' -f (Get-Date), $Level, $Message
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue }
    $color = switch ($Level) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } default { 'Gray' } }
    if (-not ($Json -and $Action -eq 'Diagnose')) { Write-Host $line -ForegroundColor $color }
}

function Test-IsWindows { return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT }

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedCopy {
    if (-not $PSCommandPath) { throw 'Elevation requires TurtleFix.ps1 to be run from a file.' }
    foreach ($value in @($PSCommandPath, $BackupPath)) {
        if ($value -and $value -match '["\r\n]') { throw 'A process argument contains an unsafe quote or newline.' }
    }
    $hostPath = (Get-Process -Id $PID).Path
    $arguments = @('-NoProfile')
    if ($PSVersionTable.PSEdition -eq 'Desktop') { $arguments += @('-ExecutionPolicy', 'Bypass') }
    $arguments += @('-File', ('"{0}"' -f $PSCommandPath), '-Action', $Action, '-Strategy', $Strategy)
    foreach ($switchName in @('SkipReboot', 'NonInteractive', 'Force', 'NoBitLockerSuspend', 'Json', 'WhatIf')) {
        if ($script:InvocationParameters.ContainsKey($switchName) -and $script:InvocationParameters[$switchName]) { $arguments += "-$switchName" }
    }
    if ($BackupPath) { $arguments += @('-BackupPath', ('"{0}"' -f $BackupPath)) }
    Write-Host 'Administrator rights are required. Opening the UAC prompt...' -ForegroundColor Yellow
    $process = Start-Process -FilePath $hostPath -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    return $process.ExitCode
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [switch]$AllowFailure
    )
    # PowerShell can promote a native process' stderr records to terminating
    # errors when the caller uses ErrorActionPreference=Stop. Native tools such
    # as Microsoft's DG readiness script legitimately emit stderr for optional
    # registry values and still return success, so capture it and trust the
    # process exit code instead.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "Command failed ($exitCode): $FilePath $($Arguments -join ' ')`n$($output -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Invoke-NativeCommandWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 4
    )
    if (@($Arguments | Where-Object { $_ -match '[\s"]' }).Count -gt 0) {
        throw 'Timed native-command arguments must not contain whitespace or quotes.'
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $Arguments -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { return [pscustomobject]@{ ExitCode = 1; Output = @('Process did not start.'); TimedOut = $false } }
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch {}
        return [pscustomobject]@{ ExitCode = 1460; Output = @("Timed out after $TimeoutSeconds seconds."); TimedOut = $true }
    }
    $output = @($process.StandardOutput.ReadToEnd() -split "`r?`n" | Where-Object { $_ })
    $errors = @($process.StandardError.ReadToEnd() -split "`r?`n" | Where-Object { $_ })
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = @($output + $errors); TimedOut = $false }
}

function Get-PropertyValue {
    param($InputObject, [string]$Name, $Default = $null)
    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Get-CimInstanceSafe {
    param([string]$ClassName, [string]$Namespace = 'root\cimv2')
    try { return Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop }
    catch { return $null }
}

function Get-RegistryValueState {
    param([string]$Path, [string]$Name)
    $state = [ordered]@{ Path = $Path; Name = $Name; Exists = $false; Kind = $null; Value = $null }
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]$state }
    $key = Get-Item -LiteralPath $Path
    try {
        if (@($key.GetValueNames()) -notcontains $Name) { return [pscustomobject]$state }
        $state.Exists = $true
        $state.Kind = $key.GetValueKind($Name).ToString()
        $state.Value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        return [pscustomobject]$state
    } finally {
        $key.Dispose()
    }
}

function Open-RegistryKeyWritable {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Create
    )
    $match = [regex]::Match($Path, '^(HKLM|HKCU):\\(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { throw "Unsupported registry path: $Path" }

    $rootKey = if ($match.Groups[1].Value -ieq 'HKLM') {
        [Microsoft.Win32.Registry]::LocalMachine
    } else {
        [Microsoft.Win32.Registry]::CurrentUser
    }
    $subKey = $match.Groups[2].Value
    if ($Create) { return $rootKey.CreateSubKey($subKey) }
    return $rootKey.OpenSubKey($subKey, $true)
}

function Set-RegistryDword {
    param([string]$Path, [string]$Name, [int]$Value)
    $registryKey = Open-RegistryKeyWritable -Path $Path -Create
    if ($null -eq $registryKey) { throw "Could not open registry key for writing: $Path" }
    try {
        $registryKey.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::DWord)
    } finally {
        $registryKey.Dispose()
    }
}

function Restore-RegistryValue {
    param($State)
    if ([bool]$State.Exists) {
        $registryKey = Open-RegistryKeyWritable -Path ([string]$State.Path) -Create
        if ($null -eq $registryKey) { throw "Could not open registry key for restore: $($State.Path)" }
        $kind = [Microsoft.Win32.RegistryValueKind]([Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$State.Kind))
        $value = switch ([string]$State.Kind) {
            'DWord' { [int]$State.Value }
            'QWord' { [long]$State.Value }
            'Binary' { [byte[]]@($State.Value) }
            'MultiString' { [string[]]@($State.Value) }
            default { [string]$State.Value }
        }
        try {
            $registryKey.SetValue([string]$State.Name, $value, $kind)
        } finally {
            $registryKey.Dispose()
        }
    } else {
        $registryKey = Open-RegistryKeyWritable -Path ([string]$State.Path)
        if ($null -eq $registryKey) { return }
        try {
            $registryKey.DeleteValue([string]$State.Name, $false)
        } finally {
            $registryKey.Dispose()
        }
    }
}

function Remove-RegistryTarget {
    param([string]$Path, [string]$Name)
    $registryKey = Open-RegistryKeyWritable -Path $Path
    if ($null -eq $registryKey) { return }
    try {
        $registryKey.DeleteValue($Name, $false)
    } finally {
        $registryKey.Dispose()
    }
}

function Get-OptionalFeatureStateSafe {
    param([string]$Name)
    if (-not (Test-IsAdministrator)) {
        return [pscustomobject]@{ Name = $Name; Present = $null; State = 'Unknown'; Error = 'Administrator rights required for an authoritative feature state.' }
    }
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop
        return [pscustomobject]@{ Name = $Name; Present = $true; State = $feature.State.ToString() }
    } catch {
        return [pscustomobject]@{ Name = $Name; Present = $null; State = 'Unknown'; Error = $_.Exception.Message }
    }
}

function Get-CurrentBootIdentifier {
    $result = Invoke-NativeCommand -FilePath 'bcdedit.exe' -Arguments @('/enum', '{current}', '/v')
    $match = [regex]::Match(($result.Output -join "`n"), '\{[0-9a-fA-F-]{36}\}')
    if (-not $match.Success) { throw 'Could not determine the current BCD boot identifier.' }
    return $match.Value
}

function Get-BcdElement {
    param([string]$Name, [string]$Identifier = '{current}')
    $result = Invoke-NativeCommand -FilePath 'bcdedit.exe' -Arguments @('/enum', $Identifier) -AllowFailure
    $pattern = '(?im)^{0}\s+(\S+)' -f [regex]::Escape($Name)
    $match = [regex]::Match(($result.Output -join "`n"), $pattern)
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Get-HypervisorLaunchType {
    param([string]$Identifier = '{current}')
    return Get-BcdElement -Name 'hypervisorlaunchtype' -Identifier $Identifier
}

function Assert-BootIdentifier {
    param([string]$Identifier, [string]$Label)
    if ($Identifier -notmatch '^\{[0-9a-fA-F-]{36}\}$') { throw "Backup contains an invalid $Label boot identifier." }
}

function Get-VirtualBoxInfo {
    $installDir = $null
    $registryVersion = $null
    foreach ($path in @('HKLM:\SOFTWARE\Oracle\VirtualBox', 'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox')) {
        if (Test-Path -LiteralPath $path) {
            $item = Get-ItemProperty -LiteralPath $path
            if (-not $installDir) { $installDir = Get-PropertyValue $item 'InstallDir' }
            if (-not $registryVersion) { $registryVersion = Get-PropertyValue $item 'Version' }
        }
    }
    $vboxManage = Get-Command 'VBoxManage.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    $vboxPath = if ($vboxManage) { $vboxManage.Source } elseif ($installDir) { Join-Path $installDir 'VBoxManage.exe' } else { $null }
    if ($vboxPath -and -not (Test-Path -LiteralPath $vboxPath)) { $vboxPath = $null }
    $version = $registryVersion
    $running = @()
    if ($vboxPath) {
        $versionResult = Invoke-NativeCommandWithTimeout -FilePath $vboxPath -Arguments @('--version')
        if ($versionResult.ExitCode -eq 0 -and $versionResult.Output.Count -gt 0) { $version = $versionResult.Output[0].Trim() }
        $runningResult = Invoke-NativeCommandWithTimeout -FilePath $vboxPath -Arguments @('list', 'runningvms')
        if ($runningResult.ExitCode -eq 0) { $running = @($runningResult.Output | Where-Object { $_.Trim() }) }
    }
    $normalizedVersion = if ($version -and $version -match '^([0-9]+\.[0-9]+\.[0-9]+)') { $matches[1] } else { $null }
    $updateRecommended = $false
    if ($normalizedVersion) {
        try { $updateRecommended = [version]$normalizedVersion -lt $script:LatestKnownVirtualBoxVersion } catch {}
    }
    return [pscustomobject]@{
        Installed = [bool]($vboxPath -or $registryVersion)
        Version = $version
        LatestKnownVersion = $script:LatestKnownVirtualBoxVersion.ToString()
        UpdateRecommended = $updateRecommended
        VBoxManagePath = $vboxPath
        RunningVMs = $running
    }
}

function Get-WslDistributions {
    $lxssPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path -LiteralPath $lxssPath)) { return @() }
    return @(Get-ChildItem -LiteralPath $lxssPath -ErrorAction SilentlyContinue | ForEach-Object {
        $distribution = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        $name = Get-PropertyValue $distribution 'DistributionName'
        if ($name) { $name }
    })
}

function Get-BitLockerState {
    if (-not (Test-IsAdministrator)) {
        return [pscustomobject]@{ Available = $false; Protected = $null; MountPoint = $env:SystemDrive; Error = 'Administrator rights required for an authoritative BitLocker state.' }
    }
    if (-not (Get-Command 'Get-BitLockerVolume' -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Available = $false; Protected = $false; MountPoint = $env:SystemDrive }
    }
    try {
        $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        return [pscustomobject]@{ Available = $true; Protected = ($volume.ProtectionStatus.ToString() -eq 'On'); MountPoint = $volume.MountPoint }
    } catch {
        return [pscustomobject]@{ Available = $true; Protected = $null; MountPoint = $env:SystemDrive; Error = $_.Exception.Message }
    }
}

function Get-TurtleDiagnostics {
    $os = Get-CimInstanceSafe -ClassName Win32_OperatingSystem
    $computer = Get-CimInstanceSafe -ClassName Win32_ComputerSystem
    $cpu = Get-CimInstanceSafe -ClassName Win32_Processor | Select-Object -First 1
    $deviceGuard = Get-CimInstanceSafe -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard
    $windowsRegistry = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $features = @($script:OptionalFeatureTargets | ForEach-Object { Get-OptionalFeatureStateSafe $_ })
    $virtualBox = Get-VirtualBoxInfo
    $wsl = @(Get-WslDistributions)
    $bitLocker = Get-BitLockerState
    $hypervisorPresent = Get-PropertyValue $computer 'HypervisorPresent' $null
    if ($null -ne $hypervisorPresent) { $hypervisorPresent = [bool]$hypervisorPresent }
    $vbsStatus = Get-PropertyValue $deviceGuard 'VirtualizationBasedSecurityStatus' $null
    if ($null -ne $vbsStatus) { $vbsStatus = [int]$vbsStatus }
    $servicesRunning = @((Get-PropertyValue $deviceGuard 'SecurityServicesRunning' @()))
    $enabledFeatures = @($features | Where-Object { $_.Present -and $_.State -match 'Enabled|EnablePending' } | ForEach-Object { $_.Name })
    $dockerDetected = [bool](Get-Process -Name 'Docker Desktop', 'com.docker.backend' -ErrorAction SilentlyContinue)
    $fallbackBuild = Get-PropertyValue $windowsRegistry 'CurrentBuildNumber' ([Environment]::OSVersion.Version.Build)
    $fallbackCaption = Get-PropertyValue $windowsRegistry 'ProductName' 'Windows'
    if ([int]$fallbackBuild -ge 22000) { $fallbackCaption = $fallbackCaption -replace 'Windows 10', 'Windows 11' }
    return [pscustomobject][ordered]@{
        ToolVersion = $script:TurtleFixVersion
        Timestamp = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        Windows = [pscustomobject]@{
            Caption = Get-PropertyValue $os 'Caption' $fallbackCaption
            Version = Get-PropertyValue $os 'Version' ([Environment]::OSVersion.Version.ToString())
            Build = Get-PropertyValue $os 'BuildNumber' $fallbackBuild
            Architecture = Get-PropertyValue $os 'OSArchitecture' $env:PROCESSOR_ARCHITECTURE
        }
        CPU = [pscustomobject]@{
            Name = Get-PropertyValue $cpu 'Name' $env:PROCESSOR_IDENTIFIER
            Manufacturer = Get-PropertyValue $cpu 'Manufacturer'
            VirtualizationFirmwareEnabled = Get-PropertyValue $cpu 'VirtualizationFirmwareEnabled'
            VMMonitorModeExtensions = Get-PropertyValue $cpu 'VMMonitorModeExtensions'
        }
        VirtualBox = $virtualBox
        HypervisorPresent = $hypervisorPresent
        GreenTurtleLikely = $hypervisorPresent
        HypervisorLaunchType = Get-HypervisorLaunchType
        VsmLaunchType = Get-BcdElement -Name 'vsmlaunchtype'
        VirtualizationBasedSecurityStatus = $vbsStatus
        SecurityServicesRunning = $servicesRunning
        OptionalFeatures = $features
        EnabledConflictingFeatures = $enabledFeatures
        WslDistributions = $wsl
        DockerDetected = $dockerDetected
        BitLocker = $bitLocker
        RebootPending = [bool]((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))
    }
}

function Write-DiagnosticSummary {
    param($Diagnostics)
    Write-Host ''
    Write-Host "TurtleFix $($Diagnostics.ToolVersion) diagnosis" -ForegroundColor Cyan
    Write-Host ('-' * 62)
    Write-Host "Windows:       $($Diagnostics.Windows.Caption) build $($Diagnostics.Windows.Build) ($($Diagnostics.Windows.Architecture))"
    Write-Host "VirtualBox:    $(if ($Diagnostics.VirtualBox.Installed) { $Diagnostics.VirtualBox.Version } else { 'not detected' })"
    $hypervisorText = if ($null -eq $Diagnostics.HypervisorPresent) { 'unknown (rerun as Administrator)' } elseif ($Diagnostics.HypervisorPresent) { 'RUNNING - green turtle expected' } else { 'not running - native VirtualBox path available' }
    $vbsText = if ($null -eq $Diagnostics.VirtualizationBasedSecurityStatus) { 'unknown' } else { "$($Diagnostics.VirtualizationBasedSecurityStatus) (0=off, 1=configured, 2=running)" }
    Write-Host "Hypervisor:    $hypervisorText"
    Write-Host "VBS status:    $vbsText"
    Write-Host "BCD launch:    $(if ($Diagnostics.HypervisorLaunchType) { $Diagnostics.HypervisorLaunchType } else { 'default (Auto)' })"
    Write-Host "VSM launch:    $(if ($Diagnostics.VsmLaunchType) { $Diagnostics.VsmLaunchType } else { 'default (Auto)' })"
    Write-Host "Firmware VT:   $($Diagnostics.CPU.VirtualizationFirmwareEnabled)"
    $bitLockerText = if ($null -eq $Diagnostics.BitLocker.Protected) { 'unknown' } elseif ($Diagnostics.BitLocker.Protected) { 'protected' } else { 'not protected / unavailable' }
    Write-Host "BitLocker:     $bitLockerText"
    if ($Diagnostics.EnabledConflictingFeatures.Count -gt 0) { Write-Host "Hyper-V stack: $($Diagnostics.EnabledConflictingFeatures -join ', ')" -ForegroundColor Yellow }
    if ($Diagnostics.WslDistributions.Count -gt 0) { Write-Host "WSL detected:  $($Diagnostics.WslDistributions -join ', ')" -ForegroundColor Yellow }
    if ($Diagnostics.DockerDetected) { Write-Host 'Docker:        running/detected' -ForegroundColor Yellow }
    if ($Diagnostics.VirtualBox.RunningVMs.Count -gt 0) { Write-Host "Running VMs:   $($Diagnostics.VirtualBox.RunningVMs -join ', ')" -ForegroundColor Yellow }
    if ($Diagnostics.VirtualBox.UpdateRecommended) { Write-Host "VirtualBox update recommended: $($Diagnostics.VirtualBox.LatestKnownVersion)" -ForegroundColor Yellow }
    Write-Host ''
}

function New-ChangeBackup {
    param($Diagnostics, [string]$SelectedStrategy)
    $backupRoot = Join-Path $script:StateRoot 'backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $runId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $directory = Join-Path $backupRoot $runId
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $bcdBackup = Join-Path $directory 'bcd.bak'
    Invoke-NativeCommand -FilePath 'bcdedit.exe' -Arguments @('/export', $bcdBackup) | Out-Null
    $registry = @(($script:RegistryTargets + $script:RegistryDeleteTargets) | ForEach-Object { Get-RegistryValueState -Path $_.Path -Name $_.Name })
    $sipolicyPath = Join-Path $env:SystemRoot 'System32\CodeIntegrity\SIPolicy.p7b'
    $sipolicyBackup = Join-Path $directory 'SIPolicy.p7b'
    $sipolicyExisted = Test-Path -LiteralPath $sipolicyPath
    if ($sipolicyExisted) { Copy-Item -LiteralPath $sipolicyPath -Destination $sipolicyBackup -Force }

    $capabilitiesPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Capabilities'
    $capabilitiesBackup = Join-Path $directory 'DeviceGuard-Capabilities.reg'
    $capabilitiesExisted = Test-Path -LiteralPath $capabilitiesPath
    if ($capabilitiesExisted) {
        Invoke-NativeCommand -FilePath 'reg.exe' -Arguments @('export', 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Capabilities', $capabilitiesBackup, '/y') | Out-Null
    }

    $taskBackup = Join-Path $directory 'EnforcementTask.xml'
    $taskExisted = $false
    if (Get-Command 'Get-ScheduledTask' -ErrorAction SilentlyContinue) {
        $existingTask = Get-ScheduledTask -TaskName $script:EnforcementTaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Export-ScheduledTask -TaskName $script:EnforcementTaskName | Set-Content -LiteralPath $taskBackup -Encoding Unicode
            $taskExisted = $true
        }
    }
    $state = [ordered]@{
        SchemaVersion = 2
        ToolVersion = $script:TurtleFixVersion
        CreatedAt = (Get-Date).ToString('o')
        Strategy = $SelectedStrategy
        SourceBootIdentifier = Get-CurrentBootIdentifier
        OriginalHypervisorLaunchType = Get-HypervisorLaunchType
        OriginalVsmLaunchType = Get-BcdElement -Name 'vsmlaunchtype'
        BcdBackup = $bcdBackup
        Registry = $registry
        OptionalFeatures = $Diagnostics.OptionalFeatures
        SIPolicy = [ordered]@{ Existed = $sipolicyExisted; OriginalPath = $sipolicyPath; BackupPath = $sipolicyBackup }
        Capabilities = [ordered]@{ Existed = $capabilitiesExisted; RegistryPath = $capabilitiesPath; BackupPath = $capabilitiesBackup }
        EnforcementTask = [ordered]@{ Existed = $taskExisted; BackupPath = $taskBackup }
        BitLockerWasProtected = [bool]$Diagnostics.BitLocker.Protected
        DriverVerifierWasReset = $false
    }
    $statePath = Join-Path $directory 'state.json'
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
    return [pscustomobject]@{ Directory = $directory; Path = $statePath; State = $state }
}

function Update-BackupState {
    param($Backup)
    $Backup.State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Backup.Path -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $script:StateRoot 'latest-backup.txt') -Value $Backup.Path -Encoding ASCII
}

function Protect-StateDirectory {
    if (-not (Test-Path -LiteralPath $script:StateRoot)) { return }
    Invoke-NativeCommand -FilePath 'icacls.exe' -Arguments @($script:StateRoot, '/inheritance:r') | Out-Null
    Invoke-NativeCommand -FilePath 'icacls.exe' -Arguments @($script:StateRoot, '/grant:r', '*S-1-5-18:(OI)(CI)(F)', '*S-1-5-32-544:(OI)(CI)(F)') | Out-Null
}

function Suspend-BitLockerForRestart {
    param($Diagnostics)
    if ($NoBitLockerSuspend -or -not $Diagnostics.BitLocker.Protected) { return }
    if (-not (Get-Command 'Suspend-BitLocker' -ErrorAction SilentlyContinue)) {
        throw 'BitLocker is protected, but Suspend-BitLocker is unavailable. Use -NoBitLockerSuspend only after saving the recovery key.'
    }
    Write-Log INFO 'Suspending BitLocker protection for one restart.'
    Suspend-BitLocker -MountPoint $Diagnostics.BitLocker.MountPoint -RebootCount 1 | Out-Null
}

function Install-PostRebootVerifier {
    New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null
    $installedScript = Join-Path $script:StateRoot 'TurtleFix.ps1'
    Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
    if (-not (Get-Command 'Register-ScheduledTask' -ErrorAction SilentlyContinue)) {
        Write-Log WARN 'Scheduled Tasks module is unavailable; automatic post-reboot verification was skipped.'
        return
    }
    $argument = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action Verify -NonInteractive' -f $installedScript
    $taskAction = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $argument
    $trigger = New-ScheduledTaskTrigger -AtStartup
    if ($trigger.PSObject.Properties['Delay']) { $trigger.Delay = 'PT30S' }
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $script:PostRebootTaskName -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Log OK 'Installed a one-time post-reboot verification task.'
}

function Remove-PostRebootVerifier {
    if ((Test-IsAdministrator) -and (Get-Command 'Unregister-ScheduledTask' -ErrorAction SilentlyContinue)) {
        Unregister-ScheduledTask -TaskName $script:PostRebootTaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Test-DGReadinessFiles {
    param([string]$Directory)
    foreach ($entry in $script:DGReadinessFiles.GetEnumerator()) {
        $path = Join-Path $Directory $entry.Key
        if (-not (Test-Path -LiteralPath $path)) { return $false }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry.Value) { return $false }
    }
    $toolScript = Join-Path $Directory 'DG_Readiness_Tool_v3.6.ps1'
    $signature = Get-AuthenticodeSignature -LiteralPath $toolScript
    return ($signature.Status -eq 'Valid' -and $signature.SignerCertificate -and $signature.SignerCertificate.Subject -match 'O=Microsoft Corporation')
}

function Install-DGReadinessTool {
    $toolDirectory = Join-Path $script:StateRoot 'tools\DGReadiness-v3.6'
    if (Test-DGReadinessFiles -Directory $toolDirectory) { return $toolDirectory }
    $downloadDirectory = Join-Path $script:StateRoot 'downloads'
    New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null
    $zipPath = Join-Path $downloadDirectory 'dgreadiness_v3.6.zip'
    $expanded = Join-Path $downloadDirectory 'dgreadiness-v3.6-expanded'
    Write-Log INFO 'Downloading the pinned Microsoft Device Guard readiness tool v3.6.'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $script:DGReadinessUrl -OutFile $zipPath -UseBasicParsing
    if ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ine $script:DGReadinessZipSha256) {
        throw 'Microsoft Device Guard readiness ZIP failed its pinned SHA-256 check.'
    }
    if (Test-Path -LiteralPath $expanded) { Remove-Item -LiteralPath $expanded -Recurse -Force }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $expanded -Force
    $source = Join-Path $expanded 'dgreadiness_v3.6'
    if (-not (Test-DGReadinessFiles -Directory $source)) { throw 'Microsoft Device Guard readiness files failed hash or Authenticode validation.' }
    if (Test-Path -LiteralPath $toolDirectory) { Remove-Item -LiteralPath $toolDirectory -Recurse -Force }
    New-Item -ItemType Directory -Path (Split-Path -Parent $toolDirectory) -Force | Out-Null
    Move-Item -LiteralPath $source -Destination $toolDirectory
    Write-Log OK 'Validated and cached Microsoft Device Guard readiness tool v3.6.'
    return $toolDirectory
}

function Invoke-DGReadinessTool {
    param([string]$ToolDirectory, [ValidateSet('Disable', 'Ready')][string]$Mode)
    if (-not (Test-DGReadinessFiles -Directory $ToolDirectory)) { throw 'Device Guard readiness tool validation failed immediately before execution.' }
    $toolScript = Join-Path $ToolDirectory 'DG_Readiness_Tool_v3.6.ps1'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $toolScript, "-$Mode")
    Write-Log INFO "Running Microsoft Device Guard readiness tool in -$Mode mode."
    $result = Invoke-NativeCommand -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Arguments $arguments -AllowFailure
    foreach ($line in $result.Output) { Write-Log INFO "DGReadiness: $line" }
    if ($result.ExitCode -ne 0) { throw "Microsoft Device Guard readiness tool -$Mode failed with exit code $($result.ExitCode)." }
}

function Stage-DefaultSIPolicy {
    param([string]$ToolDirectory)
    $source = Join-Path $ToolDirectory 'DefaultWindows_Audit_sipolicy.p7b'
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ine $script:DGReadinessFiles['DefaultWindows_Audit_sipolicy.p7b']) {
        throw 'The pinned Microsoft audit SIPolicy failed validation.'
    }
    $destination = Join-Path $env:SystemRoot 'System32\CodeIntegrity\SIPolicy.p7b'
    Copy-Item -LiteralPath $source -Destination $destination -Force
    Write-Log OK 'Staged the validated Microsoft audit SIPolicy for the readiness-tool disable workflow.'
}

function Set-CapabilityValue {
    param([string]$Name, [int]$Value)
    Set-RegistryDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Capabilities' -Name $Name -Value $Value
}

function Reset-DriverVerifier {
    $result = Invoke-NativeCommand -FilePath 'verifier.exe' -Arguments @('/reset') -AllowFailure
    if ($result.ExitCode -eq 0) { Write-Log OK 'Reset Driver Verifier settings.'; return $true }
    throw "Driver Verifier reset failed with exit code $($result.ExitCode): $($result.Output -join ' ')"
}

function Update-DeviceGuardCapabilities {
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Capabilities'
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }

    $secureBoot = 0
    try { if (Confirm-SecureBootUEFI -ErrorAction Stop) { $secureBoot = 2 } } catch {}
    $cpu = Get-CimInstanceSafe -ClassName Win32_Processor | Select-Object -First 1
    $virtualization = if ((Get-PropertyValue $cpu 'VirtualizationFirmwareEnabled' $false) -and (Get-PropertyValue $cpu 'VMMonitorModeExtensions' $false)) { 2 } else { 0 }
    $tpm = 0
    if (Get-Command 'Get-Tpm' -ErrorAction SilentlyContinue) {
        try { $tpmState = Get-Tpm -ErrorAction Stop; if ($tpmState.TpmPresent -and $tpmState.TpmReady) { $tpm = 2 } elseif ($tpmState.TpmPresent) { $tpm = 1 } } catch {}
    }
    $operatingSystem = Get-CimInstanceSafe -ClassName Win32_OperatingSystem
    $dep = if (Get-PropertyValue $operatingSystem 'DataExecutionPrevention_Available' $false) { 2 } else { 0 }
    $deviceGuard = Get-CimInstanceSafe -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard
    $properties = @((Get-PropertyValue $deviceGuard 'AvailableSecurityProperties' @()))
    $secureMor = if ($properties -contains 4) { 2 } else { 1 }
    $smm = if ($properties -contains 6) { 2 } else { 1 }
    $hsti = if ($secureBoot -eq 2 -and $tpm -gt 0) { 2 } else { 1 }
    $driverCompat = 0
    $drivers = Get-CimInstanceSafe -ClassName Win32_PnPSignedDriver
    if ($null -ne $drivers) { $driverCompat = if (@($drivers | Where-Object { $_.IsSigned -eq $false }).Count -eq 0) { 2 } else { 1 } }

    $values = [ordered]@{
        SecureBoot = $secureBoot; Virtualization = $virtualization; TPM = $tpm; UEFINX = $dep
        SecureMOR = $secureMor; SMMProtections = $smm; DriverCompat = $driverCompat; OSSKU = 2; HSTI = $hsti
    }
    foreach ($entry in $values.GetEnumerator()) { Set-CapabilityValue -Name $entry.Key -Value $entry.Value }
    Set-CapabilityValue -Name 'CG_Capable' -Value ([Math]::Min($secureBoot, [Math]::Min($virtualization, $tpm)))
    Set-CapabilityValue -Name 'HVCI_Capable' -Value ([Math]::Min($virtualization, $driverCompat))
    Set-CapabilityValue -Name 'DG_Capable' -Value ([Math]::Min($secureBoot, [Math]::Min($virtualization, $driverCompat)))
    Write-Log OK 'Updated Device Guard capability telemetry without enabling Driver Verifier.'
}

function Update-DeviceGuardRunningState {
    $deviceGuard = Get-CimInstanceSafe -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard
    $services = @((Get-PropertyValue $deviceGuard 'SecurityServicesRunning' @()))
    $vbs = [int](Get-PropertyValue $deviceGuard 'VirtualizationBasedSecurityStatus' 0)
    Set-CapabilityValue -Name 'CG_Running' -Value $(if ($services -contains 1) { 1 } else { 0 })
    Set-CapabilityValue -Name 'HVCI_Running' -Value $(if ($services -contains 2) { 1 } else { 0 })
    Set-CapabilityValue -Name 'DG_Running' -Value $(if ($vbs -eq 2) { 1 } else { 0 })
}

function Remove-ActiveSIPolicySafely {
    $policyPath = Join-Path $env:SystemRoot 'System32\CodeIntegrity\SIPolicy.p7b'
    if (-not (Test-Path -LiteralPath $policyPath)) { return }
    $hash = (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash
    $quarantine = Join-Path $script:StateRoot 'quarantine\sipolicy'
    New-Item -ItemType Directory -Path $quarantine -Force | Out-Null
    $backup = Join-Path $quarantine ("SIPolicy-{0}.p7b" -f $hash)
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $policyPath -Destination $backup -Force }
    Remove-Item -LiteralPath $policyPath -Force
    Write-Log WARN "Removed active SIPolicy.p7b after preserving SHA-256 $hash in quarantine."
}

function Apply-PermanentDisablePolicy {
    foreach ($target in $script:RegistryTargets) {
        Set-RegistryDword -Path $target.Path -Name $target.Name -Value $target.Value
    }
    foreach ($target in $script:RegistryDeleteTargets) { Remove-RegistryTarget -Path $target.Path -Name $target.Name }
    Remove-ActiveSIPolicySafely
    foreach ($featureName in $script:OptionalFeatureTargets) {
        $feature = Get-OptionalFeatureStateSafe -Name $featureName
        if ($feature.Present -and $feature.State -match 'Enabled|EnablePending') {
            Write-Log INFO "Disabling optional feature $($feature.Name)."
            Disable-WindowsOptionalFeature -Online -FeatureName $feature.Name -NoRestart -ErrorAction Stop | Out-Null
        }
    }
    Invoke-NativeCommand -FilePath 'bcdedit.exe' -Arguments @('/set', '{current}', 'hypervisorlaunchtype', 'off') | Out-Null
    Invoke-NativeCommand -FilePath 'bcdedit.exe' -Arguments @('/set', '{current}', 'vsmlaunchtype', 'off') | Out-Null
    Write-Log OK 'Applied permanent Hyper-V, VBS, Credential Guard, policy UI, DMA, storage and exploit-policy settings.'
}

function Install-EnforcementTask {
    $installedScript = Join-Path $script:StateRoot 'TurtleFix.ps1'
    Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
    if (-not (Get-Command 'Register-ScheduledTask' -ErrorAction SilentlyContinue)) { throw 'Scheduled Tasks module is required for permanent enforcement.' }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action Enforce -NonInteractive -Force' -f $installedScript
    $taskAction = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $arguments
    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    if ($startupTrigger.PSObject.Properties['Delay']) { $startupTrigger.Delay = 'PT15S' }
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn
    $dailyTrigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.AddHours(3))
    $triggers = @($startupTrigger, $logonTrigger, $dailyTrigger)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $script:EnforcementTaskName -Action $taskAction -Trigger $triggers -Principal $principal -Settings $settings -Force | Out-Null
    Write-Log OK 'Installed permanent SYSTEM startup, logon and daily enforcement for the Hyper-V-off configuration.'
}

function Remove-EnforcementTask {
    if (Get-Command 'Unregister-ScheduledTask' -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $script:EnforcementTaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Confirm-PermanentDisable {
    param($Diagnostics)
    if ($Force -or $WhatIfPreference) { return }
    if ($NonInteractive) { throw 'PermanentDisable in non-interactive mode requires -Force.' }
    Write-Host ''
    Write-Host 'PermanentDisable turns off Windows security and platform features that depend on Hyper-V.' -ForegroundColor Yellow
    if ($Diagnostics.WslDistributions.Count -gt 0) { Write-Host 'WSL 2 distributions may stop starting.' -ForegroundColor Yellow }
    if ($Diagnostics.DockerDetected) { Write-Host 'Docker Desktop may stop starting.' -ForegroundColor Yellow }
    Write-Host 'There is no Hyper-V fallback boot profile. Restore is available only as an explicit rollback action.' -ForegroundColor Yellow
    $answer = Read-Host 'Type PERMANENT-DISABLE to continue'
    if ($answer -cne 'PERMANENT-DISABLE') { throw 'PermanentDisable was cancelled.' }
}

function Invoke-Fix {
    $diagnostics = Get-TurtleDiagnostics
    Write-DiagnosticSummary $diagnostics
    if ($null -eq $diagnostics.HypervisorPresent) { throw 'Could not determine whether the Microsoft hypervisor is running. Rerun from a fully elevated local PowerShell session.' }
    if ($diagnostics.BitLocker.Available -and $null -eq $diagnostics.BitLocker.Protected) { throw "Could not determine BitLocker protection state: $($diagnostics.BitLocker.Error)" }
    if ($diagnostics.HypervisorPresent -eq $false -and $diagnostics.CPU.VMMonitorModeExtensions -eq $false) { throw 'The CPU does not report virtualization extensions. Native VirtualBox acceleration is unavailable.' }
    if ($diagnostics.HypervisorPresent -eq $false -and $diagnostics.CPU.VirtualizationFirmwareEnabled -eq $false) { throw 'VT-x/AMD-V is disabled in UEFI/BIOS. Enable it there, then rerun TurtleFix.' }
    if ($diagnostics.VirtualBox.RunningVMs.Count -gt 0) { throw 'VirtualBox VMs are running. Shut them down cleanly before changing the boot configuration.' }
    Confirm-PermanentDisable $diagnostics
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Apply TurtleFix strategy $Strategy and prepare a restart")) { return 0 }
    New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null
    $backup = New-ChangeBackup -Diagnostics $diagnostics -SelectedStrategy $Strategy
    Update-BackupState $backup
    Protect-StateDirectory
    Write-Log OK "Saved reversible state and BCD backup to $($backup.Directory)."
    try {
        $toolDirectory = Install-DGReadinessTool
        Suspend-BitLockerForRestart $diagnostics
        $backup.State.DriverVerifierWasReset = Reset-DriverVerifier
        Update-BackupState $backup
        Update-DeviceGuardCapabilities
        Stage-DefaultSIPolicy -ToolDirectory $toolDirectory
        Invoke-DGReadinessTool -ToolDirectory $toolDirectory -Mode Disable
        Apply-PermanentDisablePolicy
        Update-DeviceGuardRunningState
        Install-EnforcementTask
        Install-PostRebootVerifier
        Update-BackupState $backup
        Protect-StateDirectory
    } catch {
        $applyError = $_.Exception.Message
        Write-Log ERROR "Apply failed: $applyError"
        try {
            Restore-BackupStateCore -State $backup.State
            Write-Log OK 'Automatically rolled back the managed pre-fix state after the failure.'
        } catch {
            Write-Log ERROR "Automatic rollback also failed: $($_.Exception.Message)"
        }
        Write-Log WARN "Restore with: .\TurtleFix.ps1 -Action Restore -BackupPath `"$($backup.Path)`""
        throw $applyError
    }
    Write-Log OK 'Changes are staged successfully. A restart is required.'
    Write-Host "Restore state: $($backup.Path)" -ForegroundColor Cyan
    if ($SkipReboot -or $WhatIfPreference) { Write-Log INFO 'Restart skipped. Run Restart-Computer when ready.'; return 0 }
    if (-not $NonInteractive -and -not $Force) {
        $answer = Read-Host 'Restart now? [Y/n]'
        if ($answer -and $answer -notmatch '^(?i)y(es)?$') { Write-Log INFO 'Restart postponed.'; return 0 }
    }
    Write-Log INFO 'Restarting Windows now.'
    Restart-Computer
    return 0
}

function Test-PermanentDisablePolicy {
    param($Diagnostics)
    $registryFailures = @()
    foreach ($target in $script:RegistryTargets) {
        $state = Get-RegistryValueState -Path $target.Path -Name $target.Name
        if (-not $state.Exists -or [int]$state.Value -ne [int]$target.Value) { $registryFailures += "$($target.Path)\$($target.Name)" }
    }
    foreach ($target in $script:RegistryDeleteTargets) {
        $state = Get-RegistryValueState -Path $target.Path -Name $target.Name
        if ($state.Exists) { $registryFailures += "$($target.Path)\$($target.Name)" }
    }
    $taskPresent = $false
    if (Get-Command 'Get-ScheduledTask' -ErrorAction SilentlyContinue) {
        $taskPresent = $null -ne (Get-ScheduledTask -TaskName $script:EnforcementTaskName -ErrorAction SilentlyContinue)
    }
    $capabilityFailures = @()
    $capabilityPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Capabilities'
    foreach ($name in @('SecureBoot', 'Virtualization', 'TPM', 'UEFINX', 'SecureMOR', 'SMMProtections', 'DriverCompat', 'OSSKU', 'HSTI', 'CG_Capable', 'HVCI_Capable', 'DG_Capable', 'CG_Running', 'HVCI_Running', 'DG_Running')) {
        $state = Get-RegistryValueState -Path $capabilityPath -Name $name
        if (-not $state.Exists -or [int]$state.Value -notin @(0, 1, 2)) { $capabilityFailures += $name }
    }
    return [pscustomobject]@{
        RegistryFailures = $registryFailures
        CapabilityFailures = $capabilityFailures
        BcdHypervisorOff = $Diagnostics.HypervisorLaunchType -ieq 'Off'
        BcdVsmOff = $Diagnostics.VsmLaunchType -ieq 'Off'
        FeaturesDisabled = $Diagnostics.EnabledConflictingFeatures.Count -eq 0
        SIPolicyRemoved = -not (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\CodeIntegrity\SIPolicy.p7b'))
        VbsStopped = $Diagnostics.VirtualizationBasedSecurityStatus -eq 0
        HypervisorStopped = $Diagnostics.HypervisorPresent -eq $false
        EnforcementTaskPresent = $taskPresent
    }
}

function Invoke-Verify {
    $toolDirectory = Install-DGReadinessTool
    Invoke-DGReadinessTool -ToolDirectory $toolDirectory -Mode Ready
    $diagnostics = Get-TurtleDiagnostics
    Update-DeviceGuardRunningState
    Write-DiagnosticSummary $diagnostics
    $policy = Test-PermanentDisablePolicy -Diagnostics $diagnostics
    $success = $policy.HypervisorStopped -and $policy.VbsStopped -and $policy.BcdHypervisorOff -and $policy.BcdVsmOff -and $policy.FeaturesDisabled -and $policy.SIPolicyRemoved -and $policy.EnforcementTaskPresent -and $policy.RegistryFailures.Count -eq 0 -and $policy.CapabilityFailures.Count -eq 0
    $report = [ordered]@{ VerifiedAt = (Get-Date).ToString('o'); Success = $success; GreenTurtleExpected = $diagnostics.HypervisorPresent; Policy = $policy; Diagnostics = $diagnostics }
    try {
        if (Test-IsAdministrator) {
            New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null
            $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $script:StateRoot 'latest-verification.json') -Encoding UTF8
        }
    } catch { Write-Log WARN "Could not save verification report: $($_.Exception.Message)" }
    Remove-PostRebootVerifier
    if ($success) { Write-Log OK 'Verified: Hyper-V/VBS are stopped, all policy surfaces are enforced, and VirtualBox can use native VT-x/AMD-V.'; return 0 }
    if ($null -eq $diagnostics.HypervisorPresent) {
        Write-Log ERROR 'Verification was inconclusive because Windows denied the hypervisor runtime query.'
    } else {
        Write-Log ERROR 'Verification failed: the Microsoft hypervisor is still running, so the green turtle is expected.'
    }
    if ($policy.RegistryFailures.Count -gt 0) { Write-Log ERROR "Registry verification failures: $($policy.RegistryFailures -join ', ')" }
    if ($policy.CapabilityFailures.Count -gt 0) { Write-Log ERROR "Device Guard capability verification failures: $($policy.CapabilityFailures -join ', ')" }
    if (-not $policy.SIPolicyRemoved) { Write-Log ERROR 'Classic SIPolicy.p7b is still active.' }
    if (-not $policy.EnforcementTaskPresent) { Write-Log ERROR 'Permanent SYSTEM enforcement task is missing.' }
    return 2
}

function Get-LatestBackupPath {
    if ($BackupPath) { return $BackupPath }
    $pointer = Join-Path $script:StateRoot 'latest-backup.txt'
    if (-not (Test-Path -LiteralPath $pointer)) { throw 'No TurtleFix backup was found. Supply -BackupPath explicitly.' }
    return (Get-Content -LiteralPath $pointer -Raw).Trim()
}

function Assert-BackupState {
    param($State, [string]$StatePath)
    if ($null -eq $State -or $State.SchemaVersion -ne 2) { throw 'Unsupported or missing TurtleFix backup schema.' }
    if ($State.Strategy -ne 'PermanentDisable') { throw 'Backup contains an invalid strategy.' }
    Assert-BootIdentifier -Identifier $State.SourceBootIdentifier -Label 'source'

    $allowedRegistry = @{}
    foreach ($target in ($script:RegistryTargets + $script:RegistryDeleteTargets)) { $allowedRegistry[("{0}|{1}" -f $target.Path, $target.Name)] = $true }
    if (@($State.Registry).Count -ne ($script:RegistryTargets.Count + $script:RegistryDeleteTargets.Count)) { throw 'Backup registry snapshot is incomplete or contains duplicates.' }
    $seenRegistry = @{}
    foreach ($entry in @($State.Registry)) {
        $key = "{0}|{1}" -f $entry.Path, $entry.Name
        if (-not $allowedRegistry.ContainsKey($key)) { throw "Backup contains an unmanaged registry value: $key" }
        if ($seenRegistry.ContainsKey($key)) { throw "Backup contains a duplicate registry value: $key" }
        $seenRegistry[$key] = $true
        if ($entry.Exists -and $entry.Kind -notin @('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')) {
            throw "Backup contains an unsupported registry kind for $key."
        }
    }

    if (@($State.OptionalFeatures).Count -ne $script:OptionalFeatureTargets.Count) { throw 'Backup optional-feature snapshot is incomplete or contains duplicates.' }
    $seenFeatures = @{}
    foreach ($feature in @($State.OptionalFeatures)) {
        if ($feature.Name -notin $script:OptionalFeatureTargets) { throw "Backup contains an unmanaged optional feature: $($feature.Name)" }
        if ($seenFeatures.ContainsKey($feature.Name)) { throw "Backup contains a duplicate optional feature: $($feature.Name)" }
        $seenFeatures[$feature.Name] = $true
    }

    $fullStatePath = [IO.Path]::GetFullPath($StatePath)
    $allowedRoot = [IO.Path]::GetFullPath((Join-Path $script:StateRoot 'backups')).TrimEnd('\') + '\'
    if (-not $fullStatePath.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Backup state must be inside the protected TurtleFix backup root.' }
    $directory = [IO.Path]::GetFullPath((Split-Path -Parent $fullStatePath)).TrimEnd('\')
    $expectedFiles = @{
        ([IO.Path]::GetFullPath([string]$State.BcdBackup)) = 'bcd.bak'
        ([IO.Path]::GetFullPath([string]$State.SIPolicy.BackupPath)) = 'SIPolicy.p7b'
        ([IO.Path]::GetFullPath([string]$State.Capabilities.BackupPath)) = 'DeviceGuard-Capabilities.reg'
        ([IO.Path]::GetFullPath([string]$State.EnforcementTask.BackupPath)) = 'EnforcementTask.xml'
    }
    foreach ($path in $expectedFiles.Keys) {
        if ((Split-Path -Parent $path).TrimEnd('\') -ine $directory -or (Split-Path -Leaf $path) -ine $expectedFiles[$path]) {
            throw "Backup references an unsafe file path: $path"
        }
    }
    $expectedSIPolicy = Join-Path $env:SystemRoot 'System32\CodeIntegrity\SIPolicy.p7b'
    if ([IO.Path]::GetFullPath([string]$State.SIPolicy.OriginalPath) -ine [IO.Path]::GetFullPath($expectedSIPolicy)) { throw 'Backup contains an invalid SIPolicy destination.' }
}

function Restore-BackupStateCore {
    param($State)
    Remove-EnforcementTask
    Invoke-NativeCommand -FilePath 'bcdedit.exe' -Arguments @('/import', [string]$State.BcdBackup) | Out-Null
    foreach ($registryState in $State.Registry) { Restore-RegistryValue $registryState }
    foreach ($feature in $State.OptionalFeatures) {
        if ($feature.Present) {
            $currentFeature = Get-OptionalFeatureStateSafe $feature.Name
            $originallyEnabled = $feature.State -match 'Enabled|EnablePending'
            $currentlyEnabled = $currentFeature.State -match 'Enabled|EnablePending'
            if ($currentFeature.Present -and $originallyEnabled -and -not $currentlyEnabled) {
                Write-Log INFO "Re-enabling optional feature $($feature.Name)."
                Enable-WindowsOptionalFeature -Online -FeatureName $feature.Name -NoRestart -ErrorAction Stop | Out-Null
            } elseif ($currentFeature.Present -and -not $originallyEnabled -and $currentlyEnabled) {
                Write-Log INFO "Restoring disabled state for optional feature $($feature.Name)."
                Disable-WindowsOptionalFeature -Online -FeatureName $feature.Name -NoRestart -ErrorAction Stop | Out-Null
            }
        }
    }

    if ($State.SIPolicy.Existed) { Copy-Item -LiteralPath $State.SIPolicy.BackupPath -Destination $State.SIPolicy.OriginalPath -Force }
    elseif (Test-Path -LiteralPath $State.SIPolicy.OriginalPath) { Remove-Item -LiteralPath $State.SIPolicy.OriginalPath -Force }

    $capabilitiesPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Capabilities'
    if (Test-Path -LiteralPath $capabilitiesPath) { Remove-Item -LiteralPath $capabilitiesPath -Recurse -Force }
    if ($State.Capabilities.Existed) { Invoke-NativeCommand -FilePath 'reg.exe' -Arguments @('import', [string]$State.Capabilities.BackupPath) | Out-Null }

    if ($State.EnforcementTask.Existed) {
        $taskXml = Get-Content -LiteralPath $State.EnforcementTask.BackupPath -Raw
        Register-ScheduledTask -TaskName $script:EnforcementTaskName -Xml $taskXml -Force | Out-Null
    }
    Remove-PostRebootVerifier
}

function Invoke-Restore {
    $statePath = Get-LatestBackupPath
    if (-not (Test-Path -LiteralPath $statePath)) { throw "Backup state does not exist: $statePath" }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Assert-BackupState $state $statePath
    foreach ($requiredFile in @([string]$state.BcdBackup)) {
        if (-not (Test-Path -LiteralPath $requiredFile)) { throw "Required backup file is missing: $requiredFile" }
    }
    if ($state.SIPolicy.Existed -and -not (Test-Path -LiteralPath $state.SIPolicy.BackupPath)) { throw 'Original SIPolicy backup is missing.' }
    if ($state.Capabilities.Existed -and -not (Test-Path -LiteralPath $state.Capabilities.BackupPath)) { throw 'Original Device Guard capabilities backup is missing.' }
    if ($state.EnforcementTask.Existed -and -not (Test-Path -LiteralPath $state.EnforcementTask.BackupPath)) { throw 'Original enforcement-task XML backup is missing.' }
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Restore TurtleFix state from $statePath")) { return 0 }
    Restore-BackupStateCore -State $state
    Write-Log OK 'Original TurtleFix-managed settings were restored. Restart Windows to complete the restore.'
    if (-not $SkipReboot -and ($NonInteractive -or $Force)) { Restart-Computer }
    return 0
}

function Invoke-Enforce {
    Apply-PermanentDisablePolicy
    Update-DeviceGuardCapabilities
    Update-DeviceGuardRunningState
    Protect-StateDirectory
    return 0
}

function Invoke-Diagnose {
    $diagnostics = Get-TurtleDiagnostics
    if ($Json) { [Console]::Out.WriteLine(($diagnostics | ConvertTo-Json -Depth 8)) } else { Write-DiagnosticSummary $diagnostics }
    return 0
}

function Invoke-TurtleFix {
    if (-not (Test-IsWindows)) { throw 'TurtleFix supports Windows hosts only.' }
    $requiresAdmin = $Action -in @('Fix', 'Verify', 'Restore', 'Enforce')
    if ($requiresAdmin -and -not (Test-IsAdministrator)) { return Start-ElevatedCopy }
    Initialize-Logging -MachineScope:$requiresAdmin
    Write-Log INFO "TurtleFix $script:TurtleFixVersion action=$Action strategy=$Strategy"
    switch ($Action) {
        'Diagnose' { return Invoke-Diagnose }
        'Fix' { return Invoke-Fix }
        'Verify' { return Invoke-Verify }
        'Restore' { return Invoke-Restore }
        'Enforce' { return Invoke-Enforce }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { $exitCode = Invoke-TurtleFix; exit $exitCode }
    catch { if (-not $script:LogFile) { Initialize-Logging }; Write-Log ERROR $_.Exception.Message; exit 1 }
}
