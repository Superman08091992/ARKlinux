# ARKlinux Native Restart Dependency Baseline

This file separates host/OS packages from isolated Python/model dependencies. AI Python packages must not be installed into the system Python with pip.

## 1. Base, build, boot and filesystem — pacman

- base, base-devel
- linux, linux-headers, linux-firmware
- btrfs-progs, snapper
- dosfstools, gptfdisk, efibootmgr
- cryptsetup, tpm2-tools
- systemd, dbus-broker, polkit
- sudo
- git, openssh, rsync, curl, wget
- jq, ripgrep, fd, zstd, tar, unzip
- cmake, ninja, clang, llvm, rust
- python, python-pip, python-setuptools, python-wheel, python-virtualenv

## 2. Hardware, GPU and CUDA — detected hardware profile

- `ark-gpu-detect` inventories display-class PCI devices and records the active kernel binding
- `nvidia-pascal`: pinned proprietary `nvidia-580xx-dkms`, `nvidia-580xx-utils`, and `opencl-nvidia-580xx`
- `nvidia-open`: nvidia-open, nvidia-utils, nvidia-settings (Turing or newer only)
- system-default: mesa, libdrm, vulkan-icd-loader, vulkan-tools
- cuda, cudnn (not installed for Pascal; CUDA 13 removed compute capability 6.1 support)
- nvidia-container-toolkit
- vulkan-icd-loader, vulkan-tools
- mesa
- lm_sensors, pciutils, usbutils, smartmontools, nvme-cli

The native HP Z4 inventory contains `10de:1d01` (GT 1030) and `10de:1c31`
(Quadro P2200). Both are Pascal. The open kernel modules are incompatible with
them, so the automatic profile selects proprietary R580. Unknown or mixed
NVIDIA generations require an explicit profile and do not trigger package
changes.

The R580 package recipe is locked to one immutable AUR commit and verifies the
NVIDIA runfile SHA-256 before building as the unprivileged `nobody` account.
Installation is an explicit administrator action:

```bash
sudo ark-gpu-install auto
sudo reboot
sudo ark-gpu-detect --verify
nvidia-smi
```

`ark-bootstrap-ai auto` uses the same selection. On Pascal it installs the
R580 driver, leaves Ollama on its CPU runtime, and installs the pinned PyTorch
2.7.1 CUDA 12.6 wheel that remains usable on compute capability 6.1. It does
not install CUDA 13 or vLLM; those current compute paths no longer support the
two Pascal cards.

## 3. Desktop/compositor/toolkits — pacman

- plasma-desktop, plasma-workspace, kwin
- qt6-base, qt6-declarative, qt6-wayland, qt6-tools
- qt6-webengine, qt6-webchannel, qt6-websockets
- xorg-xwayland
- gtk3, gtk4, libxfce4ui
- pyside6, python-pyqt6, python-pyqt6-webengine
- ghostwriter, sonnet
- thunar, firefox, foot

## 4. Accessibility, audio and media — pacman

- at-spi2-core, orca, speech-dispatcher, espeak-ng
- pipewire, pipewire-alsa, pipewire-pulse, pipewire-jack, wireplumber
- alsa-utils
- gstreamer, gst-plugins-base, gst-plugins-good
- ffmpeg

## 5. Network/security/system services — pacman

- networkmanager, network-manager-applet
- nftables
- openssh
- chrony
- avahi
- libcap, libseccomp
- audit

## 6. Virtualization/containers/build verification — pacman

- qemu-full, edk2-ovmf, libvirt, virt-manager, dnsmasq
- docker, docker-compose, containerd
- nvidia-container-toolkit
- arch-install-scripts, archiso

## 7. Local inference/model host — pacman / isolated runtime

- `ollama` is part of the native base image and is supervised by `ollama.service`
- `nomic-embed-text:latest` is provisioned by `ark-embedding-model.service`; the exact resolved Ollama digest is recorded before use
- the real embedding contract is `ark-semantic-v1`, L2-normalized, exactly 768 dimensions
- ollama-cuda may replace the CPU package only for a compatible nvidia-open profile
- llama.cpp/ggml CUDA capability may be added as a separate package profile

## 8. Isolated Python AI environment — venv/container only

Interpreter target: Python 3.11 or 3.12 for model stacks that have not yet caught up with the host Arch Python.

- pip, setuptools, wheel
- torch
- tensorflow[and-cuda]
- triton
- nvidia-nccl-cu12 (or the version required by the selected framework)
- transformers
- accelerate
- safetensors
- tokenizers
- sentence-transformers
- vllm
- fastapi
- uvicorn
- pydantic
- httpx
- websockets
- psutil
- numpy
- scipy
- pandas

## 9. Network acquisition/automation environment — isolated Python environment

- requests
- httpx
- beautifulsoup4
- lxml
- selenium
- playwright
- aiohttp
- tenacity
- python-dateutil

Playwright browser binaries/system libraries must be installed during image/runtime preparation, not silently downloaded at first execution.

## 10. ARK-native required layers

These are architecture components rather than third-party packages:

- low-level process supervisor contracts: Kyle, Aletheia, Joey, HRM, Kenny
- model router
- KJ Joey→HRM-accounted→Kenny bridge
- append-only evidence/event ledger
- quarantine/intake service
- memory service
- Graveyard service
- checkpoint/recovery service
- bounded execution broker
- hardware observer
- read-only display adapter
- privileged named-operation desktop broker
- autonomous trading coordinator (disabled until mandate/credentials exist)
- execution-transparency/outcome ledger

## 11. Filesystem/runtime invariants

- Btrfs `@ark` is mounted at `/`.
- `/ark` is a native top-level ARKlinux system hierarchy.
- `/run/ark` is volatile IPC/runtime state.
- No legacy installed-root alias is created on new images.
- KJ is not the event ledger and not the display adapter.
- The GUI does not connect directly to low-level agent sockets or KJ.
