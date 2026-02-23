# ARKLinux Build Environment Documentation

**Generated:** 2026-02-23  
**Build Host:** Genspark Sandbox (Debian 13 / Linux 6.1.158)  
**Repository:** https://github.com/Superman08091992/ARKlinux

---

## System Summary

| Item | Value |
|------|-------|
| Kernel | 6.1.158 |
| OS | Debian GNU/Linux 13 (trixie) |
| Architecture | x86_64 |
| CPUs | 2 vCPU |
| RAM | 985 MB total / ~350 MB available during build |
| Disk (/) | 26 GB total / 5.4 GB used / 20 GB free |
| Python | 3.12.12 |
| Git | 2.47.3 |
| Bash | 5.2.37 |
| ShellCheck | 0.10.0 |
| pip | 25.0.1 |

> **Note:** This sandbox is a *development/staging* environment only.
> Official ISO builds run inside the Docker container defined in
> `build/docker/Dockerfile` (base: `archlinux:base-devel`, pinned snapshot mirror).
> The Docker build is the authoritative build environment.

---

## Why This Environment Is Different From the Official Build

The official ISO is produced by **GitHub Actions** running
`build/docker/Dockerfile`. Key differences:

| Dimension | This Sandbox | Official Docker Build |
|-----------|-------------|----------------------|
| Base OS | Debian 13 | Arch Linux (archlinux:base-devel) |
| Package manager | dpkg/apt | pacman |
| Snapshot mirror | N/A | `archive.archlinux.org/repos/2026/02/01` |
| archiso | Not installed | Installed via pacman |
| mkarchiso | Not available | `/usr/bin/mkarchiso` |
| mkinitcpio | Not available | `/usr/bin/mkinitcpio` |
| QEMU/KVM | Installed (no KVM) | Not needed (ISO test in CI) |
| xorriso | Installed | Installed |

---

## Python Environment (pip packages)

Full list at `docs/sandbox-env/pip-requirements.txt`. Key packages used
by ARK tooling:

| Package | Version | Used By |
|---------|---------|---------|
| aiohttp | 3.12.14 | ark-core async HTTP |
| beautifulsoup4 | 4.13.4 | ark-core web parsing |
| cryptography | (system) | ark identity / key management |
| pytest | (system) | unit tests |
| shellcheck (binary) | 0.10.0 | CI lint step |

---

## System Packages (dpkg)

Full list at `docs/sandbox-env/dpkg-packages.tsv` (665 packages).

Selected build-relevant packages:

```
git                2.47.3
xorriso            1.5.6
qemu-system-x86_64 10.0.7
nftables           (installed, kernel module unavailable in sandbox)
shellcheck         0.10.0
python3            3.12.12
python3-pip        25.0.1
```

---

## Tool Versions

See `docs/sandbox-env/tool-versions.txt` for the full captured output.

---

## Node / npm Cache

An npm cache of ~728 MB exists at `/opt/npm-cache`. This is a sandbox
pre-installed cache and is **not part of the ARKLinux build**. The ARKLinux
build does not use Node.js or npm.

---

## Kernel Limitations in This Sandbox

The sandbox kernel does not expose certain kernel modules:

- `nf_tables` — nftables rules cannot be validated with `nft -c` (module absent)
- `kvm` / `kvm_intel` — no hardware virtualisation; QEMU runs without KVM
- No memory for QEMU VM launch (< 60 MB free during earlier test)

These limitations are **sandbox-specific** and do not affect official CI builds
running in GitHub Actions with dedicated runners.

---

## Reproducing the Official Build

See `docs/BUILDING.md` for the single-command reproducible build.

Short version:

```bash
git clone https://github.com/Superman08091992/ARKlinux
cd ARKlinux
docker build -t arklinux-builder build/docker/
docker run --rm --privileged \
  -v "$PWD":/src -w /src \
  arklinux-builder \
  bash build/docker/entrypoint.sh
# Output: out/arklinux-<version>-x86_64.iso
```

---

## File Inventory at Build Time

```
/home/user/ARKlinux/
├── .github/workflows/build-release.yml   (CI pipeline)
├── archiso/                              (mkarchiso profile)
│   ├── profiledef.sh
│   ├── packages.x86_64
│   ├── pacman.conf
│   ├── airootfs/
│   │   ├── etc/
│   │   │   ├── customize_airootfs.sh
│   │   │   ├── fstab
│   │   │   ├── hostname
│   │   │   ├── locale.conf / locale.gen
│   │   │   ├── mkinitcpio.conf
│   │   │   ├── nftables.conf
│   │   │   ├── os-release
│   │   │   └── systemd/system/
│   │   │       ├── ark-core.service
│   │   │       ├── ark-watchdog.service
│   │   │       ├── ark-quarantine.target
│   │   │       └── ark.target
│   │   └── usr/local/bin/
│   │       ├── ark-install
│   │       ├── ark-core
│   │       ├── ark-watchdog
│   │       └── ark-verify-perms
│   ├── efiboot/loader/
│   │   ├── loader.conf
│   │   └── entries/ (arklinux.conf, arklinux-debug.conf)
│   └── syslinux/syslinux.cfg
├── build/
│   ├── docker/Dockerfile + entrypoint.sh
│   ├── installer/ark-install.sh
│   ├── lock/packages.lock
│   └── scripts/pin-packages.sh
├── docs/
│   ├── BUILDING.md
│   ├── BUILD_ENV.md          (this file)
│   └── sandbox-env/
│       ├── dpkg-packages.tsv
│       ├── pip-requirements.txt
│       ├── tool-versions.txt
│       ├── system-info.txt
│       └── etc/ (chrony.conf, sysctl.conf)
├── nftables/arklinux.nft
├── releases/v1.0-final/
│   ├── arklinux-v1.0-final-x86_64.iso   (Git LFS, 111 MB)
│   └── MANIFEST.sha256
├── schemas/*.json (CPA, MDS, SAL, VerifiedClaim, ParameterArtifact)
├── system/bin/
├── systemd_units/
├── LICENSE
└── README.md
```
