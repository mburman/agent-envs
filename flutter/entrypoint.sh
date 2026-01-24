#!/bin/bash
set -e

if [ -z "$REPO_URL" ]; then
  echo "Error: REPO_URL environment variable is required"
  echo "Usage: docker run -e REPO_URL=git@github.com:user/repo.git ..."
  exit 1
fi

# Set up git user config if provided
if [ -n "$GIT_USER_NAME" ]; then
  git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
  git config --global user.email "$GIT_USER_EMAIL"
fi

echo "Cloning $REPO_URL (branch: $REPO_BRANCH)..."
git clone --branch "$REPO_BRANCH" --single-branch "$REPO_URL" /app

cd /app

# In worker mode, block git commit and push (only Manager can do that)
if [ "$WORKER_MODE" = "true" ]; then
  echo "Worker mode: installing git hooks to block commits/pushes..."
  mkdir -p .git/hooks

  cat > .git/hooks/pre-commit << 'HOOK'
#!/bin/bash
echo "ERROR: Workers cannot commit. Only the Manager can commit code."
echo "Your changes are saved in the working directory."
exit 1
HOOK

  cat > .git/hooks/pre-push << 'HOOK'
#!/bin/bash
echo "ERROR: Workers cannot push. Only the Manager can push code."
exit 1
HOOK

  chmod +x .git/hooks/pre-commit .git/hooks/pre-push
fi

echo "Installing dependencies..."
flutter pub get

# Install dependencies for any subdirectory with a pubspec.yaml (monorepo support)
find . -mindepth 2 -name "pubspec.yaml" -type f | while read pubspec; do
  dir=$(dirname "$pubspec")
  echo "Installing dependencies for $dir..."
  (cd "$dir" && dart pub get)
done

# Set up Claude config to skip onboarding and enable bypass permissions mode
mkdir -p ~/.claude
cat > ~/.claude.json <<'EOF'
{
  "hasCompletedOnboarding": true
}
EOF

# Set bypass permissions in settings to avoid the warning dialog
cat > ~/.claude/settings.json <<'EOF'
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
EOF

# Set default model to Opus (can be overridden via ANTHROPIC_MODEL env var)
export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-opus-4-5-20251101}"

