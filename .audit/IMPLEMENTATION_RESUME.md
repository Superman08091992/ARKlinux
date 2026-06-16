# ARKlinux Canonical Architecture Implementation

Status: in progress

Canonical installed root: `/ark`.
Legacy `/opt/ark` paths are migration inputs only.

Implementation scope:
1. Establish machine-readable ARKlinux ownership and path contracts.
2. Rename boot artifacts to explicit ARKlinux kernel names.
3. Replace new-install `/opt/ark` storage with `/ark`.
4. Add validation checks preventing boundary and path regressions.
5. Coordinate ARK_GENESIS runtime-root migration and registry facets.
