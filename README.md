# ARKLinux — Individual Operator Edition

> A hardened, self-governing Arch Linux–based OS built as the native substrate
> for the **A.R.K.** (Autonomous Reasoning Kernel) platform.

[![Build](https://github.com/Superman08091992/ARKlinux/actions/workflows/build-release.yml/badge.svg)](https://github.com/Superman08091992/ARKlinux/actions/workflows/build-release.yml)

---

## Download

| File | Description |
|------|-------------|
| [`arklinux-1.0.1-x86_64.iso`](https://github.com/Superman08091992/ARKlinux/releases/latest) | Bootable ISO — BIOS + UEFI |
| `SHA256SUMS` | Checksums |
| `SHA256SUMS.sigstore.json` | Cosign / Sigstore signature |
| `arklinux-1.0.1.sbom.spdx.json` | Software Bill of Materials |
| `provenance.json` | SLSA-style build provenance |

**Verify before use:**

```bash
# Checksum
sha256sum -c SHA256SUMS

# Cosign signature
cosign verify-blob \
  --bundle SHA256SUMS.sigstore.json \
  --certificate-identity-regexp "https://github.com/Superman08091992/ARKlinux" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  SHA256SUMS
```

Full verification guide → [docs/BUILDING.md](docs/BUILDING.md#verifying-a-published-release)

---

## Install

Boot the ISO, then:

```bash
ark-install /dev/sdX --confirm
```

Creates BTRFS subvolumes `@` `@home` `@log` `@snapshots` `@opt_ark`,
installs **systemd-boot**, and generates `/etc/fstab`.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  ARKLinux (host OS — Arch Linux base, kernel 6.18.9)        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  nftables — default-deny, loopback-only             │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  /opt/ark (canonical state root, ark:ark 750)       │    │
│  │  ├── models/     ingest/    bus/    memory/          │    │
│  │  ├── logs/       agents/    run/    backup/          │    │
│  │  ├── secrets/    id/        quarantine/ (700)        │    │
│  │  └── aletheia/  ─►  audit/  manifests/ (immutable)  │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌────────────────────┐  ┌──────────────────────────────┐   │
│  │  ark-core.service  │  │  ark-watchdog.service        │   │
│  │  (Python, ark uid) │  │  SHA-256 aletheia tree/60 s  │   │
│  │  heartbeat + state │  │  → quarantine on violation   │   │
│  └────────────────────┘  └──────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Build (reproducible)

```bash
git clone https://github.com/Superman08091992/ARKlinux.git
cd ARKlinux
docker build -t arklinux-builder build/docker/
docker run --privileged \
  -v "$(pwd)":/src -v /tmp/out:/out \
  arklinux-builder
```

All packages are pinned to the **Arch Linux Archive snapshot 2026-02-01**.
CI (GitHub Actions) is the **only path** to an official signed release.

→ [docs/BUILDING.md](docs/BUILDING.md) — full build, verify, and reproduce guide.

---

## Supply chain

| Layer | Tool / mechanism |
|-------|-----------------|
| Build environment | `archlinux:base` container, pinned Arch Archive snapshot |
| Package lock | `build/lock/packages.lock` (regenerate: `./build/scripts/pin-packages.sh`) |
| Static analysis | ShellCheck (all bash scripts), Python `py_compile` |
| nftables validation | `nft -c -f` in CI |
| Artifact signing | cosign keyless (Sigstore OIDC via GitHub Actions) |
| SBOM | Syft → SPDX JSON |
| Provenance | SLSA-style `provenance.json` + GitHub artifact attestation |
| Official release | CI tag push only — no local one-off builds |

---

## Security profile

| Feature | Implementation |
|---------|---------------|
| Firewall | nftables `policy drop` on all chains, loopback-only |
| Service isolation | `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `CapabilityBoundingSet=` |
| Non-root services | `ark` system user (UID 973), no login shell |
| Fail-closed quarantine | watchdog exit-2 → `ark-quarantine.target` → stops all ARK services |
| Evidence integrity | SHA-256 hash of aletheia tree every 60 s |
| Egress control | `IPAddressDeny=any` per service unit |

---

## Repository layout

```
archiso/                    ← mkarchiso profile (THE authoritative build input)
│  profiledef.sh            ← ISO metadata and file permissions
│  packages.x86_64          ← Pinned package list
│  pacman.conf              ← Arch Archive snapshot mirror
│  airootfs/
│    etc/
│      customize_airootfs.sh ← User creation, service enablement, assertions
│      mkinitcpio.conf       ← archiso live-boot hooks
│      nftables.conf         ← Default-deny firewall
│      systemd/system/       ← ark-core, ark-watchdog, ark-quarantine, ark.target
│    usr/local/bin/
│      ark-install           ← BTRFS + systemd-boot installer
│      ark-core              ← Core agent (Python)
│      ark-watchdog          ← Integrity watchdog (Python)
│      ark-verify-perms      ← Permission auditor
│  efiboot/loader/           ← systemd-boot entries (UEFI)
│  syslinux/                 ← syslinux config (BIOS)
.github/workflows/
│  build-release.yml        ← CI: lint → build → SBOM → sign → release
build/
│  docker/Dockerfile        ← Reproducible build container
│  scripts/pin-packages.sh  ← Regenerate packages.lock
│  lock/packages.lock       ← Exact package versions (generated)
docs/
│  BUILDING.md              ← One-command build, verify, reproduce
```

---

## Related repositories

- [`Superman08091992/ark`](https://github.com/Superman08091992/ark) — ARK agent runtime
- [`Superman08091992/ARK_GENESIS`](https://github.com/Superman08091992/ARK_GENESIS) — origin specification
