#!/bin/bash
# Drives the real installapps non-interactively, inside the test container.
# Usage: run-installapps.sh <repo_path> <app_name>
# Selects ALL executable apps (order-independent); the caller asserts the
# specific <app_name> landed in ~/bin. installapps installs into $HOME/bin.
set -euo pipefail
repo="$1"
n="$(find "$repo/apps" -maxdepth 1 -type f -executable | wc -l)"
{ seq 1 "$n"; echo done; } | HOME=/root bash "$repo/installapps" "$repo"
