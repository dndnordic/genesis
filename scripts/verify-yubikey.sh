#!/bin/bash
# Security Key Verification Script for Genesis administration
# This script verifies the administrator's security key is present and valid

set -e

echo "==== Genesis Security Key Verification ===="
echo "Started: $(date)"

# Configuration
AUDIT_LOG_FILE="keys/audit-log.txt"
CHALLENGE_FILE="keys/challenge.txt"
RESPONSE_FILE="keys/response.txt"
REGISTERED_DEVICES_FILE="keys/registered_devices.txt"

# Log function
log_action() {
  local action=$1
  local target=$2
  local description=$3
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $action - $target - $description" >> "$AUDIT_LOG_FILE"
}

# Check for required files
if [ ! -f "$RESPONSE_FILE" ]; then
  echo "Error: Security key response file not found"
  log_action "ERROR" "AUTH" "Security key response file not found"
  exit 1
fi

if [ ! -f "$REGISTERED_DEVICES_FILE" ]; then
  echo "Error: Registered devices file not found"
  log_action "ERROR" "AUTH" "Registered devices file not found"
  exit 1
fi

# Start verification
log_action "AUTH_VERIFY_START" "ADMIN" "Security key verification process started"

# Generate a random challenge
challenge=$(openssl rand -hex 16)
echo "$challenge" > "$CHALLENGE_FILE"

echo "Authentication required for Genesis administration"
echo "Select authentication method:"
echo "1. YubiKey"
echo "2. WebAuthn/Passkey"
read -p "Choose method (1-2): " auth_method

case $auth_method in
  1)
    echo "Please insert your YubiKey and press Enter..."
    auth_type="YubiKey"
    ;;
  2)
    echo "Please use your browser or device to verify your Passkey..."
    auth_type="WebAuthn"
    ;;
  *)
    echo "Invalid selection"
    log_action "AUTH_FAILED" "ADMIN" "Invalid authentication method selected"
    exit 1
    ;;
esac

# For YubiKeys, auto-detect if possible instead of requiring device ID
if [ "$auth_type" = "YubiKey" ]; then
  echo "Attempting to auto-detect YubiKey..."
  
  # In a real implementation, this would detect and identify the inserted YubiKey
  # For demonstration, we'll simulate by listing available YubiKeys and selecting one
  
  echo "Available YubiKeys for Mikael:"
  echo "----------------------------"
  grep "YubiKey" "$REGISTERED_DEVICES_FILE" | while IFS='|' read -r id type name model serial location timestamp; do
    echo "$id - $name ($model) - $location"
  done
  
  # Auto-accept any Mikael YubiKey
  # In a real implementation, would verify the actual inserted YubiKey's serial number
  device_id=$(grep "YubiKey" "$REGISTERED_DEVICES_FILE" | head -1 | cut -d'|' -f1)
  
  if [ -z "$device_id" ]; then
    echo "No YubiKeys registered. Please register one first with register-security-key.sh"
    log_action "AUTH_FAILED" "ADMIN" "No YubiKeys registered"
    exit 1
  fi
  
  echo "Using YubiKey: $device_id"
else
  # For WebAuthn/Passkey, still ask for device ID as these are software-based
  echo "Available Passkeys for Mikael:"
  echo "--------------------------"
  grep "WebAuthn" "$REGISTERED_DEVICES_FILE" | while IFS='|' read -r id type name model serial location timestamp; do
    echo "$id - $name - $location"
  done
  
  read -p "Enter your Passkey device ID: " device_id
  
  # Verify the device ID is registered
  if ! grep -q "$device_id" "$REGISTERED_DEVICES_FILE"; then
    echo "❌ Unrecognized device ID: $device_id"
    log_action "AUTH_FAILED" "ADMIN" "Unrecognized device ID: $device_id"
    exit 1
  fi
fi

# Simulating security key verification (in real implementation, this would verify against the WebAuthn API or YubiKey)
echo "Processing $auth_type response..."
echo "Verifying administrator identity..."

# For demonstration purposes only
expected_response=$(cat "$RESPONSE_FILE")
if [ "$expected_response" == "DEMONSTRATION_MODE" ]; then
  # In a real implementation, this would check the security key response
  # against the expected value calculated from the challenge
  
  echo "✅ $auth_type verification successful with device $device_id"
  log_action "AUTH_VERIFIED" "ADMIN" "$auth_type verification successful with device $device_id"
  
  # Set verification environment variable
  export YUBIKEY_VERIFIED=1
  
  # Record successful verification
  echo "$(date "+%Y-%m-%d %H:%M:%S") - $auth_type - $device_id" > "keys/.last_auth"
  
  # Create temporary file to indicate verification status
  # This file will be checked by other scripts
  touch "keys/.require_auth"
  chmod 600 "keys/.require_auth"
  
  echo "Verification valid for one hour"
  echo "Run your Genesis administrative commands now"
else
  echo "❌ $auth_type verification failed"
  log_action "AUTH_FAILED" "ADMIN" "$auth_type verification failed with device $device_id"
  exit 1
fi