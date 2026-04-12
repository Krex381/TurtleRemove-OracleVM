# Schildkrote-Fix (VirtualBox Turtle Fix)

A one-command PowerShell script for Windows 11 that removes the VirtualBox "green turtle" bottleneck by disabling conflicting Hyper-V / VBS layers.

The goal is simple: get VirtualBox back to native VT-x/AMD-V performance.

## What It Does

- Disables VBS, HVCI, and Credential Guard related registry settings
- Disables Hyper-V related optional features that conflict with VirtualBox
- Sets `hypervisorlaunchtype off` via `bcdedit`
- Stages a `SecConfig.efi` fallback automatically if UEFI lock is still enforcing VBS
- Writes capability/runtime telemetry and detailed logs
- Creates a startup persistence task so Windows updates do not silently re-enable settings

## Target Outcome

- No green turtle icon in VirtualBox
- `HypervisorPresent = False`
- `VirtualizationBasedSecurityStatus = 0`

## Requirements

- Windows 11 (24H2/25H2 recommended)
- BIOS/UEFI virtualization enabled
- Run from an elevated (Administrator) PowerShell session

## Usage

Only one parameter is supported:

```powershell
.\Disable-VirtualBoxTurtle-Full.ps1
.\Disable-VirtualBoxTurtle-Full.ps1 -SkipReboot
```

- No parameter: runs everything and reboots automatically
- `-SkipReboot`: runs everything but leaves reboot to you

## Verification (After Reboot)

```powershell
Get-ComputerInfo | Select-Object HypervisorPresent
Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard |
  Select-Object VirtualizationBasedSecurityStatus, SecurityServicesRunning
```

Expected:

- `HypervisorPresent` -> `False`
- `VirtualizationBasedSecurityStatus` -> `0`

## About the F3 / Firmware Prompt

On some systems, Credential Guard can be protected by UEFI lock.
If that happens, the script stages a `SecConfig.efi` one-time boot fallback.
If a firmware confirmation screen appears on next boot (F3/F-key prompt), approve it.

## Logs

- Main folder: `C:\SchildkroteFix`
- Each run creates a timestamped log file

## Known Side Effects

- Some Hyper-V-based features may stop working (for example WSL2/HVCI scenarios)
- Managed devices (Intune/GPO) can re-apply enterprise policies
- On BitLocker systems, suspending protectors before changes is safer

## Safety Note

This script changes security-related system configuration.
It is intended for personal/lab devices where VirtualBox performance is the priority.
For corporate devices, validate policy compliance first.

## Why This Repo?

Because this should be one clean action, not 30 manual commands.
