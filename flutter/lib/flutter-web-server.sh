#!/bin/bash
# Starts Flutter web server in the background with file-watching for hot restart
# and a live-reload proxy for automatic browser refresh.
#
# Architecture:
#   Browser -> Live-reload proxy (WEB_PORT) -> Flutter dev server (WEB_PORT+1)
#
# When a .dart file changes:
#   1. inotifywait detects the change
#   2. 'r' is sent to Flutter for hot restart (recompilation)
#   3. After recompilation, the proxy tells the browser to reload via SSE
#
# Usage: flutter-web-server.sh <port> <app_dir>

set -e

WEB_PORT="${1:?Port required}"
APP_DIR="${2:?App directory required}"
FLUTTER_PORT=$((WEB_PORT + 1))
FIFO="/tmp/flutter-stdin"
LOG="/tmp/flutter-web-server.log"
PID_FILE="/tmp/flutter-web-server.pid"
PROXY_PID_FILE="/tmp/live-reload-proxy.pid"

# Clean up from any previous run
rm -f "$FIFO" "$PID_FILE" "$PROXY_PID_FILE"
mkfifo "$FIFO"

cd "$APP_DIR"

echo "[flutter-web-server] Starting Flutter web server on internal port $FLUTTER_PORT..."
echo "[flutter-web-server] Live-reload proxy will listen on port $WEB_PORT"
echo "[flutter-web-server] Log file: $LOG"

# Start flutter run on the internal port (not exposed to host)
(
  # Hold the pipe open indefinitely so flutter run doesn't exit
  sleep infinity > "$FIFO" &
  SLEEP_PID=$!

  flutter run -d web-server --web-port "$FLUTTER_PORT" --web-hostname 0.0.0.0 < "$FIFO" >> "$LOG" 2>&1
  EXIT_CODE=$?

  kill "$SLEEP_PID" 2>/dev/null || true
  echo "[flutter-web-server] Flutter process exited with code $EXIT_CODE" >> "$LOG"
) &
FLUTTER_PID=$!
echo "$FLUTTER_PID" > "$PID_FILE"

echo "[flutter-web-server] Flutter PID: $FLUTTER_PID"

# Wait for Flutter server to be ready, then start the live-reload proxy
(
  for i in $(seq 1 120); do
    if grep -q "is being served at" "$LOG" 2>/dev/null; then
      echo "[flutter-web-server] Flutter server is ready, starting live-reload proxy..." >> "$LOG"

      # Start the live-reload proxy on the user-facing port
      FLUTTER_PORT="$FLUTTER_PORT" PROXY_PORT="$WEB_PORT" \
        node /opt/flutter-env/lib/live-reload-proxy.js >> "$LOG" 2>&1 &
      echo $! > "$PROXY_PID_FILE"

      echo "[flutter-web-server] Live-reload proxy started on port $WEB_PORT" >> "$LOG"
      break
    fi
    if ! kill -0 "$FLUTTER_PID" 2>/dev/null; then
      echo "[flutter-web-server] Flutter process died. Check $LOG for details." >> "$LOG"
      break
    fi
    sleep 1
  done
) &

# Start file watcher for hot restart + browser reload
(
  QUIET_PERIOD=5  # seconds of no changes before triggering restart
  echo "[flutter-web-server] Starting file watcher (${QUIET_PERIOD}s quiet period)..." >> "$LOG"
  while true; do
    # Wait for the first .dart file change
    inotifywait -r -q -e modify,create,delete --include '\.dart$' "$APP_DIR" 2>/dev/null

    # Quiet period: keep waiting while changes are still coming in.
    # inotifywait -t N exits non-zero on timeout (= no more changes), 0 on change.
    while inotifywait -r -q -t "$QUIET_PERIOD" -e modify,create,delete \
          --include '\.dart$' "$APP_DIR" 2>/dev/null; do
      echo "[flutter-web-server] More changes detected, resetting quiet period..." >> "$LOG"
    done

    # No changes for $QUIET_PERIOD seconds — trigger hot restart
    if [ -p "$FIFO" ] && kill -0 "$FLUTTER_PID" 2>/dev/null; then
      echo "r" > "$FIFO"
      echo "[flutter-web-server] Hot restart triggered at $(date '+%H:%M:%S')" >> "$LOG"

      # Wait for Flutter to finish recompiling before telling the browser to reload.
      # Poll the Flutter server - when it responds, recompilation is done.
      sleep 1
      for attempt in $(seq 1 30); do
        if curl -s -o /dev/null -w '' "http://127.0.0.1:$FLUTTER_PORT/" 2>/dev/null; then
          break
        fi
        sleep 0.5
      done

      # Signal the proxy to reload all connected browsers
      curl -s -X POST "http://127.0.0.1:$WEB_PORT/__trigger_reload" > /dev/null 2>&1 || true
      echo "[flutter-web-server] Browser reload triggered at $(date '+%H:%M:%S')" >> "$LOG"
    else
      echo "[flutter-web-server] Flutter process gone, stopping watcher." >> "$LOG"
      break
    fi
  done
) &
WATCHER_PID=$!

echo "[flutter-web-server] File watcher PID: $WATCHER_PID"
echo "[flutter-web-server] Background setup complete."
