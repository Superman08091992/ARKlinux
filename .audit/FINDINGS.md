# Implementation Findings

- The repository still treats `/opt/ark` as the canonical state root in the installer, service units, permission verifier, Python substrate helpers, profile permissions, and README.
- The installer currently creates an `@opt_ark` BTRFS subvolume.
- Boot installation currently copies the generic Arch artifact `vmlinuz-linux` rather than an explicit ARKlinux kernel artifact name.
- These are implementation conflicts with the approved `/ark` canonical-root and ARKlinux-kernel naming requirements.
