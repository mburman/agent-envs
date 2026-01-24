# Claude Code Context

This repo contains Docker environments for running Claude Code with `--dangerously-skip-permissions` in isolated containers.

## Repository Structure

```
agent-envs/
├── README.md           # Overview and quick start
├── CLAUDE.md           # This file
└── flutter/            # Flutter/Dart environment
    ├── Dockerfile      # Ubuntu 22.04 + Flutter SDK + Node.js + Claude Code
    ├── entrypoint.sh   # Clones repo, installs deps, starts Claude
    └── README.md
```

## Flutter Environment

The Flutter environment (`flutter/`) includes:
- Ubuntu 22.04, Flutter SDK (stable), Dart SDK, Node.js 20, Claude Code CLI
- Build tools: clang, cmake, ninja, pkg-config, GTK3

**Monorepo support**: The entrypoint automatically detects and installs dependencies for any subdirectory containing a `pubspec.yaml`. This handles common structures like:
- `packages/*/pubspec.yaml` (Dart packages)
- `mcp/pubspec.yaml` (MCP servers)
- Any other nested Dart/Flutter packages

## Adding a New Environment

1. Create a new directory (e.g., `python/`, `node/`, `rust/`)
2. Add these files:
   - `Dockerfile` - Base image with all tools needed
   - `entrypoint.sh` - Script that clones repo, installs deps, starts Claude
   - `README.md` - Environment-specific docs

3. Update the root README.md to list the new environment

## Common Patterns

Each environment follows this pattern:

```dockerfile
# Dockerfile
FROM base-image
# Install language toolchain
# Install Node.js (for Claude Code)
# Install Claude Code: npm install -g @anthropic-ai/claude-code
# Prepare SSH for GitHub
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

```bash
# entrypoint.sh
#!/bin/bash
set -e
# Validate REPO_URL
# Clone repo
# Install dependencies
exec claude --dangerously-skip-permissions "$@"
```

## Authentication

Claude Code uses a long-lived token passed via `CLAUDE_CODE_OAUTH_TOKEN` environment variable.

```bash
# Get a token (one-time):
claude setup-token

# Save to file:
echo "your-token-here" > ~/.claude-token
chmod 600 ~/.claude-token

# Pass to container:
-e CLAUDE_CODE_OAUTH_TOKEN="$(cat ~/.claude-token | tr -d '\n')"
```

## Environment Variables (All Environments)

| Variable | Purpose |
|----------|---------|
| `REPO_URL` | SSH URL of repo to clone |
| `REPO_BRANCH` | Branch to clone (default: `main`) |

## Testing

```bash
# Build an environment
cd flutter
docker build -t claude-flutter .

# Test it
docker run -it --rm \
  -e REPO_URL="git@github.com:user/test-repo.git" \
  -e CLAUDE_CODE_OAUTH_TOKEN="$(cat ~/.claude-token | tr -d '\n')" \
  -v ~/.ssh/id_ed25519:/home/dev/.ssh/id_ed25519:ro \
  claude-flutter
```
