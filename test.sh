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

  docker build -t claude-orchestrator orchestrator/ > /dev/null 2>&1 \
    && pass "Built claude-orchestrator" \
    || fail "Failed to build claude-orchestrator"

  docker build -t claude-flutter flutter/ > /dev/null 2>&1 \
    && pass "Built claude-flutter" \
    || fail "Failed to build claude-flutter"
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

# ------------------------------
# Test 3: Verify tools installed in flutter worker
# ------------------------------
info "Checking flutter worker has required tools..."

docker run --rm --entrypoint /bin/bash claude-flutter -c "which flutter" > /dev/null 2>&1 \
  && pass "Flutter installed in worker" \
  || fail "Flutter not found in worker"

docker run --rm --entrypoint /bin/bash claude-flutter -c "which claude" > /dev/null 2>&1 \
  && pass "Claude Code installed in worker" \
  || fail "Claude Code not found in worker"

docker run --rm --entrypoint /bin/bash claude-flutter -c "which jq" > /dev/null 2>&1 \
  && pass "jq installed in worker" \
  || fail "jq not found in worker"

# ------------------------------
# Test 4: Verify orchestrator scripts exist and are executable
# ------------------------------
info "Checking orchestrator scripts..."

for script in spawn-worker.sh show-plan.sh get-ready-tasks.sh update-task-status.sh list-workers.sh cleanup.sh; do
  docker run --rm --entrypoint /bin/bash claude-orchestrator -c "test -x /opt/orchestrator/lib/$script" \
    && pass "Script $script exists and is executable" \
    || fail "Script $script missing or not executable"
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
# Test 8: Verify sudo docker works
# ------------------------------
info "Testing sudo docker access..."

docker run --rm \
  --entrypoint /bin/bash \
  -v /var/run/docker.sock:/var/run/docker.sock \
  claude-orchestrator -c "sudo docker ps" > /dev/null 2>&1 \
  && pass "sudo docker works in orchestrator" \
  || fail "sudo docker failed - socket permissions issue"

# ------------------------------
# Summary
# ------------------------------
echo ""
echo "========================================"
echo -e "  ${GREEN}All tests passed!${NC}"
echo "========================================"
echo ""
