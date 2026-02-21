#!/bin/bash
set -e

CONFIG_DIR="/home/opencode/.config/opencode"
CONFIG_FILE="${CONFIG_DIR}/opencode.json"
TEMPLATE="/home/opencode/opencode.json.template"

# Bootstrap opencode.json from template if not present in the mounted volume
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "[entrypoint] opencode.json not found, copying default template..."
  mkdir -p "${CONFIG_DIR}"
  cp "${TEMPLATE}" "${CONFIG_FILE}"
fi

bootstrap_ssh() {
  if [ "${SSH_BOOTSTRAP:-true}" != "true" ]; then
    return
  fi

  local source_dir="${SSH_SOURCE_DIR:-/home/opencode/.ssh-host}"
  local target_dir="/home/opencode/.ssh"
  local key_name="${SSH_PRIVATE_KEY_NAME:-id_ed25519}"
  local key_path="${source_dir}/${key_name}"

  if [ ! -d "${source_dir}" ]; then
    echo "[entrypoint] SSH source dir not found (${source_dir}), skipping SSH bootstrap."
    return
  fi

  mkdir -p "${target_dir}"
  chmod 700 "${target_dir}"

  if [ -f "${key_path}" ]; then
    cp "${key_path}" "${target_dir}/${key_name}"
    chmod 600 "${target_dir}/${key_name}"
    if [ -f "${key_path}.pub" ]; then
      cp "${key_path}.pub" "${target_dir}/${key_name}.pub"
      chmod 644 "${target_dir}/${key_name}.pub"
    fi
  else
    echo "[entrypoint] SSH private key not found (${key_path}), skipping key copy."
  fi

  if [ -f "${source_dir}/known_hosts" ]; then
    cp "${source_dir}/known_hosts" "${target_dir}/known_hosts"
    chmod 644 "${target_dir}/known_hosts"
  fi

  if [ -f "${source_dir}/config" ]; then
    cp "${source_dir}/config" "${target_dir}/config"
    chmod 600 "${target_dir}/config"
  fi

  if [ "${SSH_ADD_GITHUB_KNOWN_HOSTS:-true}" = "true" ]; then
    if ! grep -q "github.com" "${target_dir}/known_hosts" 2>/dev/null; then
      ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "${target_dir}/known_hosts" 2>/dev/null || true
      chmod 644 "${target_dir}/known_hosts" 2>/dev/null || true
    fi
  fi

  if [ "${GIT_USE_SSH_FOR_GITHUB:-true}" = "true" ]; then
    git config --global url."git@github.com:".insteadOf "https://github.com/" || true
  fi
}

bootstrap_ocx() {
  if [ "${OCX_BOOTSTRAP:-true}" != "true" ]; then
    return
  fi

  if ! command -v ocx >/dev/null 2>&1; then
    echo "[entrypoint] ocx CLI not found, skipping OCX bootstrap."
    return
  fi

  if [ ! -d "/workspace" ] || [ ! -w "/workspace" ]; then
    echo "[entrypoint] /workspace is not writable, skipping OCX bootstrap."
    return
  fi

  local registry_url="${OCX_REGISTRY_URL:-https://registry.kdco.dev}"
  local registry_name="${OCX_REGISTRY_NAME:-kdco}"
  local background_component="${OCX_BACKGROUND_COMPONENT:-kdco/background-agents}"
  local plugin_dir="/workspace/.opencode/plugin"

  # Safe to retry on every boot; ocx handles idempotent updates with --force.
  if ! ocx registry add "${registry_url}" --name "${registry_name}" --global --force >/dev/null 2>&1; then
    echo "[entrypoint] Warning: failed to add OCX registry (${registry_name})."
  fi

  if [ ! -f "/workspace/.opencode/ocx.jsonc" ]; then
    if ! ocx init -f --cwd /workspace >/dev/null 2>&1; then
      echo "[entrypoint] Warning: failed to initialize OCX in /workspace."
      return
    fi
  fi

  if [ -f "${plugin_dir}/background-agents.ts" ] || [ -f "${plugin_dir}/kdco-background-agents.ts" ]; then
    return
  fi

  if ocx add "${background_component}" --cwd /workspace --force >/dev/null 2>&1; then
    echo "[entrypoint] Installed OCX component: ${background_component}"
  else
    echo "[entrypoint] Warning: failed to install OCX component (${background_component})."
  fi
}

bootstrap_ssh
bootstrap_ocx

exec "$@"
