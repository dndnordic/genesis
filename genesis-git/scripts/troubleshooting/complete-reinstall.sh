#!/bin/bash
# Script for complete reinstallation of Genesis infrastructure

set -e

echo "=== Genesis Infrastructure Reinstallation Script ==="
echo "This script will reinstall all components of the Genesis infrastructure"
echo "including fixing common issues with PostgreSQL, Caddy, and other services."
echo ""
echo "WARNING: This script assumes you're running on AlmaLinux/RHEL/CentOS"
echo ""

echo "=== Step 1: Installing prerequisites ==="
# Install necessary packages
dnf update -y
dnf install -y wget curl jq git ca-certificates gnupg lsb-release tmux vim

# Install PostgreSQL
echo "=== Step 2: Installing PostgreSQL ==="
dnf install -y postgresql postgresql-server

# Initialize PostgreSQL
if [ ! -f "/var/lib/pgsql/data/pg_hba.conf" ]; then
  echo "Initializing PostgreSQL database..."
  postgresql-setup --initdb
fi

# Configure PostgreSQL for local access
echo "Configuring PostgreSQL..."
cat > /var/lib/pgsql/data/pg_hba.conf << EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
EOF

echo "Starting PostgreSQL..."
systemctl enable postgresql
systemctl restart postgresql
sleep 2

# Check PostgreSQL status
if systemctl is-active --quiet postgresql; then
  echo "✅ PostgreSQL is running!"
else
  echo "❌ PostgreSQL failed to start. Please check the logs."
  journalctl -xeu postgresql.service --no-pager | tail -n 20
  exit 1
fi

# Install Nginx instead of Caddy for more reliability
echo "=== Step 3: Installing Nginx ==="
dnf install -y nginx

# Configure Nginx for Gitea
cat > /etc/nginx/conf.d/gitea.conf << EOF
server {
    listen 80;
    server_name _;

    access_log /var/log/nginx/gitea.access.log;
    error_log /var/log/nginx/gitea.error.log;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Start Nginx
echo "Starting Nginx..."
systemctl enable nginx
systemctl restart nginx

# Install Docker
echo "=== Step 4: Installing Docker ==="
dnf install -y yum-utils
yum-utils --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io

# Start Docker
echo "Starting Docker..."
systemctl enable docker
systemctl restart docker

# Create users and directories
echo "=== Step 5: Creating directories and users ==="
mkdir -p /opt/gitea /opt/genesis /opt/origin /opt/singularity /opt/builder
mkdir -p /var/log/genesis /var/log/gitea /var/log/origin /var/log/singularity

# Create users if they don't exist
for user in gitea genesis origin singularity builder; do
  if ! id -u $user &>/dev/null; then
    useradd -r -s /bin/bash -d /opt/$user $user
  fi
  chown -R $user:$user /opt/$user
  chown -R $user:$user /var/log/$user
done

# Setup SSH
echo "=== Step 6: Setting up SSH ==="
for user in gitea genesis origin singularity builder; do
  USER_HOME="/opt/$user"
  mkdir -p $USER_HOME/.ssh
  
  # Generate SSH key if it doesn't exist
  if [ ! -f "$USER_HOME/.ssh/id_ed25519" ]; then
    ssh-keygen -t ed25519 -f $USER_HOME/.ssh/id_ed25519 -N "" -C "$user@$(hostname)"
    cat $USER_HOME/.ssh/id_ed25519.pub >> $USER_HOME/.ssh/authorized_keys
    chmod 700 $USER_HOME/.ssh
    chmod 600 $USER_HOME/.ssh/authorized_keys
    chown -R $user:$user $USER_HOME/.ssh
  fi
done

# Setup Gitea
echo "=== Step 7: Setting up Gitea ==="
GITEA_VERSION="1.19.3"
if [ ! -f "/usr/local/bin/gitea" ]; then
  wget -O /usr/local/bin/gitea https://dl.gitea.io/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64 || \
  curl -L https://dl.gitea.io/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64 -o /usr/local/bin/gitea
  chmod +x /usr/local/bin/gitea
fi

# Create Gitea database user and database
echo "Setting up Gitea database..."
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='gitea'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE USER gitea WITH PASSWORD 'gitea_passwd';"
fi

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='gitea'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE DATABASE gitea OWNER gitea;"
fi

# Create Gitea config
mkdir -p /opt/gitea/config
cat > /opt/gitea/config/app.ini << EOF
APP_NAME = Genesis Git Server
RUN_USER = gitea
RUN_MODE = prod

[database]
DB_TYPE = postgres
HOST = 127.0.0.1:5432
NAME = gitea
USER = gitea
PASSWD = gitea_passwd
SCHEMA = public
SSL_MODE = disable

[repository]
ROOT = /opt/gitea/data/gitea-repositories
DEFAULT_PRIVATE = private
DEFAULT_BRANCH = main

[server]
DOMAIN = localhost
HTTP_PORT = 3000
ROOT_URL = http://localhost/
DISABLE_SSH = false
SSH_PORT = 22
START_SSH_SERVER = false
SSH_DOMAIN = localhost
LFS_START_SERVER = true
LFS_JWT_SECRET = $(openssl rand -base64 32)

[security]
INSTALL_LOCK = true
SECRET_KEY = $(openssl rand -base64 32)
INTERNAL_TOKEN = $(openssl rand -base64 64)
PASSWORD_HASH_ALGO = pbkdf2
MIN_PASSWORD_LENGTH = 12

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = true
ENABLE_NOTIFY_MAIL = false
DEFAULT_ADMIN_EMAIL = admin@example.com

[log]
MODE = file
LEVEL = Info
ROOT_PATH = /var/log/gitea
EOF

# Create Gitea service
cat > /etc/systemd/system/gitea.service << EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=syslog.target
After=network.target
After=postgresql.service

[Service]
RestartSec=2s
Type=simple
User=gitea
Group=gitea
WorkingDirectory=/opt/gitea
ExecStart=/usr/local/bin/gitea web --config /opt/gitea/config/app.ini
Restart=always
Environment=USER=gitea HOME=/opt/gitea

[Install]
WantedBy=multi-user.target
EOF

# Create required directories
mkdir -p /opt/gitea/data/gitea-repositories
mkdir -p /var/log/gitea
chown -R gitea:gitea /opt/gitea
chown -R gitea:gitea /var/log/gitea

# Start Gitea
echo "Starting Gitea..."
systemctl daemon-reload
systemctl enable gitea
systemctl restart gitea

# Check installation
echo "=== Step 8: Verifying installation ==="
echo "Checking services..."
services=("postgresql" "nginx" "docker" "gitea")
for service in "${services[@]}"; do
  status=$(systemctl is-active $service)
  if [ "$status" == "active" ]; then
    echo "✅ $service is running"
  else
    echo "❌ $service is NOT running"
  fi
done

echo ""
echo "=== Installation Complete ==="
echo "Access Gitea at: http://$(hostname -I | awk '{print $1}')"
echo ""
echo "If any services are not running, check the logs with:"
echo "  journalctl -xeu SERVICE_NAME.service"