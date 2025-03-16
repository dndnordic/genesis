#!/bin/bash
# CA Sync Script
# This script synchronizes CA certificates between the three Origin clusters
# It runs as a CronJob in each cluster to ensure CA consistency

set -e

# Configuration
CLUSTERS=("alpha" "beta" "gamma")
PRIMARY_CLUSTER="alpha"
BACKUP_CLUSTERS=("beta" "gamma")
CA_SECRET_NAME="internal-ca-key-pair"
CA_SECRET_NAMESPACE="cert-manager"
KUBECONFIG_DIR="/etc/kubernetes/kubeconfig"
LOG_FILE="/var/log/ca-sync.log"

# Log function
log() {
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $1" >> $LOG_FILE
  echo "[$timestamp] $1"
}

# Function to get current cluster name
get_current_cluster() {
  # Try several methods to determine current cluster
  
  # Method 1: From config
  if [ -f "/etc/config/cluster.json" ]; then
    CLUSTER=$(jq -r '.cluster.name' /etc/config/cluster.json)
    if [ -n "$CLUSTER" ]; then
      echo "$CLUSTER"
      return
    fi
  fi
  
  # Method 2: From environment variable
  if [ -n "$CLUSTER_NAME" ]; then
    echo "$CLUSTER_NAME"
    return
  fi
  
  # Method 3: From label on node
  NODE_NAME=$(hostname)
  CLUSTER=$(kubectl get node "$NODE_NAME" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/region}')
  if [ -n "$CLUSTER" ]; then
    echo "$CLUSTER"
    return
  fi
  
  # Default to unknown
  echo "unknown"
}

# Get the current cluster
CURRENT_CLUSTER=$(get_current_cluster)
log "Current cluster: $CURRENT_CLUSTER"

# Function to check CA certificate validity
check_ca_validity() {
  local cluster=$1
  local kubeconfig="${KUBECONFIG_DIR}/${cluster}.kubeconfig"
  
  log "Checking CA certificate validity in cluster $cluster"
  
  # Get CA certificate from secret
  CA_CERT=$(kubectl --kubeconfig=$kubeconfig get secret $CA_SECRET_NAME -n $CA_SECRET_NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d)
  
  if [ -z "$CA_CERT" ]; then
    log "ERROR: Failed to get CA certificate from cluster $cluster"
    return 1
  fi
  
  # Check validity using openssl
  CERT_INFO=$(echo "$CA_CERT" | openssl x509 -noout -text)
  EXPIRES=$(echo "$CERT_INFO" | grep "Not After" | cut -d: -f2-)
  
  log "CA certificate in cluster $cluster expires: $EXPIRES"
  
  # Check if certificate is valid
  echo "$CA_CERT" | openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt - >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    log "WARNING: CA certificate validation failed in cluster $cluster"
    return 1
  fi
  
  return 0
}

# Function to get CA certificates from all clusters
get_all_ca_certs() {
  local output_dir=$1
  mkdir -p $output_dir
  
  for cluster in "${CLUSTERS[@]}"; do
    local kubeconfig="${KUBECONFIG_DIR}/${cluster}.kubeconfig"
    
    log "Getting CA certificate from cluster $cluster"
    
    # Skip if kubeconfig doesn't exist
    if [ ! -f "$kubeconfig" ]; then
      log "Skipping cluster $cluster - kubeconfig not found"
      continue
    fi
    
    # Get CA certificate from secret
    CA_CERT=$(kubectl --kubeconfig=$kubeconfig get secret $CA_SECRET_NAME -n $CA_SECRET_NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d)
    CA_KEY=$(kubectl --kubeconfig=$kubeconfig get secret $CA_SECRET_NAME -n $CA_SECRET_NAMESPACE -o jsonpath='{.data.tls\.key}' | base64 -d)
    
    if [ -z "$CA_CERT" ]; then
      log "WARNING: Failed to get CA certificate from cluster $cluster"
      continue
    fi
    
    if [ -z "$CA_KEY" ]; then
      log "WARNING: Failed to get CA private key from cluster $cluster"
      continue
    }
    
    # Save to file
    echo "$CA_CERT" > "${output_dir}/${cluster}.crt"
    echo "$CA_KEY" > "${output_dir}/${cluster}.key"
    chmod 600 "${output_dir}/${cluster}.key"
    
    log "Successfully retrieved CA from cluster $cluster"
  done
}

