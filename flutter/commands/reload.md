Kill the Flutter web server and restart it from scratch so all code changes are picked up.

Steps:
1. Read the PID from `/tmp/flutter-web-server.pid`
2. Kill the entire process group (flutter run + sleep infinity + file watcher) using `pkill -P` on the PID, then kill the PID itself. Also kill any remaining `dart` or `flutter` processes serving on the web port, and any `inotifywait` file watcher processes.
3. Clean up `/tmp/flutter-web-server.pid`, `/tmp/flutter-stdin`, and `/tmp/flutter-web-server.log`
4. Determine the web port by reading the `WEB_PORT` environment variable (default `8080`)
5. Restart the server by running: `flutter-web-server.sh $WEB_PORT /app`
6. Confirm the server is back up by checking the log for "is being served at"

Run all of this via bash commands. Do NOT ask for confirmation, just do it.
