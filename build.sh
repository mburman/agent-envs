#!/bin/bash
set -e

cd "$(dirname "$0")"

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: ./build.sh [OPTIONS]"
    echo ""
    echo "Build the claude-flutter Docker image."
    echo ""
    echo "Options:"
    echo "  --no-cache    Force rebuild without using Docker cache"
    echo "  --help, -h    Show this help message"
    exit 0
fi

DOCKER_ARGS=""

if [[ "$1" == "--no-cache" ]]; then
    DOCKER_ARGS="--no-cache"
    echo "Building claude-flutter (no cache)..."
else
    echo "Building claude-flutter..."
fi

docker build $DOCKER_ARGS -t claude-flutter -f flutter/Dockerfile .

echo ""
echo "Done! Run with: ./run.sh --repo git@github.com:user/repo.git"
