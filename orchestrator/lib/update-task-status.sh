#!/bin/bash
# Update a task's status in the plan
# Usage: update-task-status.sh <task-id> <status>

TASK_ID="$1"
STATUS="$2"
PLAN_FILE="/orchestration/plan.json"

if [ -z "$TASK_ID" ] || [ -z "$STATUS" ]; then
  echo "Usage: update-task-status.sh <task-id> <status>"
  echo "Status: pending, running, completed, failed"
  exit 1
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "Error: Plan file not found: $PLAN_FILE"
  exit 1
fi

# Update the status with file locking
LOCK_FILE="/orchestration/plan.lock"
(
  flock -w 10 200 || { echo "Warning: Could not acquire lock"; exit 1; }
  jq --arg id "$TASK_ID" --arg status "$STATUS" \
    '.tasks[$id].status = $status' "$PLAN_FILE" > "${PLAN_FILE}.tmp" \
    && mv "${PLAN_FILE}.tmp" "$PLAN_FILE"
) 200>"$LOCK_FILE"

echo "Updated $TASK_ID status to: $STATUS"
