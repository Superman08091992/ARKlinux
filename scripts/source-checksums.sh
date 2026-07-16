#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-${root}/build/SOURCE_SHA256SUMS}"
mkdir -p "$(dirname "$out")"

(
  cd "$root"
  find . -type f \
    -not -path './.git/*' \
    -not -path './build/*' \
    -not -path './releases/*' \
    -print0 \
    | sort -z \
    | xargs -0 sha256sum
) > "$out"

echo "$out"

