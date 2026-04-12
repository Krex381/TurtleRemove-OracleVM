#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disable VBS/Hypervisor on Windows 11 24H2/25H2 - Remove VirtualBox green turtle
.PARAMETER SkipReboot
    Skip automatic reboot (manual reboot required)
.EXAMPLE
    .\Disable-VirtualBoxTurtle-Full.ps1
    .\Disable-VirtualBoxTurtle-Full.ps1 -SkipReboot
#>

param([switch]$SkipReboot)

$ErrorActionPreference = "Continue"
$LogDir = "C:\SchildkröteFix"
$PersistDir = "C:\ProgramData\SchildkroteFix"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "VBS_Disabler_$Timestamp.log"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Log {
    param([string]$Message)
    $ts = Get-Date -Format "HH:mm:ss"
    $entry = "[$ts] $Message"
    Add-Content $LogFile -Value $entry -ErrorAction SilentlyContinue
    Write-Host $entry
}

function Confirm-Yes {
    param([string]$Prompt)
    $answer = Read-Host $Prompt
    return $answer -match '^(?i)y(es)?$'
}

function Test-RedstoneOrLater {
    return [System.Environment]::OSVersion.Version.Build -gt 10586
}

function Write-SIPolicyForParity {
    $ciDir = "$env:WINDIR\System32\CodeIntegrity"
    if (-not (Test-Path $ciDir)) { New-Item -ItemType Directory -Path $ciDir -Force | Out-Null }

    $candidates = @(
        (Join-Path $PSScriptRoot "DefaultWindows_Audit_sipolicy.p7b"),
        (Join-Path $PSScriptRoot "DefaultWindows_Enforced_sipolicy.p7b"),
        "C:\SchildkröteFix\DefaultWindows_Audit_sipolicy.p7b",
        "C:\SchildkröteFix\DefaultWindows_Enforced_sipolicy.p7b"
    )

    $source = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($source) {
        Copy-Item $source "$ciDir\SIPolicy.p7b" -Force -ErrorAction SilentlyContinue
        Log "OK: SIPolicy.p7b staged for DG parity"
    } else {
        Log "INFO: No default SIPolicy.p7b found for parity stage"
    }
}

function Set-CapabilityValue {
    param(
        [string]$Name,
        [int]$Value
    )

    $capPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Capabilities"
    if (-not (Test-Path $capPath)) { New-Item -Path $capPath -Force | Out-Null }
    Set-ItemProperty -Path $capPath -Name $Name -Value $Value -Type DWord -Force -ErrorAction SilentlyContinue
}

