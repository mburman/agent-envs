#!/bin/bash
set -e

cd "$(dirname "$0")"

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
