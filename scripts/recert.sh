#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
ENV_FILE="${ROOT_DIR}/.env"

set -a; source "$ENV_FILE"; set +a

echo "============================================"
echo " SSL Certificate Recreation"
echo " Domain:  ${DOMAIN}"
echo " Static:  ${STATIC_DOMAIN}"
echo "============================================"

# --- Switch to pre mode ---
echo ""
echo "[1/4] Switching to pre-certbot mode..."
sed -i "s/^CERTBOT_STAGE=.*/CERTBOT_STAGE=pre/" "$ENV_FILE"
docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d nginx
sleep 3

# --- Request certificates ---
echo ""
echo "[2/4] Requesting certificate for ${DOMAIN} + www.${DOMAIN}..."
docker compose -f "${ROOT_DIR}/docker-compose.yml" run --rm \
    --entrypoint certbot certbot certonly \
    --webroot --webroot-path=/var/www/certbot \
    -d "${DOMAIN}" -d "www.${DOMAIN}" \
    --email "${CERTBOT_EMAIL}" \
    --agree-tos --no-eff-email

echo ""
echo "[3/4] Requesting certificate for ${STATIC_DOMAIN}..."
docker compose -f "${ROOT_DIR}/docker-compose.yml" run --rm \
    --entrypoint certbot certbot certonly \
    --webroot --webroot-path=/var/www/certbot \
    -d "${STATIC_DOMAIN}" \
    --email "${CERTBOT_EMAIL}" \
    --agree-tos --no-eff-email

# --- Switch to post mode ---
echo ""
echo "[4/4] Switching to HTTPS mode..."
sed -i "s/^CERTBOT_STAGE=.*/CERTBOT_STAGE=post/" "$ENV_FILE"
docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d

echo ""
echo "============================================"
echo " Done!"
echo " https://${DOMAIN}"
echo " https://www.${DOMAIN}"
echo " https://${STATIC_DOMAIN}"
echo "============================================"
