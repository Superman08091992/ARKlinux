#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${ARK_OUTPUT_DIR:-${root}/build/out}"
image="${ARK_BUILDER_IMAGE:-arklinux-builder:2026-07-15}"

command -v docker >/dev/null || {
  echo 'dependency blocker: docker is required for the canonical ISO build' >&2
  exit 2
}

mkdir -p "$out"
bash "${root}/scripts/validate-iso-profile.sh"

docker build \
  --build-arg ARCH_SNAPSHOT=2026/07/15 \
  --tag "$image" \
  --file "${root}/build/docker/Dockerfile" \
  "$root"

docker run --rm --privileged \
  --volume "${root}:/src:ro" \
  --volume "${out}:/out" \
  "$image"

(
  cd "$out"
  sha256sum --check SHA256SUMS
  test -s packages.lock
)
