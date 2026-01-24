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
  STARTED_AT="$(date -Iseconds)"

  # Write initial status
  cat > "$STATUS_FILE" << EOF
{
  "worker_id": "worker-${TASK_ID}",
  "task_id": "$TASK_ID",
  "status": "running",
  "started_at": "$STARTED_AT",
  "last_heartbeat": "$STARTED_AT"
}
EOF

  # Start heartbeat process in background (updates every 30 seconds)
  (
    while true; do
      sleep 30
      if [ -f "$STATUS_FILE" ]; then
        # Update heartbeat timestamp
        HEARTBEAT="$(date -Iseconds)"
        jq --arg hb "$HEARTBEAT" '.last_heartbeat = $hb' "$STATUS_FILE" > "${STATUS_FILE}.tmp" 2>/dev/null \
          && mv "${STATUS_FILE}.tmp" "$STATUS_FILE" 2>/dev/null || true
      else
        # Status file gone, stop heartbeat
        break
      fi
    done
  ) &
  HEARTBEAT_PID=$!

  # Run Claude headlessly and capture output
  echo "Running Claude with prompt..."
  set +e  # Don't exit on error
  OUTPUT=$(claude -p "$PROMPT" --dangerously-skip-permissions 2>&1)
  EXIT_CODE=$?
  set -e

  # Stop heartbeat process
  kill $HEARTBEAT_PID 2>/dev/null || true

  # Determine status based on exit code
  if [ $EXIT_CODE -eq 0 ]; then
    STATUS="success"
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
  cat > "$STATUS_FILE" << EOF
{
  "worker_id": "worker-${TASK_ID}",
  "task_id": "$TASK_ID",
  "status": "$STATUS",
  "started_at": "$STARTED_AT",
  "completed_at": "$COMPLETED_AT",
  "last_heartbeat": "$COMPLETED_AT"
}
EOF

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
