# Security model

TurtleFix intentionally disables Windows security and virtualization features. Treat `Fix` as a high-impact host reconfiguration, not as a cosmetic VirtualBox tweak.

## Trust boundaries

- Mutation actions require an elevated local administrator; startup enforcement runs as `SYSTEM`.
- `Fix` uses a closed registry and optional-feature allowlist. Backup restore rejects unmanaged registry entries, duplicate entries, invalid boot identifiers, unexpected schema/strategy values and file paths outside the selected backup directory.
- The official Microsoft readiness ZIP is downloaded only from a fixed `download.microsoft.com` URL. The ZIP and required internal files are pinned by SHA-256, and the script must have a valid Microsoft Corporation Authenticode signature immediately before execution.
- The remote installer has a separate pinned hash for `TurtleFix.ps1` and refuses mismatches.
- State, cached tools, logs and SIPolicy quarantine are ACL-restricted to Administrators and SYSTEM.
- New classic SIPolicies discovered by enforcement are copied to hash-addressed quarantine before removal.

## Recovery

Before mutation, TurtleFix exports BCD and snapshots all managed registry values, optional features, the active classic SIPolicy, Device Guard capabilities and a pre-existing enforcement task. Restore accepts only schema v2 `PermanentDisable` state and checks required artifacts before the first write.

BitLocker is suspended for one reboot by default. Keep the recovery key available because BCD and UEFI security-state changes can still trigger recovery.

Driver Verifier reset is not fully reversible: Windows does not provide a dependable export/import of every verifier configuration. The state records that the reset occurred.

## Security trade-off

The permanent configuration disables VBS, HVCI/Memory Integrity, Credential Guard, Secure Launch, Hyper-V, Application Guard and other hypervisor-backed defenses. It also clears a centrally supplied classic Exploit Protection XML policy and classic SIPolicy. Use TurtleFix only on a host where native VirtualBox performance is more important than those protections and workloads.

Report suspected command injection, restore path traversal, signature bypass, hash bypass, ACL weakness or unsafe rollback behavior privately to the repository owner before public disclosure.
