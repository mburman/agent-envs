# Agent Environments

Docker environments for running [Claude Code](https://github.com/anthropics/claude-code) with `--dangerously-skip-permissions` in isolated containers.

## Available Environments

| Environment | Description |
|-------------|-------------|
| [flutter/](./flutter/) | Flutter + Dart with monorepo support (auto-detects nested packages) |

## Why?

Running Claude Code with `--dangerously-skip-permissions` allows it to execute commands without confirmation prompts. This is useful for autonomous coding tasks but risky on your host machine. These containers provide:

- **Isolation**: Claude can only modify files inside the container
- **Fresh state**: Each run clones your repo fresh - changes are discarded when the container stops
- **Full toolchain**: All dependencies pre-installed for each environment

## Prerequisites

**Claude Code authentication**: You need a long-lived token from Claude Code.

```bash
# On your host machine:
claude setup-token

# Save the token to a file:
echo "your-token-here" > ~/.claude-token
chmod 600 ~/.claude-token
```

## Quick Start

```bash
# Build a specific environment
cd flutter
docker build -t claude-flutter .

# Run with your repo
docker run -it --rm \
  -e REPO_URL="git@github.com:your-username/your-repo.git" \
  -e CLAUDE_CODE_OAUTH_TOKEN="$(cat ~/.claude-token)" \
  -v ~/.ssh/id_ed25519:/home/dev/.ssh/id_ed25519:ro \
  claude-flutter
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
