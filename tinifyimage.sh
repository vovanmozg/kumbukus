#!/bin/bash

# requirements: curl, exiftool, jpegtran
# install: sudo apt install curl exiftool libjpeg-progs

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
METADATA_FILE="${OPTIMIZED_DIR}/${FILE_NAME}.metadata"

# Сохраняем метаданные из исходного изображения
exiftool -j "$SOURCE_FILE" > "$METADATA_FILE"
sed -i "s#\"SourceFile\": \"$FILE_NAME\"#\"SourceFile\": \"$OPTIMIZED_FILE\"#" "$METADATA_FILE"

touch "${OPTIMIZED_FILE_PROGRESS}"

# https://tinypng.com/developers/reference#compressing-images
response=$(curl --user api:$TINYPNG_API_KEY --dump-header /dev/stdout --data-binary @"$SOURCE_FILE" https://api.tinify.com/shrink)

location_url=$(echo "$response" | grep -i Location: | awk '{print $2}' | tr -d '\r')
rm "${OPTIMIZED_FILE_PROGRESS}"

# Если location_url не пустой, делаем второй запрос
if [ ! -z "$location_url" ]; then
    curl -L "$location_url" --output "$OPTIMIZED_FILE"

    # Поворот изображения в соответствии с ориентацией
    orientation=$(exiftool -s -s -s -Orientation "$SOURCE_FILE")
    echo '------------'
    echo $orientation
    echo '------------'

    if [ "$orientation" = "Rotate 90 CW" ]; then
        jpegtran -rotate 90 -copy all -outfile "$OPTIMIZED_FILE" "$OPTIMIZED_FILE"
        echo "Restored rotation"
    elif [ "$orientation" = "Rotate 270 CW" ]; then
        jpegtran -rotate 270 -copy all -outfile "$OPTIMIZED_FILE" "$OPTIMIZED_FILE"
        echo "Restored rotation"
    elif [ "$orientation" = "Rotate 180" ]; then
        jpegtran -rotate 180 -copy all -outfile "$OPTIMIZED_FILE" "$OPTIMIZED_FILE"
        echo "Restored rotation"
    fi


    # Восстанавливаем метаданные в оптимизированное изображение
    exiftool -overwrite_original -json="$METADATA_FILE" "$OPTIMIZED_FILE"
    # Удаление ориентации из метаданных (опционально)
    exiftool -overwrite_original -Orientation=Horizontal "$OPTIMIZED_FILE"

    touch -r "$SOURCE_FILE" "$OPTIMIZED_FILE"

    # Удаляем временный файл с метаданными
    rm "$METADATA_FILE"

    echo "Оптимизация завершена: $OPTIMIZED_FILE"
else
    echo "Не удалось извлечь URL из заголовка Location."
fi
