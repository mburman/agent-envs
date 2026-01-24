#!/bin/bash
# Detect and optionally kill stuck workers based on heartbeat timestamps

STALE_THRESHOLD=${1:-120}  # Seconds before considering stuck (default: 2 minutes)
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
  HEARTBEAT=$(jq -r '.last_heartbeat // empty' "$status_file")

  # Skip completed workers
  if [ "$STATUS" = "success" ] || [ "$STATUS" = "completed" ] || [ "$STATUS" = "error" ] || [ "$STATUS" = "failed" ]; then
    continue
  fi

  # Calculate time since last heartbeat
  if [ -n "$HEARTBEAT" ]; then
    # Try GNU date first, then BSD date
    HEARTBEAT_TS=$(date -d "$HEARTBEAT" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${HEARTBEAT%+*}" +%s 2>/dev/null || echo "0")
    SINCE_HEARTBEAT=$((NOW - HEARTBEAT_TS))
  else
    SINCE_HEARTBEAT=999999
  fi

  # Check if stuck
  if [ "$SINCE_HEARTBEAT" -gt "$STALE_THRESHOLD" ]; then
    STUCK_COUNT=$((STUCK_COUNT + 1))
    CONTAINER_NAME="worker-${TASK_ID}"

    echo "⚠ STUCK: $TASK_ID (no heartbeat for ${SINCE_HEARTBEAT}s)"

    if [ "$DRY_RUN" = "kill" ]; then
      echo "  → Killing container: $CONTAINER_NAME"
      sudo docker kill "$CONTAINER_NAME" 2>/dev/null || echo "  → Container not running"

      # Update status to failed
      cat > "$status_file" << EOF
{
  "worker_id": "$CONTAINER_NAME",
  "task_id": "$TASK_ID",
  "status": "failed",
  "error": "Killed due to no heartbeat for ${SINCE_HEARTBEAT}s",
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
      echo "  → Would kill: sudo docker kill $CONTAINER_NAME"
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
