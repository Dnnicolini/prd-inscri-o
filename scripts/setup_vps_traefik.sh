#!/usr/bin/env bash
set -euo pipefail

# Quick setup for this app behind Traefik (Ubuntu/Debian VPS).
# Usage:
#   sudo DEPLOY_USER=ubuntu DOMAIN=prd.dnnicolini.com bash scripts/setup_vps_traefik.sh
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
  echo "Run as root. Example:"
  echo "  sudo DEPLOY_USER=ubuntu DOMAIN=prd.dnnicolini.com bash scripts/setup_vps_traefik.sh"
  exit 1
fi

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

DEPLOY_USER="${DEPLOY_USER:-${SUDO_USER:-}}"
if [[ -z "${DEPLOY_USER}" || "${DEPLOY_USER}" == "root" ]]; then
  echo "Set DEPLOY_USER to your linux user."
  echo "Example:"
  echo "  sudo DEPLOY_USER=ubuntu DOMAIN=${DOMAIN} bash scripts/setup_vps_traefik.sh"
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
DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv python3-pip

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

echo "==> Writing Traefik dynamic config"
mkdir -p "${TRAEFIK_DYNAMIC_DIR}"
cat > "${TRAEFIK_DYNAMIC_DIR}/${TRAEFIK_CONFIG_FILE}" <<EOF
http:
  routers:
    ${APP_NAME}-http:
      rule: Host(\`${DOMAIN}\`)
      entryPoints:
        - ${TRAEFIK_ENTRYPOINT_HTTP}
      middlewares:
        - ${APP_NAME}-https-redirect
      service: ${APP_NAME}-service

    ${APP_NAME}-https:
      rule: Host(\`${DOMAIN}\`)
      entryPoints:
        - ${TRAEFIK_ENTRYPOINT_HTTPS}
      tls:
        certResolver: ${CERT_RESOLVER}
      service: ${APP_NAME}-service

  middlewares:
    ${APP_NAME}-https-redirect:
      redirectScheme:
        scheme: https
        permanent: true

  services:
    ${APP_NAME}-service:
      loadBalancer:
        servers:
          - url: "${APP_UPSTREAM}"
EOF

echo "==> Reloading Traefik (if managed by systemd)"
if systemctl list-unit-files | grep -q '^traefik\.service'; then
  systemctl reload traefik || systemctl restart traefik
  systemctl --no-pager --full status traefik | sed -n '1,20p' || true
else
  echo "traefik.service not found in systemd."
  echo "Reload Traefik manually to apply:"
  echo "  ${TRAEFIK_DYNAMIC_DIR}/${TRAEFIK_CONFIG_FILE}"
fi

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
echo "Traefik dynamic config:"
echo "  ${TRAEFIK_DYNAMIC_DIR}/${TRAEFIK_CONFIG_FILE}"
