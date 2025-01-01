#!/bin/bash

# requirements: curl, exiftool, jpegtran
# install: sudo apt install curl exiftool libjpeg-progs

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

# Определяем ориентацию исходного изображения
orientation=$(exiftool -s -s -s -Orientation "$SOURCE_FILE")
echo "Original orientation: $orientation"

# Приводим изображение к нормальной ориентации физически
TEMP_FILE="${OPTIMIZED_DIR}/temp_${FILE_NAME}"

cp "$SOURCE_FILE" "$TEMP_FILE"
if [ "$orientation" = "Rotate 90 CW" ]; then
    jpegtran -rotate 90 -copy none -outfile "$TEMP_FILE" "$TEMP_FILE"
elif [ "$orientation" = "Rotate 270 CW" ]; then
    jpegtran -rotate 270 -copy none -outfile "$TEMP_FILE" "$TEMP_FILE"
elif [ "$orientation" = "Rotate 180" ]; then
    jpegtran -rotate 180 -copy none -outfile "$TEMP_FILE" "$TEMP_FILE"
fi

# Удаляем ориентацию из метаданных
exiftool -overwrite_original -all= "$TEMP_FILE"

# Восстанавливаем оригинальные метаданные без ориентации
exiftool -overwrite_original -tagsfromfile "$SOURCE_FILE" -all:all -Orientation=Horizontal "$TEMP_FILE"

# Сжимаем изображение через TinyPNG
response=$(curl --user api:$TINYPNG_API_KEY --dump-header /dev/stdout --data-binary @"$TEMP_FILE" https://api.tinify.com/shrink)

location_url=$(echo "$response" | grep -i Location: | awk '{print $2}' | tr -d '\r')

if [ ! -z "$location_url" ]; then
    curl -L "$location_url" --output "$OPTIMIZED_FILE"

    # Удаляем временные файлы
    rm "$TEMP_FILE"
    rm "$METADATA_FILE"

    # Восстанавливаем временную метку исходного файла
    touch -r "$SOURCE_FILE" "$OPTIMIZED_FILE"

    echo "Оптимизация завершена: $OPTIMIZED_FILE"
else
    echo "Не удалось извлечь URL из заголовка Location."
    rm "$TEMP_FILE"
    exit 1
fi
