# Implementation Findings

- Active installers, services, permission checks, schemas, and documentation now use `/ark` as the canonical A.R.K. root.
- New ARKlinux images use `@ark` as the root Btrfs subvolume and create no `/opt/ark` alias.
- Boot installation currently copies the generic Arch artifact `vmlinuz-linux` rather than an explicit ARKlinux kernel artifact name.
- The historical v1.0-final release tree remains unchanged as release provenance and is not an active build contract.