function Invoke-CapabilityChecks {
    Log "Running capability checks (DG parity mode)"

    $score = @{
        SecureBoot = 0
        Virtualization = 0
        TPM = 0
        UEFINX = 0
        SecureMOR = 0
        SMMProtections = 0
        DriverCompat = 0
        OSSKU = 0
        HSTI = 0
    }

    $secureBoot = $false
    try { $secureBoot = Confirm-SecureBootUEFI } catch { $secureBoot = $false }
    if ($secureBoot) { $score.SecureBoot = 2 } else { $score.SecureBoot = 0 }

    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    if ($cpu.VirtualizationFirmwareEnabled -and $cpu.VMMonitorModeExtensions) { $score.Virtualization = 2 } else { $score.Virtualization = 0 }

    if (Get-Command Get-Tpm -ErrorAction SilentlyContinue) {
        $tpm = Get-Tpm
        if ($tpm.TpmPresent -and $tpm.TpmReady) {
            $score.TPM = 2
        }
    }

    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.DataExecutionPrevention_Available) { $score.UEFINX = 2 }

    $dgObj = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
    if ($null -ne $dgObj) {
        $avail = @($dgObj.AvailableSecurityProperties)
        if ($avail -contains 4) { $score.SecureMOR = 2 }
        if ($avail -contains 6) { $score.SMMProtections = 2 }
    }

    $hstiFound = $false
    $hstiHealthy = $false
    try {
        $hstiObj = Get-CimInstance -Namespace root\WMI -ClassName MSFT_HSTI -ErrorAction Stop
        $hstiFound = $true
        if ($hstiObj) {
            $hstiHealthy = $true
        }
    } catch {
        $hstiFound = $false
    }

    if ($hstiFound) {
        $score.HSTI = if ($hstiHealthy) { 2 } else { 0 }
    } else {
        $score.HSTI = 1
        Log "INFO: HSTI class not available on this device"
    }

    $sku = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).EditionID
    if ($sku) { $score.OSSKU = 2 }

    $unsigned = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object { $_.IsSigned -eq $false }
    if (-not $unsigned) {
        $score.DriverCompat = 2
    } elseif ($unsigned.Count -lt 5) {
        $score.DriverCompat = 1
    } else {
        $score.DriverCompat = 0
    }

    foreach ($k in $score.Keys) {
        Set-CapabilityValue -Name $k -Value $score[$k]
        Log ("Capability {0}={1}" -f $k, $score[$k])
    }

    $cgCap = if ($score.SecureBoot -gt 0 -and $score.Virtualization -gt 0 -and $score.TPM -gt 0) { 2 } else { 0 }
    $hvciCap = if ($score.SecureBoot -gt 0 -and $score.Virtualization -gt 0 -and $score.UEFINX -gt 0) { 2 } else { 0 }
    $dgCap = if ($cgCap -gt 0 -and $hvciCap -gt 0) { 2 } else { 1 }

    Set-CapabilityValue -Name "CG_Capable" -Value $cgCap
    Set-CapabilityValue -Name "HVCI_Capable" -Value $hvciCap
    Set-CapabilityValue -Name "DG_Capable" -Value $dgCap
    Log "Capability summary: CG_Capable=$cgCap HVCI_Capable=$hvciCap DG_Capable=$dgCap"
}

function Invoke-ReadyChecks {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
    if ($null -eq $dg) {
        Log "ERROR: Unable to query Win32_DeviceGuard"
        return
    }

    $running = @($dg.SecurityServicesRunning)
    $isCGRunning = $running -contains 1
    $isHVCIRunning = $running -contains 2
    $isDGRunning = ($isCGRunning -and $isHVCIRunning -and $dg.CodeIntegrityPolicyEnforcementStatus -ge 1)

    Set-CapabilityValue -Name "CG_Running" -Value ($(if ($isCGRunning) { 1 } else { 0 }))
    Set-CapabilityValue -Name "HVCI_Running" -Value ($(if ($isHVCIRunning) { 1 } else { 0 }))
    Set-CapabilityValue -Name "DG_Running" -Value ($(if ($isDGRunning) { 1 } else { 0 }))

    Log "Ready check: CG_Running=$([int]$isCGRunning) HVCI_Running=$([int]$isHVCIRunning) DG_Running=$([int]$isDGRunning)"
    Log "VBS Status=$($dg.VirtualizationBasedSecurityStatus) SecurityServicesRunning=$($running -join ',') CIStatus=$($dg.CodeIntegrityPolicyEnforcementStatus)"
}

function Invoke-SecConfigFallback {
    Log "Applying SecConfig.efi fallback to clear UEFI lock (next boot)"

    $driveLetter = "X:"
    mountvol $driveLetter /s 2>&1 | Out-Null
    Copy-Item "$env:WINDIR\System32\SecConfig.efi" "$driveLetter\EFI\Microsoft\Boot\SecConfig.efi" -Force -ErrorAction SilentlyContinue

    $guid = "{0cb3b571-2f2e-4343-a879-d86a476d7215}"
    bcdedit /create $guid /d "DGOptOut" /application osloader 2>&1 | Out-Null
    bcdedit /set $guid path "\EFI\Microsoft\Boot\SecConfig.efi" 2>&1 | Out-Null
    bcdedit /set "{bootmgr}" bootsequence $guid 2>&1 | Out-Null
    bcdedit /set $guid loadoptions "DISABLE-LSA-ISO,DISABLE-VBS" 2>&1 | Out-Null
    bcdedit /set $guid device "partition=$driveLetter" 2>&1 | Out-Null
    mountvol $driveLetter /d 2>&1 | Out-Null

    Log "OK: SecConfig fallback staged for next reboot"
}

