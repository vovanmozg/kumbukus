#!/bin/bash
# Runs every tests/behavior/test_*.sh; non-zero exit if any fail.
here="$(cd "$(dirname "$0")" && pwd)"
rc=0
shopt -s nullglob
for t in "$here"/test_*.sh; do
  echo "== $(basename "$t") =="
  bash "$t" || rc=1
done
exit "$rc"
