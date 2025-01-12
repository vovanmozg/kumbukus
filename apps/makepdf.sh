#!/bin/bash

# requirement: vendor/imagemagick

if [ "$#" -ne 1 ]; then
    echo "Using: $0 <directory>"
    exit 1
fi

directory="$1"

if [ ! -d "$directory" ]; then
    echo "Directory does not exists: $directory"
    exit 1
fi

readarray -t files < <(find "$directory" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" \) | sort)

if [ ${#files[@]} -eq 0 ]; then
    echo "Files not found"
    exit 0
fi

cd "$directory"

dirpath=$(dirname "$directory")
base_dirname=$(basename "$directory")

cmd="convert"
for file in "${files[@]}"; do
    cmd+=" \"$file\""
done
cmd+=" \"${dirpath}/${base_dirname}.pdf\""

eval $cmd


