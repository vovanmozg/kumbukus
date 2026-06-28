#!/bin/bash

# requirement: vendor/imagemagick
# depends on: optimizeimage.sh
#
# Optimize an image into a sibling `optimized/` folder.
# Thin wrapper over optimizeimage.sh (which holds all the optimization logic):
# computes the optimized/ destination and delegates, forwarding all flags.
#
# Usage: tinifyimage.sh [--online|--offline] [--no-metadata] [-q N] FILE

usage() {
    cat <<EOF
Usage: $0 [--online|--offline] [--no-metadata] [-q N] FILE

Optimizes FILE into ./optimized/FILE next to it (original untouched).
Delegates to optimizeimage.sh.
EOF
}

FLAGS=()
FILE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -q|--quality)  FLAGS+=("$1" "$2"); shift 2 ;;
        -h|--help)     usage; exit 0 ;;
        -*)            FLAGS+=("$1"); shift ;;
        *)             FILE="$1"; shift ;;
    esac
done

if [ -z "$FILE" ]; then
    usage; exit 1
fi
if [ ! -f "$FILE" ]; then
    echo "No such file: $FILE" >&2; exit 1
fi

OPTIMIZED_DIR="$(dirname "$FILE")/optimized"
mkdir -p "$OPTIMIZED_DIR"
DST="$OPTIMIZED_DIR/$(basename "$FILE")"

exec optimizeimage.sh "${FLAGS[@]}" "$FILE" "$DST"
