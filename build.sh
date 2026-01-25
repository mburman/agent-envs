#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building claude-flutter..."
docker build -t claude-flutter -f flutter/Dockerfile .

echo ""
echo "Done! Run with: ./run.sh --repo git@github.com:user/repo.git"
