#!/bin/bash
# Setup Nginx as an alternative to Caddy

set -e

echo "=== Installing Nginx ==="
# Try different package managers
if command -v dnf &> /dev/null; then
  dnf install -y nginx
elif command -v apt-get &> /dev/null; then
  apt-get update && apt-get install -y nginx
else
  echo "Unsupported package manager. Please install nginx manually."
  exit 1
fi

echo "=== Creating Nginx config ==="
cat > /etc/nginx/conf.d/gitea.conf << EOF
server {
    listen 80;
    server_name _;  # Match any server name

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

# Remove default config if it exists and might conflict
if [ -f /etc/nginx/conf.d/default.conf ]; then
  mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
fi

echo "=== Testing Nginx config ==="
nginx -t

echo "=== Starting Nginx ==="
systemctl enable nginx
systemctl restart nginx

echo "=== Checking Nginx status ==="
systemctl status nginx --no-pager

echo "=== Setup complete ==="
echo "Nginx installed and configured as a proxy for Gitea"
echo "Now Gitea should be accessible via http://your-server-ip/"
echo "To check Nginx logs: tail -f /var/log/nginx/gitea.error.log"