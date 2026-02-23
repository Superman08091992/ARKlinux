# ARKLinux — Individual Operator Edition v1.0-final

**ARKLinux** is an Arch Linux–based operating system designed as the native substrate for the **A.R.K.** (Autonomous Reasoning Kernel) platform. It delivers a hardened, self-governing, evidence-chain OS for single-node AI agent deployments.

---

## 📀 Latest Release

| Asset | Size | SHA256 |
|---|---|---|
| [`arklinux-v1.0-final-x86_64.iso`](releases/v1.0-final/arklinux-v1.0-final-x86_64.iso) | 111 MB | `94c3eee3348cd47990231a18ace4cdca627f8ceb9c4a47ddae983d9f72850cf9` |
| [`MANIFEST.sha256`](releases/v1.0-final/MANIFEST.sha256) | 1.2 KB | release manifest |

**Build Date:** 2026-02-23 | **Kernel:** 6.18.9-arch1-2 | **Base:** Arch Linux 2026.02.01

> ⚠️ The ISO is stored via [Git LFS](https://git-lfs.com/). Run `git lfs pull` after cloning to fetch it.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│  HOST OS                                            │
│  UEFI + GRUB2 | Linux 6.18.9 | NetworkManager      │
│  nftables (default-deny) | BTRFS subvolumes         │
├─────────────────────────────────────────────────────┤
│  CANONICAL STATE ROOT  /opt/ark/                    │
│  models | ingest | bus | memory | logs | quarantine │
│  snapshots | backup | apps | id | agents | secrets  │
├─────────────────────────────────────────────────────┤
│  SERVICE PLANE  (systemd-sandboxed)                 │
│  ark-core.service | ark-watchdog.service            │
│  Ollama LLM | Redis | MemoryEngine | PolicyGate     │
├─────────────────────────────────────────────────────┤
│  AGENT PLANE                                        │
│  Kyle | Joey | Kenny  (system users, venvs)         │
│  Optional: Aletheia/Verifier | HRM/Reasoning        │
├─────────────────────────────────────────────────────┤
│  SECURITY BOUNDARY                                  │
│  NoNewPrivileges | PrivateTmp | ReadOnlyPaths       │
│  IPAddressDeny=any | Loopback-only network          │
│  Fail-closed quarantine on evidence chain error     │
└─────────────────────────────────────────────────────┘
```

---

## 📦 Package Contents

| Component | Version |
|---|---|
| Base system | Arch Linux base |
| Kernel | linux 6.18.9.arch1-2 |
| Init | systemd 259.1 |
| Firewall | nftables 1.1.6 |
| Filesystem | btrfs-progs 6.19 |
| Python | 3.14.3 |
| OpenSSH | 10.2p1 |

---

## 🔒 Security Profile

- **Default-deny firewall** — `nftables` drops all external traffic; loopback only
- **Strict systemd sandboxing** — `NoNewPrivileges`, `PrivateTmp`, `PrivateDevices`, `ProtectSystem=strict`
- **Read-only model mounts** — `/opt/ark/models` is `ReadOnlyPaths` in all service units
- **Per-agent RW subvolumes** — agents get isolated BTRFS subvolumes
- **Fail-closed quarantine** — evidence chain corruption triggers `ark-quarantine.target`
- **IPAddressDeny=any** — all services bound to `127.0.0.1` only

---

## 🚀 Installation

Boot the ISO, then run:
```bash
ark-install /dev/sdX
```

The installer creates:
- `@` — root BTRFS subvolume
- `@home` — home subvolume
- `@log` — journal subvolume  
- `@snapshots` — snapshot subvolume
- `@opt_ark` — ARK state root subvolume

Bootloader: **systemd-boot** (EFI) with kernel cmdline `audit=1`

---

## 📁 Repository Structure

```
ARKlinux/
├── releases/
│   └── v1.0-final/
│       ├── arklinux-v1.0-final-x86_64.iso   ← Git LFS
│       └── MANIFEST.sha256
├── build/
│   └── installer/
│       └── ark-install.sh
├── systemd_units/
│   ├── ark-core.service
│   ├── ark-watchdog.service
│   ├── ark-ingestion.service
│   ├── ark-learning.service
│   ├── ark-policy.service
│   ├── ark.target
│   └── redis.service
├── nftables/
│   └── arklinux.nft
├── schemas/
│   ├── SAL_schema.json
│   ├── MDS_schema.json
│   ├── VerifiedClaim_schema.json
│   ├── CPA_schema.json
│   └── ParameterArtifact_schema.json
└── system/
    └── bin/
        ├── ark-package-manifest
        └── ark-verify-perms
```

---

## 🔗 Related Repositories

- [`Superman08091992/ark`](https://github.com/Superman08091992/ark) — ARK Python runtime
- [`Superman08091992/ARK_GENESIS`](https://github.com/Superman08091992/ARK_GENESIS) — Genesis bootstrap

---

*ARKLinux Individual Operator Edition — built for sovereign, single-node AI operations.*
