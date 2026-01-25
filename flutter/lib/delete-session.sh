#!/bin/bash
set -e
# Delete a named session

SESSION_NAME="$1"

if [ -z "$SESSION_NAME" ]; then
  echo "Usage: delete-session.sh <session-name>"
  echo ""
  echo "List sessions first with: /opt/orchestrator/lib/list-sessions.sh"
  exit 1
fi

SESSIONS_DIR="/home/dev/.claude-sessions"
SESSION_PATH="$SESSIONS_DIR/$SESSION_NAME"

if [ -d "$SESSION_PATH" ]; then
  rm -rf "$SESSION_PATH"
  echo "Deleted session: $SESSION_NAME"
else
  echo "Session not found: $SESSION_NAME"
  echo ""
  echo "Available sessions:"
  ls -1 "$SESSIONS_DIR" 2>/dev/null || echo "  (none)"
  exit 1
fi
