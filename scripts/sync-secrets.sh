#!/bin/bash
# This script syncs secrets from Genesis to other repositories
# Only Mikael and Claude Code (as Enterprise Admins) should have access to these operations

set -e

echo "==== Genesis Secret Synchronization ===="
echo "Started: $(date)"

# Configuration
GENESIS_REPO="dndnordic/genesis"
SECRETS_CONFIG_FILE="config/secrets.json"
AUDIT_LOG_FILE="keys/audit-log.txt"

# Log function
log_action() {
  local action=$1
  local target=$2
  local description=$3
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $action - $target - $description" >> "$AUDIT_LOG_FILE"
}

# Start audit entry
log_action "SYNC_STARTED" "ALL" "Secret synchronization process initiated"

# Validate config file existence
if [ ! -f "$SECRETS_CONFIG_FILE" ]; then
  log_action "ERROR" "CONFIG" "Config file $SECRETS_CONFIG_FILE not found"
  echo "Error: Config file $SECRETS_CONFIG_FILE not found"
  exit 1
fi

# Check for authentication
if [ -f "./keys/.require_auth" ] && [ -z "$YUBIKEY_VERIFIED" ]; then
  echo "⚠️  Security authentication required"
  echo "Please run verify-yubikey.sh first or set YUBIKEY_VERIFIED=1"
  log_action "ACCESS_DENIED" "AUTH" "Security authentication not completed"
  exit 1
fi

# Check if authentication has expired (more than 1 hour old)
if [ -f "./keys/.last_auth" ]; then
  last_auth=$(cat "./keys/.last_auth" | cut -d' ' -f1,2)
  last_epoch=$(date -d "$last_auth" +%s)
  now_epoch=$(date +%s)
  elapsed_seconds=$((now_epoch - last_epoch))
  
  if [ $elapsed_seconds -gt 3600 ]; then  # 3600 seconds = 1 hour
    echo "⚠️  Authentication has expired (more than 1 hour old)"
    echo "Please run verify-yubikey.sh again to re-authenticate"
    log_action "ACCESS_DENIED" "AUTH" "Authentication expired ($(($elapsed_seconds / 60)) minutes old)"
    exit 1
  fi
fi

# Function to set a secret in a repository
set_repo_secret() {
  local repo=$1
  local secret_name=$2
  local secret_value=$3
  
  echo "Setting $secret_name in $repo..."
  
  # Check for expiry metadata
  local expiry=""
  if [ -f "keys/${secret_name}_expiry.txt" ]; then
    expiry=$(cat "keys/${secret_name}_expiry.txt")
    # Check if key is expired
    if [[ "$expiry" < $(date +%Y-%m-%d) ]]; then
      echo "⚠️  WARNING: API key $secret_name is expired (Expiry: $expiry)"
      log_action "KEY_EXPIRED" "$secret_name" "API key is past expiration date: $expiry"
    fi
    
    # Check if key is about to expire
    expiry_epoch=$(date -d "$expiry" +%s)
    now_epoch=$(date +%s)
    days_diff=$(( (expiry_epoch - now_epoch) / 86400 ))
    if [ "$days_diff" -lt 30 ]; then
      echo "⚠️  WARNING: API key $secret_name expires in $days_diff days (Expiry: $expiry)"
      log_action "KEY_EXPIRING" "$secret_name" "API key expires in $days_diff days: $expiry"
    fi
  else
    echo "⚠️  WARNING: No expiry date found for $secret_name"
    log_action "NO_EXPIRY" "$secret_name" "No expiration date metadata found"
  fi
  
  # Use GitHub CLI to set secret
  echo "$secret_value" | gh secret set "$secret_name" --repo "$repo"
  
  if [ $? -eq 0 ]; then
    echo "✅ Successfully set $secret_name in $repo"
    log_action "SECRET_SET" "$repo/$secret_name" "Successfully set secret"
  else
    echo "❌ Failed to set $secret_name in $repo"
    log_action "ERROR" "$repo/$secret_name" "Failed to set secret"
    return 1
  fi
}

# Function to set repository variables
set_repo_variable() {
  local repo=$1
  local var_name=$2
  local var_value=$3
  
  echo "Setting variable $var_name in $repo..."
  
  # Use GitHub CLI to set variable
  gh variable set "$var_name" --repo "$repo" --body "$var_value"
  
  if [ $? -eq 0 ]; then
    echo "✅ Successfully set variable $var_name in $repo"
  else
    echo "❌ Failed to set variable $var_name in $repo"
    return 1
  fi
}

# Function to set enterprise variable
set_enterprise_variable() {
  local var_name=$1
  local var_value=$2
  
  echo "Setting enterprise variable $var_name..."
  
  # Use GitHub CLI to set enterprise variable
  gh variable set "$var_name" --org "dndnordic" --visibility "all" --body "$var_value"
  
  if [ $? -eq 0 ]; then
    echo "✅ Successfully set enterprise variable $var_name"
  else
    echo "❌ Failed to set enterprise variable $var_name"
    return 1
  fi
}

