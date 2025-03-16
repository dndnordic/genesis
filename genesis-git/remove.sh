#!/bin/bash
set -e

# Display banner
echo "=========================================================="
echo "     Genesis Infrastructure Removal Script                "
echo "=========================================================="
echo ""
echo "This script will remove the Genesis infrastructure components"
echo "with the option to preserve data"
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root"
  exit 1
fi

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration
if [ -f "${SCRIPT_DIR}/configs/settings.conf" ]; then
  source "${SCRIPT_DIR}/configs/settings.conf"
else
  # Default settings if config not found
  BASE_PATH="/opt"
  echo "Warning: Configuration file not found, using default settings"
fi

# Ask about data preservation
preserve_data=false
read -p "Do you want to preserve data (repositories, database, config)? (y/N): " preserve
if [[ "$preserve" =~ ^[Yy]$ ]]; then
  preserve_data=true
  echo "Data will be preserved during removal."
else
  echo "WARNING: All data will be permanently removed!"
  read -p "Are you sure you want to continue? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Removal canceled."
    exit 0
  fi
fi

# Create log file for removal process
LOG_FILE="/tmp/genesis-removal-$(date +%Y%m%d-%H%M%S).log"
echo "Logging removal process to $LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Stop services and check if they are really stopped
echo "Stopping services..."
for service in gitea docker-origin docker-singularity caddy postgresql docker; do
  if systemctl is-active --quiet $service; then
    echo "Stopping $service service..."
    systemctl stop $service || echo "Warning: Failed to stop $service service"
    systemctl disable $service || echo "Warning: Failed to disable $service service"
    
    # Verify service is stopped
    if systemctl is-active --quiet $service; then
      echo "Warning: $service service is still running. Attempting to force stop..."
      systemctl kill $service || echo "Warning: Failed to force stop $service service"
    fi
  else
    echo "$service service is not running"
  fi
done

# Check for any running Docker containers before continuing
if command -v docker &>/dev/null; then
  echo "Checking for running Docker containers..."
  if docker ps -q 2>/dev/null | grep -q .; then
    echo "Warning: Docker containers are still running. Stopping all containers..."
    docker stop $(docker ps -q) 2>/dev/null || echo "Warning: Failed to stop Docker containers"
  fi
fi

# Remove systemd service files
echo "Removing service files..."
rm -f /etc/systemd/system/gitea.service 
rm -f /etc/systemd/system/docker-origin.service
rm -f /etc/systemd/system/docker-singularity.service
rm -f /etc/systemd/system/caddy.service
rm -f /etc/tmpfiles.d/gitea.conf
rm -f /etc/tmpfiles.d/caddy.conf
systemctl daemon-reload

# Cleanup Docker thoroughly
echo "Cleaning up Docker resources..."
if command -v docker &>/dev/null; then
  # Remove Docker contexts
  echo "Removing Docker contexts..."
  docker context rm origin 2>/dev/null || echo "Warning: Failed to remove origin Docker context"
  docker context rm singularity 2>/dev/null || echo "Warning: Failed to remove singularity Docker context"
  
  # Clean up any remaining containers, images, volumes, and networks
  echo "Cleaning up Docker containers, images, and volumes..."
  docker system prune -af --volumes 2>/dev/null || echo "Warning: Failed to clean up Docker resources"
fi

# Remove Docker configuration files
rm -rf /etc/docker/contexts
rm -f /var/run/docker-origin.sock
rm -f /var/run/docker-singularity.sock

# Remove cron jobs
echo "Removing cron jobs..."
rm -f /etc/cron.d/gitea-backup

# Remove binaries and scripts
echo "Removing binaries and scripts..."
rm -f /usr/local/bin/gitea-backup.sh
[ "$preserve_data" = false ] && rm -f /usr/local/bin/gitea

