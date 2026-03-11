#!/bin/bash

# Merge all PDF files from a directory into a single PDF.
# Usage: mergepdf.sh <directory>
# Output: <parent_dir>/<directory_name>.pdf
# Files are sorted by name. Use filename prefixes (01_, 02_, ...) to control order.
#
# requirement: vendor/poppler-utils (pdfunite)

if [ "$#" -ne 1 ]; then
    echo "Using: $0 <directory>"
    exit 1
fi

directory="$1"

if [ ! -d "$directory" ]; then
    echo "Directory does not exist: $directory"
    exit 1
fi

readarray -t files < <(find "$directory" -maxdepth 1 -type f -iname "*.pdf" | sort)

if [ ${#files[@]} -eq 0 ]; then
    echo "No PDF files found"
    exit 0
fi

dirpath=$(dirname "$directory")
base_dirname=$(basename "$directory")

pdfunite "${files[@]}" "${dirpath}/${base_dirname}.pdf"
