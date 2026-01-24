#!/bin/bash
# Check status and progress of all workers

STALE_THRESHOLD=${1:-300}  # 5 minutes default (matches worker timeout)

STATUS_DIR="/orchestration/status"

if [ ! -d "$STATUS_DIR" ] || [ -z "$(ls -A "$STATUS_DIR" 2>/dev/null)" ]; then
  echo "No worker status files found."
  exit 0
fi

echo "Worker Status"
echo "============="

NOW=$(date +%s)

for status_file in "$STATUS_DIR"/worker-*.json; do
  [ -f "$status_file" ] || continue

  TASK_ID=$(jq -r '.task_id' "$status_file")
  STATUS=$(jq -r '.status' "$status_file")
  STARTED=$(jq -r '.started_at // empty' "$status_file")
  LAST_ACTIVITY=$(jq -r '.last_activity // empty' "$status_file")
  PROGRESS=$(jq -r '.progress // "No progress info"' "$status_file")

  # Calculate time since last activity
  if [ -n "$LAST_ACTIVITY" ]; then
    ACTIVITY_TS=$(date -d "$LAST_ACTIVITY" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST_ACTIVITY%+*}" +%s 2>/dev/null || echo "$NOW")
    SINCE_ACTIVITY=$((NOW - ACTIVITY_TS))
  else
    SINCE_ACTIVITY=999999
  fi

  # Calculate duration
  if [ -n "$STARTED" ]; then
    STARTED_TS=$(date -d "$STARTED" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${STARTED%+*}" +%s 2>/dev/null || echo "$NOW")
    DURATION=$((NOW - STARTED_TS))
    DURATION_STR="${DURATION}s"
    if [ "$DURATION" -ge 60 ]; then
      DURATION_STR="$((DURATION / 60))m $((DURATION % 60))s"
    fi
  else
    DURATION_STR="unknown"
  fi

  # Determine status indicator
  if [ "$STATUS" = "success" ] || [ "$STATUS" = "completed" ]; then
    INDICATOR="✓"
    STATUS_STR="completed"
  elif [ "$STATUS" = "error" ] || [ "$STATUS" = "failed" ]; then
    INDICATOR="✗"
    STATUS_STR="failed"
  elif [ "$STATUS" = "timeout" ]; then
    INDICATOR="⏱"
    STATUS_STR="timeout (killed)"
  elif [ "$SINCE_ACTIVITY" -gt "$STALE_THRESHOLD" ]; then
    INDICATOR="⚠"
    STATUS_STR="stuck (${SINCE_ACTIVITY}s inactive)"
  else
    INDICATOR="●"
    STATUS_STR="running (${DURATION_STR})"
  fi

  echo ""
  echo "$INDICATOR $TASK_ID: $STATUS_STR"

  # Show progress for non-completed workers
  if [ "$STATUS" = "running" ]; then
    echo "  ├─ Last activity: ${SINCE_ACTIVITY}s ago"
    echo "  └─ Progress: $PROGRESS"
  fi
done

echo ""
echo "Legend: ✓=completed ●=running ⚠=stuck ⏱=timeout ✗=failed"
echo ""
echo "Workers auto-kill after 5 minutes of no activity."
