# Agent Environments

[![Test Docker Builds](https://github.com/mburman/agent-envs/actions/workflows/test.yml/badge.svg)](https://github.com/mburman/agent-envs/actions/workflows/test.yml)

Docker environments for running [Claude Code](https://github.com/anthropics/claude-code) with `--dangerously-skip-permissions` in isolated containers.

## Available Environments

| Environment | Description |
|-------------|-------------|
| [orchestrator/](./orchestrator/) | **Manager agent** - coordinates workers, has Flutter + Docker CLI |
| [flutter/](./flutter/) | **Worker agent** - Flutter + Dart with monorepo support |

## Quick Start (Orchestration)

The orchestration system lets a Manager agent spawn and coordinate Worker agents:

```bash
# Build all images
./build.sh

# Start the Manager
./run.sh --repo git@github.com:your-user/your-flutter-app.git

# Talk to the Manager naturally
You: "Add dark mode support to the app"
Manager: [Creates plan, spawns workers, monitors progress, applies patches]
```

See [orchestrator/README.md](./orchestrator/README.md) for full documentation.

## Why?

Running Claude Code with `--dangerously-skip-permissions` allows it to execute commands without confirmation prompts. This is useful for autonomous coding tasks but risky on your host machine. These containers provide:

- **Isolation**: Claude can only modify files inside the container
- **Fresh state**: Each run clones your repo fresh - changes are discarded when the container stops
- **Full toolchain**: All dependencies pre-installed for each environment

## Prerequisites

**Claude Code authentication**: You need a long-lived OAuth token from Claude Code (requires Claude Pro or Max subscription).

```bash
# On your host machine, run:
claude setup-token

# Follow the browser prompt to authenticate, then save the token:
echo "your-token-here" > ~/.claude-token
chmod 600 ~/.claude-token
```

**Note**: The token from `claude setup-token` has limited scopes. Features like `/usage` will fail with permission errors, but all coding features (read, write, edit, bash, etc.) work fine.

## Quick Start

### Option A: Use Pre-built Image (Recommended)

```bash
cd flutter
docker pull ghcr.io/mburman/agent-envs/flutter:latest
docker tag ghcr.io/mburman/agent-envs/flutter:latest claude-flutter
./run.sh --repo git@github.com:your-username/your-repo.git
```

### Option B: Build Locally

```bash
cd flutter
docker build -t claude-flutter .
./run.sh --repo git@github.com:your-username/your-repo.git
```

## Adding New Environments

Create a new directory with:
```
new-env/
├── Dockerfile
├── entrypoint.sh
└── README.md
```

See existing environments for examples.

## Security Notes

- SSH keys are mounted **read-only** - Claude cannot modify them
- Claude token is passed via environment variable (not stored in image)
- Claude cannot access your host filesystem (only the cloned repo inside the container)
- Changes are ephemeral - nothing persists unless you explicitly mount volumes
- Containers run as non-root user (`dev`), isolated from your host

## License

MIT
