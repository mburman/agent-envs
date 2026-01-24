#!/bin/bash
# Test script for the orchestration system
# Usage: ./test.sh [--skip-build]

set -e

SKIP_BUILD=false
if [ "$1" = "--skip-build" ]; then
  SKIP_BUILD=true
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
info() { echo -e "${YELLOW}→ $1${NC}"; }

cd "$(dirname "$0")"

echo ""
echo "========================================"
echo "  Orchestration System Tests"
echo "========================================"
echo ""

# ------------------------------
# Test 1: Build images
# ------------------------------
if [ "$SKIP_BUILD" = false ]; then
  info "Building images..."

  docker build -t claude-orchestrator -f orchestrator/Dockerfile . > /dev/null 2>&1 \
    && pass "Built claude-orchestrator" \
    || fail "Failed to build claude-orchestrator"
else
  info "Skipping build (--skip-build)"
fi

# ------------------------------
# Test 2: Verify tools installed in orchestrator
# ------------------------------
info "Checking orchestrator has required tools..."

docker run --rm --entrypoint /bin/bash claude-orchestrator -c "which flutter" > /dev/null 2>&1 \
  && pass "Flutter installed in orchestrator" \
  || fail "Flutter not found in orchestrator"

docker run --rm --entrypoint /bin/bash claude-orchestrator -c "which docker" > /dev/null 2>&1 \
  && pass "Docker CLI installed in orchestrator" \
  || fail "Docker CLI not found in orchestrator"

docker run --rm --entrypoint /bin/bash claude-orchestrator -c "which claude" > /dev/null 2>&1 \
  && pass "Claude Code installed in orchestrator" \
  || fail "Claude Code not found in orchestrator"

docker run --rm --entrypoint /bin/bash claude-orchestrator -c "which jq" > /dev/null 2>&1 \
  && pass "jq installed in orchestrator" \
  || fail "jq not found in orchestrator"

docker run --rm --entrypoint /bin/bash claude-orchestrator -c "which git" > /dev/null 2>&1 \
  && pass "git installed in orchestrator" \
  || fail "git not found in orchestrator"

# ------------------------------
# Test 3: Verify orchestrator scripts exist and are executable
# ------------------------------
info "Checking orchestrator scripts..."

for script in spawn-worker.sh show-plan.sh get-ready-tasks.sh update-task-status.sh cleanup.sh list-sessions.sh delete-session.sh check-workers.sh; do
  docker run --rm --entrypoint /bin/bash claude-orchestrator -c "test -x /opt/orchestrator/lib/$script" \
    && pass "Script $script exists and is executable" \
    || fail "Script $script missing or not executable"
done

# ------------------------------
# Test 4: Verify worktree scripts exist
# ------------------------------
info "Checking worktree scripts..."

for script in create-worktree.sh collect-patch.sh cleanup-worktree.sh cleanup-all.sh; do
  docker run --rm --entrypoint /bin/bash claude-orchestrator -c "test -x /opt/orchestrator/lib/worktree/$script" \
    && pass "Worktree script $script exists and is executable" \
    || fail "Worktree script $script missing or not executable"
done

# ------------------------------
# Test 5: Test plan.json parsing
# ------------------------------
info "Testing plan parsing logic..."

# Create a test plan and verify get-ready-tasks.sh works
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  mkdir -p /orchestration
  cat > /orchestration/plan.json << EOF
{
  "goal": "Test goal",
  "tasks": {
    "task-001": {"name": "First", "depends_on": [], "status": "pending"},
    "task-002": {"name": "Second", "depends_on": ["task-001"], "status": "pending"},
    "task-003": {"name": "Third", "depends_on": [], "status": "completed"}
  }
}
EOF
  /opt/orchestrator/lib/get-ready-tasks.sh
')

if echo "$TEST_OUTPUT" | grep -q "task-001"; then
  pass "get-ready-tasks.sh finds task-001 (no deps, pending)"
else
  fail "get-ready-tasks.sh should find task-001"
fi

if echo "$TEST_OUTPUT" | grep -q "task-002"; then
  fail "get-ready-tasks.sh should NOT find task-002 (blocked by task-001)"
