#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="arklinux-construction:local"
ARK_PACKAGES_DIR="${ARK_GENESIS_PACKAGES_DIR:-$ROOT/out/private-ark-packages}"
ARK_REQUIRED="${ARK_GENESIS_REQUIRED:-0}"

docker build --network=host -t "$IMAGE" -f "$ROOT/build/Dockerfile" "$ROOT"
mkdir -p "$ROOT/out"

args=(
  --rm
  --privileged
  --network=host
  -v "$ROOT:/src"
  -v /dev:/dev
  -e "ARKLINUX_ARCH_SNAPSHOT=${ARKLINUX_ARCH_SNAPSHOT:-2026/08/20}"
  -e "ARKLINUX_IMAGE_SIZE_GIB=${ARKLINUX_IMAGE_SIZE_GIB:-12}"
  -e "ARKLINUX_SWAP_GIB=${ARKLINUX_SWAP_GIB:-2}"
  -e "ARK_GENESIS_REQUIRED=$ARK_REQUIRED"
)

if [[ -d "$ARK_PACKAGES_DIR" ]]; then
  ARK_PACKAGES_DIR="$(readlink -f "$ARK_PACKAGES_DIR")"
  args+=( -v "$ARK_PACKAGES_DIR:/ark-genesis-packages:ro" )
elif [[ "$ARK_REQUIRED" == "1" ]]; then
  echo "ERROR: ARK_GENESIS_REQUIRED=1 but package directory does not exist: $ARK_PACKAGES_DIR" >&2
  echo "Run scripts/build-private-ark-packages.sh first." >&2
  exit 1
fi

docker run "${args[@]}" "$IMAGE"
