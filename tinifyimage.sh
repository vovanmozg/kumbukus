#!/bin/bash

source ~/.env

if [ "$#" -ne 1 ]; then
    echo "Using: $0 file_name.jpg"
    exit 1
fi

SOURCE_FILE="$1"
FILE_NAME=$(basename "$SOURCE_FILE")
OPTIMIZED_DIR="$(dirname "$SOURCE_FILE")/optimized"

if [ ! -d "$OPTIMIZED_DIR" ]; then
    mkdir "$OPTIMIZED_DIR"
fi

OPTIMIZED_FILE="${OPTIMIZED_DIR}/${FILE_NAME}"
OPTIMIZED_FILE_PROGRESS="${OPTIMIZED_FILE}.tmp"
touch "${OPTIMIZED_FILE_PROGRESS}"

# https://tinypng.com/developers/reference#compressing-images
response=$(curl --user api:$TINYPNG_API_KEY --dump-header /dev/stdout --data-binary @"$SOURCE_FILE" https://api.tinify.com/shrink)

location_url=$(echo "$response" | grep -i Location: | awk '{print $2}' | tr -d '\r')
rm "${OPTIMIZED_FILE_PROGRESS}"

# Если location_url не пустой, делаем второй запрос
if [ ! -z "$location_url" ]; then
    curl -L "$location_url" --output "$OPTIMIZED_FILE"
    touch -r "$SOURCE_FILE" "$OPTIMIZED_FILE"
    echo "Оптимизация завершена: $OPTIMIZED_FILE"
else
    echo "Не удалось извлечь URL из заголовка Location."
fi

