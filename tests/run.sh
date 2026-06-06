#!/bin/bash
# Build & run install tests for the given apps (default: tinifyimage.sh).
# Each app gets a generated per-app Dockerfile; a successful build == PASS.
# Usage: ./tests/run.sh [app ...]
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"

# shellcheck source=/dev/null
source "$here/lib/requirements.sh"
# shellcheck source=/dev/null
source "$here/lib/checks.sh"
# shellcheck source=/dev/null
source "$here/lib/gen-dockerfile.sh"

apps=("$@")
[ ${#apps[@]} -eq 0 ] && apps=(tinifyimage.sh)

echo "==> Building base image"
docker build -t kumbukus-test-base -f "$here/Dockerfile.base" "$here"

mkdir -p "$here/.generated"
declare -a passed=() failed=()

for app in "${apps[@]}"; do
  echo "==> Testing install: $app"
  df="$here/.generated/Dockerfile.$app"
  if ! gen_dockerfile "$app" "$repo" > "$df"; then
    echo "  generation failed for $app" >&2
    failed+=("$app")
    continue
  fi
  if docker build -t "kumbukus-test-$app" -f "$df" "$repo"; then
    passed+=("$app")
  else
    failed+=("$app")
  fi
done

echo
echo "==== Summary ===="
for a in "${passed[@]}"; do echo "PASS  $a"; done
for a in "${failed[@]}"; do echo "FAIL  $a"; done

[ ${#failed[@]} -eq 0 ]