# Function to set enterprise secret
set_enterprise_secret() {
  local secret_name=$1
  local secret_value=$2
  
  echo "Setting enterprise secret $secret_name..."
  
  # Use GitHub CLI to set enterprise secret
  echo "$secret_value" | gh secret set "$secret_name" --org "dndnordic" --visibility "all"
  
  if [ $? -eq 0 ]; then
    echo "✅ Successfully set enterprise secret $secret_name"
  else
    echo "❌ Failed to set enterprise secret $secret_name"
    return 1
  fi
}

# Load secrets from config
echo "Loading secrets configuration..."
SECRETS=$(cat "$SECRETS_CONFIG_FILE")

# Process enterprise secrets
echo "Processing Enterprise secrets and variables..."
for secret in $(echo "$SECRETS" | jq -r '.enterprise.secrets[] | @base64' 2>/dev/null || echo ""); do
  if [ -z "$secret" ]; then
    echo "No enterprise secrets defined"
    break
  fi
  
  _jq() {
    echo ${secret} | base64 --decode | jq -r ${1}
  }
  
  name=$(_jq '.name')
  value=$(_jq '.value')
  # If value is a file path, load the content
  if [[ "$value" == file:* ]]; then
    file_path=${value#file:}
    if [ -f "$file_path" ]; then
      value=$(cat "$file_path")
    else
      echo "❌ Secret file not found: $file_path"
      continue
    fi
  fi
  
  set_enterprise_secret "$name" "$value"
done

for variable in $(echo "$SECRETS" | jq -r '.enterprise.variables[] | @base64' 2>/dev/null || echo ""); do
  if [ -z "$variable" ]; then
    echo "No enterprise variables defined"
    break
  fi
  
  _jq() {
    echo ${variable} | base64 --decode | jq -r ${1}
  }
  
  name=$(_jq '.name')
  value=$(_jq '.value')
  
  set_enterprise_variable "$name" "$value"
done

# Process each repository
for repo in $(echo "$SECRETS" | jq -r '.repositories | keys[]'); do
  echo "Processing $repo repository secrets..."
  
  for secret in $(echo "$SECRETS" | jq -r --arg repo "$repo" '.repositories[$repo].secrets[] | @base64'); do
    _jq() {
      echo ${secret} | base64 --decode | jq -r ${1}
    }
    
    name=$(_jq '.name')
    value=$(_jq '.value')
    # If value is a file path, load the content
    if [[ "$value" == file:* ]]; then
      file_path=${value#file:}
      if [ -f "$file_path" ]; then
        value=$(cat "$file_path")
      else
        echo "❌ Secret file not found: $file_path"
        continue
      fi
    fi
    
    set_repo_secret "$repo" "$name" "$value"
  done
  
  echo "Processing $repo repository variables..."
  for variable in $(echo "$SECRETS" | jq -r --arg repo "$repo" '.repositories[$repo].variables[] | @base64' 2>/dev/null || echo ""); do
    if [ -z "$variable" ]; then
      echo "No variables defined for $repo"
      break
    fi
    
    _jq() {
      echo ${variable} | base64 --decode | jq -r ${1}
    }
    
    name=$(_jq '.name')
    value=$(_jq '.value')
    
    set_repo_variable "$repo" "$name" "$value"
  done
done

echo "==== Secret synchronization completed ===="
echo "Finished: $(date)"
echo ""
log_action "SYNC_COMPLETED" "ALL" "Secret synchronization process completed"

# Check for keys that need rotation
echo "Checking for keys needing rotation..."
for key_file in keys/*_expiry.txt; do
  if [ -f "$key_file" ]; then
    key_name=$(basename "$key_file" _expiry.txt)
    expiry=$(cat "$key_file")
    expiry_epoch=$(date -d "$expiry" +%s)
    now_epoch=$(date +%s)
    days_diff=$(( (expiry_epoch - now_epoch) / 86400 ))
    
    if [ "$days_diff" -lt 0 ]; then
      echo "❌ EXPIRED: $key_name (Expired on $expiry)"
    elif [ "$days_diff" -lt 30 ]; then
      echo "⚠️  WARNING: $key_name expires in $days_diff days (Expiry: $expiry)"
    fi
  fi
done

# Generate rotation report
echo ""
echo "API Key Rotation Report:"
echo "-----------------------"
echo "Keys to rotate immediately:"
grep "KEY_EXPIRED" "$AUDIT_LOG_FILE" | tail -n 10
echo ""
echo "Keys to rotate soon:"
grep "KEY_EXPIRING" "$AUDIT_LOG_FILE" | tail -n 10
echo ""

echo "⚠️  IMPORTANT: Only Mikael and Claude Code (Enterprise Admins) should run this script"
echo "               All sensitive API keys are now stored in GitHub secrets"
echo "               Singularity has minimal access to credentials"
echo "               Check the audit log at $AUDIT_LOG_FILE for detailed history"