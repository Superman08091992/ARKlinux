# ARKlinux Canonical Architecture Implementation

Status: path and root-subvolume migration implemented; release-image proof pending

Canonical installed root: `/ark`.
New images create no `/opt/ark` compatibility alias.

Implementation scope:
1. Establish machine-readable ARKlinux ownership and path contracts.
2. Rename boot artifacts to explicit ARKlinux kernel names.
3. Replace new-install `/opt/ark` storage with `/ark` and root `@` with `@ark`.
4. Add validation checks preventing boundary and path regressions.
5. Coordinate ARK_GENESIS runtime-root migration and registry facets.
