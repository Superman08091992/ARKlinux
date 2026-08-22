# ARKlinux construction architecture

This tree builds ARKlinux through the A.R.K. process layer while holding the later Aletheia/DREAMER/ID/Cube implementation boundary.

## Physical/runtime chain

```
hardware
  -> UEFI
  -> systemd-boot (ARKlinux entries)
  -> /boot/arklinux-kernel
  -> /boot/initramfs-arklinux.img
  -> ARKROOT Btrfs
  -> systemd
  -> native process groups
  -> coordinated process set = A.R.K.
```

A.R.K. is not a single binary. `arkd` is one coordinator process; A.R.K. names the ensemble.

## Filesystem law

`config/subvolumes.tsv` is authoritative for the initial Btrfs topology. OS state, A.R.K. process/state domains, and reserved Aletheia persistence are independently addressable subvolumes. Rejected fixed Cube-plane semantic names are intentionally absent.

The Aletheia subvolumes are storage reservations only in this phase. There is no Aletheia process, DREAMER process, ID runtime, Graveyard admission logic, or Cube semantic engine in this construction tree.

## Process groups

- core: arkd, local bus, watchdog
- lifecycle: Kyle carrier
- cognition: Joey carrier
- correspondence: HRM carrier
- effect: Kenny carrier
- intake: ingestion
- model: model-router carrier
- I/O: hardware discovery/path carrier

The carriers establish process identity, supervision, cgroup/systemd boundaries, local IPC and state paths. Higher cognition is intentionally not implemented here.
