#!/bin/bash
# Prepare a worktree for a worker sub-agent
# Usage: spawn-worker.sh <task-id>
#
# This script creates the worktree and prints instructions for spawning
# the sub-agent using Claude's Task tool.

set -e

TASK_ID="$1"

if [ -z "$TASK_ID" ]; then
  echo "Usage: spawn-worker.sh <task-id>"
  echo "Example: spawn-worker.sh task-001"
  exit 1
fi

# Paths
ORCHESTRATION_DIR="${ORCHESTRATION_DIR:-/orchestration}"
# Use worktree script from orchestrator lib (inside container)
WORKTREE_SCRIPT="/opt/orchestrator/lib/worktree/create-worktree.sh"
# Or from repo lib (outside container)
[ -f "./lib/worktree/create-worktree.sh" ] && WORKTREE_SCRIPT="./lib/worktree/create-worktree.sh"
TASK_FILE="${ORCHESTRATION_DIR}/tasks/${TASK_ID}.json"
WORKTREE_DIR=".worktrees/${TASK_ID}"

# Validate task file exists
if [ ! -f "$TASK_FILE" ]; then
  echo "Error: Task file not found: $TASK_FILE"
  echo "Create it first:"
  echo "  cat > $TASK_FILE << 'EOF'"
  echo '{"id":"'$TASK_ID'","prompt":"Your task description..."}'
  echo "EOF"
  exit 1
fi

# Read task prompt
TASK_PROMPT=$(jq -r '.prompt' "$TASK_FILE")
if [ -z "$TASK_PROMPT" ] || [ "$TASK_PROMPT" = "null" ]; then
  echo "Error: Task file missing 'prompt' field"
  exit 1
fi

# Create the worktree
echo "Creating worktree for $TASK_ID..."
if [ -f "$WORKTREE_SCRIPT" ]; then
  "$WORKTREE_SCRIPT" "$TASK_ID"
else
  # Fallback: inline worktree creation
  mkdir -p .worktrees

  # Stash if dirty
  if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo "Stashing uncommitted changes..."
    git stash push -m "worktree-auto-stash-${TASK_ID}" --include-untracked
    echo "$TASK_ID" >> .worktrees/.stash-marker
  fi

  # Create branch and worktree
  git branch "worker/${TASK_ID}" HEAD 2>/dev/null || true
  git worktree add "$WORKTREE_DIR" "worker/${TASK_ID}"

  # Install git hooks
  WORKTREE_GIT_DIR=$(git -C "$WORKTREE_DIR" rev-parse --git-dir)
  mkdir -p "${WORKTREE_GIT_DIR}/hooks"

  cat > "${WORKTREE_GIT_DIR}/hooks/pre-commit" << 'HOOK'
#!/bin/bash
echo "ERROR: Workers cannot commit."
exit 1
HOOK

  cat > "${WORKTREE_GIT_DIR}/hooks/pre-push" << 'HOOK'
#!/bin/bash
echo "ERROR: Workers cannot push."
exit 1
HOOK

  chmod +x "${WORKTREE_GIT_DIR}/hooks/pre-commit" "${WORKTREE_GIT_DIR}/hooks/pre-push"
fi

# Update plan status to running (if plan exists)
PLAN_FILE="${ORCHESTRATION_DIR}/plan.json"
if [ -f "$PLAN_FILE" ]; then
  /opt/orchestrator/lib/update-task-status.sh "$TASK_ID" running 2>/dev/null || true
fi

# Write status file
mkdir -p "${ORCHESTRATION_DIR}/status"
cat > "${ORCHESTRATION_DIR}/status/worker-${TASK_ID}.json" << EOF
{
  "task_id": "$TASK_ID",
  "status": "pending",
  "worktree": "$WORKTREE_DIR",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_activity": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Output instructions for the Manager
echo ""
echo "=========================================="
echo "Worktree ready: $WORKTREE_DIR"
echo "=========================================="
echo ""
echo "Now spawn a sub-agent using the Task tool:"
echo ""
echo "  Task tool parameters:"
echo "    subagent_type: task-worker"
echo "    description: Execute $TASK_ID"
echo "    run_in_background: true"
echo "    prompt: |"
echo "      Working directory: $(pwd)/$WORKTREE_DIR"
echo "      Task ID: $TASK_ID"
echo ""
echo "      $TASK_PROMPT"
echo ""
