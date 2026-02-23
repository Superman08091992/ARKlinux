# Building ARKLinux

This document describes how to produce a **bit-for-bit reproducible** ARKLinux ISO
and how to verify any published release artifact end-to-end.

---

## Quick start (one command)

```bash
git clone https://github.com/Superman08091992/ARKlinux.git
cd ARKlinux
docker build -t arklinux-builder build/docker/
docker run --privileged \
  -v "$(pwd)":/src \
  -v /tmp/arkout:/out \
  arklinux-builder
# ISO, SHA256SUMS and packages.lock appear in /tmp/arkout/
```

> **`--privileged` is required** — `mkarchiso` creates loop devices and bind-mounts
> inside the container when building the SquashFS image.

---

## Prerequisites

| Tool | Minimum version | Purpose |
|------|-----------------|---------|
| Docker | 24.x | Reproducible build environment |
| `cosign` | 2.x | Verify release signatures |
| `sha256sum` | any | Verify checksums |
| `syft` | 1.x | Inspect SBOM (optional) |

Install cosign:
```bash
brew install cosign          # macOS
sudo apt install cosign      # Debian/Ubuntu (if packaged)
# or: https://github.com/sigstore/cosign/releases
```

---

## Snapshot pinning strategy

ARKLinux uses the **Arch Linux Archive** to pin all packages to a specific date,
making builds fully reproducible regardless of Arch's rolling-release cadence.

The snapshot date is set in **two places** — keep them in sync:

| File | Setting |
|------|---------|
| `archiso/pacman.conf` | `Server = https://archive.archlinux.org/repos/YYYY/MM/DD/...` |
| `.github/workflows/build-release.yml` | `ARCH_SNAPSHOT: "YYYY/MM/DD"` |

**Current snapshot:** `2026/02/01` (Kernel 6.18.9-arch1-2)

### To advance the snapshot:

```bash
# 1. Choose a new date
NEW_DATE="2026/06/01"

# 2. Regenerate the package lock
./build/scripts/pin-packages.sh "$NEW_DATE"

# 3. Update both references
sed -i "s|2026/02/01|${NEW_DATE}|g" archiso/pacman.conf
sed -i "s|ARCH_SNAPSHOT: \"2026/02/01\"|ARCH_SNAPSHOT: \"${NEW_DATE}\"|g" \
  .github/workflows/build-release.yml

# 4. Commit all three files together
git add archiso/pacman.conf .github/workflows/build-release.yml build/lock/packages.lock
git commit -m "chore: advance Arch snapshot to ${NEW_DATE}"
```

---

## CI is the only official release path

**No local builds are published as official releases.**

The GitHub Actions workflow (`.github/workflows/build-release.yml`) is the
sole path to a signed, attested release artifact. This ensures:

- Every release has a verifiable build provenance tied to a specific commit.
- Signatures are issued by GitHub's OIDC identity, not a personal key.
- The SBOM and provenance are always generated from the same build that
  produced the ISO.

To trigger a release:
```bash
git tag v1.0.2
git push origin v1.0.2
# CI runs automatically; release appears at:
# https://github.com/Superman08091992/ARKlinux/releases/tag/v1.0.2
```

---

## Verifying a published release

### 1 — Checksum

```bash
VERSION="v1.0.1"
BASE="https://github.com/Superman08091992/ARKlinux/releases/download/${VERSION}"

curl -LO "${BASE}/arklinux-1.0.1-x86_64.iso"
curl -LO "${BASE}/SHA256SUMS"

sha256sum -c SHA256SUMS
# Expected: arklinux-1.0.1-x86_64.iso: OK
```

### 2 — Cosign signature (Sigstore keyless)

```bash
curl -LO "${BASE}/SHA256SUMS.sigstore.json"

cosign verify-blob \
  --bundle SHA256SUMS.sigstore.json \
  --certificate-identity-regexp "https://github.com/Superman08091992/ARKlinux" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  SHA256SUMS
# Output: Verified OK
```

### 3 — ISO sigstore bundle

```bash
curl -LO "${BASE}/arklinux-1.0.1-x86_64.iso.sigstore.json"

cosign verify-blob \
  --bundle arklinux-1.0.1-x86_64.iso.sigstore.json \
  --certificate-identity-regexp "https://github.com/Superman08091992/ARKlinux" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  arklinux-1.0.1-x86_64.iso
```

