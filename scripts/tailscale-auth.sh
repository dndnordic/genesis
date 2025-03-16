#!/bin/bash
# This script manages Tailscale authentication and network configuration
# Only Mikael and authorized Genesis admin should have access to these operations

set -e

echo "==== Genesis Tailscale Management ===="
echo "Started: $(date)"

# Configuration
TAILSCALE_CONFIG_FILE="config/tailscale.json"
TAILSCALE_KEY_FILE="keys/tailscale_api_key.txt"

# Validate files existence
if [ ! -f "$TAILSCALE_CONFIG_FILE" ]; then
  echo "Error: Config file $TAILSCALE_CONFIG_FILE not found"
  exit 1
fi

if [ ! -f "$TAILSCALE_KEY_FILE" ]; then
  echo "Error: Tailscale API key file $TAILSCALE_KEY_FILE not found"
  exit 1
fi

# Load configuration and key
TAILSCALE_CONFIG=$(cat "$TAILSCALE_CONFIG_FILE")
TAILSCALE_KEY=$(cat "$TAILSCALE_KEY_FILE")

# Function to create pre-authorized keys
create_auth_key() {
  local name=$1
  local expiry=$2
  local tags=$3
  
  echo "Creating Tailscale auth key for $name..."
  
  # Create auth key using Tailscale API
  response=$(curl -s -X POST \
    -H "Authorization: Bearer $TAILSCALE_KEY" \
    -H "Content-Type: application/json" \
    --data "{\"capabilities\":{\"devices\":{\"create\":{\"reusable\":true,\"ephemeral\":false,\"preauthorized\":true,\"tags\":[\"$tags\"]}}},\"expirySeconds\":$expiry}" \
    "https://api.tailscale.com/api/v2/tailnet/dndnordic.github/keys")
  
  key=$(echo "$response" | jq -r '.key')
  
  if [ "$key" != "null" ] && [ ! -z "$key" ]; then
    echo "✅ Successfully created auth key for $name"
    echo "Key: $key"
    # Store key in a file for later use
    echo "$key" > "keys/tailscale_auth_${name}.txt"
  else
    echo "❌ Failed to create auth key for $name"
    echo "Response: $response"
    return 1
  fi
}

# Function to get device information
get_device_info() {
  local device=$1
  
  echo "Getting info for device $device..."
  
  # Get device info using Tailscale API
  response=$(curl -s -X GET \
    -H "Authorization: Bearer $TAILSCALE_KEY" \
    "https://api.tailscale.com/api/v2/tailnet/dndnordic.github/devices?fields=all")
  
  device_info=$(echo "$response" | jq -r ".devices[] | select(.name == \"$device\")")
  
  if [ ! -z "$device_info" ]; then
    echo "✅ Successfully retrieved info for $device"
    echo "$device_info" | jq '.'
  else
    echo "❌ No information found for device $device"
    return 1
  fi
}

# Function to set device tags
set_device_tags() {
  local device_id=$1
  local tags=$2
  
  echo "Setting tags for device $device_id..."
  
  # Set device tags using Tailscale API
  response=$(curl -s -X POST \
    -H "Authorization: Bearer $TAILSCALE_KEY" \
    -H "Content-Type: application/json" \
    --data "{\"tags\":[\"$tags\"]}" \
    "https://api.tailscale.com/api/v2/tailnet/dndnordic.github/devices/$device_id")
  
  if [ -z "$response" ]; then
    echo "✅ Successfully set tags for device $device_id"
  else
    echo "❌ Failed to set tags for device $device_id"
    echo "Response: $response"
    return 1
  fi
}

# Process auth keys
echo "Processing Tailscale auth keys..."
for auth_key in $(echo "$TAILSCALE_CONFIG" | jq -r '.auth_keys[] | @base64'); do
  _jq() {
    echo ${auth_key} | base64 --decode | jq -r ${1}
  }
  
  name=$(_jq '.name')
  expiry=$(_jq '.expiry')
  tags=$(_jq '.tags')
  
  create_auth_key "$name" "$expiry" "$tags"
done

# Process devices
echo "Processing Tailscale devices..."
for device in $(echo "$TAILSCALE_CONFIG" | jq -r '.devices[] | @base64'); do
  _jq() {
    echo ${device} | base64 --decode | jq -r ${1}
  }
  
  name=$(_jq '.name')
  device_id=$(_jq '.id')
  tags=$(_jq '.tags')
  action=$(_jq '.action')
  
  case "$action" in
    info)
      get_device_info "$name"
      ;;
    tag)
      set_device_tags "$device_id" "$tags"
      ;;
    *)
      echo "Unknown action: $action for device $name"
      ;;
  esac
done

echo "==== Tailscale management completed ===="
echo "Finished: $(date)"