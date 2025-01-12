#!/bin/bash

# requirement: vendor/jpegoptim

DEFAULT_COMPRESSION=50

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <file_name.jpg> [compression_level]"
    exit 1
fi

SOURCE_FILE="$1"
COMPRESSION_LEVEL="${2:-$DEFAULT_COMPRESSION}"  # Use default if not provided

if ! [[ "$COMPRESSION_LEVEL" =~ ^[0-9]+$ ]] || [ "$COMPRESSION_LEVEL" -lt 0 ] || [ "$COMPRESSION_LEVEL" -gt 100 ]; then
    echo "Error: Compression level must be an integer between 0 and 100."
    exit 1
fi

FILE_NAME=$(basename "$SOURCE_FILE")
OPTIMIZED_DIR="$(dirname "$SOURCE_FILE")/optimized"

if [ ! -d "$OPTIMIZED_DIR" ]; then
    mkdir "$OPTIMIZED_DIR"
fi

OPTIMIZED_FILE="${OPTIMIZED_DIR}/${FILE_NAME}"

cp "$SOURCE_FILE" "$OPTIMIZED_FILE"

jpegoptim --force --max="$COMPRESSION_LEVEL" --preserve-perms "$OPTIMIZED_FILE"

touch -r "$SOURCE_FILE" "$OPTIMIZED_FILE"

echo "Optimization completed: $OPTIMIZED_FILE (Compression level: $COMPRESSION_LEVEL)"
