#!/bin/bash
# Script to restart Genesis services with proper order

set -e

echo "=== Restarting Genesis services ==="

echo "Starting PostgreSQL..."
systemctl restart postgresql
systemctl status postgresql --no-pager

echo "Starting Gitea..."
systemctl restart gitea
systemctl status gitea --no-pager

echo "Starting Origin Docker service..."
systemctl restart docker-origin
systemctl status docker-origin --no-pager

echo "Starting Singularity Docker service..."
systemctl restart docker-singularity
systemctl status docker-singularity --no-pager

# Try to fix Caddy issues before starting
echo "Checking Caddy configuration..."
if [ -f /etc/caddy/Caddyfile ]; then
  # Create backup
  cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak
  
  # Check for common issues in Caddyfile
  if grep -q "https://" /etc/caddy/Caddyfile; then
    echo "WARNING: Found https:// in Caddyfile, which may cause issues. Caddy handles HTTPS automatically."
    # Fix by removing https:// from the config
    sed -i 's|https://||g' /etc/caddy/Caddyfile
  fi
  
  # Validate Caddy config
  if command -v caddy &>/dev/null; then
    echo "Validating Caddy configuration..."
    caddy validate --config /etc/caddy/Caddyfile || echo "WARNING: Caddy configuration validation failed"
  fi
fi

echo "Starting Caddy..."
systemctl restart caddy
systemctl status caddy --no-pager

echo "=== Status of all services ==="
services=("postgresql" "gitea" "caddy" "docker" "docker-origin" "docker-singularity")
for service in "${services[@]}"; do
  status=$(systemctl is-active "$service")
  if [ "$status" == "active" ]; then
    echo "✓ $service is running"
  else
    echo "✗ $service is NOT running"
  fi
done