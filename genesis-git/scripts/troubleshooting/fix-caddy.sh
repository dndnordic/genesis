#!/bin/bash
# Script to fix Caddy issues on AlmaLinux

set -e

echo "=== Checking Caddy installation ==="
# Verify caddy is installed
if ! command -v caddy &> /dev/null; then
  echo "Caddy not found. Installing..."
  # For AlmaLinux/RHEL
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/setup.rpm.sh' | sudo bash
  dnf install caddy -y
fi

echo "=== Creating minimal Caddyfile ==="
# Create the simplest possible Caddyfile for testing
cat > /tmp/Caddyfile.minimal << EOF
{
  auto_https off  # Disable HTTPS for testing
  admin off       # Disable admin API
}

:80 {
  respond "Caddy is working!"
}
EOF

# Copy to both locations to be sure
echo "Copying minimal config to /etc/caddy/Caddyfile"
cp /tmp/Caddyfile.minimal /etc/caddy/Caddyfile

echo "=== Checking Caddy permissions ==="
# Ensure caddy user exists
if ! id -u caddy &>/dev/null; then
  echo "Creating caddy user..."
  useradd -r -d /var/lib/caddy -s /sbin/nologin caddy
fi

# Create data directories with proper permissions
mkdir -p /var/lib/caddy
mkdir -p /var/log/caddy
chown -R caddy:caddy /var/lib/caddy
chown -R caddy:caddy /var/log/caddy
chown caddy:caddy /etc/caddy/Caddyfile

echo "=== Validating Caddy config ==="
caddy validate --config /etc/caddy/Caddyfile

echo "=== Restarting Caddy service ==="
# Restart service
systemctl daemon-reload
systemctl restart caddy
sleep 2

# Check if service is running
if systemctl is-active --quiet caddy; then
  echo "✅ Caddy is now running!"
else
  echo "❌ Caddy is still not running. Checking logs..."
  journalctl -xeu caddy.service --no-pager | tail -n 20
fi

echo "=== Testing Caddy locally ==="
curl -v http://localhost:80