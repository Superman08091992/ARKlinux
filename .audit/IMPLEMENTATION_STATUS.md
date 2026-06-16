# Canonical architecture implementation status

## Implemented in the repository

- Canonical `/ark` layout contract and twelve functional facets.
- ARKlinux kernel naming and canonical ESP artifact paths.
- Canonical namespace initializer.
- Boot-time namespace preparation unit and system preset.
- Global `ARK_STATE_ROOT=/ark` service environment.
- Kernel staging helper and package-update hook.
- Single repository-side installer entry point targeting the archiso installer.

## Not yet verified

- No GitHub status check has reported for the current implementation head.
- No installed-node validation has been performed from this session.
- No ISO build result has been produced from this session.

## Remaining blockers

- The authoritative archiso installer still contains the legacy initial-install layout because the remote connector rejected modification of that protected installer file.
- The prepared custom ARKlinux kernel branch is not present on the remote repository and therefore was not merged or built here.
- Existing legacy service definitions still require reconciliation against the canonical namespace.

## Exact resume point

Continue from ARKlinux commit `9fe1f63b6f57c03db9cc9480793f11f6f3a763ed` and ARK_GENESIS commit `9fd54ba75001a62b6de6264c42066a3a8620b5b4`.