Log "Starting VBS/Hypervisor disable routine"

$isAdmin = ([Security.Principal.WindowsIdentity]::GetCurrent().Groups -match "S-1-5-32-544")
if (-not $isAdmin) {
    Log "ERROR: Not running as Administrator. Exiting."
    exit 1
}
Log "OK: Running as Administrator"

# DG parity: clear old telemetry and reset verifier each run.
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Capabilities" /f 2>&1 | Out-Null
verifier /reset 2>&1 | Out-Null
Log "OK: Cleared capabilities and reset verifier"

Invoke-CapabilityChecks

$osVersion = [System.Environment]::OSVersion.Version
Log "Windows build: $($osVersion.Build)"
if ($osVersion.Build -lt 26100) {
    Log "WARNING: Script designed for Windows 11 24H2/25H2 (build 26100+)"
}

Log "P1: CPU virtualization check"

$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuMfg = $cpu.Manufacturer
$virtFirmware = $cpu.VirtualizationFirmwareEnabled
$virtSupport = $cpu.VMMonitorModeExtensions

Log "CPU virtualization support: $virtSupport"
Log "Firmware virtualization enabled: $virtFirmware"

$isIntel = $cpuMfg -match "GenuineIntel"
$isAmd = $cpuMfg -match "AuthenticAMD"

if ($virtSupport -eq $false) {
    Log "ERROR: CPU does not support virtualization extensions"
    exit 1
}

if ($virtFirmware -eq $true) {
    Log "OK: BIOS virtualization is enabled"
} else {
    Log "WARNING: BIOS virtualization is disabled"

    if ($isIntel) {
        Write-Host "Enable Intel VT-x in BIOS (DEL/F2/F10/F12), then rerun."
    } elseif ($isAmd) {
        Write-Host "Enable AMD SVM/AMD-V in BIOS (DEL/F2/F10), then rerun."
    } else {
        Write-Host "Enable virtualization in BIOS/UEFI, then rerun."
    }

    if (-not (Confirm-Yes "Already enabled in BIOS? (y/n)")) {
        Log "Aborted: enable BIOS virtualization first"
        exit 0
    }
}

Log "P2: BitLocker check"

if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
    $bitLockerDrive = Get-BitLockerVolume -ErrorAction SilentlyContinue | Where-Object { $_.VolumeType -eq "OperatingSystem" }
    if ($bitLockerDrive -and $bitLockerDrive.ProtectionStatus -eq "On") {
        Log "WARNING: BitLocker is enabled on system drive"
        Write-Host "Suspend first: manage-bde -protectors -disable C:"
        Write-Host "Re-enable after reboot: manage-bde -protectors -enable C:"
        if (-not (Confirm-Yes "Continue anyway? (y/n)")) {
            Log "Aborted by user."
            exit 0
        }
    } else {
        Log "OK: BitLocker not enabled or already suspended"
    }
} else {
    Log "INFO: BitLocker cmdlet not available. Skipping explicit BitLocker status check."
}

Log "P3: Tamper Protection check"

if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
    $tampering = Get-MpComputerStatus -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IsTamperProtected
    if ($tampering -eq $true) {
        Log "WARNING: Windows Defender Tamper Protection is enabled"
        Write-Host "Turn off Tamper Protection in Windows Security if writes fail."
        if (-not (Confirm-Yes "Continue anyway? (y/n)")) {
            Log "Aborted by user."
            exit 0
        }
    } else {
        Log "OK: Tamper Protection disabled or not detected"
    }
} else {
    Log "INFO: Defender status cmdlet not available. Skipping explicit Tamper Protection check."
}

Log "P4: WSL2 check"

