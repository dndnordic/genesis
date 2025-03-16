#!/bin/bash
# Script to fix PostgreSQL issues

set -e

echo "=== Checking PostgreSQL installation ==="
# Check if PostgreSQL is installed
if command -v psql &> /dev/null; then
  echo "PostgreSQL client is installed"
else
  echo "PostgreSQL client not found. Installing..."
  if command -v dnf &> /dev/null; then
    # RHEL/CentOS/Fedora
    dnf install -y postgresql postgresql-server
  elif command -v apt-get &> /dev/null; then
    # Debian/Ubuntu
    apt-get update
    apt-get install -y postgresql postgresql-contrib
  else
    echo "Unsupported package manager. Please install PostgreSQL manually."
    exit 1
  fi
fi

# Check for PostgreSQL server
if command -v postgresql-setup &> /dev/null; then
  echo "=== Initializing PostgreSQL database ==="
  postgresql-setup --initdb || echo "Database may already be initialized"
elif [ -x /usr/lib/postgresql/*/bin/initdb ]; then
  # Debian-based systems
  PG_VERSION=$(ls /usr/lib/postgresql/)
  echo "=== Initializing PostgreSQL $PG_VERSION database ==="
  if [ ! -d "/var/lib/postgresql/$PG_VERSION/main" ]; then
    sudo -u postgres /usr/lib/postgresql/$PG_VERSION/bin/initdb -D /var/lib/postgresql/$PG_VERSION/main
  else
    echo "PostgreSQL database already initialized"
  fi
else
  echo "Could not find PostgreSQL initialization tools"
fi

echo "=== Starting PostgreSQL service ==="
if systemctl is-active --quiet postgresql; then
  echo "PostgreSQL service is already running"
else
  systemctl enable postgresql
  systemctl start postgresql
  sleep 2
fi

# Check if PostgreSQL is running
if systemctl is-active --quiet postgresql; then
  echo "✅ PostgreSQL is now running!"
else
  echo "❌ PostgreSQL is still not running. Checking logs..."
  journalctl -xeu postgresql.service --no-pager | tail -n 20
  
  # Try alternative service name on some distributions
  if systemctl is-active --quiet postgresql.service; then
    echo "✅ PostgreSQL is running under postgresql.service!"
  else
    echo "Trying to find the correct PostgreSQL service name..."
    systemctl list-units | grep -i postgres
  fi
fi

echo "=== Setting up Gitea database ==="
# Create PostgreSQL user and database for Gitea
if systemctl is-active --quiet postgresql || systemctl is-active --quiet postgresql.service; then
  echo "Creating PostgreSQL user and database for Gitea..."
  
  # Try to connect to PostgreSQL
  if sudo -u postgres psql -c "\l" &>/dev/null; then
    echo "Successfully connected to PostgreSQL"
    
    # Create user if it doesn't exist
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='gitea'" | grep -q 1; then
      echo "Creating gitea user..."
      sudo -u postgres psql -c "CREATE USER gitea WITH PASSWORD 'gitea_passwd';"
    else
      echo "User gitea already exists"
    fi
    
    # Create database if it doesn't exist
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='gitea'" | grep -q 1; then
      echo "Creating gitea database..."
      sudo -u postgres psql -c "CREATE DATABASE gitea OWNER gitea;"
    else
      echo "Database gitea already exists"
    fi
    
    echo "Database setup completed successfully"
  else
    echo "❌ Could not connect to PostgreSQL. Please check the logs and configuration."
  fi
else
  echo "❌ PostgreSQL service is not running. Cannot set up database."
fi

echo "=== PostgreSQL Configuration Summary ==="
echo "Data directory: $(sudo -u postgres psql -c "SHOW data_directory;" 2>/dev/null || echo "Unable to determine")"
echo "Listening on: $(sudo -u postgres psql -c "SHOW listen_addresses;" 2>/dev/null || echo "Unable to determine")"
echo "Port: $(sudo -u postgres psql -c "SHOW port;" 2>/dev/null || echo "Unable to determine")"