#!/bin/bash
# Check status and progress of all workers (sub-agents in worktrees)
# Usage: check-workers.sh [stale-threshold-seconds]

STALE_THRESHOLD=${1:-300}  # 5 minutes default

ORCHESTRATION_DIR="${ORCHESTRATION_DIR:-/orchestration}"
STATUS_DIR="${ORCHESTRATION_DIR}/status"
RESULTS_DIR="${ORCHESTRATION_DIR}/results"
WORKTREE_BASE=".worktrees"

if [ ! -d "$STATUS_DIR" ] || [ -z "$(ls -A "$STATUS_DIR" 2>/dev/null | grep -v '.last-spawn')" ]; then
  echo "No worker status files found."
  echo ""
  echo "To spawn a worker:"
  echo "  1. Create task file: /orchestration/tasks/task-001.json"
  echo "  2. Run: /opt/orchestrator/lib/spawn-worker.sh task-001"
  echo "  3. Use Task tool to spawn sub-agent in worktree"
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
  WORKTREE=$(jq -r '.worktree // empty' "$status_file")

  # Check if result file exists (indicates completion)
  RESULT_FILE="${RESULTS_DIR}/${TASK_ID}.json"
  if [ -f "$RESULT_FILE" ]; then
    RESULT_STATUS=$(jq -r '.status // "unknown"' "$RESULT_FILE")
    if [ "$RESULT_STATUS" = "success" ] || [ "$RESULT_STATUS" = "no_changes" ]; then
      STATUS="completed"
    elif [ "$RESULT_STATUS" = "error" ]; then
      STATUS="failed"
    fi
  fi

  # Check if worktree exists
  WORKTREE_EXISTS=false
  if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
    WORKTREE_EXISTS=true
  fi

  # Calculate time since last activity
  if [ -n "$LAST_ACTIVITY" ]; then
    # Try GNU date first, then BSD date
    ACTIVITY_TS=$(date -d "$LAST_ACTIVITY" +%s 2>/dev/null || \
                  date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_ACTIVITY" +%s 2>/dev/null || \
                  echo "$NOW")
    SINCE_ACTIVITY=$((NOW - ACTIVITY_TS))
  else
    SINCE_ACTIVITY=999999
  fi

  # Calculate duration
  if [ -n "$STARTED" ]; then
    STARTED_TS=$(date -d "$STARTED" +%s 2>/dev/null || \
                 date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED" +%s 2>/dev/null || \
                 echo "$NOW")
    DURATION=$((NOW - STARTED_TS))
    if [ "$DURATION" -ge 3600 ]; then
      DURATION_STR="$((DURATION / 3600))h $((DURATION % 3600 / 60))m"
    elif [ "$DURATION" -ge 60 ]; then
      DURATION_STR="$((DURATION / 60))m $((DURATION % 60))s"
    else
      DURATION_STR="${DURATION}s"
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
    STATUS_STR="timeout"
  elif [ "$STATUS" = "no_changes" ]; then
    INDICATOR="○"
    STATUS_STR="no changes"
  elif [ "$SINCE_ACTIVITY" -gt "$STALE_THRESHOLD" ] && [ "$WORKTREE_EXISTS" = true ]; then
    INDICATOR="⚠"
    STATUS_STR="possibly stuck (${SINCE_ACTIVITY}s inactive)"
  elif [ "$WORKTREE_EXISTS" = true ]; then
    INDICATOR="●"
    STATUS_STR="running (${DURATION_STR})"
  else
    INDICATOR="?"
    STATUS_STR="unknown (worktree missing)"
  fi

  echo ""
  echo "$INDICATOR $TASK_ID: $STATUS_STR"

  # Show additional info for running/stuck workers
  if [ "$STATUS" = "running" ] || [ "$STATUS" = "pending" ]; then
    if [ "$WORKTREE_EXISTS" = true ]; then
      echo "  ├─ Worktree: $WORKTREE"
      echo "  ├─ Last activity: ${SINCE_ACTIVITY}s ago"
      echo "  └─ Progress: $PROGRESS"
    fi
  fi

  # Show result file location for completed
  if [ "$STATUS" = "completed" ] || [ "$STATUS" = "success" ]; then
    if [ -f "${RESULTS_DIR}/${TASK_ID}.patch" ]; then
      PATCH_SIZE=$(wc -c < "${RESULTS_DIR}/${TASK_ID}.patch" 2>/dev/null | tr -d ' ')
      echo "  └─ Patch: ${RESULTS_DIR}/${TASK_ID}.patch (${PATCH_SIZE} bytes)"
    fi
  fi
done

echo ""
echo "Legend: ✓=completed ●=running ○=no changes ⚠=stuck ⏱=timeout ✗=failed"
echo ""
echo "To collect results: /opt/orchestrator/lib/worktree/collect-patch.sh <task-id>"
echo "To apply patch: git apply /orchestration/results/<task-id>.patch"
