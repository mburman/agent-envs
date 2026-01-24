#!/bin/bash
# Collect a patch from a completed worktree
# Usage: collect-patch.sh <task-id>

set -e

TASK_ID="$1"
WORKTREE_BASE=".worktrees"
WORKTREE_DIR="${WORKTREE_BASE}/${TASK_ID}"
ORCHESTRATION_DIR="${ORCHESTRATION_DIR:-/orchestration}"
RESULTS_DIR="${ORCHESTRATION_DIR}/results"

if [ -z "$TASK_ID" ]; then
  echo "Usage: collect-patch.sh <task-id>"
  exit 1
fi

if [ ! -d "$WORKTREE_DIR" ]; then
  echo "Error: Worktree not found: $WORKTREE_DIR"
  exit 1
fi

mkdir -p "$RESULTS_DIR"

# Save current directory
ORIG_DIR=$(pwd)

# Change to worktree directory
cd "$WORKTREE_DIR"

# Get list of modified/untracked files before staging
MODIFIED_FILES=$(git status --porcelain | grep -E '^.M|^M' | awk '{print $2}' | head -50 || true)
UNTRACKED_FILES=$(git ls-files --others --exclude-standard | head -20 || true)
DELETED_FILES=$(git status --porcelain | grep -E '^.D|^D' | awk '{print $2}' | head -20 || true)

# Stage all changes and generate patch
PATCH_FILE="${RESULTS_DIR}/${TASK_ID}.patch"
ERROR_MSG=""

if ! git add -A 2>&1; then
  ERROR_MSG="Failed to stage changes"
fi

# Generate patch from staged changes (use absolute path)
if [ -z "$ERROR_MSG" ]; then
  if ! git diff --cached > "$PATCH_FILE" 2>&1; then
    ERROR_MSG="Failed to generate patch"
  fi
fi

# Reset staging (don't leave worktree in staged state)
git reset HEAD >/dev/null 2>&1 || true

# Return to original directory
cd "$ORIG_DIR"

# Determine status
if [ -n "$ERROR_MSG" ]; then
  STATUS="error"
  echo "Error: $ERROR_MSG" >&2
elif [ ! -s "$PATCH_FILE" ]; then
  STATUS="no_changes"
  echo "No changes detected in worktree"
else
  STATUS="success"
  PATCH_SIZE=$(wc -c < "$PATCH_FILE" | tr -d ' ')
  echo "Patch collected: $PATCH_FILE ($PATCH_SIZE bytes)"
fi

# Write result JSON
RESULT_FILE="${RESULTS_DIR}/${TASK_ID}.json"
cat > "$RESULT_FILE" << EOF
{
  "task_id": "$TASK_ID",
  "status": "$STATUS",
  "error": "$ERROR_MSG",
  "patch_file": "$PATCH_FILE",
  "modified_files": "$(echo "$MODIFIED_FILES" | tr '\n' ' ')",
  "untracked_files": "$(echo "$UNTRACKED_FILES" | tr '\n' ' ')",
  "deleted_files": "$(echo "$DELETED_FILES" | tr '\n' ' ')",
  "collected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "Result written: $RESULT_FILE"
