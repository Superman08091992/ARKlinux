# Architecture gap analysis

## Executive finding

No inspected repository currently proves the requested end-to-end acceptance path. ARKlinux has a plausible ArchISO profile and destructive installer, while ARK_GENESIS has a real Python runtime base mixed with stubs and legacy mock applications. These are useful inputs, not a finished system.

## Baseline gaps

| Area | Implemented evidence | Gap / risk | Required closure |
|---|---|---|---|
| ISO build | ArchISO profile and container builder exist | No current-commit ISO artifact or complete build log; Docker command in documentation uses the wrong build context | One canonical build script; CI build artifact, full log, SHA-256 |
| QEMU live boot | BIOS and UEFI entries exist | No automated QEMU test or console proof | TCG-safe serial boot test with explicit success marker |
| Installer | Explicit device argument, confirmation, GPT, Btrfs, systemd-boot logic exist | Destructive; `--confirm` is too weak for unattended use; sleeps instead of device settlement; no QEMU installation proof | Require disposable-disk attestation; use `udevadm settle`; test only against generated qcow2/raw disk |
| Installed boot | systemd-boot copy logic exists | initramfs is rebuilt after it is copied to ESP; copied ESP image may be stale; no reboot proof | Reorder rebuild/copy, verify loader entry, reboot test |
| Btrfs | Subvolume logic exists | Legacy and canonical layouts conflict (`@opt_ark` versus `/ark` facets) | One documented installed layout with migration compatibility only |
| Services | Legacy `ark-core`/watchdog and partial canonical layout units exist | Required service boundary is not implemented; customization script is not reliable as an ArchISO execution hook | Package real units and sysusers/tmpfiles definitions; test every required unit |
| Firewall | nftables source exists | Loaded state is not proven after installed reboot; SSH is enabled despite local-first/default-deny intent | Boot-time `nft list ruleset` assertion and explicit network policy |
| Runtime API | Current FastAPI route surface exists in ARK_GENESIS | Several routes are stubs; responses lack mandatory envelope fields; `/evidence/write` creates replaceable files | Typed schemas, structured `not_implemented`, append-only evidence, policy middleware |
| Pipeline | Runtime contracts and tests exist | Current API does not enforce Kyle → Aletheia → Joey → HRM → Kenny stage tokens | Correlation-scoped stage ledger with bypass rejection tests |
| Policy | Dry-run defaults and broker mediation exist | Legacy console hard-codes `allowed:true`; execution endpoint returns HTTP success-shaped payload | Default deny, explicit rejection status, authenticated human-approval record |
| Evidence | JSONL bus and evidence writer components exist | API evidence is timestamp-file mutable; policy/evidence integrity not proven | Hash-chained append-only records plus startup verification |
| Model routing | Ollama references exist | Runtime service currently wants Ollama/Valkey; offline start and graceful unavailable state are not proven | Local router service with optional model backends and no cloud startup dependency |
| Provenance | Combined manifest and checksum document exist | Original archives are not available in this checkout; hashes cannot be independently recomputed | Import archives under provenance storage and verify on CI |
| Naming/authority | Canonical ARK spec exists | It assigns broad “software governance” language that conflicts with DREAMER’s no-governance-over-people boundary unless carefully scoped | Define authority exclusively over software/resources; prohibit decisions over human status, punishment, housing, work, morality |

## Milestone gate

This PR addresses only ISO construction and live QEMU boot observability. Installer, installed reboot, runtime, and agent-pipeline claims remain explicitly incomplete.

