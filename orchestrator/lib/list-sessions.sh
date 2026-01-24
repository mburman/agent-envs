#!/bin/bash
# List available named sessions

SESSIONS_DIR="/home/dev/.claude-sessions"

echo "Available sessions:"
echo "==================="

if [ -d "$SESSIONS_DIR" ] && [ "$(ls -A $SESSIONS_DIR 2>/dev/null)" ]; then
  for session in "$SESSIONS_DIR"/*/; do
    [ -d "$session" ] || continue
    name=$(basename "$session")
    # Get modification time (works on both Linux and macOS)
    if stat --version >/dev/null 2>&1; then
      # GNU stat (Linux)
      modified=$(stat -c %y "$session" 2>/dev/null | cut -d' ' -f1)
    else
      # BSD stat (macOS)
      modified=$(stat -f %Sm -t %Y-%m-%d "$session" 2>/dev/null)
    fi
    echo "  $name (last used: ${modified:-unknown})"
  done
else
  echo "  (no sessions found)"
fi

echo ""
echo "To resume a session:"
echo "  ./run.sh --repo <url> --session <name>"
