# WordPress Docker Stack

Dockerized WordPress stack with Nginx reverse proxy, automatic SSL certificates (Let's Encrypt), and a static asset subdomain.

**Services:** MySQL 8.0, PHP-FPM 8.3, Nginx, Certbot

## Prerequisites

- A Debian-based server (e.g. Debian 12/13, Ubuntu 22.04+) with a public IP address
- DNS records for your domain(s) pointing to the server IP
- SSH access with root or sudo privileges

## 1. Server Preparation

Connect to your server via SSH and install the required packages.

### 1.1 Update the system

```bash
sudo apt update && sudo apt upgrade -y
```

### 1.2 Install Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
```

### 1.3 Install just

```bash
sudo apt install -y just
```

### 1.4 Allow your user to run Docker (optional)

```bash
sudo usermod -aG docker $USER
```

Log out and back in for the group change to take effect.

### 1.5 Configure the firewall (UFW)

```bash
sudo apt install -y ufw
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
```

### 1.6 Set up swap

Recommended for low-memory servers.

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 2. Project Setup

### 2.1 Clone the repository

```bash
cd /opt
sudo git clone <REPO_URL> wordpress
sudo chown -R $USER:$USER /opt/wordpress
cd /opt/wordpress
```

### 2.2 Create the environment file

Create a `.env` file in the project root:

```bash
cat > .env << 'EOF'
CERTBOT_STAGE=pre

DOMAIN=example.com
STATIC_DOMAIN=static.example.com
CERTBOT_EMAIL=admin@example.com

DB_NAME=wordpress
DB_USER=wp_user
DB_PASSWORD=your_strong_password
DB_ROOT_PASSWORD=your_strong_root_password
EOF
```

> **Important:** Replace `example.com`, `static.example.com`, the email address, and both passwords with your own values.

## 3. Upload WordPress Files and Database

Three things need to be transferred to the server from your source environment.

### 3.1 WordPress files

Copy the full WordPress installation into the `www/` directory:

```bash
# From your local machine or source server:
rsync -avz /source/wordpress/ server:/opt/wordpress/www/
```

### 3.2 Static assets (if any)

Copy videos and images into the `static/` directory:

```bash
rsync -avz /source/static/ server:/opt/wordpress/static/
```

### 3.3 Database dump

Place the SQL dump at `sql/wordpress.sql`:

```bash
scp /source/wordpress.sql server:/opt/wordpress/sql/wordpress.sql
```

## 4. Configure wp-config.php

Edit `www/wp-config.php` so it connects to MySQL through the Docker network:

```php
define( 'DB_HOST',     'mysql:3306' );
define( 'DB_NAME',     'wordpress' );
define( 'DB_USER',     'wp_user' );
define( 'DB_PASSWORD', 'your_strong_password' );   // must match .env

define( 'FORCE_SSL_ADMIN', true );
if ( isset($_SERVER['HTTP_X_FORWARDED_PROTO']) &&
     $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {
    $_SERVER['HTTPS'] = 'on';
}
```

> **Important:** `DB_HOST` must be `mysql:3306` (the Docker Compose service name), NOT `localhost`.

## 5. Run the Setup

```bash
just setup
```

This automatically:
1. Verifies that `sql/wordpress.sql` exists
2. Starts the Docker stack in HTTP-only mode (`pre`)
3. Waits for MySQL to become ready
4. Imports the database
5. Requests Let's Encrypt SSL certificates for all domains
6. Switches to HTTPS mode (`post`) and restarts the stack

Once complete, these URLs should be live:
- `https://example.com`
- `https://www.example.com`
- `https://static.example.com`

## 6. Verify

```bash
just ps
just logs
```

## Just Commands

All operations are available through the `justfile`:

| Command | Description |
|---|---|
| `just setup` | Run the full setup (database import + SSL) |
| `just up` | Start all containers |
| `just down` | Stop all containers |
| `just restart-nginx` | Restart nginx (e.g. after config change) |
| `just rebuild` | Rebuild PHP-FPM image and restart |
| `just logs` | Follow all container logs |
| `just ps` | Show running containers |
| `just mysql` | Access the MySQL console |
| `just renew-dry-run` | Test SSL certificate renewal |

## Directory Structure

```
.
├── justfile                        # Task runner commands
├── docker-compose.yml              # Service definitions
├── .env                            # Environment variables (not committed)
├── docker/
│   └── Dockerfile.php              # Custom PHP-FPM image with mysqli/pdo extensions
├── nginx/
│   ├── entrypoint.sh               # Template processing and nginx startup
│   └── templates/
│       ├── pre/                    # HTTP-only config (before SSL)
│       └── post/                   # HTTPS config (after SSL)
├── php/
│   └── custom.ini                  # PHP settings (upload limits, memory, timeouts)
├── scripts/
│   └── setup.sh                    # One-time setup script
├── sql/
│   └── wordpress.sql               # Database dump (not committed)
├── www/                            # WordPress files (not committed)
├── static/                         # Static assets: videos, images (not committed)
└── certbot/                        # SSL certificates (generated at runtime)
```

## SSL Certificate Renewal

The `certbot` container automatically checks for certificate renewal every 12 hours. No cron job or manual intervention is needed.

To verify manually:

```bash
just renew-dry-run
```

## Troubleshooting

**Site doesn't load:**
- Verify DNS records point to the server IP
- Check that ports 80 and 443 are open (`sudo ufw status`)
- Check logs: `just logs`

**Database connection error:**
- Verify `DB_HOST` is set to `mysql:3306` in `wp-config.php`
- Verify passwords in `wp-config.php` match the `.env` file

**SSL certificate error:**
- DNS must already point to the server before running `just setup`
- Port 80 must be open for the Let's Encrypt ACME challenge

**Upload size limit:**
- PHP limit is 256 MB (`php/custom.ini`), Nginx limit is also 256 MB (`client_max_body_size` in nginx config)
- For large media files, upload them directly to the `static/` directory instead