$wslListRaw = wsl --list --verbose 2>&1
$wslDists = $wslListRaw | Select-String "^\s*\*?\s*\S+\s+(Running|Stopped|Installing)\s+2\s*$"
if ($wslDists) {
    Log "WARNING: WSL2 distributions detected"
    Write-Host "WSL2 requires Hyper-V. Convert if needed: wsl --set-version <distro> 1"
    if (-not (Confirm-Yes "Continue? (y/n)")) {
        Log "Aborted by user."
        exit 0
    }
} else {
    Log "OK: No WSL2 distributions found"
}

Log "P5: Create restore point"

# DG parity: stage default SIPolicy before disable workflow.
Write-SIPolicyForParity

$regPath = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore"
$freqKey = "SystemRestorePointCreationFrequency"
$originalFreq = $null
$freqKeyExisted = $false

try {
    $freqValue = Get-ItemProperty -Path $regPath -Name $freqKey -ErrorAction SilentlyContinue
    if ($freqValue) {
        $originalFreq = $freqValue.$freqKey
        $freqKeyExisted = $true
    }

    Set-ItemProperty -Path $regPath -Name $freqKey -Value 0 -Type DWord -Force -ErrorAction Stop

    Checkpoint-Computer -Description "VBS/Hypervisor Disabler - Pre-change backup" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    Log "OK: System restore point created"
} catch {
    Log "WARNING: Could not create restore point: $_"
} finally {
    try {
        if ($freqKeyExisted -and $originalFreq -ne $null) {
            Set-ItemProperty -Path $regPath -Name $freqKey -Value $originalFreq -Type DWord -Force -ErrorAction SilentlyContinue
        } elseif (-not $freqKeyExisted) {
            Remove-ItemProperty -Path $regPath -Name $freqKey -ErrorAction SilentlyContinue
        }
    } catch {
        Log "WARNING: Could not restore original frequency: $_"
    }
}

Log "Creating pre-change registry snapshot..."
$PreBackupPaths = @(
    "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard",
    "HKLM\SYSTEM\CurrentControlSet\Control\Lsa",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageHealth",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender ExploitGuard\Exploit Protection",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device performance and health",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security"
)

foreach ($regPath in $PreBackupPaths) {
    $name = Split-Path $regPath -Leaf
    reg export $regPath "$LogDir\prechange-registry-$name-$Timestamp.reg" /y 2>&1 | Out-Null
}
Log "OK: Pre-change registry snapshot exported"

Log "P6: Registry updates"

$RegMods = @(
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Value = 0},
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "RequirePlatformSecurityFeatures"; Value = 0},
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"; Name = "LsaCfgFlags"; Value = 0},
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Value = 0},
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard"; Name = "Enabled"; Value = 0},
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\DmaGuard"; Name = "Enabled"; Value = 0},
    @{Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Value = 0}
)

foreach ($mod in $RegMods) {
    $path = $mod.Path
    $name = $mod.Name
    $value = $mod.Value
    
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    
    Set-ItemProperty -Path $path -Name $name -Value $value -Type DWord -Force -ErrorAction SilentlyContinue
}

Log "Applying policy overrides..."
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v "EnableVirtualizationBasedSecurity" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v "DeployConfigCIPolicy" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v "RequirePlatformSecurityFeatures" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v "HypervisorEnforcedCodeIntegrity" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v "LsaCfgFlags" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection" /v "DeviceEnumerationPolicy" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageHealth" /v "AllowDiskHealthModelUpdates" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device performance and health" /v "UILockdown" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security" /v "DisableClearTpmButton" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security" /v "DisableTpmFirmwareUpdateWarning" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security" /v "HideSecureBoot" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security" /v "HideTPMTroubleshooting" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security" /v "UILockdown" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender ExploitGuard\Exploit Protection" /v "ExploitProtectionSettings" /f 2>&1 | Out-Null
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender ExploitGuard\Exploit Protection" /ve /f 2>&1 | Out-Null
Log "OK: Registry modifications complete"

