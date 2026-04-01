#!/usr/bin/env bash
set -euo pipefail

# Quick setup for this app on an Ubuntu/Debian VPS.
# Usage:
#   sudo DOMAIN=prd.dnnicolini.com APP_DIR=/opt/ficha APP_NAME=ficha bash scripts/setup_vps.sh

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root. Example:"
  echo "  sudo DOMAIN=prd.dnnicolini.com bash scripts/setup_vps.sh"
  exit 1
fi

DOMAIN="${DOMAIN:-prd.dnnicolini.com}"
APP_NAME="${APP_NAME:-ficha}"
APP_DIR="${APP_DIR:-/opt/ficha}"
APP_PORT="${APP_PORT:-8000}"
APP_MODULE="${APP_MODULE:-app:app}"

DEPLOY_USER="${DEPLOY_USER:-${SUDO_USER:-}}"
if [[ -z "${DEPLOY_USER}" || "${DEPLOY_USER}" == "root" ]]; then
  echo "Set DEPLOY_USER to your linux user."
  echo "Example:"
  echo "  sudo DEPLOY_USER=ubuntu DOMAIN=${DOMAIN} bash scripts/setup_vps.sh"
  exit 1
fi
DEPLOY_GROUP="$(id -gn "${DEPLOY_USER}")"

if [[ ! -f "${APP_DIR}/requirements.txt" ]]; then
  echo "Project not found in ${APP_DIR} (requirements.txt missing)."
  echo "Copy/clone the project first, then run again."
  exit 1
fi

echo "==> Installing system packages"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv python3-pip caddy

echo "==> Setting ownership for ${APP_DIR}"
chown -R "${DEPLOY_USER}:${DEPLOY_GROUP}" "${APP_DIR}"

echo "==> Creating virtualenv and installing python packages"
sudo -u "${DEPLOY_USER}" python3 -m venv "${APP_DIR}/.venv"
sudo -u "${DEPLOY_USER}" "${APP_DIR}/.venv/bin/pip" install --upgrade pip
sudo -u "${DEPLOY_USER}" "${APP_DIR}/.venv/bin/pip" install -r "${APP_DIR}/requirements.txt" gunicorn

SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
echo "==> Writing systemd service ${SERVICE_FILE}"
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=${APP_NAME} (Gunicorn)
After=network.target

[Service]
User=${DEPLOY_USER}
Group=${DEPLOY_GROUP}
WorkingDirectory=${APP_DIR}
Environment="PATH=${APP_DIR}/.venv/bin"
ExecStart=${APP_DIR}/.venv/bin/gunicorn --workers 2 --bind 127.0.0.1:${APP_PORT} ${APP_MODULE}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "==> Enabling and starting ${APP_NAME}"
systemctl daemon-reload
systemctl enable --now "${APP_NAME}"

echo "==> Writing Caddy config for ${DOMAIN}"
cat > /etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    reverse_proxy 127.0.0.1:${APP_PORT}
}
EOF

echo "==> Restarting Caddy"
systemctl restart caddy

echo "==> Opening firewall ports (if ufw exists)"
if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
fi

echo
echo "Setup complete."
echo "Domain: https://${DOMAIN}"
echo "Service status:"
systemctl --no-pager --full status "${APP_NAME}" | sed -n '1,20p' || true
echo
systemctl --no-pager --full status caddy | sed -n '1,20p' || true
