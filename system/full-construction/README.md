# ARKlinux full construction

This is the corrected ARKlinux build boundary: direct ARKlinux kernel artifact, UEFI boot, ARKlinux initramfs, full Btrfs topology, systemd substrate, and the native coordinated process set called A.R.K. It does **not** implement Aletheia, DREAMER, ID, or Cube cognition yet.

## Build

On the Arch development tower with Docker:

```bash
./scripts/verify-topology.sh
sudo systemctl enable --now docker
./build/run.sh
```

Output:

```text
out/arklinux-x86_64.raw
out/SHA256SUMS
out/kernel/arklinux-kernel
out/kernel/kernel-release
out/evidence/
```

The construction container uses Arch only as an external build/bootstrap ecosystem. The raw image boots ARKlinux directly on firmware/hardware (or QEMU hardware emulation); no Arch host exists underneath ARKlinux at runtime.

## Validate in QEMU

```bash
./scripts/verify-image.sh
./scripts/qemu-smoke.sh
```

The default raw image is 12 GiB with a 2 GiB Btrfs swapfile so it can be exercised on a 16 GB disposable test medium before any internal-disk install.
