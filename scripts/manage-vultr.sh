#!/bin/bash
# This script manages Vultr resources
# Only Mikael and authorized Genesis admin should have access to these operations

set -e

echo "==== Genesis Vultr Management ===="
echo "Started: $(date)"

# Configuration
VULTR_API_KEY_FILE="keys/vultr_api_key.txt"
VULTR_ACCOUNT_ID_FILE="keys/vultr_account_id.txt"

# Validate files existence
if [ ! -f "$VULTR_API_KEY_FILE" ]; then
  echo "Error: Vultr API key file $VULTR_API_KEY_FILE not found"
  exit 1
fi

if [ ! -f "$VULTR_ACCOUNT_ID_FILE" ]; then
  echo "Error: Vultr Account ID file $VULTR_ACCOUNT_ID_FILE not found"
  exit 1
fi

# Load API credentials
VULTR_API_KEY=$(cat "$VULTR_API_KEY_FILE")
VULTR_ACCOUNT_ID=$(cat "$VULTR_ACCOUNT_ID_FILE")

# Function to list Vultr instances
list_instances() {
  echo "Listing Vultr instances..."
  
  # Get instances using Vultr API
  response=$(curl -s -X GET \
    -H "Authorization: Bearer $VULTR_API_KEY" \
    "https://api.vultr.com/v2/instances")
  
  instances=$(echo "$response" | jq -r '.instances')
  
  if [ "$instances" != "null" ] && [ ! -z "$instances" ]; then
    echo "✅ Instances found:"
    echo "$instances" | jq -r '.[] | "- \(.label): \(.id) (\(.os)) - \(.status) - \(.main_ip)"'
  else
    echo "❌ No instances found or error occurred"
    echo "Response: $response"
    return 1
  fi
}

# Function to get instance information
get_instance_info() {
  local instance_id=$1
  
  echo "Getting info for instance $instance_id..."
  
  # Get instance info using Vultr API
  response=$(curl -s -X GET \
    -H "Authorization: Bearer $VULTR_API_KEY" \
    "https://api.vultr.com/v2/instances/$instance_id")
  
  instance=$(echo "$response" | jq -r '.instance')
  
  if [ "$instance" != "null" ] && [ ! -z "$instance" ]; then
    echo "✅ Instance information:"
    echo "$instance" | jq '.'
  else
    echo "❌ Instance not found or error occurred"
    echo "Response: $response"
    return 1
  fi
}

# Function to manage Kubernetes clusters
list_kubernetes_clusters() {
  echo "Listing Kubernetes clusters..."
  
  # Get Kubernetes clusters using Vultr API
  response=$(curl -s -X GET \
    -H "Authorization: Bearer $VULTR_API_KEY" \
    "https://api.vultr.com/v2/kubernetes/clusters")
  
  clusters=$(echo "$response" | jq -r '.vke_clusters')
  
  if [ "$clusters" != "null" ] && [ ! -z "$clusters" ]; then
    echo "✅ Kubernetes clusters found:"
    echo "$clusters" | jq -r '.[] | "- \(.label): \(.id) - \(.status) - \(.region)"'
  else
    echo "❌ No Kubernetes clusters found or error occurred"
    echo "Response: $response"
    return 1
  fi
}

# Function to get Kubernetes cluster config
get_kubernetes_config() {
  local cluster_id=$1
  
  echo "Getting config for Kubernetes cluster $cluster_id..."
  
  # Get Kubernetes cluster config using Vultr API
  response=$(curl -s -X GET \
    -H "Authorization: Bearer $VULTR_API_KEY" \
    "https://api.vultr.com/v2/kubernetes/clusters/$cluster_id/config")
  
  kubeconfig=$(echo "$response" | jq -r '.kubeconfig')
  
  if [ "$kubeconfig" != "null" ] && [ ! -z "$kubeconfig" ]; then
    echo "✅ Kubernetes config retrieved successfully"
    echo "$kubeconfig" > "keys/kubeconfig-$cluster_id.yaml"
    echo "Saved to keys/kubeconfig-$cluster_id.yaml"
  else
    echo "❌ Failed to retrieve Kubernetes config"
    echo "Response: $response"
    return 1
  fi
}

# Function to list registry information
list_registry_info() {
  echo "Getting container registry information..."
  
  # Get registry info using Vultr API
  response=$(curl -s -X GET \
    -H "Authorization: Bearer $VULTR_API_KEY" \
    "https://api.vultr.com/v2/registry")
  
  registry=$(echo "$response" | jq -r '.registry')
  
  if [ "$registry" != "null" ] && [ ! -z "$registry" ]; then
    echo "✅ Registry information:"
    echo "$registry" | jq '.'
  else
    echo "❌ Registry information not found or error occurred"
    echo "Response: $response"
    return 1
  fi
}

# Function to list registry repositories
list_registry_repositories() {
  echo "Listing container registry repositories..."
  
  # Get registry repositories using Vultr API
  response=$(curl -s -X GET \
    -H "Authorization: Bearer $VULTR_API_KEY" \
    "https://api.vultr.com/v2/registry/repositories")
  
  repositories=$(echo "$response" | jq -r '.repositories')
  
  if [ "$repositories" != "null" ] && [ ! -z "$repositories" ]; then
    echo "✅ Repositories found:"
    echo "$repositories" | jq -r '.[] | "- \(.name): \(.image_count) images, \(.pull_count) pulls, last updated \(.last_updated)"'
  else
    echo "❌ No repositories found or error occurred"
    echo "Response: $response"
    return 1
  fi
}

# Parse command line arguments
case "$1" in
  list-instances)
    list_instances
    ;;
    
  instance-info)
    if [ -z "$2" ]; then
      echo "Error: Instance ID required"
      echo "Usage: $0 instance-info <instance_id>"
      exit 1
    fi
    get_instance_info "$2"
    ;;
    
  list-kubernetes)
    list_kubernetes_clusters
    ;;
    
  kubernetes-config)
    if [ -z "$2" ]; then
      echo "Error: Cluster ID required"
      echo "Usage: $0 kubernetes-config <cluster_id>"
      exit 1
    fi
    get_kubernetes_config "$2"
    ;;
    
  list-registry)
    list_registry_info
    ;;
    
  list-repositories)
    list_registry_repositories
    ;;
    
  *)
    echo "Usage: $0 {list-instances|instance-info|list-kubernetes|kubernetes-config|list-registry|list-repositories}"
    echo "Examples:"
    echo "  $0 list-instances"
    echo "  $0 instance-info abc123"
    echo "  $0 list-kubernetes"
    echo "  $0 kubernetes-config def456"
    echo "  $0 list-registry"
    echo "  $0 list-repositories"
    exit 1
    ;;
esac

echo "==== Vultr management completed ===="
echo "Finished: $(date)"