# Ask about removing installed packages
remove_packages=false
read -p "Do you want to remove installed packages (PostgreSQL, Docker, Caddy)? (y/N): " remove_pkgs
if [[ "$remove_pkgs" =~ ^[Yy]$ ]]; then
  echo "Removing installed packages..."
  
  # Stop PostgreSQL service before removing
  systemctl stop postgresql 2>/dev/null || true
  systemctl disable postgresql 2>/dev/null || true
  
  # Stop Docker service before removing
  systemctl stop docker 2>/dev/null || true
  systemctl disable docker 2>/dev/null || true
  
  # Stop Caddy service before removing
  systemctl stop caddy 2>/dev/null || true
  systemctl disable caddy 2>/dev/null || true
  
  # Remove packages based on detected package manager
  if command -v dnf &>/dev/null; then
    echo "Using DNF package manager..."
    dnf -y remove postgresql postgresql-server postgresql-contrib
    dnf -y remove docker-ce docker-ce-cli containerd.io
    dnf -y remove caddy
    
    # Remove package repositories
    echo "Removing package repositories..."
    rm -f /etc/yum.repos.d/docker-ce.repo
    dnf config-manager --disable copr:copr.fedorainfracloud.org:g:caddy:caddy 2>/dev/null || true
    rm -f /etc/yum.repos.d/group_caddy-caddy-epel-9.repo
  elif command -v yum &>/dev/null; then
    echo "Using YUM package manager..."
    yum -y remove postgresql postgresql-server postgresql-contrib
    yum -y remove docker-ce docker-ce-cli containerd.io
    yum -y remove caddy
    
    # Remove package repositories
    echo "Removing package repositories..."
    rm -f /etc/yum.repos.d/docker-ce.repo
    rm -f /etc/yum.repos.d/group_caddy-caddy-epel-9.repo
  elif command -v apt-get &>/dev/null; then
    echo "Using APT package manager..."
    apt-get -y remove --purge postgresql postgresql-contrib
    apt-get -y remove --purge docker-ce docker-ce-cli containerd.io
    apt-get -y remove --purge caddy
    
    # Remove package repositories
    echo "Removing package repositories..."
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
  else
    echo "Warning: Couldn't detect package manager. Packages must be removed manually."
  fi
  
  # Remove configuration files
  echo "Removing remaining configuration files..."
  rm -rf /etc/docker
  rm -rf /var/lib/docker
  rm -rf /var/lib/postgresql
  rm -rf /var/lib/pgsql
  rm -rf /etc/caddy
  
  # Clean up log files including rotated ones
  echo "Cleaning up log files..."
  rm -rf /var/log/gitea*
  rm -rf /var/log/caddy*
  rm -rf /var/log/docker*
  rm -rf /var/log/postgresql*
  
  # Clean up temporary files
  echo "Cleaning up temporary files..."
  rm -rf /tmp/gitea*
  rm -rf /tmp/docker*
  rm -rf /tmp/caddy*
  rm -rf /tmp/postgres*
  
  # Clean up package caches
  if command -v dnf &>/dev/null; then
    echo "Cleaning package cache..."
    dnf clean all
  elif command -v yum &>/dev/null; then
    echo "Cleaning package cache..."
    yum clean all
  elif command -v apt-get &>/dev/null; then
    echo "Cleaning package cache..."
    apt-get clean
  fi
  
  echo "Installed packages removed successfully"
fi

# Remove directories based on preservation choice
if [ "$preserve_data" = true ]; then
  echo "Preserving data directories..."
  # Only remove non-data directories
  rm -rf $BASE_PATH/auth
  rm -rf $BASE_PATH/security
  
  echo "Disconnecting symlinks..."
  # Remove symlinks but keep the actual data
  rm -f /var/lib/gitea
  rm -f /etc/gitea
  rm -f /var/log/gitea
  rm -f /var/lib/singularity
  rm -f /etc/singularity
  rm -f /var/log/singularity
  rm -f /var/lib/origin
  rm -f /etc/origin
  rm -f /var/log/origin
  rm -f /etc/caddy
  rm -f /var/log/caddy
  rm -f /var/lib/caddy
  rm -f /var/lib/builds
  rm -f /etc/builds
  rm -f /var/log/builds
  
  echo "Data preserved in:"
  echo "- Repository data: $BASE_PATH/gitea/data"
  echo "- Configuration: $BASE_PATH/gitea/config"
  echo "- Database: PostgreSQL database '$DB_NAME'"
  echo "- Backups: $BASE_PATH/backups"
  
  echo "To completely remove data later, run:"
  echo "  rm -rf $BASE_PATH/{gitea,builds,caddy,singularity,origin,genesis,backups}"
  echo "  sudo -u postgres psql -c \"DROP DATABASE $DB_NAME;\""
