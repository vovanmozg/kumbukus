#!/bin/bash

# requirement: vendor/imagemagick
#
# Make a PDF from images.
#   makepdf.sh <directory>    combine *.jpg/*.png in the folder into <directory>.pdf
#   makepdf.sh <image-file>   convert a single image into <name>.pdf next to it
# Output is written next to the input and never overwrites: if the target
# exists, <base>-1.pdf, <base>-2.pdf, ... is used instead.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Using: $0 <image-file-or-directory>"
    exit 1
fi

arg="$1"

if [ -d "$arg" ]; then
    readarray -t imgs < <(find "$arg" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" \) | sort)
    if [ ${#imgs[@]} -eq 0 ]; then
        echo "No images found in $arg"
        exit 0
    fi
    out_dir=$(dirname "$arg")
    out_name=$(basename "$arg")
elif [ -f "$arg" ]; then
    imgs=("$arg")
    out_dir=$(dirname "$arg")
    out_name=$(basename "${arg%.*}")
else
    echo "Not a file or directory: $arg"
    exit 1
fi

# Pick an unused output name, then convert.
out="$out_dir/$out_name.pdf"
i=1
while [ -e "$out" ]; do
    out="$out_dir/$out_name-$i.pdf"
    i=$((i + 1))
done

convert "${imgs[@]}" "$out"
