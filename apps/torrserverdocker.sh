#!/bin/bash

# requirement: vendor/docker

docker run --rm -d --name torrserver -p 8090:8090 ghcr.io/yourok/torrserver:latest