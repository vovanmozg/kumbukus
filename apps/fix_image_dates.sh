#!/bin/bash

if ! command -v docker &>/dev/null; then
  echo "Error: Docker is not installed. Please install Docker and try again."
  exit 1
fi

if ! docker image inspect vovan/media_tools &>/dev/null; then
  echo "The Docker image 'vovan/media_tools' is not found. Pulling the image..."
  docker pull vovan/media_tools
  if [ $? -ne 0 ]; then
    echo "Error: Failed to pull the image. Please check your internet connection or the image name."
    exit 1
  fi
fi

if [ -z "$1" ]; then
  echo "Error: Please specify the folder path as the first argument."
  echo "Usage: $0 <dir_path>"
  exit 1
fi

FOLDER_PATH=$1

docker run --rm --name media_tools -u=$UID:$UID -v "$FOLDER_PATH":/app/media vovan/media_tools ruby ./fix-dates.rb
