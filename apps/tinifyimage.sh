#!/bin/bash

# requirement: vendor/curl
# requirement: vendor/exiftool
# requirement: vendor/mozjpeg
# requirement: vendor/pngquant
# requirement: vendor/oxipng
# requirement: vendor/imagemagick
#
# Optimize an image into a sibling `optimized/` folder, preserving metadata + mtime.
#
# Modes:
#   --offline  (default)  local tools, always lossless quality:
#                           jpg -> mozjpeg
#                           png -> pngquant (only if <=256 colors & <=8-bit, i.e.
#                                  palette is lossless), otherwise oxipng only
#   --online              TinyPNG/Tinify API (needs TINYPNG_API_KEY in ~/.env)
#
# Local tools (offline mode):
#   /opt/mozjpeg/bin/{cjpeg,djpeg} (built from source, see vendor/mozjpeg)
#   pngquant  oxipng  identify (ImageMagick)  exiftool
# Online mode also needs: curl

JPEG_QUALITY=75          # mozjpeg quality for local jpg (Squoosh-style)
OXIPNG_LEVEL=4           # oxipng optimization level (png, lossless)
MOZJPEG_BIN=/opt/mozjpeg/bin   # mozjpeg built from source (no PATH symlinks)

usage() {
    cat <<EOF
Usage: $0 [--online|--offline] [--no-metadata] [-q N] FILE

  --offline        local, always lossless: jpg=mozjpeg; png=pngquant if <=256
                   colors (palette is lossless) else oxipng
  --online         compress via Tinify API (requires TINYPNG_API_KEY in ~/.env)
  --no-metadata    drop EXIF/metadata (orientation is still kept for jpg)
  -q, --quality N  mozjpeg quality for local jpg (default ${JPEG_QUALITY})

Result goes to ./optimized/FILE next to the source; original is untouched.
EOF
}

MODE=offline
NO_METADATA=false
SOURCE_FILE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --online)            MODE=online ;;
        --offline|--local)   MODE=offline ;;
        --no-metadata)       NO_METADATA=true ;;
        -q|--quality)        shift; JPEG_QUALITY="$1" ;;
        -h|--help)           usage; exit 0 ;;
        -*)                  echo "Unknown option: $1" >&2; usage; exit 1 ;;
        *)                   SOURCE_FILE="$1" ;;
    esac
    shift
done

if [ -z "$SOURCE_FILE" ]; then
    usage; exit 1
fi
if [ ! -f "$SOURCE_FILE" ]; then
    echo "No such file: $SOURCE_FILE" >&2; exit 1
fi

FILE_NAME=$(basename "$SOURCE_FILE")
OPTIMIZED_DIR="$(dirname "$SOURCE_FILE")/optimized"
mkdir -p "$OPTIMIZED_DIR"
OPTIMIZED_FILE="${OPTIMIZED_DIR}/${FILE_NAME}"

