#!/bin/bash
# Clean up orchestration state and/or workers
# Usage: cleanup.sh [--workers] [--state] [--all]

CLEAN_WORKERS=false
CLEAN_STATE=false

if [ $# -eq 0 ]; then
  echo "Usage: cleanup.sh [--workers] [--state] [--all]"
  echo ""
  echo "  --workers  Stop and remove all worker containers"
  echo "  --state    Clear orchestration state (tasks, results, plan)"
  echo "  --all      Both workers and state"
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --workers) CLEAN_WORKERS=true; shift ;;
    --state) CLEAN_STATE=true; shift ;;
    --all) CLEAN_WORKERS=true; CLEAN_STATE=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ "$CLEAN_WORKERS" = true ]; then
  echo "Stopping worker containers..."
  WORKERS=$(sudo docker ps -aq --filter "name=worker-" 2>/dev/null)
  if [ -n "$WORKERS" ]; then
    sudo docker rm -f $WORKERS
    echo "Removed workers."
  else
    echo "No workers running."
  fi
fi

if [ "$CLEAN_STATE" = true ]; then
  echo "Clearing orchestration state..."
  rm -f /orchestration/plan.json /orchestration/plan.lock
  rm -f /orchestration/tasks/*.json
  rm -f /orchestration/results/*.json /orchestration/results/*.patch
  rm -f /orchestration/status/*.json
  rm -f /orchestration/help-requests/*.json
  echo "State cleared."
fi

echo "Done."
