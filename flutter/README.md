# Flutter Environment

Docker environment for running Claude Code with Flutter SDK in an isolated container.

## What's Included

- Ubuntu 22.04
- Flutter SDK (stable channel)
- Dart SDK
- Node.js 20
- Claude Code
- Git, jq, inotify-tools, and common dev tools

## Live Reload Dev Server

When the container starts and a Flutter project is detected (`pubspec.yaml` + `lib/` in `/app`), a dev server automatically starts with **live reload** — your browser refreshes automatically when code changes.

### Architecture

```
Browser  -->  Live-reload proxy (:WEB_PORT)  -->  Flutter dev server (:WEB_PORT+1)
                     |
                SSE connection
                     |
              Auto page reload
```

A lightweight Node.js proxy sits in front of the Flutter dev server. It injects a small script into the page that listens for reload events via Server-Sent Events (SSE).

### How it works

1. A file watcher (`inotifywait`) monitors all `.dart` files in the project
2. When changes are detected, it waits for a **5-second quiet period** (no more changes) before acting — this batches rapid edits so you get one recompilation instead of many
3. Sends `r` to the Flutter process for hot restart (recompilation)
4. Waits for recompilation to finish
5. Signals the proxy, which tells all connected browsers to reload via SSE

The quiet period is particularly important when AI agents are making changes to many files in succession — without it, each file save would trigger a separate recompilation.

### Logs and troubleshooting

- **Logs**: `/tmp/flutter-web-server.log`
- **Full restart**: `flutter-web-reload.sh` (kills everything and restarts from scratch)
- **Manual start**: `flutter-web-server.sh <port> /app`
- The port is auto-assigned (8080-8999) or set via `--port`

## Quick Start

```bash
# Build the image
./build.sh

# Start Claude Code with your repo
./run.sh --repo git@github.com:your-user/your-flutter-app.git
```

## Options

| Flag | Description |
|------|-------------|
| `--repo URL` | Git repo to clone (required for new sessions) |
| `--branch BRANCH` | Branch to clone (default: main) |
| `--session NAME` | Named session for persistence |
| `--token FILE` | Claude token file (default: ~/.claude-token) |
| `--ssh-key FILE` | SSH key for Git (default: ~/.ssh/id_ed25519) |
| `--model MODEL` | Model to use |
| `--port PORT` | Port for Flutter web server |

## Session Management

Sessions persist your Claude conversation and repo state across container restarts.

```bash
# Start new session
./run.sh --repo git@... --session my-feature

# Resume session
./run.sh --session my-feature

# List sessions
./run.sh --list-sessions

# Inside the container:
/opt/flutter-env/lib/list-sessions.sh              # List sessions
/opt/flutter-env/lib/delete-session.sh my-session  # Delete a session
```

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `REPO_URL` | Git repo to clone |
| `REPO_BRANCH` | Branch to clone |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude authentication |
| `ANTHROPIC_MODEL` | Model to use |
| `SESSION_NAME` | Named session for persistence |
