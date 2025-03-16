#!/bin/bash
# Manual Caddy setup without relying on systemd service

set -e

CADDY_DIR="/opt/caddy"
mkdir -p "$CADDY_DIR"
cd "$CADDY_DIR"

echo "=== Installing Caddy binary ==="
# Download latest Caddy
if [ ! -f "$CADDY_DIR/caddy" ]; then
  curl -o "$CADDY_DIR/caddy" -L "https://github.com/caddyserver/caddy/releases/download/v2.7.5/caddy_2.7.5_linux_amd64"
  chmod +x "$CADDY_DIR/caddy"
fi

echo "=== Creating minimal Caddyfile ==="
cat > "$CADDY_DIR/Caddyfile" << EOF
{
  auto_https off
  admin off
}

:80 {
  respond "Caddy is working!"
}
EOF

echo "=== Creating directories ==="
mkdir -p "$CADDY_DIR/data"
mkdir -p "$CADDY_DIR/logs"

echo "=== Creating run script ==="
cat > "$CADDY_DIR/run.sh" << EOF
#!/bin/bash
cd "$CADDY_DIR"
nohup ./caddy run --config Caddyfile > logs/caddy.log 2>&1 &
echo \$! > caddy.pid
echo "Caddy started with PID \$(cat caddy.pid)"
EOF

chmod +x "$CADDY_DIR/run.sh"

echo "=== Creating stop script ==="
cat > "$CADDY_DIR/stop.sh" << EOF
#!/bin/bash
if [ -f "$CADDY_DIR/caddy.pid" ]; then
  PID=\$(cat "$CADDY_DIR/caddy.pid")
  echo "Stopping Caddy (PID \$PID)..."
  kill \$PID
  rm "$CADDY_DIR/caddy.pid"
else
  echo "No Caddy PID file found."
fi
EOF

chmod +x "$CADDY_DIR/stop.sh"

echo "=== Starting Caddy manually ==="
# Stop previous instance if running
if [ -f "$CADDY_DIR/caddy.pid" ]; then
  "$CADDY_DIR/stop.sh"
fi

# Start Caddy
"$CADDY_DIR/run.sh"

echo "=== Testing connection ==="
sleep 2
curl -v http://localhost:80

echo "=== Setup complete ==="
echo "Caddy installed at $CADDY_DIR"
echo "To start: $CADDY_DIR/run.sh"
echo "To stop: $CADDY_DIR/stop.sh"
echo "Logs: $CADDY_DIR/logs/caddy.log"