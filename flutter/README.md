# Flutter Environment

Docker environment for running Claude Code with Flutter/Dart projects.

## What's Included

- **Ubuntu 22.04** base image
- **Flutter SDK** (stable channel)
- **Dart SDK** (bundled with Flutter)
- **Node.js 20** (for Claude Code)
- **Claude Code** CLI
- **Build tools**: clang, cmake, ninja, pkg-config
- **Linux desktop dependencies**: GTK3, etc.

## Quick Start

```bash
# Build the image (one-time, takes a while)
docker build -t claude-flutter .

# Run with your Flutter repo (easy way)
./run.sh --repo git@github.com:your-username/your-flutter-repo.git

# Or with custom options
./run.sh --repo git@github.com:user/repo.git --branch feature/my-branch
```

**Alternative** (full docker command):
```bash
docker run -it --rm \
  -e REPO_URL="git@github.com:your-username/your-flutter-repo.git" \
  -e CLAUDE_CODE_OAUTH_TOKEN="$(cat ~/.claude-token | tr -d '\n')" \
  -v ~/.ssh/id_ed25519:/home/dev/.ssh/id_ed25519:ro \
  claude-flutter
```

## Prerequisites

**Claude Code authentication**: You need a long-lived OAuth token from Claude Code (requires Claude Pro or Max subscription).

```bash
# On your host machine, run:
claude setup-token

# Follow the browser prompt to authenticate, then save the token:
echo "your-token-here" > ~/.claude-token
chmod 600 ~/.claude-token
```

**Note**: The `tr -d '\n'` in the run command strips newlines from the token, which would otherwise cause HTTP header errors.

## Using the run.sh Script

```bash
# Basic usage
./run.sh --repo git@github.com:user/repo.git

# With custom branch
./run.sh --repo git@github.com:user/repo.git --branch feature/my-branch

# With custom token/SSH key paths
./run.sh --repo git@github.com:user/repo.git \
  --token ~/my-token.txt \
  --ssh-key ~/.ssh/id_rsa

# Or use environment variable
export REPO_URL="git@github.com:user/repo.git"
./run.sh
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `REPO_URL` | Yes | - | Git URL of the repo to clone (SSH format) |
| `REPO_BRANCH` | No | `main` | Branch to clone |

## Usage Examples

### Basic usage
```bash
docker run -it --rm \
  -e REPO_URL="git@github.com:user/my-flutter-app.git" \
  -e CLAUDE_CODE_OAUTH_TOKEN="$(cat ~/.claude-token | tr -d '\n')" \
  -v ~/.ssh/id_ed25519:/home/dev/.ssh/id_ed25519:ro \
  claude-flutter
```

### Specify a branch
```bash
docker run -it --rm \
  -e REPO_URL="git@github.com:user/my-flutter-app.git" \
  -e REPO_BRANCH="feature/new-feature" \
  -e CLAUDE_CODE_OAUTH_TOKEN="$(cat ~/.claude-token | tr -d '\n')" \
  -v ~/.ssh/id_ed25519:/home/dev/.ssh/id_ed25519:ro \
  claude-flutter
```

### Cache pub dependencies across runs
```bash
docker run -it --rm \
  -e REPO_URL="git@github.com:user/my-flutter-app.git" \
  -e CLAUDE_CODE_OAUTH_TOKEN="$(cat ~/.claude-token | tr -d '\n')" \
  -v ~/.ssh/id_ed25519:/home/dev/.ssh/id_ed25519:ro \
  -v flutter-pub-cache:/root/.pub-cache \
  claude-flutter
```

## How It Works

1. On container start, the entrypoint script clones your repo from `REPO_URL`
2. Runs `flutter pub get` for the root project
3. Auto-detects any subdirectory with a `pubspec.yaml` and runs `dart pub get` (monorepo support)
4. Launches Claude Code with `--dangerously-skip-permissions`
5. When you exit, the container stops and all changes are discarded

## Customization

### Updating Flutter version
Change the branch in the Dockerfile:
```dockerfile
RUN git clone https://github.com/flutter/flutter.git -b stable $FLUTTER_HOME
```
Options: `stable`, `beta`, `master`, or a specific version tag.

## Rebuilding

Only rebuild when you need to update the tools (Flutter, Claude Code, etc.):

```bash
docker build --no-cache -t claude-flutter .
```

## Notes

- The image is large (~3-4GB) due to Flutter SDK
- First build takes a while; subsequent builds use Docker cache
- Target repo is cloned fresh each run (ephemeral)

## Known Limitations

- **Limited OAuth scopes**: Tokens from `claude setup-token` only have `user:inference` scope
- **Profile features unavailable**: Commands like `/usage` require `user:profile` scope and will fail with permission errors
- **macOS credential storage**: Credentials are stored in macOS Keychain (not `~/.claude`), so mounting `~/.claude` won't provide full authentication
- **Coding features work**: All core features (read, write, edit, bash, grep, etc.) work normally
