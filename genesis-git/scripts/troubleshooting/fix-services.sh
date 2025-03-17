#!/bin/bash
set -e

# Set colorful output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Genesis Services Repair Script${NC}"
echo -e "${YELLOW}============================${NC}"

# Function to display status
status() {
  echo -e "${GREEN}[+] $1${NC}"
}

error() {
  echo -e "${RED}[!] $1${NC}"
  exit 1
}

warn() {
  echo -e "${YELLOW}[!] $1${NC}"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  error "This script must be run as root"
fi

# Load configuration
BASE_PATH="/opt"
status "Loading configuration from settings.conf"
if [ -f "/home/sing/genesis/genesis-git/configs/settings.conf" ]; then
  source "/home/sing/genesis/genesis-git/configs/settings.conf"
  status "Configuration loaded successfully"
else
  warn "Configuration file not found, using default values"
fi

# Fix Gitea service
status "Fixing Gitea service..."
mkdir -p $BASE_PATH/gitea/bin
mkdir -p $BASE_PATH/gitea/config
mkdir -p $BASE_PATH/gitea/data/gitea-repositories
mkdir -p $BASE_PATH/gitea/data/tmp/package-upload
mkdir -p $BASE_PATH/gitea/data/home
mkdir -p $BASE_PATH/gitea/logs

# Create or verify gitea user
if ! id -u gitea &>/dev/null; then
  status "Creating gitea user..."
  useradd -r -u ${GITEA_UID:-990} -m -d $BASE_PATH/gitea -s /bin/bash gitea
else
  status "Gitea user already exists"
fi

# Verify gitea binary
GITEA_BIN="$BASE_PATH/gitea/bin/gitea"
if [ ! -f "$GITEA_BIN" ]; then
  status "Downloading Gitea..."
  GITEA_VERSION="1.19.3"
  
  if command -v wget &> /dev/null; then
    wget -O "$GITEA_BIN" https://dl.gitea.io/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64
  elif command -v curl &> /dev/null; then
    curl -L https://dl.gitea.io/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64 -o "$GITEA_BIN"
  else
    error "Neither wget nor curl is installed. Please install one of them and try again."
  fi
  
  chmod +x "$GITEA_BIN"
  
  # Create symlink for backward compatibility
  ln -sf "$GITEA_BIN" /usr/local/bin/gitea
  status "Gitea binary installed"
fi

# Set proper ownership for gitea
chown -R gitea:gitea $BASE_PATH/gitea

# Create Gitea systemd service
status "Creating Gitea service file..."
cat > /etc/systemd/system/gitea.service << EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target postgresql.service
Requires=postgresql.service

[Service]
User=gitea
Group=gitea
WorkingDirectory=$BASE_PATH/gitea/
Environment=USER=gitea HOME=$BASE_PATH/gitea GITEA_WORK_DIR=$BASE_PATH/gitea
ExecStart=$BASE_PATH/gitea/bin/gitea web --config $BASE_PATH/gitea/config/app.ini
Restart=always
RestartSec=2s
Type=simple
WatchdogSec=30s

[Install]
WantedBy=multi-user.target
EOF

# Fix Caddy service
status "Fixing Caddy service..."
# Create caddy user if it doesn't exist
if ! id -u caddy &>/dev/null; then
  useradd -r -d /var/lib/caddy -s /sbin/nologin caddy
else
  status "Caddy user already exists"
fi

# Create Caddy directories
mkdir -p /etc/caddy
mkdir -p $BASE_PATH/caddy/logs
mkdir -p $BASE_PATH/caddy/data
chown -R caddy:caddy $BASE_PATH/caddy

# Create a very simple Caddyfile for testing
status "Creating simple Caddyfile for testing..."
cat > /etc/caddy/Caddyfile << EOF
{
    admin off
    auto_https off
}

:80 {
    respond "Caddy is working!"
}
EOF

# Create Caddy service file
status "Creating Caddy service file..."
cat > /etc/systemd/system/caddy.service << EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=simple
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadWritePaths=/etc/caddy /opt/caddy

[Install]
WantedBy=multi-user.target
EOF

# Fix Docker Origin service
status "Fixing Docker Origin service..."
# Create docker-origin group if it doesn't exist
if ! grep -q "^docker-origin:" /etc/group; then
  groupadd -f docker-origin
fi

# Create origin user if it doesn't exist
if ! id -u origin &>/dev/null; then
  useradd -r -u ${ORIGIN_UID:-993} -m -d $BASE_PATH/origin -s /bin/bash origin
  usermod -aG docker-origin origin
else
  status "Origin user already exists"
fi

# Create Docker Origin directories
mkdir -p $BASE_PATH/origin/docker
mkdir -p /var/run/docker-origin
mkdir -p /etc/docker/contexts/origin

# Create Docker Origin daemon.json
status "Creating Docker Origin configuration..."
cat > /etc/docker/contexts/origin/daemon.json << EOF
{
    "data-root": "$BASE_PATH/origin/docker",
    "hosts": ["unix:///var/run/docker-origin.sock"],
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF

# Set proper ownership
chown -R origin:docker-origin $BASE_PATH/origin
chown -R origin:docker-origin /var/run/docker-origin

# Create Docker Origin service file
status "Creating Docker Origin service file..."
cat > /etc/systemd/system/docker-origin.service << EOF
[Unit]
Description=Docker Application Container Engine (Origin Context)
Documentation=https://docs.docker.com
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/dockerd --config-file=/etc/docker/contexts/origin/daemon.json --host unix:///var/run/docker-origin.sock
ExecReload=/bin/kill -s HUP \$MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
User=origin
Group=docker-origin
WorkingDirectory=$BASE_PATH/origin
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

# Fix Docker Singularity service
status "Fixing Docker Singularity service..."
# Create docker-singularity group if it doesn't exist
if ! grep -q "^docker-singularity:" /etc/group; then
  groupadd -f docker-singularity
fi

# Create singularity user if it doesn't exist
if ! id -u singularity &>/dev/null; then
  useradd -r -u ${SINGULARITY_UID:-992} -m -d $BASE_PATH/singularity -s /bin/bash singularity
  usermod -aG docker-singularity singularity
else
  status "Singularity user already exists"
fi

# Create Docker Singularity directories
mkdir -p $BASE_PATH/singularity/docker
mkdir -p /var/run/docker-singularity
mkdir -p /etc/docker/contexts/singularity

# Create Docker Singularity daemon.json
status "Creating Docker Singularity configuration..."
cat > /etc/docker/contexts/singularity/daemon.json << EOF
{
    "data-root": "$BASE_PATH/singularity/docker",
    "hosts": ["unix:///var/run/docker-singularity.sock"],
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF

# Set proper ownership
chown -R singularity:docker-singularity $BASE_PATH/singularity
chown -R singularity:docker-singularity /var/run/docker-singularity

# Create Docker Singularity service file
status "Creating Docker Singularity service file..."
cat > /etc/systemd/system/docker-singularity.service << EOF
[Unit]
Description=Docker Application Container Engine (Singularity Context)
Documentation=https://docs.docker.com
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/dockerd --config-file=/etc/docker/contexts/singularity/daemon.json --host unix:///var/run/docker-singularity.sock
ExecReload=/bin/kill -s HUP \$MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
User=singularity
Group=docker-singularity
WorkingDirectory=$BASE_PATH/singularity
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start services
status "Reloading systemd daemon and enabling services..."
systemctl daemon-reload
systemctl enable gitea.service 
systemctl enable caddy.service
systemctl enable docker-origin.service
systemctl enable docker-singularity.service

# Try to start the services
status "Starting services..."
echo "Starting Gitea..."
systemctl restart gitea.service || warn "Gitea service failed to start. Check with: systemctl status gitea.service"

echo "Starting Caddy..."
systemctl restart caddy.service || warn "Caddy service failed to start. Check with: systemctl status caddy.service"

echo "Starting Docker Origin..."
systemctl restart docker-origin.service || warn "Docker Origin service failed to start. Check with: systemctl status docker-origin.service"

echo "Starting Docker Singularity..."
systemctl restart docker-singularity.service || warn "Docker Singularity service failed to start. Check with: systemctl status docker-singularity.service"

echo -e "${GREEN}Services setup completed!${NC}"
echo -e "Check service status with: ${YELLOW}systemctl status <service-name>${NC}"
echo -e "View logs with: ${YELLOW}journalctl -xeu <service-name>${NC}"