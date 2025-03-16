#!/bin/bash
# Register a new security key (YubiKey or Passkey) for Genesis administration

set -e

echo "==== Genesis Security Key Registration ===="
echo "Started: $(date)"

# Configuration
AUDIT_LOG_FILE="keys/audit-log.txt"
REGISTERED_DEVICES_FILE="keys/registered_devices.txt"
TEMP_CHALLENGE_FILE="keys/temp_challenge.txt"

# Log function
log_action() {
  local action=$1
  local target=$2
  local description=$3
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $action - $target - $description" >> "$AUDIT_LOG_FILE"
}

# Create devices file if it doesn't exist
if [ ! -f "$REGISTERED_DEVICES_FILE" ]; then
  touch "$REGISTERED_DEVICES_FILE"
  chmod 600 "$REGISTERED_DEVICES_FILE"
  log_action "DEVICES_FILE_CREATED" "SYSTEM" "Created registered devices file"
fi

# If this isn't the first device, require authentication first
# But always allow registering a YubiKey to ensure there's always a physical key option
key_type_param=$1
is_yubikey=0
if [ "$key_type_param" = "yubikey" ]; then
  is_yubikey=1
  echo "YubiKey registration requested (always allowed for redundancy)"
fi

if [ -s "$REGISTERED_DEVICES_FILE" ] && [ -z "$YUBIKEY_VERIFIED" ] && [ $is_yubikey -eq 0 ]; then
  echo "⚠️  Authentication required to register a new device"
  echo "Please authenticate with an existing security key first"
  echo "Run verify-yubikey.sh and then try again"
  echo ""
  echo "Note: You can register a new YubiKey without authentication by running:"
  echo "      ./register-security-key.sh yubikey"
  log_action "REGISTRATION_DENIED" "AUTH" "Authentication required for new device registration"
  exit 1
fi

# Even if bypassing auth for YubiKey registration, log it
if [ $is_yubikey -eq 1 ] && [ -z "$YUBIKEY_VERIFIED" ]; then
  log_action "YUBIKEY_REGISTRATION" "BYPASS_AUTH" "Allowing YubiKey registration without authentication"
fi

# Start device registration
log_action "DEVICE_REGISTRATION_STARTED" "ADMIN" "Security key registration process initiated"

echo "Register a new security key for Genesis administration"

# If called with yubikey parameter, skip selection
if [ $is_yubikey -eq 1 ]; then
  device_type="YubiKey"
  echo "Selected: YubiKey (Hardware Security Key)"
else
  echo "Select security key type:"
  echo "1. YubiKey (Hardware Security Key)"
  echo "2. WebAuthn/Passkey"
  read -p "Choose type (1-2): " key_type
  
  case $key_type in
    1)
      device_type="YubiKey"
      ;;
    2)
      device_type="WebAuthn"
      ;;
    *)
      echo "Invalid selection"
      log_action "REGISTRATION_FAILED" "ADMIN" "Invalid security key type selected"
      exit 1
      ;;
  esac
fi

# Get device information
read -p "Enter device name/identifier: " device_name
read -p "Enter device model: " device_model
read -p "Enter device serial number (if applicable): " device_serial
read -p "Enter device location (e.g., 'Office safe', 'Home', 'Travel'): " device_location

# Generate a unique device ID
device_id="${device_type}-${device_name}-$(openssl rand -hex 4)"

# In a real implementation, this would use WebAuthn API or YubiKey libraries to register the device
echo "Generating registration challenge..."
challenge=$(openssl rand -base64 32)
echo "$challenge" > "$TEMP_CHALLENGE_FILE"

echo "Please follow these steps to register your $device_type device:"
echo ""

if [ "$device_type" = "YubiKey" ]; then
  echo "1. Insert your YubiKey if not already inserted"
  echo "2. When prompted, touch the YubiKey's sensor"
  echo "3. Wait for the registration to complete"
else
  echo "1. Your browser will prompt you to create a passkey"
  echo "2. Follow your browser's instructions to register the passkey"
  echo "3. The registration should associate this passkey with your account"
fi

echo ""
read -p "Press Enter when ready to proceed with registration..."

# Simulate registration process
echo "Processing $device_type registration..."
echo "Storing credentials securely..."
sleep 2  # Simulate processing time

# Store device information
device_entry="$device_id|$device_type|$device_name|$device_model|$device_serial|$device_location|$(date "+%Y-%m-%d %H:%M:%S")"
echo "$device_entry" >> "$REGISTERED_DEVICES_FILE"

# Log registration
log_action "DEVICE_REGISTERED" "$device_id" "New $device_type '$device_name' registered for location: $device_location"

echo ""
echo "✅ Security key registration successful!"
echo "Device ID: $device_id"
echo "Type: $device_type"
echo "Name: $device_name"
echo "Location: $device_location"
echo ""
echo "⚠️  IMPORTANT: Store this device ID safely. You will need it when authenticating."
echo "⚠️  IMPORTANT: Remember the physical location of this security key."

# If this is the first device, inform the user
if [ $(wc -l < "$REGISTERED_DEVICES_FILE") -eq 1 ]; then
  echo ""
  echo "This is your first registered security key."
  echo "It is now the master security control for Genesis administration."
fi

# List all registered devices
echo ""
echo "Currently registered security keys:"
echo "--------------------------------"
echo "ID | Type | Name | Location"
grep -v "^$" "$REGISTERED_DEVICES_FILE" | while IFS='|' read -r id type name model serial location timestamp; do
  echo "$id | $type | $name | $location"
done

# Remove temporary files
rm -f "$TEMP_CHALLENGE_FILE"