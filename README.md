# Agent Environments

Docker environments for running [Claude Code](https://github.com/anthropics/claude-code) with `--dangerously-skip-permissions` in isolated containers.

## Quick Start

```bash
# Build the image
./build.sh

# Start Claude Code with your repo
./run.sh --repo git@github.com:your-user/your-flutter-app.git

# Or start with a named session (for resumption)
./run.sh --repo git@github.com:your-user/your-flutter-app.git --session my-feature

# Resume an existing session
./run.sh --session my-feature

# List available sessions
./run.sh --list-sessions
```

## Available Environments

- **flutter/** - Ubuntu + Flutter SDK + Claude Code, with live-reload dev server (browser auto-refreshes on code changes)

## Why Docker?

Running Claude Code with `--dangerously-skip-permissions` allows it to execute commands without confirmation prompts. This is useful for autonomous coding tasks but risky on your host machine. The Docker container provides:

- **Isolation**: Claude can only modify files inside the container
- **Session persistence**: Named sessions survive container restarts
- **Full toolchain**: All dependencies pre-installed (Flutter, Node.js, etc.)

## Prerequisites

**Claude Code authentication**: You need a long-lived OAuth token from Claude Code (requires Claude Pro or Max subscription).

```bash
# On your host machine, run:
claude setup-token

# Follow the browser prompt to authenticate, then save the token:
echo "your-token-here" > ~/.claude-token
chmod 600 ~/.claude-token
```

## Session Management

Sessions persist your Claude conversation and repo state across container restarts.

```bash
# Start a new session (auto-generates ID like s-20250124-143022)
./run.sh --repo git@github.com:user/app.git

# Start with a custom session name
./run.sh --repo git@github.com:user/app.git --session dark-mode-feature

# List available sessions
./run.sh --list-sessions

# Resume an existing session (no --repo needed)
./run.sh --session dark-mode-feature

# Reset all state
./run.sh --clean-all
```

## Security Notes

- SSH keys are mounted **read-only** - Claude cannot modify them
- Claude token is passed via environment variable (not stored in image)
- Claude cannot access your host filesystem (only the cloned repo inside the container)
- Containers run as non-root user (`dev`), isolated from your host

## License

MIT
