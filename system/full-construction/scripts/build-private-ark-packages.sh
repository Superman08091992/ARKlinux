#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/config/ark-genesis.lock"
# shellcheck disable=SC1090
source "$LOCK"

SRC="${ARK_GENESIS_SOURCE:-${1:-}}"
OUT="${ARK_GENESIS_PACKAGES_DIR:-$ROOT/out/private-ark-packages}"

if [[ -z "$SRC" ]]; then
  echo "usage: ARK_GENESIS_SOURCE=/path/to/private/ARK_GENESIS $0" >&2
  exit 2
fi
SRC="$(readlink -f "$SRC")"
[[ -d "$SRC/.git" ]] || { echo "ERROR: not an ARK_GENESIS git checkout: $SRC" >&2; exit 1; }

HEAD="$(git -C "$SRC" rev-parse HEAD)"
if [[ "$HEAD" != "$ARK_GENESIS_COMMIT" ]]; then
  echo "ERROR: ARK_GENESIS checkout is $HEAD; integration lock requires $ARK_GENESIS_COMMIT" >&2
  exit 1
fi

if [[ -n "$(git -C "$SRC" status --porcelain --untracked-files=no)" ]]; then
  echo "ERROR: tracked ARK_GENESIS files are modified; refusing an unattributable package build" >&2
  exit 1
fi

printf 'Validating private A.R.K. source at %s\n' "$HEAD"
(
  cd "$SRC"
  make compile
  make test
  make validate-packaging
  make validate-deployment
  make validate-architecture
  make smoke-contract
  make packages
)

rm -rf "$OUT"
mkdir -p "$OUT"

for package in $ARK_GENESIS_PACKAGES; do
  mapfile -t matches < <(find "$SRC/out/packages" -maxdepth 1 -type f -name "${package}-*.pkg.tar.*" ! -name '*.sig' -print | sort)
  if [[ "${#matches[@]}" -ne 1 ]]; then
    echo "ERROR: expected exactly one built package for $package, found ${#matches[@]}" >&2
    printf '  %s\n' "${matches[@]:-}" >&2
    exit 1
  fi
  cp --reflink=auto "${matches[0]}" "$OUT/"
done

printf '%s\n' "$ARK_GENESIS_COMMIT" > "$OUT/ARK_GENESIS_COMMIT"
printf '%s\n' "$ARK_GENESIS_REPOSITORY" > "$OUT/ARK_GENESIS_REPOSITORY"
(
  cd "$OUT"
  sha256sum ./*.pkg.tar.* > SHA256SUMS
)

cat > "$OUT/MANIFEST" <<EOF
repository=$ARK_GENESIS_REPOSITORY
commit=$ARK_GENESIS_COMMIT
packages=$ARK_GENESIS_PACKAGES
built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

printf 'Private A.R.K. package set staged at %s\n' "$OUT"
printf 'Pinned commit: %s\n' "$ARK_GENESIS_COMMIT"
