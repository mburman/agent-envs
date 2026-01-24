# Agent Environments

[![Test Docker Builds](https://github.com/mburman/agent-envs/actions/workflows/test.yml/badge.svg)](https://github.com/mburman/agent-envs/actions/workflows/test.yml)

Docker environments for running [Claude Code](https://github.com/anthropics/claude-code) with `--dangerously-skip-permissions` in isolated containers.

## Quick Start

The orchestration system lets a Manager agent spawn and coordinate Worker sub-agents:

```bash
# Build the image
./build.sh

# Start the Manager
./run.sh --repo git@github.com:your-user/your-flutter-app.git

# Or start with a named session (for resumption)
./run.sh --repo git@github.com:your-user/your-flutter-app.git --session my-feature

# List available sessions
./run.sh --list-sessions

# Talk to the Manager naturally
You: "Add dark mode support to the app"
Manager: [Creates plan, spawns worker sub-agents, monitors progress, applies patches]
```

See [orchestrator/README.md](./orchestrator/README.md) for full documentation.

## Architecture

- **Manager** runs in a Docker container with `--dangerously-skip-permissions` (sandboxed)
- **Workers** are Claude Code sub-agents spawned via the Task tool
- Workers operate in isolated **git worktrees** (`.worktrees/<task-id>/`)
- Workers cannot commit or push (git hooks block them)
- Manager collects patches, reviews, and commits

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

**Note**: The token from `claude setup-token` has limited scopes. Features like `/usage` will fail with permission errors, but all coding features work fine.

## Security Notes

- SSH keys are mounted **read-only** - Claude cannot modify them
- Claude token is passed via environment variable (not stored in image)
- Claude cannot access your host filesystem (only the cloned repo inside the container)
- Containers run as non-root user (`dev`), isolated from your host
- Workers run in git worktrees with commit/push hooks disabled

## License

MIT
