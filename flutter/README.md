# Flutter Environment

Docker environment for running Claude Code with Flutter SDK in an isolated container.

## What's Included

- Ubuntu 22.04
- Flutter SDK (stable channel)
- Dart SDK
- Node.js 20
- Claude Code
- Git, jq, and common dev tools

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
