#!/bin/bash
# Create an isolated git worktree for a task
# Usage: create-worktree.sh <task-id>

set -e

TASK_ID="$1"
WORKTREE_BASE=".worktrees"
WORKTREE_DIR="${WORKTREE_BASE}/${TASK_ID}"
BRANCH_NAME="worker/${TASK_ID}"
STASH_FILE="${WORKTREE_BASE}/.stash-marker"

if [ -z "$TASK_ID" ]; then
  echo "Usage: create-worktree.sh <task-id>"
  exit 1
fi

# Create worktrees directory if needed
mkdir -p "$WORKTREE_BASE"

# Check if worktree already exists
if [ -d "$WORKTREE_DIR" ]; then
  echo "Error: Worktree already exists: $WORKTREE_DIR"
  exit 1
fi

# Auto-stash uncommitted changes if repo is dirty
if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  echo "Stashing uncommitted changes..."
  git stash push -m "worktree-auto-stash-${TASK_ID}" --include-untracked
  echo "$TASK_ID" >> "$STASH_FILE"
fi

# Create new branch from current HEAD (ignore error if branch exists)
git branch "$BRANCH_NAME" HEAD 2>/dev/null || true

# Create the worktree
git worktree add "$WORKTREE_DIR" "$BRANCH_NAME"

# Install git hooks to block commits/pushes in the worktree
# Git worktrees share the main .git/hooks by default. We need to use
# core.hooksPath to point to worktree-specific hooks.
WORKTREE_GIT_DIR=$(git -C "$WORKTREE_DIR" rev-parse --git-dir)
HOOKS_DIR="${WORKTREE_GIT_DIR}/hooks"
mkdir -p "$HOOKS_DIR"

cat > "${HOOKS_DIR}/pre-commit" << 'HOOK'
#!/bin/bash
echo "ERROR: Workers cannot commit. The Manager will review and commit your changes."
echo "Your changes are saved in the working directory."
exit 1
HOOK

cat > "${HOOKS_DIR}/pre-push" << 'HOOK'
#!/bin/bash
echo "ERROR: Workers cannot push. Only the Manager can push code."
exit 1
HOOK

chmod +x "${HOOKS_DIR}/pre-commit"
chmod +x "${HOOKS_DIR}/pre-push"

# Configure the worktree to use its own hooks directory
git -C "$WORKTREE_DIR" config core.hooksPath "$HOOKS_DIR"

echo "Created worktree: $WORKTREE_DIR (branch: $BRANCH_NAME)"
echo "Git hooks installed to block commit/push"
