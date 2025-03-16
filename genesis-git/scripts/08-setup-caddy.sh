#!/bin/bash
set -e

# Determine script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/configs/settings.conf"

# Check if Caddy is already installed
if command -v caddy &> /dev/null; then
    echo "Caddy is already installed, skipping..."
else
    # Install Caddy - try different package managers
    echo "Installing Caddy..."
    if command -v dnf &> /dev/null; then
        # RHEL/CentOS/Fedora
        dnf -y install yum-utils || true
        dnf config-manager --add-repo https://copr.fedorainfracloud.org/coprs/g/caddy/caddy/repo/epel-9/group_caddy-caddy-epel-9.repo || true
        dnf -y install caddy || {
            echo "Failed to install Caddy using dnf. Trying alternative method..."
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/setup.rpm.sh' | bash
            dnf -y install caddy
        }
    elif command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        apt-get update
        apt-get -y install debian-keyring debian-archive-keyring apt-transport-https
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt-get update
        apt-get -y install caddy
    else
        echo "Unsupported package manager. Installing Caddy using direct download..."
        curl -o /usr/local/bin/caddy -L "https://github.com/caddyserver/caddy/releases/download/v2.7.5/caddy_2.7.5_linux_amd64"
        chmod +x /usr/local/bin/caddy
        echo "Creating systemd service for Caddy..."
        cat > /etc/systemd/system/caddy.service << 'EOF'
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/local/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        
        # Create caddy user and group if they don't exist
        id -u caddy &>/dev/null || useradd -r -d /var/lib/caddy -s /sbin/nologin caddy
    fi
fi

# Ensure Caddy config directory exists
mkdir -p /etc/caddy

# Create Caddy configuration for Gitea with the external hostname
mkdir -p $BASE_PATH/caddy/config
mkdir -p $BASE_PATH/caddy/logs

# Create a simpler Caddyfile for initial testing
cat << EOF > $BASE_PATH/caddy/config/Caddyfile
# Global settings
{
    email $EMAIL  # For ACME/Let's Encrypt account
    # Use HTTP during initial setup to avoid certificate issues
    auto_https off
}

:80 {
    reverse_proxy localhost:3000
    log {
        output file $BASE_PATH/caddy/logs/gitea.log
    }
}
EOF

# Copy to standard location
cp $BASE_PATH/caddy/config/Caddyfile /etc/caddy/Caddyfile

# Create log directory
mkdir -p $BASE_PATH/caddy/logs
mkdir -p $BASE_PATH/caddy/data

# Set proper ownership
chown -R caddy:caddy $BASE_PATH/caddy

echo "Caddy setup completed successfully"