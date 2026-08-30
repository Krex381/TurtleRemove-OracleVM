# Changelog

## 2026.08.30

- Replaced the former dual boot-profile design with one permanently enforced `PermanentDisable` strategy and removed the Hyper-V fallback profile.
- Integrated Microsoft's signed Device Guard and Credential Guard Hardware Readiness Tool v3.6 with pinned ZIP and internal-file hashes.
- Added official UEFI-lock disable staging, VBS/HVCI/Credential Guard/System Guard policy coverage, both BCD launch controls and expanded optional-feature removal.
- Restored the requested Defender UI, Kernel DMA, Storage Health, Exploit Protection, Driver Verifier reset and Device Guard capability mechanisms.
- Added hash-addressed SIPolicy quarantine, startup SYSTEM enforcement and strict post-reboot verification.
- Expanded schema-v2 backup and restore to cover the complete BCD store, every managed registry value, optional features, SIPolicy, capability telemetry and task collision recovery.
- Added automatic managed-state rollback when a fix step fails.
- Hardened installer pinning, ACLs and untrusted backup validation.
- Added PowerShell 7 and Windows PowerShell 5.1 static/unit/JSON smoke coverage.