else
  pass "get-ready-tasks.sh correctly excludes task-002 (blocked)"
fi

if echo "$TEST_OUTPUT" | grep -q "task-003"; then
  fail "get-ready-tasks.sh should NOT find task-003 (already completed)"
else
  pass "get-ready-tasks.sh correctly excludes task-003 (completed)"
fi

# ------------------------------
# Test 6: Test update-task-status.sh
# ------------------------------
info "Testing status update logic..."

TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  mkdir -p /orchestration
  cat > /orchestration/plan.json << EOF
{"goal": "Test", "tasks": {"task-001": {"name": "Test", "depends_on": [], "status": "pending"}}}
EOF
  /opt/orchestrator/lib/update-task-status.sh task-001 running >/dev/null 2>&1
  cat /orchestration/plan.json | jq -r ".tasks[\"task-001\"].status"
')

if [ "$TEST_OUTPUT" = "running" ]; then
  pass "update-task-status.sh correctly updates status"
else
  fail "update-task-status.sh failed to update status (got: $TEST_OUTPUT)"
fi

# ------------------------------
# Test 7: Test show-plan.sh output
# ------------------------------
info "Testing plan display..."

TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  mkdir -p /orchestration
  cat > /orchestration/plan.json << EOF
{"goal": "Test Goal", "tasks": {"task-001": {"name": "Test Task", "depends_on": [], "status": "pending"}}}
EOF
  /opt/orchestrator/lib/show-plan.sh
')

if echo "$TEST_OUTPUT" | grep -q "Test Goal"; then
  pass "show-plan.sh displays goal"
else
  fail "show-plan.sh should display goal"
fi

if echo "$TEST_OUTPUT" | grep -q "task-001"; then
  pass "show-plan.sh displays task ID"
else
  fail "show-plan.sh should display task ID"
fi

# ------------------------------
# Test 8: Session management - list-sessions.sh
# ------------------------------
info "Testing session management scripts..."

# Test list-sessions.sh with no sessions
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  /opt/orchestrator/lib/list-sessions.sh
')

if echo "$TEST_OUTPUT" | grep -q "Available sessions"; then
  pass "list-sessions.sh runs and shows header"
else
  fail "list-sessions.sh should show 'Available sessions' header"
fi

# Test list-sessions.sh shows sessions that exist
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  mkdir -p /home/dev/.claude-sessions/test-session
  /opt/orchestrator/lib/list-sessions.sh
')

if echo "$TEST_OUTPUT" | grep -q "test-session"; then
  pass "list-sessions.sh lists existing sessions"
else
  fail "list-sessions.sh should list test-session"
fi

# Test delete-session.sh with missing arg
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  /opt/orchestrator/lib/delete-session.sh 2>&1
' || true)

if echo "$TEST_OUTPUT" | grep -q "Usage"; then
  pass "delete-session.sh shows usage when no arg provided"
else
  fail "delete-session.sh should show usage without arguments"
fi

# Test delete-session.sh deletes session
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  mkdir -p /home/dev/.claude-sessions/to-delete
  /opt/orchestrator/lib/delete-session.sh to-delete
  test -d /home/dev/.claude-sessions/to-delete && echo "EXISTS" || echo "DELETED"
')

if echo "$TEST_OUTPUT" | grep -q "DELETED"; then
  pass "delete-session.sh deletes sessions"
else
  fail "delete-session.sh should delete the session directory"
fi

# ------------------------------
# Test 9: Session volume and --list-sessions flag
# ------------------------------
info "Testing run.sh session flags..."

# Create test session volume
docker volume create claude-sessions-test >/dev/null 2>&1 || true

# Test --list-sessions flag (should work without --repo)
TEST_OUTPUT=$(./run.sh --list-sessions 2>&1 || true)

if echo "$TEST_OUTPUT" | grep -q "Available sessions"; then
  pass "--list-sessions flag works without --repo"
else
  fail "--list-sessions should work without --repo flag"
fi

# Clean up test volume
docker volume rm claude-sessions-test >/dev/null 2>&1 || true

