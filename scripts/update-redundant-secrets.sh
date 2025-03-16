#!/bin/bash
# This script generates secure random passwords for redundant services
# and updates the secret files in the Genesis repository.

set -e

echo "==== Genesis Redundant Services Secret Update ===="
echo "Started: $(date)"

# Configuration
SECRET_DIR="keys/redundant-services"
LOG_FILE="$SECRET_DIR/update-log.txt"
EXPIRY_DAYS=90

# Log message to file
log_message() {
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Check for YubiKey verification
if [ -z "$YUBIKEY_VERIFIED" ]; then
  echo "⚠️  Authentication required"
  echo "Please run verify-yubikey.sh first"
  exit 1
fi

# Log start of update
log_message "Starting redundant services secret update"

# Generate strong random passwords
generate_strong_password() {
  # Generate a secure 32-character password with mixed characters
  openssl rand -base64 32 | tr -dc 'a-zA-Z0-9!@#$%^&*()-_=+' | head -c 32
}

# Update a secret file
update_secret() {
  local file="$1"
  local description="$2"
  
  echo "Updating $description secret..."
  local new_password=$(generate_strong_password)
  echo "$new_password" > "$SECRET_DIR/$file"
  chmod 600 "$SECRET_DIR/$file"
  
  # Create or update expiry date
  local expiry_date=$(date -d "+$EXPIRY_DAYS days" "+%Y-%m-%d")
  echo "$expiry_date" > "$SECRET_DIR/$file.expiry"
  
  log_message "Updated $file (expires: $expiry_date)"
  echo "✅ $description secret updated"
}

# Function to prompt for confirmation
confirm_update() {
  local service="$1"
  read -p "Update $service secrets? (yes/no): " confirm
  
  if [ "$confirm" != "yes" ]; then
    echo "Skipping $service secrets update"
    return 1
  fi
  
  return 0
}

# Update Keycloak secrets (internally generated)
if confirm_update "Keycloak"; then
  update_secret "keycloak_admin_password.txt" "Keycloak admin"
  update_secret "keycloak_db_password.txt" "Keycloak database"
fi

# Update PostgreSQL secrets (internally generated)
if confirm_update "PostgreSQL"; then
  update_secret "postgres_superuser_password.txt" "PostgreSQL superuser"
  update_secret "postgres_replication_password.txt" "PostgreSQL replication"
  update_secret "postgres_app_password.txt" "PostgreSQL application"
fi

# Update Vault secrets (internally generated)
if confirm_update "Vault"; then
  update_secret "vault_unseal_key.txt" "Vault unseal key"
  update_secret "vault_root_token.txt" "Vault root token"
  update_secret "vault_transit_token.txt" "Vault transit token"
fi

# Update MinIO/S3-compatible storage secrets (internally generated)
if confirm_update "MinIO (S3-compatible storage)"; then
  update_secret "minio_root_user.txt" "MinIO root username"
  update_secret "minio_root_password.txt" "MinIO root password"
  update_secret "minio_backup_access_key.txt" "MinIO backup access key" 
  update_secret "minio_backup_secret_key.txt" "MinIO backup secret key"
  update_secret "minio_replication_access_key.txt" "MinIO replication access key"
  update_secret "minio_replication_secret_key.txt" "MinIO replication secret key"
fi

# Prompt for external service credentials
update_external_credential() {
  local file="$1"
  local description="$2"
  
  echo "Updating $description..."
  read -p "Enter new value for $description (or press Enter to keep existing): " new_value
  
  if [ -n "$new_value" ]; then
    echo "$new_value" > "$SECRET_DIR/$file"
    chmod 600 "$SECRET_DIR/$file"
    
    # Create or update expiry date
    local expiry_date=$(date -d "+$EXPIRY_DAYS days" "+%Y-%m-%d")
    echo "$expiry_date" > "$SECRET_DIR/$file.expiry"
    
    log_message "Updated $file (expires: $expiry_date)"
    echo "✅ $description updated"
  else
    echo "Keeping existing value for $description"
  fi
}

# Update CA certificates for internal CA
if confirm_update "Internal Certificate Authority"; then
  
  echo "We're using our internal CA for all services"
  
  # Check if CA already exists
  if [ -s "$SECRET_DIR/ca_private_key.txt" ] && [ -s "$SECRET_DIR/ca_certificate.txt" ]; then
    echo "CA certificate and private key already exist."
    read -p "Do you want to generate a new CA? (yes/no): " regenerate_ca
    
    if [ "$regenerate_ca" != "yes" ]; then
      echo "Keeping existing CA certificate and private key"
    else
      # Generate new CA keypair
      echo "Generating new CA private key and certificate..."
      
      # CA private key
      openssl genrsa -out "$SECRET_DIR/ca_private_key.txt.new" 4096
      chmod 600 "$SECRET_DIR/ca_private_key.txt.new"
      
      # Create the CA certificate
      openssl req -x509 -new -nodes -key "$SECRET_DIR/ca_private_key.txt.new" \
        -sha256 -days 3650 \
        -out "$SECRET_DIR/ca_certificate.txt.new" \
        -subj "/CN=DND Nordic Internal CA/O=DND Nordic/C=SE"
      
      # Move new files into place
      mv "$SECRET_DIR/ca_private_key.txt.new" "$SECRET_DIR/ca_private_key.txt"
      mv "$SECRET_DIR/ca_certificate.txt.new" "$SECRET_DIR/ca_certificate.txt"
      
      # Set permissions
      chmod 600 "$SECRET_DIR/ca_private_key.txt"
      chmod 644 "$SECRET_DIR/ca_certificate.txt"
      
      # Create or update expiry date (10 years)
      local expiry_date=$(date -d "+3650 days" "+%Y-%m-%d")
      echo "$expiry_date" > "$SECRET_DIR/ca_private_key.txt.expiry"
      echo "$expiry_date" > "$SECRET_DIR/ca_certificate.txt.expiry"
      
      # Save raw (non-base64) version for trust stores
      cat "$SECRET_DIR/ca_certificate.txt" > "$SECRET_DIR/ca_certificate_raw.txt"
      
      log_message "Generated new CA private key and certificate (expires: $expiry_date)"
      echo "✅ CA certificate and private key updated"
    fi
  else
    # Generate new CA keypair if it doesn't exist
    echo "No existing CA found. Generating new CA private key and certificate..."
    
    # CA private key
    openssl genrsa -out "$SECRET_DIR/ca_private_key.txt" 4096
    chmod 600 "$SECRET_DIR/ca_private_key.txt"
    
    # Create the CA certificate
    openssl req -x509 -new -nodes -key "$SECRET_DIR/ca_private_key.txt" \
      -sha256 -days 3650 \
      -out "$SECRET_DIR/ca_certificate.txt" \
      -subj "/CN=DND Nordic Internal CA/O=DND Nordic/C=SE"
    
    # Set permissions
    chmod 600 "$SECRET_DIR/ca_private_key.txt"
    chmod 644 "$SECRET_DIR/ca_certificate.txt"
    
    # Create or update expiry date (10 years)
    local expiry_date=$(date -d "+3650 days" "+%Y-%m-%d")
    echo "$expiry_date" > "$SECRET_DIR/ca_private_key.txt.expiry"
    echo "$expiry_date" > "$SECRET_DIR/ca_certificate.txt.expiry"
    
    # Save raw (non-base64) version for trust stores
    cat "$SECRET_DIR/ca_certificate.txt" > "$SECRET_DIR/ca_certificate_raw.txt"
    
    log_message "Generated new CA private key and certificate (expires: $expiry_date)"
    echo "✅ CA certificate and private key generated"
  fi
  
  # Display fingerprint for verification
  echo "CA Certificate Fingerprint (SHA256):"
  openssl x509 -in "$SECRET_DIR/ca_certificate.txt" -noout -fingerprint -sha256
fi

echo ""
echo "==== Secret update completed ===="
echo "Next steps:"
echo "1. Run sync-secrets.sh to distribute the updated secrets"
echo "2. Apply Kubernetes updates in Origin repository for any changed services"
echo ""
echo "⚠️  IMPORTANT: Keep these secrets secure. Never commit actual secret values to Git."
echo ""
echo "Note: Once Vault is fully deployed, most of these secrets will be migrated there."
echo "      Only the bootstrap credentials for Vault itself will remain in Genesis."

log_message "Secret update completed"