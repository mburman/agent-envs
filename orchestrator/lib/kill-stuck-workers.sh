#!/bin/bash
# Detect and optionally kill stuck workers based on activity timestamps
# Note: Workers auto-kill after 5 minutes of inactivity, but this script
# can be used to manually kill workers earlier.

STALE_THRESHOLD=${1:-180}  # Seconds before considering stuck (default: 3 minutes)
DRY_RUN=${2:-false}        # Set to "kill" to actually kill workers

STATUS_DIR="/orchestration/status"

if [ ! -d "$STATUS_DIR" ] || [ -z "$(ls -A "$STATUS_DIR" 2>/dev/null)" ]; then
  echo "No worker status files found."
  exit 0
fi

NOW=$(date +%s)
STUCK_COUNT=0

echo "Checking for stuck workers (threshold: ${STALE_THRESHOLD}s)..."
echo ""

for status_file in "$STATUS_DIR"/worker-*.json; do
  [ -f "$status_file" ] || continue

  TASK_ID=$(jq -r '.task_id' "$status_file")
  STATUS=$(jq -r '.status' "$status_file")
  LAST_ACTIVITY=$(jq -r '.last_activity // .last_heartbeat // empty' "$status_file")

  # Skip completed/failed/timeout workers
  if [ "$STATUS" = "success" ] || [ "$STATUS" = "completed" ] || [ "$STATUS" = "error" ] || [ "$STATUS" = "failed" ] || [ "$STATUS" = "timeout" ]; then
    continue
  fi

  # Calculate time since last activity
  if [ -n "$LAST_ACTIVITY" ]; then
    # Try GNU date first, then BSD date
    ACTIVITY_TS=$(date -d "$LAST_ACTIVITY" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST_ACTIVITY%+*}" +%s 2>/dev/null || echo "0")
    SINCE_ACTIVITY=$((NOW - ACTIVITY_TS))
  else
    SINCE_ACTIVITY=999999
  fi

  # Check if stuck
  if [ "$SINCE_ACTIVITY" -gt "$STALE_THRESHOLD" ]; then
    STUCK_COUNT=$((STUCK_COUNT + 1))
    CONTAINER_NAME="worker-${TASK_ID}"

    echo "⚠ STUCK: $TASK_ID (no heartbeat for ${SINCE_ACTIVITY}s)"

    if [ "$DRY_RUN" = "kill" ]; then
      echo "  → Killing container: $CONTAINER_NAME"
      sudo /usr/bin/docker kill "$CONTAINER_NAME" 2>/dev/null || echo "  → Container not running"

      # Update status to failed
      cat > "$status_file" << EOF
{
  "worker_id": "$CONTAINER_NAME",
  "task_id": "$TASK_ID",
  "status": "failed",
  "error": "Killed due to no heartbeat for ${SINCE_ACTIVITY}s",
  "killed_at": "$(date -Iseconds)"
}
EOF

      # Update plan status
      PLAN_FILE="/orchestration/plan.json"
      LOCK_FILE="/orchestration/plan.lock"
      if [ -f "$PLAN_FILE" ]; then
        (
          flock -w 10 200 || exit 0
          jq --arg id "$TASK_ID" '.tasks[$id].status = "failed"' "$PLAN_FILE" > "${PLAN_FILE}.tmp" \
            && mv "${PLAN_FILE}.tmp" "$PLAN_FILE"
        ) 200>"$LOCK_FILE"
      fi
    else
      echo "  → Would kill: sudo /usr/bin/docker kill $CONTAINER_NAME"
    fi
  fi
done

echo ""
if [ "$STUCK_COUNT" -eq 0 ]; then
  echo "No stuck workers found."
else
  echo "Found $STUCK_COUNT stuck worker(s)."
  if [ "$DRY_RUN" != "kill" ]; then
    echo ""
    echo "To kill stuck workers, run:"
    echo "  /opt/orchestrator/lib/kill-stuck-workers.sh $STALE_THRESHOLD kill"
  fi
fi
