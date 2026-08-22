#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="arklinux-construction:local"
docker build --network=host -t "$IMAGE" -f "$ROOT/build/Dockerfile" "$ROOT"
mkdir -p "$ROOT/out"
docker run --rm --privileged --network=host \
  -v "$ROOT:/src" \
  -v /dev:/dev \
  -e ARKLINUX_ARCH_SNAPSHOT="${ARKLINUX_ARCH_SNAPSHOT:-2026/08/20}" \
  -e ARKLINUX_IMAGE_SIZE_GIB="${ARKLINUX_IMAGE_SIZE_GIB:-12}" \
  -e ARKLINUX_SWAP_GIB="${ARKLINUX_SWAP_GIB:-2}" \
  "$IMAGE"
