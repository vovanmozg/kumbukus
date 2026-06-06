#!/bin/bash
# Drives the real installapps non-interactively, inside the test container.
# Usage: run-installapps.sh <repo_path>
# Selects ALL executable apps (order-independent); the generated Dockerfile's
# `test -x /root/bin/<app>` asserts the specific app landed. installapps installs into $HOME/bin.
# NOTE: n counts from the COPY'd working tree; installapps clones the same /repo,
# so counts match as long as there are no uncommitted executables in apps/.
set -euo pipefail
repo="$1"
n="$(find "$repo/apps" -maxdepth 1 -type f -executable | wc -l)"
{ seq 1 "$n"; echo done; } | HOME=/root bash "$repo/installapps" "$repo"
