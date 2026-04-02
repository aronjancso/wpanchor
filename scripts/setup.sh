#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
ENV_FILE="${ROOT_DIR}/.env"
BACKUP_FILE="${ROOT_DIR}/sql/wordpress.sql"

set -a; source "$ENV_FILE"; set +a

echo "============================================"
echo " WordPress + Static subdomain setup"
echo " Domain:  ${DOMAIN}"
echo " Static:  ${STATIC_DOMAIN}"
echo "============================================"

# --- 1. Check SQL dump ---
echo ""
echo "[1/5] Checking database dump..."
if [ ! -f "$BACKUP_FILE" ]; then
    echo "      ERROR: sql/wordpress.sql not found."
    echo "      Place your SQL dump at: ${BACKUP_FILE}"
    exit 1
fi
echo "      Found: ${BACKUP_FILE}"

# --- 2. Start stack in pre mode ---
echo ""
echo "[2/5] Starting stack in pre-certbot mode..."
sed -i "s/^CERTBOT_STAGE=.*/CERTBOT_STAGE=pre/" "$ENV_FILE"
docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d

# Wait for MySQL process to be alive
echo "      Waiting for MySQL to be ready..."
RETRIES=30
COUNT=0
until docker compose -f "${ROOT_DIR}/docker-compose.yml" exec -T mysql \
    mysqladmin ping -h localhost -uroot -p"${DB_ROOT_PASSWORD}" --silent 2>/dev/null; do
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -ge "$RETRIES" ]; then
        echo ""
        echo "      ERROR: MySQL did not become ready after $((RETRIES * 2)) seconds."
        docker compose -f "${ROOT_DIR}/docker-compose.yml" logs mysql
        exit 1
    fi
    printf "."
    sleep 2
done
echo ""
echo "      MySQL is accepting connections."

# Wait for root auth to be fully initialized
echo "      Waiting for root authentication to be ready..."
COUNT=0
until docker compose -f "${ROOT_DIR}/docker-compose.yml" exec -T mysql \
    mysql -uroot -p"${DB_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; do
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -ge "$RETRIES" ]; then
        echo ""
        echo "      ERROR: MySQL root auth did not become ready after $((RETRIES * 2)) seconds."
        docker compose -f "${ROOT_DIR}/docker-compose.yml" logs mysql
        exit 1
    fi
    printf "."
    sleep 2
done
echo ""
echo "      MySQL is ready."

# --- 3. Import database ---
echo ""
echo "[3/5] Importing database..."
docker compose -f "${ROOT_DIR}/docker-compose.yml" exec -T mysql \
    mysql -uroot -p"${DB_ROOT_PASSWORD}" -e \
    "DROP DATABASE IF EXISTS \`${DB_NAME}\`; CREATE DATABASE \`${DB_NAME}\`;"

docker compose -f "${ROOT_DIR}/docker-compose.yml" exec -T mysql \
    mysql -uroot -p"${DB_ROOT_PASSWORD}" "${DB_NAME}" < "$BACKUP_FILE"

echo "      Database imported."

# --- 4. Request SSL certificates ---
echo ""
echo "[4/5] Requesting certificates..."

echo "      ${DOMAIN} + www.${DOMAIN}..."
docker compose -f "${ROOT_DIR}/docker-compose.yml" run --rm \
    --entrypoint certbot certbot certonly \
    --webroot --webroot-path=/var/www/certbot \
    -d "${DOMAIN}" -d "www.${DOMAIN}" \
    --email "${CERTBOT_EMAIL}" \
    --agree-tos --no-eff-email

echo "      ${STATIC_DOMAIN}..."
docker compose -f "${ROOT_DIR}/docker-compose.yml" run --rm \
    --entrypoint certbot certbot certonly \
    --webroot --webroot-path=/var/www/certbot \
    -d "${STATIC_DOMAIN}" \
    --email "${CERTBOT_EMAIL}" \
    --agree-tos --no-eff-email

# --- 5. Switch to HTTPS mode ---
echo ""
echo "[5/5] Switching to HTTPS mode..."
sed -i "s/^CERTBOT_STAGE=.*/CERTBOT_STAGE=post/" "$ENV_FILE"
docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d

echo ""
echo "============================================"
echo " Done!"
echo " https://${DOMAIN}"
echo " https://www.${DOMAIN}"
echo " https://${STATIC_DOMAIN}"
echo "============================================"
