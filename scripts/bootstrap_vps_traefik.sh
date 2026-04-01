#!/usr/bin/env bash
set -euo pipefail

# Full bootstrap for a fresh VPS:
# 1) install git
# 2) clone/update repo
# 3) run full setup (venv + gunicorn + systemd + traefik dynamic config)
#
# Usage example:
# sudo DEPLOY_USER=ubuntu \
#      REPO_URL=https://github.com/seu-user/seu-repo.git \
#      BRANCH=main \
#      DOMAIN=prd.dnnicolini.com \
#      bash scripts/bootstrap_vps_traefik.sh
#
# Optional env:
#   APP_NAME=ficha
#   APP_DIR=/opt/ficha
#   APP_PORT=8000
#   APP_MODULE=app:app
#   APP_UPSTREAM=http://127.0.0.1:8000
#   TRAEFIK_DYNAMIC_DIR=/etc/traefik/dynamic
#   TRAEFIK_CONFIG_FILE=ficha.yml
#   TRAEFIK_ENTRYPOINT_HTTP=web
#   TRAEFIK_ENTRYPOINT_HTTPS=websecure
#   CERT_RESOLVER=letsencrypt

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root."
  echo "Example:"
  echo "  sudo DEPLOY_USER=ubuntu REPO_URL=https://github.com/seu-user/seu-repo.git DOMAIN=prd.dnnicolini.com bash scripts/bootstrap_vps_traefik.sh"
  exit 1
fi

DEPLOY_USER="${DEPLOY_USER:-${SUDO_USER:-}}"
if [[ -z "${DEPLOY_USER}" || "${DEPLOY_USER}" == "root" ]]; then
  echo "Set DEPLOY_USER to your linux user."
  echo "Example: sudo DEPLOY_USER=ubuntu ..."
  exit 1
fi
DEPLOY_GROUP="$(id -gn "${DEPLOY_USER}")"

REPO_URL="${REPO_URL:-}"
if [[ -z "${REPO_URL}" ]]; then
  echo "Set REPO_URL with your repository URL."
  echo "Example: REPO_URL=https://github.com/seu-user/seu-repo.git"
  exit 1
fi

BRANCH="${BRANCH:-main}"
DOMAIN="${DOMAIN:-prd.dnnicolini.com}"
APP_NAME="${APP_NAME:-ficha}"
APP_DIR="${APP_DIR:-/opt/ficha}"
APP_PORT="${APP_PORT:-8000}"
APP_MODULE="${APP_MODULE:-app:app}"
APP_UPSTREAM="${APP_UPSTREAM:-http://127.0.0.1:${APP_PORT}}"
TRAEFIK_DYNAMIC_DIR="${TRAEFIK_DYNAMIC_DIR:-/etc/traefik/dynamic}"
TRAEFIK_CONFIG_FILE="${TRAEFIK_CONFIG_FILE:-ficha.yml}"
TRAEFIK_ENTRYPOINT_HTTP="${TRAEFIK_ENTRYPOINT_HTTP:-web}"
TRAEFIK_ENTRYPOINT_HTTPS="${TRAEFIK_ENTRYPOINT_HTTPS:-websecure}"
CERT_RESOLVER="${CERT_RESOLVER:-letsencrypt}"

echo "==> Installing minimum packages for bootstrap"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y git

echo "==> Ensuring app directory parent exists"
mkdir -p "$(dirname "${APP_DIR}")"
chown "${DEPLOY_USER}:${DEPLOY_GROUP}" "$(dirname "${APP_DIR}")"

if [[ -d "${APP_DIR}/.git" ]]; then
  echo "==> Repo already exists in ${APP_DIR}, updating"
  sudo -u "${DEPLOY_USER}" git -C "${APP_DIR}" fetch --all --prune
  sudo -u "${DEPLOY_USER}" git -C "${APP_DIR}" checkout "${BRANCH}"
  sudo -u "${DEPLOY_USER}" git -C "${APP_DIR}" pull --ff-only origin "${BRANCH}"
else
  if [[ -d "${APP_DIR}" ]]; then
    echo "Directory ${APP_DIR} exists but is not a git repository."
    echo "Remove it or change APP_DIR."
    exit 1
  fi
  echo "==> Cloning repo to ${APP_DIR}"
  sudo -u "${DEPLOY_USER}" git clone --branch "${BRANCH}" --single-branch "${REPO_URL}" "${APP_DIR}"
fi

SETUP_SCRIPT="${APP_DIR}/scripts/setup_vps_traefik.sh"
if [[ ! -f "${SETUP_SCRIPT}" ]]; then
  echo "Setup script not found: ${SETUP_SCRIPT}"
  echo "Check if REPO_URL/BRANCH are correct."
  exit 1
fi

echo "==> Running full setup script"
DEPLOY_USER="${DEPLOY_USER}" \
DOMAIN="${DOMAIN}" \
APP_NAME="${APP_NAME}" \
APP_DIR="${APP_DIR}" \
APP_PORT="${APP_PORT}" \
APP_MODULE="${APP_MODULE}" \
APP_UPSTREAM="${APP_UPSTREAM}" \
TRAEFIK_DYNAMIC_DIR="${TRAEFIK_DYNAMIC_DIR}" \
TRAEFIK_CONFIG_FILE="${TRAEFIK_CONFIG_FILE}" \
TRAEFIK_ENTRYPOINT_HTTP="${TRAEFIK_ENTRYPOINT_HTTP}" \
TRAEFIK_ENTRYPOINT_HTTPS="${TRAEFIK_ENTRYPOINT_HTTPS}" \
CERT_RESOLVER="${CERT_RESOLVER}" \
bash "${SETUP_SCRIPT}"

echo
echo "Bootstrap complete."
echo "Domain configured: https://${DOMAIN}"
echo "Deploy next updates with:"
echo "  cd ${APP_DIR} && bash scripts/deploy_vps.sh"
