#!/usr/bin/env bash
set -euo pipefail

# Deploy para stack docker+traefik:
# - git pull
# - docker compose up -d --build
#
# Uso:
#   cd /opt/ficha
#   bash scripts/deploy_vps_docker.sh
#
# Opcional:
#   BRANCH=main DOMAIN=prd.dnnicolini.com TRAEFIK_CERTRESOLVER=le bash scripts/deploy_vps_docker.sh

APP_DIR="${APP_DIR:-/opt/ficha}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.traefik.yml}"
DOMAIN="${DOMAIN:-prd.dnnicolini.com}"
TRAEFIK_CERTRESOLVER="${TRAEFIK_CERTRESOLVER:-le}"

if [[ ! -d "${APP_DIR}/.git" ]]; then
  echo "Git repository not found in ${APP_DIR}"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose plugin missing."
  exit 1
fi

cd "${APP_DIR}"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
BRANCH="${BRANCH:-${CURRENT_BRANCH}}"

echo "==> Deploying branch ${BRANCH}"
git fetch --all --prune
git checkout "${BRANCH}"
git pull --ff-only origin "${BRANCH}"

echo "==> Rebuilding and restarting stack"
DOMAIN="${DOMAIN}" TRAEFIK_CERTRESOLVER="${TRAEFIK_CERTRESOLVER}" \
  docker compose -f "${COMPOSE_FILE}" up -d --build --remove-orphans

echo
echo "Deploy complete."
docker compose -f "${COMPOSE_FILE}" ps
