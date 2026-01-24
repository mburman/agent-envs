#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building claude-orchestrator..."
docker build -t claude-orchestrator -f orchestrator/Dockerfile .

echo ""
echo "Done! Run with: ./run.sh --repo git@github.com:user/repo.git"
