Kill the Flutter web server and restart it from scratch so all code changes are picked up.

Run this single bash command (do NOT ask for confirmation):

```
flutter-web-reload.sh
```

This script handles everything: killing the old server, cleaning up, restarting, and waiting for readiness. The timeout for the bash command should be 300000 (5 minutes) to allow for Flutter compilation.
