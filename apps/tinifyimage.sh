#!/bin/bash

# requirement: vendor/curl
# requirement: vendor/exiftool

source ~/.env

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 file_name.jpg [--no-metadata]"
    exit 1
fi

SOURCE_FILE="$1"
NO_METADATA=false

if [ "$2" == "--no-metadata" ]; then
    NO_METADATA=true
fi

FILE_NAME=$(basename "$SOURCE_FILE")
OPTIMIZED_DIR="$(dirname "$SOURCE_FILE")/optimized"

if [ ! -d "$OPTIMIZED_DIR" ]; then
    mkdir "$OPTIMIZED_DIR"
fi

OPTIMIZED_FILE="${OPTIMIZED_DIR}/${FILE_NAME}"
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

# Remove progress showing file
if [ "$NO_METADATA" == true ]; then
    rm "${OPTIMIZED_FILE_PROGRESS}"
fi

if [ ! -z "$location_url" ]; then
    curl -L "$location_url" --output "$OPTIMIZED_FILE"

    if [ "$NO_METADATA" == false ]; then
        exiftool -overwrite_original -all= "$OPTIMIZED_FILE"

        exiftool -overwrite_original -tagsfromfile "$SOURCE_FILE" -all:all -Orientation=Horizontal "$OPTIMIZED_FILE"

        rm "$METADATA_FILE"
    fi

    # Restore timestamp
    touch -r "$SOURCE_FILE" "$OPTIMIZED_FILE"

    echo "Compression finished: $OPTIMIZED_FILE"
else
    echo "Error extracting URL from Location header"
    exit 1
fi
