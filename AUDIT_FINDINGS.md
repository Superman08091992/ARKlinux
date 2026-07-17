# Mock, breakage, dependency, destructive-operation, and claim register

This register is based on the public ARKlinux tree plus GitHub inspection of the current ARK_GENESIS tree. “Every” means every item observed in the accessible sources on 2026-07-16; the private archive bytes must be scanned again after import.

## Mock or success-shaped functionality

- `ARK_GENESIS/opt/ark/runtime/modules/tradeanalyzer/modules/tradeanalyzer/services/broker.ts`: random quote prices; fabricated account number, balances, SPY and AAPL holdings.
- `ARK_GENESIS/opt/ark/ui/operator-console/ark-api/src/index.js`: random Joey score, simulated Kenny order ID, and Aletheia `allowed:true`; writes to external Supabase.
- `ARK_GENESIS/opt/ark/runtime/api/asgi.py`: memory search, promotion, Kyle, Joey, HRM, AEM, execution and trading routes acknowledge requests without performing their named contracts; `/trading/decision` always returns `hold`.
- `ARK_GENESIS/opt/ark/runtime/api/asgi.py`: `/evidence/write` creates a mutable timestamp-named JSON file rather than an append-only evidence record.
- Search-identified legacy paths requiring quarantine review: `tradeanalyzer/ark/server.ts`, `ark_worker/worker.py`, `ark_cli/verifier.py`, `GreekMatrix.tsx`, `geminiService.ts`, `operator-console/scripts/index.js`, and `execution_broker/tools.py`.

## Broken or unverified integration

- No automated QEMU boot/install/reboot test exists on the inspected baseline.
- `docs/BUILDING.md` builds Docker with context `build/docker/`, but the Dockerfile copies `build/docker/entrypoint.sh`; that path exists only when repository root is the context.
- The Arch snapshot is date-pinned, but the Docker base image is tag-pinned rather than digest-pinned; bit-for-bit reproducibility is not proven.
- `customize_airootfs.sh` is stored under `/etc`; current ArchISO does not guarantee executing that file. User/directory/service setup must use package scripts, sysusers, tmpfiles and presets.
- Installer rebuilds initramfs after copying it to the ESP, risking a stale boot artifact.
- Installer accepts generic `--confirm` for destructive unattended operation and uses `sleep 1` rather than positive device-settlement verification.
- `/opt/ark` and `/ark` remain conflicting roots across profile, installer, services, runtime and canonical specification.
- Required service set (`arkd`, `ark-api`, bus, memory, evidence, model-router, policyd, hardwared and five agent instances) is absent.
- Current runtime service depends on Valkey/Ollama ordering without proving local offline degraded startup.
- Current API lacks the mandatory correlation/timestamp/source/policy/mode/evidence/status envelope.
- No complete private source checkout or original archive bytes were available to recompute the checked-in combined-runtime hashes.

## Missing or unidentified dependencies

- Exact immutable Docker image digest.
- A fully locked package/version set proven resolvable from the selected Arch archive date.
- Pinned Python runtime lockfile for the canonical runtime package.
- Approved local model artifact, checksum, license and hardware requirements.
- Configured broker adapter (live brokerage must remain `not_implemented`).
- Human authentication and approval-record mechanism.

## Destructive operations

- `archiso/airootfs/usr/local/bin/ark-install`: `sgdisk --zap-all`, repartitioning, formatting, rsync with `--delete`, mount/unmount and bootloader writes against a caller-supplied block device.
- `scripts/reconstruct_combined_runtime_bundle.sh` in ARK_GENESIS: recursive deletion of its configured output directory.
- Build scripts remove/recreate work directories; these must remain path-bounded under repository build output.

## Unverifiable or overstated claims

- Historical “installed successfully,” “all assertions passed,” release names, manifests, evidence summaries, and prior test-count files prove only their own recorded event, not the current commit.
- “Bit-for-bit reproducible” in `docs/BUILDING.md` is contradicted by its own timestamp caveat and unpinned container digest.
- Service `active` state alone is not runtime correctness.
- Route presence is not endpoint implementation.
- A draft or merged PR is not installation evidence.

