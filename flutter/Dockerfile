FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    wget \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    libstdc++-12-dev \
    openssh-client \
    sudo \
    expect \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Flutter
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$PATH"

RUN git clone https://github.com/flutter/flutter.git -b stable $FLUTTER_HOME \
    && flutter precache \
    && flutter config --no-analytics \
    && dart --disable-analytics \
    && chmod -R a+rwx $FLUTTER_HOME

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Create non-root user
RUN useradd -m -s /bin/bash dev \
    && mkdir -p /app \
    && chown dev:dev /app

# Prepare SSH for dev user
RUN mkdir -p /home/dev/.ssh \
    && ssh-keyscan github.com >> /home/dev/.ssh/known_hosts \
    && chown -R dev:dev /home/dev/.ssh \
    && chmod 700 /home/dev/.ssh

# Prepare Claude config directory
RUN mkdir -p /home/dev/.config/claude-code \
    && chown -R dev:dev /home/dev/.config

WORKDIR /app

ENV REPO_URL=""
ENV REPO_BRANCH="main"

COPY entrypoint.sh /entrypoint.sh
COPY start-claude.exp /start-claude.exp
RUN chmod +x /entrypoint.sh /start-claude.exp

USER dev

# Mark Flutter as safe directory for git (owned by root, run as dev)
RUN git config --global --add safe.directory /opt/flutter

ENTRYPOINT ["/entrypoint.sh"]
