# 2026 codebase audit

## Scope

The complete PowerShell surface was reviewed: core actions, compatibility wrapper, installer, registry and BCD mutations, optional features, Microsoft readiness integration, persistence, backup/restore, documentation and tests.

## Findings and disposition

| Severity | Legacy/current issue | 2026 disposition |
|---|---|---|
| Critical | Security-sensitive writes had no trustworthy complete rollback. | Schema-v2 snapshots every managed value and feature plus SIPolicy, capabilities, BCD and task state; restore is allowlisted and path constrained. |
| Critical | Precompiled policy files lacked runtime provenance. | Nothing is vendored. The official Microsoft v3.6 ZIP, internal files and Authenticode publisher are verified before execution. |
| High | Hyper-V could return through default BCD state, VBS defaults, Windows features or servicing drift. | Both BCD controls are explicitly Off, all relevant policy/runtime surfaces and features are disabled, and a SYSTEM startup task enforces the state. |
| High | A fallback boot profile contradicted permanent removal. | Boot-profile creation and cleanup logic were deleted. There is no Hyper-V-enable fallback. |
| High | Credential Guard with UEFI lock cannot be disabled by ordinary registry writes. | The official readiness tool's `-Disable` path stages `SecConfig.efi` and the documented physical-presence flow. Explicit zero values are applied afterward. |
| High | Blind SIPolicy deletion could destroy later administrator policy. | Every subsequently detected classic SIPolicy is copied to SHA-256-addressed quarantine before removal. |
| Medium | Defender UI, DMA, Storage Health and Exploit Protection settings were previously described as turtle causes. | They are restored for requested compatibility but clearly labeled as independent policy mutations, backed up and verified separately. |
| Medium | Device Guard capability values were discarded as meaningless. | The official tool confirms the capability key is part of its supported surface. TurtleFix now writes hardware-derived 0/1/2 values without enabling Driver Verifier. |
| Medium | Driver Verifier state could remain enabled after readiness testing. | TurtleFix resets it before capability evaluation and records the irreversible reset in state. |
| Medium | Remote install could execute mutable content. | Remote core content is release-hash pinned; Microsoft tooling is independently URL/hash/publisher pinned. |
| Low | Diagnostics could overclaim success when CIM/BCD queries were denied. | Unknown stays unknown, Verify requires elevation and uses all independent runtime/configuration checks. |

## Mutation map

```text
Fix
  -> diagnose and block running VMs
  -> backup and validate recovery artifacts
  -> BitLocker one-reboot suspension
  -> reset verifier and compute capabilities
  -> validate/run Microsoft Device Guard -Disable
  -> apply registry + optional-feature + BCD permanent policy
  -> install SYSTEM enforcement + one-shot verifier
  -> reboot

Persistent enforcement (startup, logon and daily)
  -> reapply registry deletion/value allowlists
  -> quarantine/remove classic SIPolicy
  -> disable reintroduced features
  -> force hypervisorlaunchtype/vsmlaunchtype Off

Restore
  -> validate schema, allowlists and local artifact paths
  -> remove TurtleFix enforcement
  -> restore the complete BCD store and exact registry/feature/SIPolicy/capability/task state
  -> reboot
```

## Remaining validation boundary

Parser, static, unit and non-mutating diagnostic tests can run in the repository. End-to-end proof of firmware confirmation, reboot behavior and the disappearance of the VirtualBox turtle requires a disposable elevated Windows host with VirtualBox. Those host mutations are intentionally not performed by the repository test suite.
