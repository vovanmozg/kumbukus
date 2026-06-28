#!/bin/bash

# requirement: vendor/poppler-utils
# requirement: vendor/imagemagick
# depends on: optimizeimage.sh
#
# Compress a PDF by re-optimizing its page images with local tools (no cloud).
#   compresspdf.sh <file.pdf> [--width=<px>]
# Output goes to <dir>/optimized/<name>.pdf; the original is untouched.
# Each page image is optimized via optimizeimage.sh --offline (jpeg -> mozjpeg;
# png -> pngquant if losslessly quantizable, then oxipng).
# With --width=N each page image is first downscaled to N px wide (shrink only).

set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Using: $0 <file.pdf> [--width=<px>]"
    exit 1
fi

SOURCE_PDF=""
WIDTH=""
for arg in "$@"; do
    case "$arg" in
        --width=*) WIDTH="${arg#*=}" ;;
        -*)        echo "Unknown option: $arg" >&2; exit 1 ;;
        *)         SOURCE_PDF="$arg" ;;
    esac
done

if [ -z "$SOURCE_PDF" ] || [ ! -f "$SOURCE_PDF" ]; then
    echo "No such file: $SOURCE_PDF" >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Extract page images.
pdfimages -all "$SOURCE_PDF" "$TEMP_DIR/img"
if ! ls "$TEMP_DIR"/img* >/dev/null 2>&1; then
    echo "No images found in $SOURCE_PDF"
    exit 0
fi

for img in "$TEMP_DIR"/img*; do
    [ -f "$img" ] || continue
    if [ -n "$WIDTH" ]; then
        mogrify -resize "${WIDTH}x>" "$img"
    fi
    optimizeimage.sh --offline --no-metadata "$img" "$img" >/dev/null
done

OPTIMIZED_DIR=$(dirname "$SOURCE_PDF")/optimized
mkdir -p "$OPTIMIZED_DIR"
OPTIMIZED_FILE="$OPTIMIZED_DIR/$(basename "$SOURCE_PDF")"

convert "$TEMP_DIR"/img* "$OPTIMIZED_FILE"
echo "Compression finished: $OPTIMIZED_FILE"
