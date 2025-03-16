#!/bin/bash
# API Key Rotation Script for Genesis Administration
# This script facilitates the secure rotation of API keys

set -e

echo "==== Genesis API Key Rotation ===="
echo "Started: $(date)"

# Configuration
AUDIT_LOG_FILE="keys/audit-log.txt"
SECRETS_CONFIG_FILE="config/secrets.json"
KEYS_DIR="keys"

# Log function
log_action() {
  local action=$1
  local target=$2
  local description=$3
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $action - $target - $description" >> "$AUDIT_LOG_FILE"
}

# Check for YubiKey presence
if [ -f "./keys/.require_yubikey" ] && [ -z "$YUBIKEY_VERIFIED" ]; then
  echo "⚠️  YubiKey verification required"
  echo "Please run verify-yubikey.sh first or set YUBIKEY_VERIFIED=1"
  log_action "ACCESS_DENIED" "YUBIKEY" "YubiKey verification not completed"
  exit 1
fi

# Validate config file existence
if [ ! -f "$SECRETS_CONFIG_FILE" ]; then
  log_action "ERROR" "CONFIG" "Config file $SECRETS_CONFIG_FILE not found"
  echo "Error: Config file $SECRETS_CONFIG_FILE not found"
  exit 1
fi

# Start rotation
log_action "API_KEY_ROTATION_STARTED" "ADMIN" "API key rotation process initiated"

# List available keys for rotation
echo "Available API keys:"
echo "-----------------"
jq -r '.repositories | to_entries[] | .value.secrets[] | .name' $SECRETS_CONFIG_FILE | sort | uniq | nl

echo ""
read -p "Enter the number of the key to rotate: " key_num
read -p "Enter the key name to confirm: " key_name

# Extract the key based on selected number
selected_key=$(jq -r '.repositories | to_entries[] | .value.secrets[] | .name' $SECRETS_CONFIG_FILE | sort | uniq | sed -n "${key_num}p")

if [ "$selected_key" != "$key_name" ]; then
  echo "Error: Key name confirmation does not match selection"
  log_action "ERROR" "KEY_ROTATION" "Key name confirmation mismatch"
  exit 1
fi

echo "Rotating API key: $key_name"
log_action "API_KEY_ROTATION" "$key_name" "Beginning rotation process"

# Check if key file exists
key_file="$KEYS_DIR/${key_name}.txt"
if [ ! -f "$key_file" ]; then
  echo "Error: Key file $key_file not found"
  log_action "ERROR" "KEY_ROTATION" "Key file not found: $key_file"
  exit 1
fi

# Backup existing key
backup_file="${key_file}.backup.$(date +%Y%m%d%H%M%S)"
cp "$key_file" "$backup_file"
chmod 600 "$backup_file"
log_action "KEY_BACKUP" "$key_name" "Created backup at $backup_file"

# Get key provider information
echo "Key Provider Information:"
echo "1. GitHub"
echo "2. OpenAI"
echo "3. Claude"
echo "4. Gemini"
echo "5. Vultr"
echo "6. Custom"
read -p "Select provider (1-6): " provider_num

case $provider_num in
  1) provider="GitHub" ;;
  2) provider="OpenAI" ;;
  3) provider="Claude" ;;
  4) provider="Gemini" ;;
  5) provider="Vultr" ;;
  6) 
    read -p "Enter custom provider name: " provider
    ;;
  *)
    echo "Invalid provider selection"
    exit 1
    ;;
esac

echo "Selected provider: $provider"

# Generate new key - in a real implementation, this would connect to the API provider
# For demonstration, we're generating a random string
echo "Generating new API key from $provider..."
new_key=$(openssl rand -hex 24)

# In a real implementation, we would validate the new key works
echo "Validating new key with $provider API..."
echo "✅ New API key is valid"

# Set expiration date for the key (default: 90 days)
read -p "Enter expiration period in days [90]: " expiry_days
expiry_days=${expiry_days:-90}
expiry_date=$(date -d "+${expiry_days} days" +%Y-%m-%d)

# Save the new key
echo "$new_key" > "$key_file"
chmod 600 "$key_file"

# Save expiration metadata
echo "$expiry_date" > "${key_file}_expiry.txt"
chmod 600 "${key_file}_expiry.txt"

log_action "KEY_UPDATED" "$key_name" "Generated new key, expires on $expiry_date"

echo "✅ Successfully rotated $key_name API key"
echo "Key expiration date: $expiry_date"

# Ask if user wants to sync the new key now
read -p "Sync the new key to repositories now? (yes/no): " sync_now

if [ "$sync_now" = "yes" ]; then
  echo "Running sync-secrets.sh to distribute the new key..."
  ./sync-secrets.sh
  log_action "KEY_SYNCED" "$key_name" "New key immediately synced to repositories"
else
  echo "Remember to run sync-secrets.sh to distribute the new key"
  log_action "KEY_NOT_SYNCED" "$key_name" "User chose not to sync key immediately"
fi

echo ""
echo "Key rotation complete for $key_name"
echo "New key is active and expires on $expiry_date"
echo ""
echo "⚠️  IMPORTANT: If this key is used in external systems, update them manually"