### 4 — SLSA provenance

```bash
curl -LO "${BASE}/provenance.json"
cat provenance.json | python3 -m json.tool
# Inspect builder.id → should reference the GitHub Actions run URL
# Inspect invocation.configSource.digest → should match the git commit SHA
```

### 5 — SBOM inspection

```bash
curl -LO "${BASE}/arklinux-1.0.1.sbom.spdx.json"
# View with syft:
syft convert arklinux-1.0.1.sbom.spdx.json -o table
# or with grep:
jq '.packages[].name' arklinux-1.0.1.sbom.spdx.json
```

---

## Reproducing the exact published SHA256

A third party can reproduce the published ISO hash by:

1. Checking out the **exact commit** referenced in `provenance.json`
2. Using the **same snapshot date** (`ARCH_SNAPSHOT` in the workflow)
3. Building with the **same Docker image** (`archlinux:base@sha256:<pinned>`)

```bash
# Get the commit SHA from provenance.json
COMMIT=$(jq -r '.invocation.configSource.digest.sha1' provenance.json)

git clone https://github.com/Superman08091992/ARKlinux.git
cd ARKlinux
git checkout "$COMMIT"

docker build -t arklinux-builder build/docker/
docker run --privileged \
  -v "$(pwd)":/src \
  -v /tmp/repro:/out \
  arklinux-builder

# Compare
sha256sum /tmp/repro/*.iso
# Should match SHA256SUMS from the release
```

> **Note on full bit-for-bit reproducibility:** The build is reproducible at the
> package-version level (all packages pinned to the Arch Archive snapshot).
> Timestamps embedded by `mkarchiso` and `mksquashfs` may differ between runs.
> Full timestamp-neutralised reproducibility requires `SOURCE_DATE_EPOCH` support
> in `mkarchiso` — tracked in [issue #1](https://github.com/Superman08091992/ARKlinux/issues/new).

---

## Profile structure

```
archiso/
├── profiledef.sh               ← ISO metadata, build modes, file permissions
├── packages.x86_64             ← Package list (one package per line, with comments)
├── pacman.conf                 ← Pinned Arch Archive mirror
├── airootfs/
│   ├── etc/
│   │   ├── customize_airootfs.sh   ← Post-install hook (users, permissions, services)
│   │   ├── mkinitcpio.conf         ← Hooks: base udev archiso (live boot)
│   │   ├── os-release              ← ARKLinux identity
│   │   ├── hostname
│   │   ├── locale.conf / locale.gen
│   │   ├── fstab                   ← tmpfs entries (real fstab from genfstab)
│   │   ├── nftables.conf           ← Default-deny firewall
│   │   ├── ark/config.toml         ← ARK runtime config
│   │   └── systemd/system/
│   │       ├── ark-core.service
│   │       ├── ark-watchdog.service
│   │       ├── ark-quarantine.target
│   │       └── ark.target
│   ├── opt/ark/                    ← State root scaffold (dirs created by hook)
│   └── usr/local/bin/
│       ├── ark-install             ← Disk installer (BTRFS + systemd-boot)
│       ├── ark-core                ← Core agent (Python)
│       ├── ark-watchdog            ← Integrity watchdog (Python)
│       └── ark-verify-perms        ← Permission auditor (bash)
├── efiboot/loader/
│   ├── loader.conf
│   └── entries/
│       ├── arklinux.conf           ← Normal boot entry
│       └── arklinux-debug.conf     ← Serial/verbose entry
└── syslinux/
    └── syslinux.cfg                ← BIOS boot menu
```

---

## Security claims and their evidence

| Claim | Evidence |
|-------|---------|
| Default-deny firewall | `archiso/airootfs/etc/nftables.conf` — `policy drop` on all chains |
| Strict systemd sandboxing | `ark-core.service`: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `CapabilityBoundingSet=` |
| Non-root service user | `customize_airootfs.sh` — `useradd --system --uid 973` |
| Fail-closed quarantine | `ark-watchdog` exits 2 → `ExecStopPost` → `ark-quarantine.target` |
| Evidence chain integrity | `ark-watchdog` SHA-256 hashes aletheia tree every 60 s |
| Reproducible build inputs | Arch Archive snapshot + packages.lock |
| Signed release artifacts | cosign keyless (Sigstore OIDC) + GitHub attestation |
