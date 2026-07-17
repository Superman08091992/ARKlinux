#!/usr/bin/env bash
set -euo pipefail

evidence_dir="evidence/builds/arklinux-1.0.1"
required=(
  BUILD_RECORD.md
  SHA256SUMS
  SOURCE_SHA256SUMS
  packages.lock
  qemu-live-boot-summary.json
  ARTIFACT_PROVENANCE.json
)

for file in "${required[@]}"; do
  test -s "${evidence_dir}/${file}" || {
    echo "missing or empty permanent evidence file: ${evidence_dir}/${file}" >&2
    exit 1
  }
done

python -m json.tool "${evidence_dir}/ARTIFACT_PROVENANCE.json" >/dev/null
python -m json.tool "${evidence_dir}/qemu-live-boot-summary.json" >/dev/null
grep -Fqx \
  '30810d132e5676d7075c4ed84dfbf695f19100c48109873742fb09cc1856fef8  arklinux-1.0.1-x86_64.iso' \
  "${evidence_dir}/SHA256SUMS"

echo "permanent milestone evidence record is complete"
