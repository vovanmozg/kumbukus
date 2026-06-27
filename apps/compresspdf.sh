#!/bin/bash

# requirement: vendor/poppler-utils
# requirement: vendor/imagemagick
# requirement: vendor/mozjpeg
# requirement: vendor/pngquant
# requirement: vendor/oxipng
#
# Compress a PDF by re-optimizing its page images with local tools (no cloud).
#   compresspdf.sh <file.pdf> [--width=<px>]
# Output goes to <dir>/optimized/<name>.pdf; the original is untouched.
# Page images are optimized like tinifyimage.sh --offline:
#   jpeg -> mozjpeg (q75); png -> pngquant if losslessly quantizable, then oxipng.
# With --width=N each page image is first downscaled to N px wide (shrink only).

set -euo pipefail

JPEG_QUALITY=75
OXIPNG_LEVEL=4
MOZJPEG_BIN=/opt/mozjpeg/bin

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

# Optimize one image in place, mirroring tinifyimage.sh --offline.
optimize_image() {
    local img="$1" fmt m n z
    m=$(file -b --mime-type "$img" 2>/dev/null || true)
    case "$m" in
        image/jpeg) fmt=jpeg ;;
        image/png)  fmt=png ;;
        *)
            case "${img,,}" in
                *.jpg|*.jpeg) fmt=jpeg ;;
                *.png)        fmt=png ;;
                *)            fmt="" ;;
            esac
            ;;
    esac

    case "$fmt" in
        jpeg)
            "$MOZJPEG_BIN/djpeg" "$img" \
                | "$MOZJPEG_BIN/cjpeg" -quality "$JPEG_QUALITY" -quant-table 3 -progressive -optimize -outfile "$img.tmp"
            mv -f "$img.tmp" "$img"
            ;;
        png)
            read -r n z < <(identify -format '%k %z\n' "$img" 2>/dev/null || echo "999999 16")
            if [ "${n:-999999}" -le 256 ] 2>/dev/null && [ "${z:-16}" -le 8 ] 2>/dev/null; then
                if pngquant 256 --skip-if-larger --force --output "$img.q" "$img" 2>/dev/null; then
                    mv -f "$img.q" "$img"
                fi
            fi
            oxipng -o "$OXIPNG_LEVEL" --strip safe --alpha "$img" >/dev/null 2>&1 || true
            ;;
        *)
            : # leave non jpg/png images unchanged
            ;;
    esac
}

for img in "$TEMP_DIR"/img*; do
    [ -f "$img" ] || continue
    if [ -n "$WIDTH" ]; then
        mogrify -resize "${WIDTH}x>" "$img"
    fi
    optimize_image "$img"
done

OPTIMIZED_DIR=$(dirname "$SOURCE_PDF")/optimized
mkdir -p "$OPTIMIZED_DIR"
OPTIMIZED_FILE="$OPTIMIZED_DIR/$(basename "$SOURCE_PDF")"

convert "$TEMP_DIR"/img* "$OPTIMIZED_FILE"
echo "Compression finished: $OPTIMIZED_FILE"
