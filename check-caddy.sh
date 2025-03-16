#!/bin/bash
# Script to diagnose Caddy issues

echo "=== Checking Caddy status ==="
systemctl status caddy.service

echo -e "\n=== Checking Caddy logs ==="
journalctl -xeu caddy.service --no-pager | tail -n 50

echo -e "\n=== Checking Caddy configuration ==="
if [ -f /etc/caddy/Caddyfile ]; then
  cat /etc/caddy/Caddyfile
else
  echo "Caddyfile not found at /etc/caddy/Caddyfile"
  
  # Check for Caddyfile in other locations
  echo "Searching for Caddyfile in other locations:"
  find /opt -name "Caddyfile" 2>/dev/null
  find /etc -name "Caddyfile" 2>/dev/null
fi

echo -e "\n=== Checking network ports ==="
ss -tuln | grep -E '80|443|2015'

echo -e "\n=== Checking DNS configuration ==="
if command -v host &>/dev/null; then
  host d1-fra.in.centralcloud.net
elif command -v nslookup &>/dev/null; then
  nslookup d1-fra.in.centralcloud.net
else
  echo "No DNS tools found (host/nslookup)"
fi

echo -e "\n=== Checking Caddy version ==="
caddy version 2>/dev/null || echo "Caddy not in PATH or not installed"