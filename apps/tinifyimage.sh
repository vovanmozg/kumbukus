#!/bin/bash

# requirements: curl, exiftool
# install: sudo apt install curl exiftool

source ~/.env

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 file_name.jpg"
    exit 1
fi

SOURCE_FILE="$1"
FILE_NAME=$(basename "$SOURCE_FILE")
OPTIMIZED_DIR="$(dirname "$SOURCE_FILE")/optimized"

if [ ! -d "$OPTIMIZED_DIR" ]; then
    mkdir "$OPTIMIZED_DIR"
fi

OPTIMIZED_FILE="${OPTIMIZED_DIR}/${FILE_NAME}"
METADATA_FILE="${OPTIMIZED_DIR}/${FILE_NAME}.metadata"

# Сохраняем метаданные из исходного изображения
exiftool -j "$SOURCE_FILE" > "$METADATA_FILE"

# Сжимаем изображение через TinyPNG
response=$(curl --user api:$TINYPNG_API_KEY --dump-header /dev/stdout --data-binary @"$SOURCE_FILE" https://api.tinify.com/shrink)

location_url=$(echo "$response" | grep -i Location: | awk '{print $2}' | tr -d '\r')

if [ ! -z "$location_url" ]; then
    curl -L "$location_url" --output "$OPTIMIZED_FILE"

    # Удаляем все существующие метаданные из сжатого изображения
    exiftool -overwrite_original -all= "$OPTIMIZED_FILE"

    # Восстанавливаем метаданные из исходного файла без ориентации
    exiftool -overwrite_original -tagsfromfile "$SOURCE_FILE" -all:all -Orientation=Horizontal "$OPTIMIZED_FILE"

    # Восстанавливаем временную метку исходного файла
    touch -r "$SOURCE_FILE" "$OPTIMIZED_FILE"

    # Удаляем временный файл метаданных
    rm "$METADATA_FILE"

    echo "Оптимизация завершена: $OPTIMIZED_FILE"
else
    echo "Не удалось извлечь URL из заголовка Location."
    exit 1
fi
