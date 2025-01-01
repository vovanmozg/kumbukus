#!/bin/bash

# Проверка на наличие аргумента (имя файла)
if [ "$#" -ne 1 ]; then
    echo "Using: $0 file_name.avi"
    exit 1
fi

SOURCE_FILE="$1"
FILE_NAME=$(basename "$SOURCE_FILE")
OPTIMIZED_DIR="$(dirname "$SOURCE_FILE")/compressed"

if [ ! -d "$OPTIMIZED_DIR" ]; then
    mkdir "$OPTIMIZED_DIR"
fi

OPTIMIZED_FILE="${OPTIMIZED_DIR}/${FILE_NAME}"


jpegoptim --force --max=50 --strip-all --preserve-perms "$OPTIMIZED_FILE"

touch -r "$SOURCE_FILE" "$OPTIMIZED_FILE"

echo "Оптимизация завершена: $OPTIMIZED_FILE"
