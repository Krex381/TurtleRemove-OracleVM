# Schildkrote-Fix (VirtualBox Turtle Fix)

A one-command PowerShell script for Windows 11 that removes the VirtualBox "green turtle" bottleneck by disabling conflicting Hyper-V / VBS layers.

The goal is simple: get VirtualBox back to native VT-x/AMD-V performance.

## What It Does

- Disables VBS, HVCI, and Credential Guard related registry settings
- Disables Hyper-V related optional features that conflict with VirtualBox
- Sets `hypervisorlaunchtype off` via `bcdedit`
- Stages a `SecConfig.efi` fallback only after explicit `YES` confirmation if UEFI lock is still enforcing VBS
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

## One-Liner Install (IEX)

Run directly from GitHub Raw:

```powershell
iwr -useb https://raw.githubusercontent.com/Krex381/TurtleRemove-OracleVM/main/install.ps1 | iex
```

Optional no-reboot mode via environment variable:

```powershell
$env:SCHILDKROTE_SKIP_REBOOT='1'; iwr -useb https://raw.githubusercontent.com/Krex381/TurtleRemove-OracleVM/main/install.ps1 | iex
```

If present in the repo root, the installer also downloads:

- `DefaultWindows_Audit_sipolicy.p7b`
- `DefaultWindows_Enforced_sipolicy.p7b`

These files are optional; install continues if they are missing.

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

Before staging this fallback, the script now:

- Exports a BCD backup to the log folder
- Asks for explicit `YES` confirmation
- Registers a one-time startup cleanup task to remove the DGOptOut boot entry

## Recovery (If Boot Gets Stuck / Black Screen)

If the machine does not boot normally after firmware/security changes:

1. Enter WinRE (Advanced Startup) and open Command Prompt.
2. Restore BCD from backup (replace file name with your latest backup):

```cmd
bcdedit /import C:\SchildkroteFix\bcd-backup-YYYYMMDD_HHMMSS.bcd
```

3. Remove temporary DGOptOut entry (safe even if missing):

```cmd
bcdedit /delete {0cb3b571-2f2e-4343-a879-d86a476d7215} /f
bcdedit /bootsequence {0cb3b571-2f2e-4343-a879-d86a476d7215} /remove
```

4. Reboot.
5. If still stuck, temporarily revert recent BIOS security toggles (Secure Boot / virtualization options), then boot and retry with logs.

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
