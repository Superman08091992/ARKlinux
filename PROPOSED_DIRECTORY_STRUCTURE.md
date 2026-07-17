# Proposed canonical portfolio structure

Repository ownership remains separated where it materially improves OS/runtime provenance. A release manifest pins all repositories and assembles one installable system.

```text
ARKlinux/
  archiso/                 # live and installer image profile
  installer/               # disposable-safe installer and verification
  packages/                # PKGBUILDs for host/runtime integration
  systemd/                 # host unit sources, sysusers, tmpfiles, presets
  nftables/                # default-deny policy
  tests/qemu/              # live boot, install, reboot acceptance
  scripts/                 # canonical build/checksum/test entrypoints
  provenance/              # release source manifests, never active code
  legacy/                  # preserved obsolete host components

ARK_GENESIS/
  runtime/                 # orchestrator, schemas and API
  services/                # bus, memory, evidence, policy, models, hardware
  agents/                  # Kyle, Aletheia, Joey, HRM, Kenny contracts
  domains/trading/         # Tradeanalyzer after mock isolation
  ui/operator-console/     # observed state only
  policy/                  # deny-by-default policy and version manifest
  tests/                   # contract, bypass, approval and tamper tests
  provenance/archives/     # original immutable archives
  legacy/                  # extracted historical source, never imported at runtime

release/
  components.lock          # repository URL + immutable commit + content hash
  packages.lock            # exact packages
  source-map.tsv           # origin/current path/status/hash
  acceptance/              # commands, logs, results and known limitations
```

Installed paths follow the requested operational contract under `/etc/ark`, `/opt/ark`, `/var/lib/ark`, `/run/ark`, and `/var/log/ark`. Any `/ark` canonical-namespace experiment must be reconciled explicitly rather than creating two authoritative roots.