# Worker mode: run headlessly with task from orchestration volume
if [ "$WORKER_MODE" = "true" ]; then
  if [ -z "$TASK_ID" ]; then
    echo "Error: TASK_ID is required in worker mode"
    exit 1
  fi

  TASK_FILE="/orchestration/tasks/${TASK_ID}.json"
  if [ ! -f "$TASK_FILE" ]; then
    echo "Error: Task file not found: $TASK_FILE"
    exit 1
  fi

  echo "Worker mode: executing task $TASK_ID"

  # Extract prompt from task file
  PROMPT=$(jq -r '.prompt' "$TASK_FILE")

  STATUS_FILE="/orchestration/status/worker-${TASK_ID}.json"
  OUTPUT_FILE="/orchestration/status/worker-${TASK_ID}.output"
  STARTED_AT="$(date -Iseconds)"
  TIMEOUT_SECONDS=300  # 5 minutes

  # Write initial status
  cat > "$STATUS_FILE" << EOF
{
  "worker_id": "worker-${TASK_ID}",
  "task_id": "$TASK_ID",
  "status": "running",
  "started_at": "$STARTED_AT",
  "last_activity": "$STARTED_AT",
  "progress": "Starting task..."
}
EOF

  # Initialize output file
  echo "" > "$OUTPUT_FILE"
  LAST_SIZE=0

  # Start progress monitor in background (checks every 60 seconds)
  (
    while true; do
      sleep 60

      if [ ! -f "$STATUS_FILE" ]; then
        break  # Status file gone, stop monitoring
      fi

      # Check if output file has grown (activity detected)
      if [ -f "$OUTPUT_FILE" ]; then
        CURRENT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null || echo "0")
      else
        CURRENT_SIZE=0
      fi

      NOW=$(date +%s)
      LAST_ACTIVITY_TS=$(jq -r '.last_activity // empty' "$STATUS_FILE" 2>/dev/null)
      if [ -n "$LAST_ACTIVITY_TS" ]; then
        LAST_TS=$(date -d "$LAST_ACTIVITY_TS" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST_ACTIVITY_TS%+*}" +%s 2>/dev/null || echo "$NOW")
      else
        LAST_TS=$NOW
      fi

      if [ "$CURRENT_SIZE" -gt "$LAST_SIZE" ]; then
        # Activity detected - update progress
        LAST_SIZE=$CURRENT_SIZE
        ACTIVITY_TIME="$(date -Iseconds)"

        # Get last meaningful line from output (skip empty lines)
        LAST_LINE=$(tail -20 "$OUTPUT_FILE" 2>/dev/null | grep -v '^$' | tail -1 | cut -c1-100 || echo "Working...")

        # Escape for JSON
        LAST_LINE=$(echo "$LAST_LINE" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n\r')

        jq --arg activity "$ACTIVITY_TIME" --arg progress "$LAST_LINE" \
          '.last_activity = $activity | .progress = $progress' \
          "$STATUS_FILE" > "${STATUS_FILE}.tmp" 2>/dev/null \
          && mv "${STATUS_FILE}.tmp" "$STATUS_FILE" 2>/dev/null || true

        echo "$LAST_SIZE" > "/tmp/worker-${TASK_ID}-size"
      else
        # No activity - check if timed out
        INACTIVE_SECONDS=$((NOW - LAST_TS))
        if [ "$INACTIVE_SECONDS" -ge "$TIMEOUT_SECONDS" ]; then
          echo "TIMEOUT: No activity for ${INACTIVE_SECONDS}s (threshold: ${TIMEOUT_SECONDS}s)"

          # Update status to timeout
          jq '.status = "timeout" | .progress = "Killed: no activity for 5 minutes"' \
            "$STATUS_FILE" > "${STATUS_FILE}.tmp" 2>/dev/null \
            && mv "${STATUS_FILE}.tmp" "$STATUS_FILE" 2>/dev/null || true

          # Kill the Claude process
          pkill -f "claude -p" 2>/dev/null || true
          break
        fi
      fi
    done
  ) &
  MONITOR_PID=$!

  # Store last size for monitor
  echo "0" > "/tmp/worker-${TASK_ID}-size"

  # Run Claude headlessly and stream output to file
  echo "Running Claude with prompt..."
  set +e  # Don't exit on error
  claude -p "$PROMPT" --dangerously-skip-permissions 2>&1 | tee "$OUTPUT_FILE"
  EXIT_CODE=${PIPESTATUS[0]}
  set -e

  # Read captured output
  OUTPUT=$(cat "$OUTPUT_FILE" 2>/dev/null || echo "")

  # Stop monitor process
  kill $MONITOR_PID 2>/dev/null || true

  # Check if we were killed due to timeout
  FINAL_STATUS=$(jq -r '.status' "$STATUS_FILE" 2>/dev/null || echo "")
  if [ "$FINAL_STATUS" = "timeout" ]; then
    EXIT_CODE=124  # Timeout exit code
  fi

  # Determine status based on exit code
  if [ $EXIT_CODE -eq 0 ]; then
    STATUS="success"
  elif [ $EXIT_CODE -eq 124 ]; then
    STATUS="timeout"
  else
    STATUS="error"
  fi

  # Capture git diff of all changes (for Manager to review/apply)
  DIFF=$(git diff 2>/dev/null || echo "")
  UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | head -20 || echo "")

  # Save patch file for easy application
  # First, add all changes to staging to get a complete diff (including new files)
  PATCH_FILE="/orchestration/results/${TASK_ID}.patch"
  git add -A 2>/dev/null || true
  git diff --cached > "$PATCH_FILE" 2>/dev/null || true
  # Reset staging so we don't leave the repo in a weird state
  git reset HEAD 2>/dev/null || true

  # Write result
  RESULT_FILE="/orchestration/results/${TASK_ID}.json"
  jq -n \
    --arg task_id "$TASK_ID" \
    --arg status "$STATUS" \
    --arg output "$OUTPUT" \
    --arg diff "$DIFF" \
    --arg untracked "$UNTRACKED" \
    --arg patch_file "/orchestration/results/${TASK_ID}.patch" \
    --arg completed_at "$(date -Iseconds)" \
    '{
      task_id: $task_id,
      status: $status,
      output: $output,
      diff: $diff,
      untracked_files: $untracked,
      patch_file: $patch_file,
      completed_at: $completed_at
    }' > "$RESULT_FILE"

  # Update status file with completion info
  COMPLETED_AT="$(date -Iseconds)"
  if [ "$STATUS" = "timeout" ]; then
    FINAL_PROGRESS="Killed: no activity for 5 minutes"
  else
    FINAL_PROGRESS="Completed"
  fi
  cat > "$STATUS_FILE" << EOF
{
  "worker_id": "worker-${TASK_ID}",
  "task_id": "$TASK_ID",
  "status": "$STATUS",
  "started_at": "$STARTED_AT",
  "completed_at": "$COMPLETED_AT",
  "last_activity": "$COMPLETED_AT",
  "progress": "$FINAL_PROGRESS"
}
EOF

  # Clean up output file
  rm -f "$OUTPUT_FILE" "/tmp/worker-${TASK_ID}-size"

  # Update plan status (if plan exists) with file locking to prevent race conditions
  PLAN_FILE="/orchestration/plan.json"
  LOCK_FILE="/orchestration/plan.lock"
  if [ -f "$PLAN_FILE" ]; then
    if [ "$STATUS" = "success" ]; then
      PLAN_STATUS="completed"
    else
      PLAN_STATUS="failed"
    fi
    # Use flock for atomic updates (wait up to 10 seconds for lock)
    (
      flock -w 10 200 || { echo "Warning: Could not acquire lock for plan update"; exit 0; }
      jq --arg id "$TASK_ID" --arg status "$PLAN_STATUS" \
        '.tasks[$id].status = $status' "$PLAN_FILE" > "${PLAN_FILE}.tmp" \
        && mv "${PLAN_FILE}.tmp" "$PLAN_FILE"
    ) 200>"$LOCK_FILE"
  fi

  echo "Task $TASK_ID completed with status: $STATUS"
  echo "Result written to: $RESULT_FILE"
  exit $EXIT_CODE
fi

# Interactive mode (default)
echo "Starting Claude Code with model: $ANTHROPIC_MODEL..."
# Use expect to auto-accept the bypass permissions warning, then hand over to interactive mode
exec /start-claude.exp "$@"
