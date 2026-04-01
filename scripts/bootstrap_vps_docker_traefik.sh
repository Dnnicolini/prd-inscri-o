#!/usr/bin/env bash
set -euo pipefail

# Bootstrap completo para VPS com Traefik em container (provider docker):
# - instala git e docker (se faltar)
# - clona/atualiza repo
# - sobe app com docker compose + labels do Traefik
#
# Uso:
# sudo DEPLOY_USER=ubuntu \
#   REPO_URL=https://github.com/seu-user/seu-repo.git \
#   BRANCH=main \
#   DOMAIN=prd.dnnicolini.com \
#   APP_DIR=/opt/ficha \
#   bash scripts/bootstrap_vps_docker_traefik.sh

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root."
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
  echo "Set REPO_URL."
  echo "Example: REPO_URL=https://github.com/seu-user/seu-repo.git"
  exit 1
fi

BRANCH="${BRANCH:-main}"
DOMAIN="${DOMAIN:-prd.dnnicolini.com}"
APP_DIR="${APP_DIR:-/opt/ficha}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.traefik.yml}"
TRAEFIK_CERTRESOLVER="${TRAEFIK_CERTRESOLVER:-le}"
NETWORK_NAME="${NETWORK_NAME:-web}"

echo "==> Installing bootstrap dependencies"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ca-certificates

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker"
  curl -fsSL https://get.docker.com | sh
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose plugin missing."
  echo "Install docker compose plugin and rerun."
  exit 1
fi

usermod -aG docker "${DEPLOY_USER}" || true

echo "==> Preparing app directory"
mkdir -p "$(dirname "${APP_DIR}")"
chown "${DEPLOY_USER}:${DEPLOY_GROUP}" "$(dirname "${APP_DIR}")"

if [[ -d "${APP_DIR}/.git" ]]; then
  echo "==> Updating existing repo in ${APP_DIR}"
  sudo -u "${DEPLOY_USER}" git -C "${APP_DIR}" fetch --all --prune
  sudo -u "${DEPLOY_USER}" git -C "${APP_DIR}" checkout "${BRANCH}"
  sudo -u "${DEPLOY_USER}" git -C "${APP_DIR}" pull --ff-only origin "${BRANCH}"
else
  if [[ -d "${APP_DIR}" ]]; then
    echo "Directory ${APP_DIR} exists but is not a git repository."
    echo "Remove it or use another APP_DIR."
    exit 1
  fi
  echo "==> Cloning ${REPO_URL} (${BRANCH}) into ${APP_DIR}"
  sudo -u "${DEPLOY_USER}" git clone --branch "${BRANCH}" --single-branch "${REPO_URL}" "${APP_DIR}"
fi

if [[ ! -f "${APP_DIR}/${COMPOSE_FILE}" ]]; then
  echo "Compose file not found: ${APP_DIR}/${COMPOSE_FILE}"
  exit 1
fi

if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  echo "==> Creating docker network ${NETWORK_NAME}"
  docker network create "${NETWORK_NAME}"
fi

echo "==> Building and starting app"
cd "${APP_DIR}"
DOMAIN="${DOMAIN}" TRAEFIK_CERTRESOLVER="${TRAEFIK_CERTRESOLVER}" \
  docker compose -f "${COMPOSE_FILE}" up -d --build

echo
echo "Bootstrap complete."
echo "Domain: https://${DOMAIN}"
echo "Check containers:"
docker compose -f "${COMPOSE_FILE}" ps
