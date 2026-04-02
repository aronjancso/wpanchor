set dotenv-load

# List available recipes
default:
    @just --list

# Run the full setup (database import + SSL certificates)
setup:
    chmod +x scripts/setup.sh nginx/entrypoint.sh
    ./scripts/setup.sh

# Start all containers
up:
    docker compose up -d

# Stop all containers
down:
    docker compose down

# Restart nginx (e.g. after config change)
restart-nginx:
    docker compose restart nginx

# Rebuild PHP-FPM image and restart
rebuild:
    docker compose build php
    docker compose up -d

# Follow all container logs
logs:
    docker compose logs -f

# Show running containers
ps:
    docker compose ps

# Access the MySQL console
mysql:
    docker compose exec mysql mysql -uroot -p"${DB_ROOT_PASSWORD}"

# Test SSL certificate renewal
renew-dry-run:
    docker compose run --rm --entrypoint certbot certbot renew --dry-run
