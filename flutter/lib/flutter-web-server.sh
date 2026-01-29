#!/bin/bash
# Starts Flutter web server in the background with file-watching for hot restart.
# Usage: flutter-web-server.sh <port> <app_dir>

set -e

WEB_PORT="${1:?Port required}"
APP_DIR="${2:?App directory required}"
FIFO="/tmp/flutter-stdin"
LOG="/tmp/flutter-web-server.log"
PID_FILE="/tmp/flutter-web-server.pid"

# Clean up from any previous run
rm -f "$FIFO" "$PID_FILE"
mkfifo "$FIFO"

cd "$APP_DIR"

echo "[flutter-web-server] Starting Flutter web server on port $WEB_PORT..."
echo "[flutter-web-server] Log file: $LOG"

# Start flutter run reading from the named pipe for stdin.
# The pipe is kept open by a background sleep so flutter doesn't see EOF.
(
  # Hold the pipe open indefinitely so flutter run doesn't exit
  sleep infinity > "$FIFO" &
  SLEEP_PID=$!

  flutter run -d web-server --web-port "$WEB_PORT" --web-hostname 0.0.0.0 < "$FIFO" >> "$LOG" 2>&1
  EXIT_CODE=$?

  kill "$SLEEP_PID" 2>/dev/null || true
  echo "[flutter-web-server] Flutter process exited with code $EXIT_CODE" >> "$LOG"
) &
FLUTTER_PID=$!
echo "$FLUTTER_PID" > "$PID_FILE"

echo "[flutter-web-server] Flutter PID: $FLUTTER_PID"

# Wait for the server to be ready (look for "is being served at" in the log)
echo "[flutter-web-server] Waiting for server to be ready..."
for i in $(seq 1 120); do
  if grep -q "is being served at" "$LOG" 2>/dev/null; then
    echo "[flutter-web-server] Server is ready on port $WEB_PORT"
    break
  fi
  if ! kill -0 "$FLUTTER_PID" 2>/dev/null; then
    echo "[flutter-web-server] Flutter process died. Check $LOG for details."
    break
  fi
  sleep 1
done

# Start file watcher for hot restart
(
  echo "[flutter-web-server] Starting file watcher for hot restart..."
  while true; do
    # Watch for .dart file modifications, creations, and deletions
    inotifywait -r -q -e modify,create,delete --include '\.dart$' "$APP_DIR" 2>/dev/null
    # Small debounce to batch rapid changes
    sleep 0.5
    # Send 'r' for hot restart (Flutter web only supports hot restart, not hot reload)
    if [ -p "$FIFO" ] && kill -0 "$FLUTTER_PID" 2>/dev/null; then
      echo "r" > "$FIFO"
      echo "[flutter-web-server] Hot restart triggered at $(date '+%H:%M:%S')" >> "$LOG"
    else
      echo "[flutter-web-server] Flutter process gone, stopping watcher." >> "$LOG"
      break
    fi
  done
) &
WATCHER_PID=$!

echo "[flutter-web-server] File watcher PID: $WATCHER_PID"
echo "[flutter-web-server] Background setup complete."