# Function to compare CA certificates from all clusters
compare_ca_certs() {
  local cert_dir=$1
  local primary="${cert_dir}/${PRIMARY_CLUSTER}.crt"
  
  log "Comparing CA certificates across clusters"
  
  # Check if primary certificate exists
  if [ ! -f "$primary" ]; then
    log "ERROR: Primary CA certificate not found"
    return 1
  fi
  
  local all_match=true
  
  # Compare certificates
  for cluster in "${BACKUP_CLUSTERS[@]}"; do
    local cert="${cert_dir}/${cluster}.crt"
    
    # Skip if certificate doesn't exist
    if [ ! -f "$cert" ]; then
      log "WARNING: CA certificate for cluster $cluster not found"
      all_match=false
      continue
    fi
    
    # Compare with primary
    diff -q "$primary" "$cert" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      log "WARNING: CA certificate in cluster $cluster does not match primary"
      all_match=false
    else
      log "CA certificate in cluster $cluster matches primary"
    fi
  done
  
  if $all_match; then
    log "All CA certificates match"
    return 0
  else
    log "CA certificates don't match across all clusters"
    return 1
  fi
}

# Function to sync CA certificates to all clusters
sync_ca_certs() {
  local cert_dir=$1
  local primary="${cert_dir}/${PRIMARY_CLUSTER}"
  
  log "Syncing CA certificates from primary cluster ($PRIMARY_CLUSTER) to all others"
  
  # Check if primary certificates exist
  if [ ! -f "${primary}.crt" ] || [ ! -f "${primary}.key" ]; then
    log "ERROR: Primary CA certificates not found"
    return 1
  fi
  
  # Read certificates
  PRIMARY_CERT=$(cat "${primary}.crt")
  PRIMARY_KEY=$(cat "${primary}.key")
  
  # Encode to base64
  PRIMARY_CERT_B64=$(echo "$PRIMARY_CERT" | base64 -w0)
  PRIMARY_KEY_B64=$(echo "$PRIMARY_KEY" | base64 -w0)
  
  # Sync to all clusters
  for cluster in "${CLUSTERS[@]}"; do
    # Skip primary
    if [ "$cluster" == "$PRIMARY_CLUSTER" ]; then
      continue
    fi
    
    local kubeconfig="${KUBECONFIG_DIR}/${cluster}.kubeconfig"
    
    # Skip if kubeconfig doesn't exist
    if [ ! -f "$kubeconfig" ]; then
      log "Skipping cluster $cluster - kubeconfig not found"
      continue
    }
    
    log "Syncing CA certificate to cluster $cluster"
    
    # Prepare patch
    local patch="{\"data\":{\"tls.crt\":\"${PRIMARY_CERT_B64}\",\"tls.key\":\"${PRIMARY_KEY_B64}\"}}"
    
    # Apply patch
    kubectl --kubeconfig=$kubeconfig patch secret $CA_SECRET_NAME -n $CA_SECRET_NAMESPACE --type=merge -p "$patch"
    if [ $? -eq 0 ]; then
      log "Successfully synced CA certificate to cluster $cluster"
    else
      log "ERROR: Failed to sync CA certificate to cluster $cluster"
    fi
  done
}

# Main logic
log "Starting CA certificate sync"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf $TEMP_DIR' EXIT

# Get CA certificates from all clusters
get_all_ca_certs $TEMP_DIR

# Compare CA certificates
compare_ca_certs $TEMP_DIR
if [ $? -ne 0 ]; then
  log "CA certificates don't match, initiating sync"
  
  # Check if current cluster is primary
  if [ "$CURRENT_CLUSTER" == "$PRIMARY_CLUSTER" ]; then
    log "This is the primary cluster, syncing CA certificates to all backup clusters"
    sync_ca_certs $TEMP_DIR
  else
    log "This is not the primary cluster, skipping sync"
  fi
else
  log "All CA certificates are in sync, no action needed"
fi

log "CA certificate sync completed"
exit 0