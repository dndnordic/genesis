#!/bin/bash
# This script updates GitHub repository permissions
# Only Mikael and dnd-genesis should have access to these operations

set -e

echo "==== Genesis Permission Management ===="
echo "Started: $(date)"

# Configuration
PERMISSIONS_CONFIG_FILE="config/permissions.json"

# Validate config file existence
if [ ! -f "$PERMISSIONS_CONFIG_FILE" ]; then
  echo "Error: Config file $PERMISSIONS_CONFIG_FILE not found"
  exit 1
fi

# Load permissions configuration
echo "Loading permissions configuration..."
PERMISSIONS=$(cat "$PERMISSIONS_CONFIG_FILE")

# Function to set repository collaborators
update_collaborators() {
  local repo=$1
  local username=$2
  local permission=$3
  
  echo "Setting $username as $permission on $repo..."
  
  # Use GitHub CLI to add collaborator with specified permission
  gh api repos/$repo/collaborators/$username -X PUT -f permission=$permission
  
  if [ $? -eq 0 ]; then
    echo "✅ Successfully set $username as $permission on $repo"
  else
    echo "❌ Failed to set $username as $permission on $repo"
    return 1
  fi
}

# Process repositories and collaborators
for repo in $(echo "$PERMISSIONS" | jq -r '.repositories[] | @base64'); do
  _jq() {
    echo ${repo} | base64 --decode | jq -r ${1}
  }
  
  repo_name=$(_jq '.name')
  echo "Processing repository: $repo_name"
  
  # Process each collaborator for this repository
  for collab in $(echo "$repo" | base64 --decode | jq -r '.collaborators[] | @base64'); do
    _jq_collab() {
      echo ${collab} | base64 --decode | jq -r ${1}
    }
    
    username=$(_jq_collab '.username')
    permission=$(_jq_collab '.permission')
    
    update_collaborators "$repo_name" "$username" "$permission"
  done
  
  # Process branch protection rules if specified
  branch_protection=$(echo "$repo" | base64 --decode | jq -r '.branch_protection // empty')
  if [ ! -z "$branch_protection" ]; then
    echo "Setting branch protection rules for $repo_name..."
    
    branch=$(echo "$branch_protection" | jq -r '.branch')
    rules=$(echo "$branch_protection" | jq -c '.')
    
    # Set branch protection rules
    gh api repos/$repo_name/branches/$branch/protection -X PUT --input - <<< "$rules"
    
    if [ $? -eq 0 ]; then
      echo "✅ Successfully set branch protection rules for $repo_name"
    else
      echo "❌ Failed to set branch protection rules for $repo_name"
    fi
  fi
done

echo "==== Permission updates completed ===="
echo "Finished: $(date)"