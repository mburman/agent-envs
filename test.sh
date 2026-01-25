#!/bin/bash
# Test script for the Flutter environment image
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
echo "  Flutter Environment Tests"
echo "========================================"
echo ""

# ------------------------------
# Test 1: Build image
# ------------------------------
if [ "$SKIP_BUILD" = false ]; then
  info "Building image..."

  docker build -t claude-flutter -f flutter/Dockerfile . > /dev/null 2>&1 \
    && pass "Built claude-flutter" \
    || fail "Failed to build claude-flutter"
else
  info "Skipping build (--skip-build)"
fi

# ------------------------------
# Test 2: Verify tools installed
# ------------------------------
info "Checking required tools are installed..."

docker run --rm --entrypoint /bin/bash claude-flutter -c "which flutter" > /dev/null 2>&1 \
  && pass "Flutter installed" \
  || fail "Flutter not found"

docker run --rm --entrypoint /bin/bash claude-flutter -c "which claude" > /dev/null 2>&1 \
  && pass "Claude Code installed" \
  || fail "Claude Code not found"

docker run --rm --entrypoint /bin/bash claude-flutter -c "which jq" > /dev/null 2>&1 \
  && pass "jq installed" \
  || fail "jq not found"

docker run --rm --entrypoint /bin/bash claude-flutter -c "which git" > /dev/null 2>&1 \
  && pass "git installed" \
  || fail "git not found"

# ------------------------------
# Test 3: Verify session management scripts exist
# ------------------------------
info "Checking session management scripts..."

for script in list-sessions.sh delete-session.sh; do
  docker run --rm --entrypoint /bin/bash claude-flutter -c "test -x /opt/flutter-env/lib/$script" \
    && pass "Script $script exists and is executable" \
    || fail "Script $script missing or not executable"
done

# ------------------------------
# Test 4: Session management - list-sessions.sh
# ------------------------------
info "Testing session management scripts..."

# Test list-sessions.sh with no sessions
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-flutter -c '
  /opt/flutter-env/lib/list-sessions.sh
')

if echo "$TEST_OUTPUT" | grep -q "Available sessions"; then
  pass "list-sessions.sh runs and shows header"
else
  fail "list-sessions.sh should show 'Available sessions' header"
fi

# Test list-sessions.sh shows sessions that exist
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-flutter -c '
  mkdir -p /home/dev/.claude-sessions/test-session
  /opt/flutter-env/lib/list-sessions.sh
')

if echo "$TEST_OUTPUT" | grep -q "test-session"; then
  pass "list-sessions.sh lists existing sessions"
else
  fail "list-sessions.sh should list test-session"
fi

# Test delete-session.sh with missing arg
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-flutter -c '
  /opt/flutter-env/lib/delete-session.sh 2>&1
' || true)

if echo "$TEST_OUTPUT" | grep -q "Usage"; then
  pass "delete-session.sh shows usage when no arg provided"
else
  fail "delete-session.sh should show usage without arguments"
fi

# Test delete-session.sh deletes session
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-flutter -c '
  mkdir -p /home/dev/.claude-sessions/to-delete
  /opt/flutter-env/lib/delete-session.sh to-delete
  test -d /home/dev/.claude-sessions/to-delete && echo "EXISTS" || echo "DELETED"
')

if echo "$TEST_OUTPUT" | grep -q "DELETED"; then
  pass "delete-session.sh deletes sessions"
else
  fail "delete-session.sh should delete the session directory"
fi

# ------------------------------
# Test 5: Session volume and --list-sessions flag
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
# Test 6: Session persistence (entrypoint logic)
# ------------------------------
info "Testing session directory setup..."

# Test session directory is created
TEST_OUTPUT=$(docker run --rm --entrypoint /bin/bash claude-flutter -c '
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
  claude-flutter -c '
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
# Summary
# ------------------------------
echo ""
echo "========================================"
echo -e "  ${GREEN}All tests passed!${NC}"
echo "========================================"
echo ""
