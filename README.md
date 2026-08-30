# TurtleFix 2026

TurtleFix permanently removes the Microsoft hypervisor path that makes Oracle VirtualBox show the green turtle and run through Windows' Hyper-V compatibility layer. It is designed for Windows 11 and Windows 10 hosts that should always run VirtualBox directly on VT-x/AMD-V.

There is one strategy: `PermanentDisable`. TurtleFix does not create a Hyper-V fallback boot entry.

## What the fix automates

`Fix` performs one recoverable, logged workflow and automatically attempts rollback if application fails:

1. Detects Windows, VirtualBox, running VMs, Hyper-V/VBS, optional features, WSL, Docker and BitLocker.
2. Exports BCD and snapshots every managed registry value, optional feature, active `SIPolicy.p7b`, Device Guard capability key and pre-existing enforcement task.
3. Suspends BitLocker for one restart when protection is active.
4. Resets Driver Verifier and calculates Device Guard capability telemetry without turning verifier back on.
5. Downloads Microsoft Device Guard and Credential Guard Hardware Readiness Tool v3.6 from Microsoft, checks the pinned ZIP and file SHA-256 hashes, and requires a valid Microsoft Authenticode signature.
6. Stages Microsoft's audit SIPolicy and invokes the official tool's `-Disable` workflow, including its UEFI-lock removal boot sequence when applicable.
7. Explicitly disables VBS, HVCI, Credential Guard, DMA Guard, System Guard Secure Launch and machine-identity isolation at both runtime and policy registry surfaces.
8. Disables the Hyper-V hypervisor, Windows Hypervisor Platform, Virtual Machine Platform, Sandbox, Application Guard and Isolated User Mode features when present.
9. Sets both `hypervisorlaunchtype off` and `vsmlaunchtype off` for the current boot entry.
10. Restores the legacy Defender UI, Kernel DMA, Storage Health and Exploit Protection policy mutations requested for parity.
11. Installs a highest-privilege SYSTEM task that idempotently reapplies the permanent configuration and capability telemetry at startup, logon and daily after Windows servicing or policy drift.
12. Installs a one-shot post-reboot verification task and writes a machine-readable report.

The DMA, Storage Health and Defender UI policies are not themselves causes of the VirtualBox turtle. They are included as an explicit compatibility bundle and are independently backed up and restored.

## Run

Open PowerShell in this directory:

```powershell
.\TurtleFix.ps1 -Action Diagnose
.\TurtleFix.ps1 -Action Fix
```

Interactive `Fix` requires the exact confirmation `PERMANENT-DISABLE`. For managed execution:

```powershell
.\TurtleFix.ps1 -Action Fix -NonInteractive -Force
```

Stage everything without restarting immediately:

```powershell
.\TurtleFix.ps1 -Action Fix -SkipReboot
```

Preview the outer transaction without writing:

```powershell
.\TurtleFix.ps1 -Action Fix -WhatIf
```

After the reboot and any firmware confirmation screen:

```powershell
.\TurtleFix.ps1 -Action Verify
```

`Verify` succeeds only when Hyper-V and VBS are stopped, both BCD launch controls are `Off`, all managed optional features are disabled, every registry policy and Device Guard capability value is present, the classic SIPolicy is absent and the permanent SYSTEM task exists.

## Install

Run the installer from an elevated or normal PowerShell; it self-elevates and uses the local `TurtleFix.ps1` when both files are together:

```powershell
.\install.ps1
```

Remote installation downloads a release-pinned `TurtleFix.ps1` and refuses to execute it unless its SHA-256 matches `install.ps1`.

### One-line install and run

Paste this single line into PowerShell. It downloads the installer to a unique temporary file, verifies the installer SHA-256, runs it through Windows PowerShell with automatic UAC elevation, and removes the temporary file afterward:

