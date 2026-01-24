#!/bin/bash
# Check health of all workers based on heartbeat timestamps

STALE_THRESHOLD=${1:-60}  # Seconds before considering a worker stuck (default: 60)

STATUS_DIR="/orchestration/status"

if [ ! -d "$STATUS_DIR" ] || [ -z "$(ls -A "$STATUS_DIR" 2>/dev/null)" ]; then
  echo "No worker status files found."
  exit 0
fi

echo "Worker Status (stale threshold: ${STALE_THRESHOLD}s)"
echo "=================================================="

NOW=$(date +%s)

for status_file in "$STATUS_DIR"/worker-*.json; do
  [ -f "$status_file" ] || continue

  TASK_ID=$(jq -r '.task_id' "$status_file")
  STATUS=$(jq -r '.status' "$status_file")
  STARTED=$(jq -r '.started_at // empty' "$status_file")
  HEARTBEAT=$(jq -r '.last_heartbeat // empty' "$status_file")
  COMPLETED=$(jq -r '.completed_at // empty' "$status_file")

  # Calculate time since last heartbeat
  if [ -n "$HEARTBEAT" ]; then
    HEARTBEAT_TS=$(date -d "$HEARTBEAT" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${HEARTBEAT%+*}" +%s 2>/dev/null || echo "0")
    SINCE_HEARTBEAT=$((NOW - HEARTBEAT_TS))
  else
    SINCE_HEARTBEAT=999999
  fi

  # Determine health indicator
  if [ "$STATUS" = "success" ] || [ "$STATUS" = "completed" ]; then
    INDICATOR="✓"
    HEALTH="completed"
  elif [ "$STATUS" = "error" ] || [ "$STATUS" = "failed" ]; then
    INDICATOR="✗"
    HEALTH="failed"
  elif [ "$SINCE_HEARTBEAT" -gt "$STALE_THRESHOLD" ]; then
    INDICATOR="⚠"
    HEALTH="stuck (${SINCE_HEARTBEAT}s since heartbeat)"
  else
    INDICATOR="●"
    HEALTH="alive (${SINCE_HEARTBEAT}s ago)"
  fi

  echo "$INDICATOR $TASK_ID: $HEALTH"

  # Show timing details for running workers
  if [ "$STATUS" = "running" ]; then
    if [ -n "$STARTED" ]; then
      STARTED_TS=$(date -d "$STARTED" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${STARTED%+*}" +%s 2>/dev/null || echo "0")
      DURATION=$((NOW - STARTED_TS))
      echo "  └─ running for ${DURATION}s"
    fi
  fi
done

echo ""
echo "Legend: ✓=completed ●=alive ⚠=stuck ✗=failed"