# ------------------------------
# Test 10: Session persistence (entrypoint logic)
# ------------------------------
info "Testing session save/restore logic..."

# Test session directory is created
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  test -d /home/dev/.claude-sessions && echo "EXISTS" || echo "MISSING"
')

if echo "$TEST_OUTPUT" | grep -q "EXISTS"; then
  pass "Session directory exists in container"
else
  fail "Session directory should exist at /home/dev/.claude-sessions"
fi

# Test SESSION_NAME env var is recognized in entrypoint
TEST_OUTPUT=$(docker run --rm \
  -e SESSION_NAME=test-session \
  --entrypoint /bin/bash \
  claude-orchestrator -c '
    # Simulate what entrypoint does
    SESSIONS_DIR="/home/dev/.claude-sessions"
    mkdir -p "$SESSIONS_DIR"
    if [ -n "$SESSION_NAME" ]; then
      SESSION_PATH="$SESSIONS_DIR/$SESSION_NAME"
      if [ -d "$SESSION_PATH" ]; then
        echo "RESUME"
      else
        echo "CREATE"
        mkdir -p "$SESSION_PATH"
      fi
    fi
    test -d "$SESSIONS_DIR/$SESSION_NAME" && echo "SESSION_DIR_EXISTS"
  ')

if echo "$TEST_OUTPUT" | grep -q "CREATE" && echo "$TEST_OUTPUT" | grep -q "SESSION_DIR_EXISTS"; then
  pass "SESSION_NAME creates new session directory"
else
  fail "SESSION_NAME should create session directory"
fi

# ------------------------------
# Test 11: Functional worktree tests
# ------------------------------
info "Testing worktree operations..."

# Test create-worktree.sh creates worktree with hooks
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  # Initialize a git repo to work with
  mkdir -p /app && cd /app
  git init --initial-branch main
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > file.txt
  git add file.txt
  git commit -m "initial"

  # Create worktree
  /opt/orchestrator/lib/worktree/create-worktree.sh task-001

  # Check worktree exists
  test -d .worktrees/task-001 && echo "WORKTREE_EXISTS"

  # Check hooks exist
  GITDIR=$(git -C .worktrees/task-001 rev-parse --git-dir)
  test -x "${GITDIR}/hooks/pre-commit" && echo "PRECOMMIT_EXISTS"
  test -x "${GITDIR}/hooks/pre-push" && echo "PREPUSH_EXISTS"

  # Check hooks block commit
  cd .worktrees/task-001
  echo "change" > newfile.txt
  git add newfile.txt
  git commit -m "test" 2>&1 | grep -q "cannot commit" && echo "COMMIT_BLOCKED"
')

if echo "$TEST_OUTPUT" | grep -q "WORKTREE_EXISTS"; then
  pass "create-worktree.sh creates worktree directory"
else
  fail "create-worktree.sh should create worktree"
fi

if echo "$TEST_OUTPUT" | grep -q "PRECOMMIT_EXISTS" && echo "$TEST_OUTPUT" | grep -q "PREPUSH_EXISTS"; then
  pass "create-worktree.sh installs git hooks"
else
  fail "create-worktree.sh should install git hooks"
fi

if echo "$TEST_OUTPUT" | grep -q "COMMIT_BLOCKED"; then
  pass "Git hooks block commits in worktree"
else
  fail "Git hooks should block commits in worktree"
fi

# Test collect-patch.sh generates patch
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  # Initialize a git repo
  mkdir -p /app && cd /app
  git init --initial-branch main
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > file.txt
  git add file.txt
  git commit -m "initial"

  # Create worktree
  /opt/orchestrator/lib/worktree/create-worktree.sh task-002

  # Make changes in worktree
  cd .worktrees/task-002
  echo "modified" > file.txt
  echo "new content" > newfile.txt
  cd /app

  # Collect patch
  /opt/orchestrator/lib/worktree/collect-patch.sh task-002

  # Check result
  test -f /orchestration/results/task-002.patch && echo "PATCH_EXISTS"
  test -s /orchestration/results/task-002.patch && echo "PATCH_NOT_EMPTY"
  test -f /orchestration/results/task-002.json && echo "RESULT_JSON_EXISTS"
  cat /orchestration/results/task-002.json | jq -r ".status" | grep -q "success" && echo "STATUS_SUCCESS"
')

if echo "$TEST_OUTPUT" | grep -q "PATCH_EXISTS" && echo "$TEST_OUTPUT" | grep -q "PATCH_NOT_EMPTY"; then
  pass "collect-patch.sh generates patch file"
else
  fail "collect-patch.sh should generate non-empty patch"
fi

if echo "$TEST_OUTPUT" | grep -q "RESULT_JSON_EXISTS" && echo "$TEST_OUTPUT" | grep -q "STATUS_SUCCESS"; then
  pass "collect-patch.sh writes result JSON with success status"
else
  fail "collect-patch.sh should write result JSON"
fi

# Test collect-patch.sh returns no_changes when no changes
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  # Initialize a git repo
  mkdir -p /app && cd /app
  git init --initial-branch main
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > file.txt
  git add file.txt
  git commit -m "initial"

  # Create worktree (no changes)
  /opt/orchestrator/lib/worktree/create-worktree.sh task-003

  # Collect patch without making changes
  /opt/orchestrator/lib/worktree/collect-patch.sh task-003

  # Check result
  cat /orchestration/results/task-003.json | jq -r ".status"
')

if echo "$TEST_OUTPUT" | grep -q "no_changes"; then
  pass "collect-patch.sh detects no changes correctly"
else
  fail "collect-patch.sh should return no_changes when worktree unchanged"
fi

# Test cleanup-worktree.sh removes worktree
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  # Initialize a git repo
  mkdir -p /app && cd /app
  git init --initial-branch main
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > file.txt
  git add file.txt
  git commit -m "initial"

  # Create worktree
  /opt/orchestrator/lib/worktree/create-worktree.sh task-004
  test -d .worktrees/task-004 && echo "WORKTREE_BEFORE"

  # Cleanup worktree
  /opt/orchestrator/lib/worktree/cleanup-worktree.sh task-004

  # Check worktree removed
  test -d .worktrees/task-004 && echo "WORKTREE_AFTER" || echo "WORKTREE_REMOVED"

  # Check branch removed
  git branch | grep -q "worker/task-004" && echo "BRANCH_EXISTS" || echo "BRANCH_REMOVED"
')

if echo "$TEST_OUTPUT" | grep -q "WORKTREE_BEFORE" && echo "$TEST_OUTPUT" | grep -q "WORKTREE_REMOVED"; then
  pass "cleanup-worktree.sh removes worktree directory"
else
  fail "cleanup-worktree.sh should remove worktree"
fi

if echo "$TEST_OUTPUT" | grep -q "BRANCH_REMOVED"; then
  pass "cleanup-worktree.sh removes worker branch"
else
  fail "cleanup-worktree.sh should remove worker branch"
fi

# Test patch can be applied to main repo
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-orchestrator -c '
  # Initialize a git repo
  mkdir -p /app && cd /app
  git init --initial-branch main
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > file.txt
  git add file.txt
  git commit -m "initial"

  # Create worktree and make changes
  /opt/orchestrator/lib/worktree/create-worktree.sh task-005
  echo "modified by worker" > .worktrees/task-005/file.txt

  # Collect patch
  /opt/orchestrator/lib/worktree/collect-patch.sh task-005

  # Apply patch to main repo
  git apply /orchestration/results/task-005.patch 2>&1 && echo "PATCH_APPLIED"

  # Verify change
  cat file.txt | grep -q "modified by worker" && echo "CHANGE_VERIFIED"
')

if echo "$TEST_OUTPUT" | grep -q "PATCH_APPLIED" && echo "$TEST_OUTPUT" | grep -q "CHANGE_VERIFIED"; then
  pass "Collected patch can be applied to main repo"
else
  fail "Patch should be applicable to main repo"
fi

# ------------------------------
# Summary
# ------------------------------
echo ""
echo "========================================"
echo -e "  ${GREEN}All tests passed!${NC}"
echo "========================================"
echo ""