if (Test-Path "$env:WINDIR\System32\CodeIntegrity\SIPolicy.p7b") {
    Remove-Item "$env:WINDIR\System32\CodeIntegrity\SIPolicy.p7b" -Force -ErrorAction SilentlyContinue
    Log "OK: SIPolicy.p7b removed"
}

Log "P7: Disable Windows features"

$Features = @(
    "Microsoft-Hyper-V-All",
    "VirtualMachinePlatform",
    "HypervisorPlatform",
    "WindowsHypervisorPlatform",
    "Containers-DisposableClientVM"
)

if (-not (Test-RedstoneOrLater)) {
    $Features += "IsolatedUserMode"
}

$featureCount = 0
foreach ($feature in $Features) {
    $featureCount++
    $output = dism /online /disable-feature /featurename:$feature /norestart 2>&1
    if (-not ($output -match "successfully|not present|does not exist")) {
        Log "WARN: Feature '$feature' returned: $($output -join ' ')"
    }
}

Log "OK: Windows features disabled"

Log "P8: Disable hypervisor in BCD"

$bcdOutput = bcdedit /set hypervisorlaunchtype off 2>&1
if ($bcdOutput -match "success|successfully") {
    Log "OK: Hypervisor disabled in BCD"
} else {
    Log "WARNING: BCD command returned: $bcdOutput"
}

Log "P9: Create persistence task"

$ScriptDir = $PersistDir
if (-not (Test-Path $ScriptDir)) { New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null }

$persistScript = @'
$RegMods = @(
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Value = 0},
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "RequirePlatformSecurityFeatures"; Value = 0},
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"; Name = "LsaCfgFlags"; Value = 0},
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Value = 0},
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard"; Name = "Enabled"; Value = 0},
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\DmaGuard"; Name = "Enabled"; Value = 0}
)

foreach ($mod in $RegMods) {
    if (-not (Test-Path $mod.Path)) { New-Item -Path $mod.Path -Force | Out-Null }
    Set-ItemProperty -Path $mod.Path -Name $mod.Name -Value $mod.Value -Type DWord -Force -ErrorAction SilentlyContinue
}

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v "EnableVirtualizationBasedSecurity" /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v "DeployConfigCIPolicy" /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v "RequirePlatformSecurityFeatures" /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v "HypervisorEnforcedCodeIntegrity" /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v "LsaCfgFlags" /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection" /v "DeviceEnumerationPolicy" /t REG_DWORD /d 1 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageHealth" /v "AllowDiskHealthModelUpdates" /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device performance and health" /v "UILockdown" /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security" /v "DisableClearTpmButton" /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security" /v "DisableTpmFirmwareUpdateWarning" /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security" /v "HideSecureBoot" /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security" /v "HideTPMTroubleshooting" /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security" /v "UILockdown" /t REG_DWORD /d 0 /f | Out-Null
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender ExploitGuard\Exploit Protection" /v "ExploitProtectionSettings" /f | Out-Null
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender ExploitGuard\Exploit Protection" /ve /f | Out-Null
'@

$persistPath = "$ScriptDir\Disable-VBS-AtBoot.ps1"
Set-Content -Path $persistPath -Value $persistScript -Encoding UTF8 -Force

icacls "$ScriptDir" /inheritance:r 2>&1 | Out-Null
icacls "$ScriptDir" /grant:r "SYSTEM:(OI)(CI)(F)" "Administrators:(OI)(CI)(F)" 2>&1 | Out-Null
icacls "$persistPath" /inheritance:r 2>&1 | Out-Null
icacls "$persistPath" /grant:r "SYSTEM:(F)" "Administrators:(F)" 2>&1 | Out-Null

$TaskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$persistPath`""
$TaskTrigger = New-ScheduledTaskTrigger -AtStartup
$TaskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

try {
    Register-ScheduledTask -TaskName "Disable-VBS-Persistence" -Action $TaskAction -Trigger $TaskTrigger -Principal $TaskPrincipal -Force | Out-Null
    Log "OK: Persistence task created (will re-enforce at boot)"
} catch {
    Log "WARNING: Could not create persistence task: $_"
}

Log "P10: Backup and verification"

$BackupPaths = @(
    "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard",
    "HKLM\SYSTEM\CurrentControlSet\Control\Lsa",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageHealth",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender ExploitGuard\Exploit Protection",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device performance and health",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security"
)

foreach ($regPath in $BackupPaths) {
    $name = Split-Path $regPath -Leaf
    reg export $regPath "$LogDir\registry-backup-$name-$Timestamp.reg" /y 2>&1 | Out-Null
}
Log "OK: Registry backed up to $LogDir"

Log "Verification"
$vbsReg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -ErrorAction SilentlyContinue
if ($vbsReg.EnableVirtualizationBasedSecurity -eq 0) {
    Log "  [OK] VBS disabled in registry"
}

$policyChecks = @(
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"; Name="DeployConfigCIPolicy"; Expected=0},
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"; Name="EnableVirtualizationBasedSecurity"; Expected=0},
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection"; Name="DeviceEnumerationPolicy"; Expected=1},
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageHealth"; Name="AllowDiskHealthModelUpdates"; Expected=0},
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device performance and health"; Name="UILockdown"; Expected=0},
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security"; Name="DisableClearTpmButton"; Expected=0},
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security"; Name="DisableTpmFirmwareUpdateWarning"; Expected=0},
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security"; Name="HideSecureBoot"; Expected=0},
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security"; Name="HideTPMTroubleshooting"; Expected=0},
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security"; Name="UILockdown"; Expected=0}
)

foreach ($check in $policyChecks) {
    $current = Get-ItemProperty -Path $check.Path -Name $check.Name -ErrorAction SilentlyContinue
    if ($null -ne $current -and $current.($check.Name) -eq $check.Expected) {
        Log "  [OK] Policy $($check.Name)=$($check.Expected)"
    } else {
        Log "  [WARN] Policy $($check.Name) not at expected value ($($check.Expected))"
    }
}

$bcdCheck = bcdedit | Select-String "hypervisorlaunchtype"
if ($bcdCheck -match "off") {
    Log "  [OK] Hypervisor disabled in BCD"
}

$dgStatus = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
if ($null -ne $dgStatus) {
    Log "  DeviceGuard.VirtualizationBasedSecurityStatus: $($dgStatus.VirtualizationBasedSecurityStatus) (0=Off,1=EnabledNotRunning,2=Running)"
    if ($dgStatus.SecurityServicesRunning) {
        Log "  DeviceGuard.SecurityServicesRunning: $($dgStatus.SecurityServicesRunning -join ',')"
    } else {
        Log "  DeviceGuard.SecurityServicesRunning: none"
    }

    if ($dgStatus.VirtualizationBasedSecurityStatus -eq 0) {
        Log "  [OK] VBS runtime status is OFF"
    } else {
        Log "  [WARN] VBS is still configured/running. Policy or UEFI lock may be enforcing it."
        Log "  [INFO] If this persists after reboot, use advanced UEFI-lock removal workflow."
    }
} else {
    Log "  [INFO] Could not query Win32_DeviceGuard runtime status."
}

Invoke-ReadyChecks

if ($dgStatus -and $dgStatus.VirtualizationBasedSecurityStatus -ne 0) {
    Log "Staging SecConfig fallback automatically"
    Invoke-SecConfigFallback
}

Log "=========================================="
Log "Changes complete. Reboot required."
Log "=========================================="

if ($SkipReboot) {
    Log "Reboot skipped. Run: Restart-Computer -Force"
} else {
    Log "Rebooting in 30 seconds. Press Ctrl+C to cancel..."
    for ($i = 30; $i -gt 0; $i--) {
        Write-Host "`rRebooting in $i seconds... (Ctrl+C to cancel)  " -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
    Write-Host ""
    Log "Rebooting..."
    Restart-Computer -Force
}
