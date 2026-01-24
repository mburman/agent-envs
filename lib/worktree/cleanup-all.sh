#!/bin/bash
# Remove all worktrees and restore stashed changes
# Usage: cleanup-all.sh [--keep-results]

set -e

WORKTREE_BASE=".worktrees"
STASH_FILE="${WORKTREE_BASE}/.stash-marker"
ORCHESTRATION_DIR="${ORCHESTRATION_DIR:-/orchestration}"
KEEP_RESULTS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --keep-results)
      KEEP_RESULTS=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: cleanup-all.sh [--keep-results]"
      exit 1
      ;;
  esac
done

# List and remove all worktrees
if [ -d "$WORKTREE_BASE" ]; then
  echo "Removing all worktrees..."

  # Find all worktree directories (excluding hidden files)
  for worktree in "$WORKTREE_BASE"/*/; do
    if [ -d "$worktree" ]; then
      TASK_ID=$(basename "$worktree")
      if [ "$TASK_ID" != "*" ]; then
        echo "  Removing: $TASK_ID"
        git worktree remove --force "${WORKTREE_BASE}/${TASK_ID}" 2>/dev/null || rm -rf "${WORKTREE_BASE}/${TASK_ID}"
        git branch -D "worker/${TASK_ID}" 2>/dev/null || true
      fi
    fi
  done

  # Prune worktree metadata
  git worktree prune 2>/dev/null || true
fi

# Restore stashed changes if any
if [ -f "$STASH_FILE" ]; then
  echo "Restoring stashed changes..."
  # Get the most recent worktree stash
  STASH_REF=$(git stash list | grep "worktree-auto-stash" | head -1 | cut -d: -f1)
  if [ -n "$STASH_REF" ]; then
    git stash pop "$STASH_REF" 2>/dev/null || echo "Warning: Could not restore stash (may have conflicts)"
  fi
  rm -f "$STASH_FILE"
fi

# Clean up orchestration state unless --keep-results
if [ "$KEEP_RESULTS" = false ]; then
  if [ -d "$ORCHESTRATION_DIR" ]; then
    echo "Cleaning orchestration state..."
    rm -f "${ORCHESTRATION_DIR}/tasks/"*.json 2>/dev/null || true
    rm -f "${ORCHESTRATION_DIR}/results/"*.json "${ORCHESTRATION_DIR}/results/"*.patch 2>/dev/null || true
    rm -f "${ORCHESTRATION_DIR}/status/"*.json 2>/dev/null || true
  fi
fi

# Remove empty worktree directory
if [ -d "$WORKTREE_BASE" ]; then
  rmdir "$WORKTREE_BASE" 2>/dev/null || true
fi

echo "Cleanup complete"
