#!/bin/bash
set -e

# Determine script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/configs/settings.conf"

# Check if Gitea is already installed
mkdir -p $BASE_PATH/gitea/bin
GITEA_BIN="$BASE_PATH/gitea/bin/gitea"

if [ -f "$GITEA_BIN" ]; then
    echo "Gitea is already installed, skipping download..."
else
    # Install Gitea
    echo "Downloading Gitea..."
    export GITEA_VERSION="1.19.3"
    
    # Check if wget is installed, if not try curl
    if command -v wget &> /dev/null; then
        wget -O "$GITEA_BIN" https://dl.gitea.io/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64
    elif command -v curl &> /dev/null; then
        curl -L https://dl.gitea.io/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64 -o "$GITEA_BIN"
    else
        echo "Error: Neither wget nor curl is installed. Please install one of them and try again."
        exit 1
    fi
    
    chmod +x "$GITEA_BIN"
    
    # Create symlink for backward compatibility
    ln -sf "$GITEA_BIN" /usr/local/bin/gitea
fi

# Create Gitea configuration file
mkdir -p $BASE_PATH/gitea/config
cat > $BASE_PATH/gitea/config/app.ini << EOF
APP_NAME = Genesis Git Server
RUN_USER = gitea
RUN_MODE = prod
WORK_PATH = $BASE_PATH/gitea

[database]
DB_TYPE = postgres
HOST = 127.0.0.1:5432
NAME = $DB_NAME
USER = $DB_USER
PASSWD = $DB_PASS
SCHEMA = public
SSL_MODE = disable

[repository]
ROOT = $BASE_PATH/gitea/data/gitea-repositories
DEFAULT_PRIVATE = private
DEFAULT_BRANCH = main

[server]
DOMAIN = $DOMAIN
HTTP_PORT = 3000
ROOT_URL = https://$DOMAIN/
DISABLE_SSH = false
SSH_PORT = 22
START_SSH_SERVER = false
SSH_DOMAIN = $DOMAIN
LFS_START_SERVER = true
LFS_JWT_SECRET = $(openssl rand -base64 32)
APP_DATA_PATH = $BASE_PATH/gitea/data

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
DEFAULT_ADMIN_EMAIL = $EMAIL

[log]
MODE = file
LEVEL = Info
ROOT_PATH = $BASE_PATH/gitea/logs
EOF

# Create required directories if they don't exist
mkdir -p $BASE_PATH/gitea/data/gitea-repositories
mkdir -p $BASE_PATH/gitea/data/tmp/package-upload
mkdir -p $BASE_PATH/gitea/data/home
mkdir -p $BASE_PATH/gitea/logs

# Set proper ownership
chown -R gitea:gitea $BASE_PATH/gitea

echo "Gitea installation completed successfully"