else
  echo "Removing all data directories..."
  # Full removal of all components
  rm -rf $BASE_PATH/{gitea,builds,caddy,auth,security,singularity,origin,genesis,backups}
  rm -f /var/lib/gitea /etc/gitea /var/log/gitea
  rm -f /var/lib/singularity /etc/singularity /var/log/singularity
  rm -f /var/lib/origin /etc/origin /var/log/origin
  rm -f /etc/caddy /var/log/caddy /var/lib/caddy
  rm -f /var/lib/builds /etc/builds /var/log/builds
  
  # Drop database if PostgreSQL is running
  if systemctl is-active --quiet postgresql; then
    echo "Removing database..."
    sudo -u postgres psql -c "DROP DATABASE $DB_NAME;" || true
    sudo -u postgres psql -c "DROP USER $DB_USER;" || true
  fi
fi

# Ask about SSH key removal
remove_ssh_keys=false
read -p "Do you want to remove SSH keys for all users (including recovery user)? (y/N): " remove_keys
if [[ "$remove_keys" =~ ^[Yy]$ ]]; then
  echo "Removing SSH keys..."
  # Remove SSH keys from system users
  for user in gitea builder singularity origin genesis; do
    if [ -d "$BASE_PATH/$user/.ssh" ]; then
      rm -rf "$BASE_PATH/$user/.ssh"
      echo "Removed SSH keys for $user"
    fi
  done
  
  # Remove recovery user SSH keys if they exist
  if id recovery &>/dev/null && [ -d "/home/recovery/.ssh" ]; then
    rm -rf /home/recovery/.ssh
    echo "Removed recovery user SSH keys"
  fi
  
  # Remove SSH keys from genesis repository
  rm -rf $BASE_PATH/genesis/ssh-keys
  
  # Remove SSH emergency configuration
  rm -f /etc/ssh/sshd_config.d/emergency.conf
else
  # Keep recovery user SSH keys
  if id recovery &>/dev/null; then
    echo "Recovery user SSH keys preserved in /home/recovery/.ssh/"
  fi
fi

# Keep mhugo user intact
echo "User 'mhugo' preserved"

# Ask about removing system users
if [ "$preserve_data" = false ]; then
  read -p "Do you want to remove system users (gitea, builder, origin, singularity, genesis)? (y/N): " remove_users
  if [[ "$remove_users" =~ ^[Yy]$ ]]; then
    echo "Removing system users..."
    userdel -r gitea 2>/dev/null || true
    userdel -r builder 2>/dev/null || true
    userdel -r singularity 2>/dev/null || true
    userdel -r origin 2>/dev/null || true
    userdel -r genesis 2>/dev/null || true
    groupdel docker-origin 2>/dev/null || true
    groupdel docker-singularity 2>/dev/null || true
  fi
fi

# Verify the removal was successful
echo "Verifying removal process..."
verification_passed=true

# Check if services are still running
for service in gitea docker-origin docker-singularity caddy postgresql; do
  if systemctl is-active --quiet $service; then
    echo "Warning: $service service is still running"
    verification_passed=false
  fi
done

# Check if ports are still in use
for port in 22 80 443 3000 5432 $DOCKER_ORIGIN_PORT $DOCKER_SINGULARITY_PORT; do
  if netstat -tuln 2>/dev/null | grep -q ":$port "; then
    echo "Warning: Port $port is still in use"
    verification_passed=false
  fi
done

# Check if users still exist (only if they were supposed to be removed)
if [ "$preserve_data" = false ] && [ "$remove_users" = "y" ]; then
  for user in gitea builder singularity origin genesis; do
    if id $user &>/dev/null; then
      echo "Warning: User $user still exists"
      verification_passed=false
    fi
  done
fi

echo ""
echo "=========================================================="
echo "     Genesis Infrastructure Removal Complete!             "
echo "=========================================================="
if [ "$verification_passed" = true ]; then
  echo " Verification: SUCCESS - All components properly removed"
else
  echo " Verification: WARNING - Some components may still be present"
  echo " Check the log file at $LOG_FILE for details"
fi

if [ "$preserve_data" = true ]; then
  echo " Data has been preserved and can be reused for reinstallation"
  echo " To reinstall with preserved data, run: ./install.sh"
else
  echo " All components have been completely removed"
fi
echo "=========================================================="
echo "Removal log saved to: $LOG_FILE"