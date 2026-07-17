# ARK/DREAMER repository inventory

Audit date: 2026-07-16. This is a current-state inventory, not a completion claim.

| Repository/material | Observed revision | Role | Current disposition |
|---|---|---|---|
| `Superman08091992/ARKlinux` | `3ac0be294bbc3f0e24678d155c1c9a532c461bdb` | Public Arch-derived host profile, boot assets, installer, firewall, system services | Canonical host source; first PR target |
| `Superman08091992/ARK_GENESIS` | GitHub indexed tree `269dd973367a5a14dbc3c931ba533ed6cd185be3` | Private current A.R.K. runtime, policies, packaging, API, UI, integrated Tradeanalyzer, combined-runtime provenance | Canonical runtime candidate; requires contract and evidence remediation |
| `Superman08091992/DREAMER` | README blob `e86647716e5385dfd331b563318555869c24ba89` | New private naming/design seed | Specification input only; not a buildable system |
| Tradeanalyzer source | Integrated at `ARK_GENESIS/opt/ark/runtime/modules/tradeanalyzer/` | Trading-domain source | Legacy/domain input; mock broker and market data must remain disabled |
| `ARK_GENESIS_UNIFIED_FULL` | Referenced by `scripts/reconstruct_combined_runtime_bundle.sh` and `docs/combined-runtime/MANIFEST.txt` | Historical umbrella source | Provenance only; do not execute or present as canonical runtime |
| Combined source archives | `ARK_GENESIS_INCORPORATED_PATCHED.zip`, `ark_gleaned_project.zip`, `ID_COB_Runtime_v0_1.zip` | Historical inputs named by reconstruction script | Preserve byte-for-byte; verify only when actual archive bytes are available |

## ARKlinux current tree

- `archiso/`: live-image profile, boot entries, base filesystem overlay.
- `build/`: container builder, installer wrapper, package-lock tooling.
- `config/arklinux-layout.yaml`: `/ark` target layout contract.
- `nftables/`: default-deny host policy source.
- `systemd_units/`: legacy service unit source.
- `schemas/`: legacy domain schemas.
- `.audit/`: prior implementation boundary and unresolved findings.
- `releases/`: historical release bundle; not accepted as proof of the current tree.

## Evidence and access limitations

The public ARKlinux repository was cloned and inspected locally. Private repositories were inspected through the connected GitHub API and the checked-in combined-runtime manifest. The connector does not provide a complete private-repository checkout or original archive bytes. Consequently, archive-level SHA-256 verification and a guaranteed every-file private-tree inventory remain blocked until those bytes are made available to CI or a checkout. Blank hashes in `LEGACY_COMPONENT_MAP.tsv` mean “not verified,” never “not applicable.”

