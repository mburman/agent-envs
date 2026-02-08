#!/bin/bash
# Kills the running Flutter web server and restarts it from scratch.
# Usage: flutter-web-reload.sh [port] [app_dir]
# Defaults: port=$WEB_PORT or 8080, app_dir=/app

WEB_PORT="${1:-${WEB_PORT:-8080}}"
APP_DIR="${2:-/app}"
FLUTTER_PORT=$((WEB_PORT + 1))
PID_FILE="/tmp/flutter-web-server.pid"
PROXY_PID_FILE="/tmp/live-reload-proxy.pid"
FIFO="/tmp/flutter-stdin"
LOG="/tmp/flutter-web-server.log"

echo "[reload] Stopping Flutter web server and live-reload proxy..."

# Kill the live-reload proxy
if [ -f "$PROXY_PID_FILE" ]; then
  PROXY_PID=$(cat "$PROXY_PID_FILE" 2>/dev/null)
  if [ -n "$PROXY_PID" ]; then
    kill "$PROXY_PID" 2>/dev/null || true
  fi
fi

# Kill the process group from the PID file
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$OLD_PID" ]; then
    # Kill child processes first, then the main process
    pkill -P "$OLD_PID" 2>/dev/null || true
    kill "$OLD_PID" 2>/dev/null || true
  fi
fi

# Kill any remaining flutter/dart processes on both ports
fuser -k "$WEB_PORT/tcp" 2>/dev/null || true
fuser -k "$FLUTTER_PORT/tcp" 2>/dev/null || true

# Kill any lingering inotifywait file watchers
pkill -f "inotifywait.*$APP_DIR" 2>/dev/null || true

# Kill any remaining flutter run or dart processes
pkill -f "flutter run.*web-server.*$FLUTTER_PORT" 2>/dev/null || true

# Brief pause to let processes fully terminate
sleep 1

# Clean up state files
rm -f "$PID_FILE" "$PROXY_PID_FILE" "$FIFO" "$LOG"

echo "[reload] Starting Flutter web server on port $WEB_PORT..."

# Restart the server
flutter-web-server.sh "$WEB_PORT" "$APP_DIR"

# Wait for the server to become ready (up to 120 seconds)
echo "[reload] Waiting for server to be ready..."
for i in $(seq 1 120); do
  if grep -q "is being served at" "$LOG" 2>/dev/null; then
    echo "[reload] Server is ready on port $WEB_PORT"
    exit 0
  fi
  # Check if the flutter process died
  if [ -f "$PID_FILE" ]; then
    FLUTTER_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$FLUTTER_PID" ] && ! kill -0 "$FLUTTER_PID" 2>/dev/null; then
      echo "[reload] ERROR: Flutter process died. Check $LOG for details." >&2
      exit 1
    fi
  fi
  sleep 1
done

echo "[reload] WARNING: Timed out waiting for server, but it may still be starting."
echo "[reload] Check $LOG for status."
exit 0
