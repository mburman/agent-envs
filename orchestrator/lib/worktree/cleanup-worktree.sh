#!/bin/bash
# Remove a worktree and its branch
# Usage: cleanup-worktree.sh <task-id>

set -e

TASK_ID="$1"
WORKTREE_BASE=".worktrees"
WORKTREE_DIR="${WORKTREE_BASE}/${TASK_ID}"
BRANCH_NAME="worker/${TASK_ID}"

if [ -z "$TASK_ID" ]; then
  echo "Usage: cleanup-worktree.sh <task-id>"
  exit 1
fi

# Remove worktree if it exists
if [ -d "$WORKTREE_DIR" ]; then
  echo "Removing worktree: $WORKTREE_DIR"
  git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
fi

# Delete the worker branch
if git branch --list "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
  echo "Deleting branch: $BRANCH_NAME"
  git branch -D "$BRANCH_NAME" 2>/dev/null || true
fi

# Prune worktree metadata
git worktree prune 2>/dev/null || true

echo "Cleaned up: $TASK_ID"