```powershell
$u='https://raw.githubusercontent.com/Krex381/TurtleRemove-OracleVM/main/install.ps1';$p=Join-Path $env:TEMP ('TurtleFix-install-{0}.ps1' -f [guid]::NewGuid().ToString('N'));try{Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $p;if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne '99208C618C038025E353718F7F3DA6CCBC59E55B3F4D0F6DF6A018F3C3B1510F'){throw 'Installer SHA-256 mismatch'};& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p;if($LASTEXITCODE -ne 0){throw "Installer failed with exit code $LASTEXITCODE"}}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

The interactive safety confirmation still requires `PERMANENT-DISABLE`, and the installer asks before restarting Windows.

## Restore

Every `Fix` creates a versioned backup under `C:\ProgramData\TurtleFix\backups` and records the latest path. Restore removes TurtleFix enforcement, restores the complete pre-fix BCD store, every managed registry value and optional feature, the original SIPolicy, Device Guard capabilities and any task that previously occupied the TurtleFix task name:

```powershell
.\TurtleFix.ps1 -Action Restore
```

Or select a specific state file:

```powershell
.\TurtleFix.ps1 -Action Restore -BackupPath 'C:\ProgramData\TurtleFix\backups\...\state.json'
```

Driver Verifier is deliberately reset before the fix. Windows does not expose a reliable complete round-trip export of arbitrary verifier configuration, so that one operation is recorded but not reconstructed by `Restore`.

If a later policy recreates the classic `SIPolicy.p7b`, enforcement preserves a hash-named copy under `C:\ProgramData\TurtleFix\quarantine\sipolicy` before removing it.

## Impact

Permanent disable intentionally breaks or disables workloads that require the Microsoft hypervisor, including WSL 2, Windows Sandbox, Application Guard, Hyper-V VMs and the Hyper-V backend of Docker Desktop. WSL 1 and VirtualBox's native engine do not require Hyper-V.

The diagnosis currently treats Oracle VirtualBox 7.2.16 as the August 2026 baseline and recommends an update for older detected builds.

The official Device Guard tool may stage a pre-OS confirmation to clear Credential Guard or VBS UEFI locks. Accept the displayed disable request locally. BitLocker recovery material should always be available before boot configuration changes.

## Provenance

- Microsoft Device Guard and Credential Guard hardware readiness tool v3.6: `dgreadiness_v3.6.zip`
- Download SHA-256: `B351BE8E77C8D7994D97B8B9E60EF310EA5873A336FB8D3B5B009379F29BC6FC`
- Readiness script SHA-256: `C248C7EECF637E9CFEC4353B55336542A1AC13FBB5E58EBD622E4717CFFC09C7`
- Audit SIPolicy SHA-256: `40B975DA6D6745FFD735C8D0D9644311B099E3458AA07823F505DA109582A13A`
- Enforced SIPolicy SHA-256: `5835059E0FED0F7DBE7AD482A5033E3726586366D9B27D908B6670AB116D7C0C`

The repository does not vendor those binaries. TurtleFix retrieves them from the pinned Microsoft URL and validates them before use.

## Validation

Both PowerShell 7 and Windows PowerShell 5.1 are supported. The test suite parses all scripts, checks the permanent-disable surface and installer hash, validates backup allowlists and rejects unsafe restore paths:

```powershell
pwsh -NoProfile -File .\tests\Test-Unit.ps1
pwsh -NoProfile -File .\tests\Test-Static.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Unit.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Static.ps1
```

Real application and post-reboot verification must be performed on an expendable Windows test host because the fix intentionally changes boot and security configuration.

## Primary references

- [Oracle VirtualBox 7.2 manual: using Hyper-V on a Windows host](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/AdvancedTopics.html)
- [Oracle VirtualBox 7.2.16 official download directory](https://download.virtualbox.org/virtualbox/7.2.16/)
- [Microsoft Device Guard readiness tool download](https://www.microsoft.com/en-us/download/details.aspx?id=53337)
- [Microsoft Credential Guard configuration and UEFI-lock removal](https://learn.microsoft.com/en-us/windows/security/identity-protection/credential-guard/configure)
- [Microsoft BCDEdit `/set` options](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--set)
- [Microsoft DeviceGuard Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deviceguard)
- [Microsoft DMA Guard Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-dmaguard)
- [Microsoft Storage Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-storage)
- [Microsoft Windows Defender Security Center Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsdefendersecuritycenter)
- [Microsoft Exploit Guard Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-exploitguard)
