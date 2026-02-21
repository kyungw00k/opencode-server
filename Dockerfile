FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/opencode
ENV PATH="/home/opencode/.cargo/bin:/home/opencode/.bun/bin:/usr/local/go/bin:/home/opencode/.sdkman/candidates/kotlin/current/bin:/home/opencode/.sdkman/candidates/java/current/bin:${PATH}"

# ── System packages ───────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    # Base tools
    curl wget git unzip zip tar xz-utils gnupg ca-certificates \
    # Build essentials
    build-essential cmake pkg-config \
    # Python
    python3 python3-pip python3-venv python3-dev \
    # JVM (for Kotlin via SDKMAN)
    openjdk-21-jdk-headless zip unzip \
    # GitHub CLI
    software-properties-common \
    # Playwright dependencies (Chromium)
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libasound2t64 \
    # Utilities
    sudo jq vim less openssh-client \
  && rm -rf /var/lib/apt/lists/*

# ── GitHub CLI ────────────────────────────────────────────────────────────────
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y gh \
  && rm -rf /var/lib/apt/lists/*

# ── Google Chrome (amd64 only) ────────────────────────────────────────────────
RUN ARCH="$(dpkg --print-architecture)" \
  && if [ "${ARCH}" = "amd64" ]; then \
       curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
         | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
       && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
         > /etc/apt/sources.list.d/google-chrome.list \
       && apt-get update && apt-get install -y google-chrome-stable \
       && rm -rf /var/lib/apt/lists/*; \
     else \
       echo "Skipping Google Chrome install on architecture: ${ARCH}"; \
     fi

# ── Non-root user ─────────────────────────────────────────────────────────────
# Some base images already contain UID 1000. Reuse/rename it to keep stable UID.
RUN set -eux; \
    if id -u opencode >/dev/null 2>&1; then \
      usermod -s /bin/bash opencode; \
    elif getent passwd 1000 >/dev/null 2>&1; then \
      existing_user="$(getent passwd 1000 | cut -d: -f1)"; \
      usermod -l opencode -d /home/opencode -m "${existing_user}"; \
      if getent group "${existing_user}" >/dev/null 2>&1; then \
        groupmod -n opencode "${existing_user}"; \
      fi; \
    else \
      useradd -m -u 1000 -s /bin/bash opencode; \
    fi; \
    usermod -aG sudo opencode; \
    echo "opencode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/opencode; \
    chmod 0440 /etc/sudoers.d/opencode

USER opencode
WORKDIR /home/opencode

# ── Go ────────────────────────────────────────────────────────────────────────
RUN GO_VERSION=$(curl -fsSL https://go.dev/VERSION?m=text | head -1) \
  && curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz" \
       | sudo tar -C /usr/local -xz

# ── Rust ──────────────────────────────────────────────────────────────────────
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --profile minimal

# ── Node.js (LTS) via nvm ─────────────────────────────────────────────────────
ENV NVM_DIR=/home/opencode/.nvm
ENV NVM_SYMLINK_CURRENT=true
RUN curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
  && . "${NVM_DIR}/nvm.sh" \
  && nvm install --lts \
  && nvm alias default 'lts/*' \
  && nvm use default \
  && NODE_BIN_DIR="$(dirname "$(nvm which default)")" \
  && sudo ln -sf "${NODE_BIN_DIR}/node" /usr/local/bin/node \
  && sudo ln -sf "${NODE_BIN_DIR}/npm" /usr/local/bin/npm \
  && sudo ln -sf "${NODE_BIN_DIR}/npx" /usr/local/bin/npx
ENV PATH="${NVM_DIR}/current/bin:${PATH}"

# ── Bun ───────────────────────────────────────────────────────────────────────
RUN curl -fsSL https://bun.sh/install | bash

# ── SDKMAN (Kotlin) ───────────────────────────────────────────────────────────
RUN curl -fsSL "https://get.sdkman.io" | bash \
  && bash -c "source /home/opencode/.sdkman/bin/sdkman-init.sh && sdk install kotlin"

# ── Python uv ─────────────────────────────────────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/home/opencode/.local/bin:${PATH}"

# ── OpenCode ──────────────────────────────────────────────────────────────────
RUN curl -fsSL https://opencode.ai/install | bash
ENV PATH="/home/opencode/.opencode/bin:/home/opencode/.local/bin:${PATH}"

# ── Playwright (install browsers) ─────────────────────────────────────────────
RUN . "${NVM_DIR}/nvm.sh" \
  && npx -y playwright install chromium

# ── OpenSpec (Spec-Driven Development) ───────────────────────────────────────
RUN . "${NVM_DIR}/nvm.sh" \
  && npm install -g @fission-ai/openspec@latest

# ── OCX (OpenCode eXtensions CLI) ────────────────────────────────────────────
RUN . "${NVM_DIR}/nvm.sh" \
  && npm install -g ocx@latest

# ── OpenCode config ───────────────────────────────────────────────────────────
# Template is stored separately; entrypoint.sh copies it to the mounted config
# volume on first start if opencode.json doesn't exist yet.
RUN mkdir -p /home/opencode/.config/opencode \
             /home/opencode/.local/share/opencode \
             /home/opencode/.cache/opencode \
             /home/opencode/.ssh \
             /home/opencode/.ssh-host \
  && chmod 700 /home/opencode/.ssh

COPY --chown=opencode:opencode config/opencode.json /home/opencode/opencode.json.template
COPY --chown=opencode:opencode entrypoint.sh /home/opencode/entrypoint.sh
RUN chmod +x /home/opencode/entrypoint.sh

# ── Entrypoint ────────────────────────────────────────────────────────────────
EXPOSE 3000
ENTRYPOINT ["/home/opencode/entrypoint.sh"]
CMD ["opencode", "--verbose"]
