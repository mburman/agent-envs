Start the Flutter web dev server in the background so the app is viewable in the browser.

Run this single bash command (do NOT ask for confirmation):

```
pkill -f "flutter.*web-server.*$WEB_PORT" 2>/dev/null; sleep 1; nohup flutter run -d web-server --web-port $WEB_PORT --web-hostname 0.0.0.0 > /tmp/flutter-serve.log 2>&1 & disown; echo "Flutter web server starting on port $WEB_PORT (PID: $!)" && sleep 5 && tail -20 /tmp/flutter-serve.log
```

The timeout for the bash command should be 300000 (5 minutes) to allow for Flutter compilation. The app will be available at http://localhost:$WEB_PORT once compilation finishes.

To check on the server later, run: `tail -50 /tmp/flutter-serve.log`
