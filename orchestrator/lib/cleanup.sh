#!/bin/bash
# Clean up orchestration state, worktrees, and/or workers
# Usage: cleanup.sh [--worktrees] [--state] [--all]

CLEAN_WORKTREES=false
CLEAN_STATE=false

if [ $# -eq 0 ]; then
  echo "Usage: cleanup.sh [--worktrees] [--state] [--all]"
  echo ""
  echo "  --worktrees  Remove all worktrees and restore stashed changes"
  echo "  --state      Clear orchestration state (tasks, results, plan)"
  echo "  --all        Both worktrees and state"
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --worktrees) CLEAN_WORKTREES=true; shift ;;
    --state) CLEAN_STATE=true; shift ;;
    --all) CLEAN_WORKTREES=true; CLEAN_STATE=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

ORCHESTRATION_DIR="${ORCHESTRATION_DIR:-/orchestration}"
WORKTREE_BASE=".worktrees"
STASH_FILE="${WORKTREE_BASE}/.stash-marker"

if [ "$CLEAN_WORKTREES" = true ]; then
  echo "Cleaning up worktrees..."

  if [ -d "$WORKTREE_BASE" ]; then
    # Find all worktree directories
    for worktree in "$WORKTREE_BASE"/*/; do
      if [ -d "$worktree" ]; then
        TASK_ID=$(basename "$worktree")
        if [ "$TASK_ID" != "*" ]; then
          echo "  Removing worktree: $TASK_ID"
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
    STASH_REF=$(git stash list | grep "worktree-auto-stash" | head -1 | cut -d: -f1)
    if [ -n "$STASH_REF" ]; then
      git stash pop "$STASH_REF" 2>/dev/null || echo "Warning: Could not restore stash (may have conflicts)"
    fi
    rm -f "$STASH_FILE"
  fi

  # Remove empty worktree directory
  if [ -d "$WORKTREE_BASE" ]; then
    rmdir "$WORKTREE_BASE" 2>/dev/null || true
  fi

  echo "Worktrees cleaned."
fi

if [ "$CLEAN_STATE" = true ]; then
  echo "Clearing orchestration state..."
  rm -f "${ORCHESTRATION_DIR}/plan.json" "${ORCHESTRATION_DIR}/plan.lock"
  rm -f "${ORCHESTRATION_DIR}/tasks/"*.json 2>/dev/null || true
  rm -f "${ORCHESTRATION_DIR}/results/"*.json "${ORCHESTRATION_DIR}/results/"*.patch 2>/dev/null || true
  rm -f "${ORCHESTRATION_DIR}/status/"*.json 2>/dev/null || true
  echo "State cleared."
fi

echo "Done."
