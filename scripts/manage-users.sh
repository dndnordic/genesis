#!/bin/bash
# This script manages user accounts and permissions
# Only Mikael and authorized Genesis admin should have access to these operations

set -e

echo "==== Genesis User Management ===="
echo "Started: $(date)"

# Configuration
USERS_CONFIG_FILE="config/users.json"

# Validate file existence
if [ ! -f "$USERS_CONFIG_FILE" ]; then
  echo "Error: Config file $USERS_CONFIG_FILE not found"
  exit 1
fi

# Load user configuration
USERS=$(cat "$USERS_CONFIG_FILE")

# Function to list all users
list_users() {
  echo "Listing all users:"
  echo "$USERS" | jq -r '.users[] | "- \(.name) (\(.email)): \(.role) with \(.permissions) permissions on \(.repositories | join(", "))"'
}

# Function to get user info
get_user_info() {
  local username=$1
  
  echo "Getting info for user $username..."
  
  user_info=$(echo "$USERS" | jq -r ".users[] | select(.name == \"$username\")")
  
  if [ ! -z "$user_info" ]; then
    echo "✅ User information for $username:"
    echo "$user_info" | jq '.'
  else
    echo "❌ User not found: $username"
    return 1
  fi
}

# Function to update user permissions
update_user_permissions() {
  local username=$1
  local permission=$2
  
  echo "Updating permissions for $username to $permission..."
  
  # Update permissions in the users.json file
  updated_users=$(echo "$USERS" | jq ".users[] | select(.name == \"$username\").permissions = \"$permission\"")
  
  # Write back to file
  echo "$updated_users" > "$USERS_CONFIG_FILE"
  
  echo "✅ Updated permissions for $username to $permission"
  
  # Apply the permission changes across repositories
  for repo in $(echo "$USERS" | jq -r ".users[] | select(.name == \"$username\").repositories[]"); do
    full_repo="dndnordic/$repo"
    echo "Updating $username permissions on $full_repo to $permission..."
    
    gh api repos/$full_repo/collaborators/$username -X PUT -f permission=$permission
    
    if [ $? -eq 0 ]; then
      echo "✅ Successfully updated $username permissions on $full_repo"
    else
      echo "❌ Failed to update $username permissions on $full_repo"
    fi
  done
}

# Function to add a new user
add_user() {
  local name=$1
  local email=$2
  local role=$3
  local permissions=$4
  local repositories=$5
  
  echo "Adding new user $name ($email)..."
  
  # Check if user already exists
  existing_user=$(echo "$USERS" | jq -r ".users[] | select(.name == \"$name\")")
  
  if [ ! -z "$existing_user" ]; then
    echo "❌ User $name already exists!"
    return 1
  fi
  
  # Create new user entry
  new_user="{\"name\":\"$name\",\"email\":\"$email\",\"role\":\"$role\",\"repositories\":[$repositories],\"permissions\":\"$permissions\"}"
  
  # Add to users.json
  updated_users=$(echo "$USERS" | jq ".users += [$new_user]")
  echo "$updated_users" > "$USERS_CONFIG_FILE"
  
  echo "✅ Added new user $name"
  
  # Add the user to the specified repositories
  IFS=',' read -ra REPOS <<< "$repositories"
  for repo in "${REPOS[@]}"; do
    repo=$(echo "$repo" | tr -d '[]"')
    full_repo="dndnordic/$repo"
    echo "Adding $name to $full_repo with $permissions permissions..."
    
    gh api repos/$full_repo/collaborators/$name -X PUT -f permission=$permissions
    
    if [ $? -eq 0 ]; then
      echo "✅ Successfully added $name to $full_repo"
    else
      echo "❌ Failed to add $name to $full_repo"
    fi
  done
}

# Parse command line arguments
case "$1" in
  list)
    list_users
    ;;
    
  info)
    if [ -z "$2" ]; then
      echo "Error: Username required"
      echo "Usage: $0 info <username>"
      exit 1
    fi
    get_user_info "$2"
    ;;
    
  update-permission)
    if [ -z "$2" ] || [ -z "$3" ]; then
      echo "Error: Username and permission required"
      echo "Usage: $0 update-permission <username> <permission>"
      echo "Permissions: admin, write, read"
      exit 1
    fi
    update_user_permissions "$2" "$3"
    ;;
    
  add)
    if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ]; then
      echo "Error: Missing parameters"
      echo "Usage: $0 add <name> <email> <role> <permissions> <repositories>"
      echo "Example: $0 add new-user user@example.com bot write \"\\\"repo1\\\",\\\"repo2\\\"\""
      exit 1
    fi
    add_user "$2" "$3" "$4" "$5" "$6"
    ;;
    
  *)
    echo "Usage: $0 {list|info|update-permission|add}"
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 info dnd-genesis"
    echo "  $0 update-permission dnd-singularity admin"
    echo "  $0 add new-user user@example.com bot write \"\\\"repo1\\\",\\\"repo2\\\"\""
    exit 1
    ;;
esac

echo "==== User management completed ===="
echo "Finished: $(date)"