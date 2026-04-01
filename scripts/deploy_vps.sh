#!/usr/bin/env bash
set -euo pipefail

# Quick deploy script (pull latest code + install deps + restart service).
# Usage:
#   bash scripts/deploy_vps.sh
# Optional:
#   APP_DIR=/opt/ficha APP_NAME=ficha BRANCH=main bash scripts/deploy_vps.sh

APP_NAME="${APP_NAME:-ficha}"
APP_DIR="${APP_DIR:-/opt/ficha}"
PY_ENV="${PY_ENV:-${APP_DIR}/.venv}"

if [[ ! -d "${APP_DIR}/.git" ]]; then
  echo "Git repository not found in ${APP_DIR}"
  exit 1
fi

if [[ ! -x "${PY_ENV}/bin/python" ]]; then
  echo "Virtualenv not found in ${PY_ENV}"
  echo "Run setup first:"
  echo "  sudo bash scripts/setup_vps_traefik.sh"
  exit 1
fi

cd "${APP_DIR}"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
BRANCH="${BRANCH:-${CURRENT_BRANCH}}"

echo "==> Deploying ${APP_NAME} from branch ${BRANCH}"
git fetch --all --prune
git checkout "${BRANCH}"
git pull --ff-only origin "${BRANCH}"

echo "==> Installing python dependencies"
"${PY_ENV}/bin/pip" install -r requirements.txt gunicorn

echo "==> Restarting ${APP_NAME}"
sudo systemctl restart "${APP_NAME}"
sudo systemctl --no-pager --full status "${APP_NAME}" | sed -n '1,20p'

echo
echo "Deploy complete."
