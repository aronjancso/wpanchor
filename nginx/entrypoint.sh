#!/bin/sh
set -e

STAGE=${CERTBOT_STAGE:-pre}
TEMPLATE_DIR="/etc/nginx/templates/${STAGE}"
OUTPUT_DIR="/etc/nginx/conf.d"

echo "[nginx] Starting in '${STAGE}' mode..."

rm -f "${OUTPUT_DIR}"/*.conf

for template in "${TEMPLATE_DIR}"/*.conf.template; do
    filename=$(basename "$template" .template)

    # Skip static config when ENABLE_STATIC is not true
    if [ "$filename" = "static.conf" ] && [ "$ENABLE_STATIC" != "true" ]; then
        echo "[nginx] Skipped: ${filename} (ENABLE_STATIC is not true)"
        continue
    fi

    envsubst '$DOMAIN $STATIC_DOMAIN' < "$template" > "${OUTPUT_DIR}/${filename}"
    echo "[nginx] Generated: ${OUTPUT_DIR}/${filename}"
done

nginx -t

exec nginx -g 'daemon off;'
