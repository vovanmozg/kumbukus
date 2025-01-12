#!/bin/bash

# requirement: vendor/imagemagick

source ~/.env

# Проверка на наличие аргумента (имя файла PDF)
if [ "$#" -lt 1 ]; then
    echo "Using: $0 file_name.pdf [--compress=<value>] [--width=<value>]"
    exit 1
fi

SOURCE_PDF="$1"
COMPRESS_LEVEL= # По умолчанию нет значения
WIDTH=

# Чтение дополнительных параметров
for arg in "$@"
do
    case $arg in
        --compress=*)
            COMPRESS_LEVEL="${arg#*=}"
            shift
            ;;
        --width=*)
            WIDTH="${arg#*=}"
            shift
            ;;
        *)
            ;;
    esac
done

#OPTIMIZED_FILE="${SOURCE_PDF%.pdf}optimized.pdf"
OPTIMIZED_DIR=$(dirname "$SOURCE_PDF")/optimized
mkdir "${OPTIMIZED_DIR}"
OPTIMIZED_FILE="$OPTIMIZED_DIR/$(basename "${SOURCE_PDF}")"

touch "${OPTIMIZED_FILE}.tmp"

# Получение CRC32 хэша от имени файла

FILE_NAME=$(basename "$SOURCE_PDF" .pdf)
FILE_HASH=$(echo -n "$FILE_NAME" | cksum | awk '{print $1}')
echo "для ${FILE_NAME} хэш будет ${FILE_HASH}" >> $LOG_FILE
TEMP_DIR="/tmp/pdfcompress/$(date +%s)_${FILE_HASH}"
LOG_FILE="${TEMP_DIR}/log.txt"

mkdir -p "$TEMP_DIR"

# Извлечение изображений из PDF
echo "Извлечение изображений..." >> $LOG_FILE
pdfimages -all "$SOURCE_PDF" "$TEMP_DIR/img"

# Проверка на существование извлечённых изображений
if [ ! "$(ls -A $TEMP_DIR | grep img)" ]; then
    echo "Изображения не найдены в PDF." >> $LOG_FILE
    rm -rf "$TEMP_DIR"
    rm "${OPTIMIZED_FILE}.tmp"
    exit 1
fi

# Оптимизация изображений
for img in "$TEMP_DIR"/img*; do
    OUTPUT_IMG="$img"
    
    # Если передан параметр compress, сжимаем через jpegoptim
    if [ ! -z "$COMPRESS_LEVEL" ]; then
        jpegoptim --max="$COMPRESS_LEVEL" --strip-all --preserve-perms "$img"
    fi

    # Если передан параметр width, изменяем размер
    if [ ! -z "$WIDTH" ]; then
        mogrify -resize "${WIDTH}x" "$img"
    fi

    # Сжатие через tinify
    echo "Сжатие через tinify..." >> $LOG_FILE
    response=$(curl --user api:$TINYPNG_API_KEY --dump-header /dev/stdout --data-binary @"$img" https://api.tinify.com/shrink)

    location_url=$(echo "$response" | grep -i Location: | awk '{print $2}' | tr -d '\r')

    if [ ! -z "$location_url" ]; then
        curl -L "$location_url" --output "$OUTPUT_IMG" >> $LOG_FILE
    else
        echo "Не удалось сжать изображение $img" >> $LOG_FILE
    fi
done

# Создание нового PDF из сжатых изображений
echo "Создание нового PDF..." >> $LOG_FILE
convert "$TEMP_DIR"/img* "${OPTIMIZED_FILE}"

# Удаление временных файлов
rm -rf "$TEMP_DIR"
rm "${OPTIMIZED_FILE}.tmp"

echo "Сжатие PDF завершено. Файл создан: ${SOURCE_PDF%.pdf}_optimized.pdf" >> $LOG_FILE
