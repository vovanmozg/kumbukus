#!/bin/bash

# requirement: vendor/jq

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <json file name>"
    exit 1
fi

input_file="$1"

if [ ! -f "$input_file" ]; then
    echo "File $input_file not found!"
    exit 1
fi

output_file="${input_file%.json}.formatted.json"

if jq . "$input_file" > "$output_file"; then
    echo "JSON file has been formatted and saved as $output_file"
else
    echo "Error formatting the JSON file. Please ensure the file contains valid JSON."
    exit 1
fi