# --- ONLINE: Tinify API (unchanged behaviour) ---------------------------------
compress_online() {
    source ~/.env

    OPTIMIZED_FILE_PROGRESS="${OPTIMIZED_FILE}.tmp"
    METADATA_FILE="${OPTIMIZED_FILE}.metadata"

    if [ "$NO_METADATA" == false ]; then
        exiftool -j "$SOURCE_FILE" > "$METADATA_FILE"
    else
        touch "${OPTIMIZED_FILE_PROGRESS}"
    fi

    # https://tinypng.com/developers/reference#compressing-images
    response=$(curl --user api:$TINYPNG_API_KEY --dump-header /dev/stdout --data-binary @"$SOURCE_FILE" https://api.tinify.com/shrink)
    location_url=$(echo "$response" | grep -i Location: | awk '{print $2}' | tr -d '\r')

    if [ "$NO_METADATA" == true ]; then
        rm "${OPTIMIZED_FILE_PROGRESS}"
    fi

    if [ ! -z "$location_url" ]; then
        curl -L "$location_url" --output "$OPTIMIZED_FILE"

        if [ "$NO_METADATA" == false ]; then
            # Tinify bakes EXIF rotation into pixels, so force Orientation=Horizontal
            exiftool -overwrite_original -all= "$OPTIMIZED_FILE"
            exiftool -overwrite_original -tagsfromfile "$SOURCE_FILE" -all:all -Orientation=Horizontal "$OPTIMIZED_FILE"
            rm "$METADATA_FILE"
        fi

        touch -r "$SOURCE_FILE" "$OPTIMIZED_FILE"
        echo "Compression finished (online): $OPTIMIZED_FILE"
    else
        echo "Error extracting URL from Location header" >&2
        exit 1
    fi
}

# --- OFFLINE: local tools -----------------------------------------------------
require() {
    local missing=0
    for t in "$@"; do
        command -v "$t" >/dev/null 2>&1 || { echo "Missing tool: $t" >&2; missing=1; }
    done
    [ "$missing" -eq 0 ] || { echo "Install the missing tool(s) and retry." >&2; exit 1; }
}

restore_metadata() { # $1 = file to tag, $2 = "jpeg"|"png"
    if [ "$NO_METADATA" == false ]; then
        exiftool -overwrite_original -tagsfromfile "$SOURCE_FILE" -all:all "$1" >/dev/null 2>&1 || true
    elif [ "$2" == "jpeg" ]; then
        # keep only Orientation so rotated photos still display correctly
        exiftool -overwrite_original -tagsfromfile "$SOURCE_FILE" -Orientation "$1" >/dev/null 2>&1 || true
    fi
}

detect_format() { # echo "jpeg" | "png" | "" — prefer real content, fall back to extension
    local m=""
    if command -v file >/dev/null 2>&1; then
        m=$(file -b --mime-type "$SOURCE_FILE" 2>/dev/null)
    fi
    case "$m" in
        image/jpeg) echo jpeg; return ;;
        image/png)  echo png;  return ;;
    esac
    case "${SOURCE_FILE,,}" in
        *.jpg|*.jpeg) echo jpeg ;;
        *.png)        echo png ;;
        *)            echo "" ;;
    esac
}

compress_local() {
    local fmt tmp n z
    fmt=$(detect_format)
    tmp="${OPTIMIZED_FILE}.work.tmp"
    rm -f "$tmp"

    case "$fmt" in
        jpeg)
            require "$MOZJPEG_BIN/djpeg" "$MOZJPEG_BIN/cjpeg"
            # mozjpeg defaults already include -progressive -optimize -trellis;
            # -quant-table 3 matches Squoosh. cjpeg reads PPM, so decode first.
            "$MOZJPEG_BIN/djpeg" "$SOURCE_FILE" \
                | "$MOZJPEG_BIN/cjpeg" -quality "$JPEG_QUALITY" -quant-table 3 -progressive -optimize -outfile "$tmp"
            restore_metadata "$tmp" jpeg
            ;;
        png)
            require oxipng identify
            # pngquant only when it is provably lossless: all colors fit a
            # 256-entry, <=8-bit palette. Otherwise quantization would drop
            # colors/precision -> use lossless oxipng alone. (file -> "%k %z")
            read -r n z < <(identify -format '%k %z' "$SOURCE_FILE" 2>/dev/null)
            if [ "${n:-999999}" -le 256 ] 2>/dev/null && [ "${z:-16}" -le 8 ] 2>/dev/null; then
                require pngquant
                if ! pngquant 256 --skip-if-larger --force --output "$tmp" "$SOURCE_FILE" 2>/dev/null; then
                    cp "$SOURCE_FILE" "$tmp"   # pngquant declined -> keep original
                fi
            else
                cp "$SOURCE_FILE" "$tmp"       # >256 colors or >8-bit -> lossless only
            fi
            oxipng -o "$OXIPNG_LEVEL" --strip safe --alpha "$tmp" >/dev/null 2>&1
            restore_metadata "$tmp" png
            ;;
        *)
            echo "Unsupported type for local mode: $SOURCE_FILE (expected jpg/png)" >&2
            exit 1
            ;;
    esac

    touch -r "$SOURCE_FILE" "$tmp"
    mv -f "$tmp" "$OPTIMIZED_FILE"

    local os ns
    os=$(stat -c%s "$SOURCE_FILE"); ns=$(stat -c%s "$OPTIMIZED_FILE")
    awk -v o="$os" -v n="$ns" -v f="$OPTIMIZED_FILE" \
        'BEGIN{printf "Compression finished (local): %s  (%d -> %d bytes, -%.0f%%)\n", f, o, n, (o-n)*100/o}'
}

if [ "$MODE" == "online" ]; then
    compress_online
else
    compress_local
fi
