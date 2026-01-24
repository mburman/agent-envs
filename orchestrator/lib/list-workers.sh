#!/bin/bash
# List running worker containers and their status
# Usage: list-workers.sh

echo ""
echo "Running Workers:"
echo "────────────────────────────────────────────────────────"

WORKERS=$(sudo docker ps --filter "name=worker-" --format "{{.Names}}\t{{.Status}}\t{{.RunningFor}}" 2>/dev/null)

if [ -z "$WORKERS" ]; then
  echo "  No workers currently running."
else
  printf "  %-20s %-20s %s\n" "CONTAINER" "STATUS" "RUNNING"
  echo "  ────────────────────────────────────────────────────"
  echo "$WORKERS" | while IFS=$'\t' read -r name status running; do
    printf "  %-20s %-20s %s\n" "$name" "$status" "$running"
  done
fi

echo ""

# Also show recently exited workers
EXITED=$(sudo docker ps -a --filter "name=worker-" --filter "status=exited" --format "{{.Names}}\t{{.Status}}" 2>/dev/null | head -5)
if [ -n "$EXITED" ]; then
  echo "Recently Exited:"
  echo "────────────────────────────────────────────────────────"
  echo "$EXITED" | while IFS=$'\t' read -r name status; do
    printf "  %-20s %s\n" "$name" "$status"
  done
  echo ""
fi
