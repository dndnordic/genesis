#!/bin/bash
# Setup script for Genesis repository runner

set -e

# Set variables
RUNNER_NAME="genesis-runner-$(hostname)"
RUNNER_DIR=~/actions-runner
GITHUB_ORG="dndnordic"
GITHUB_REPO="genesis"

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "Docker is required but not installed. Aborting."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Curl is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed. Aborting."; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "GitHub CLI is required but not installed. Aborting."; exit 1; }

# Create runner directory
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Download the latest runner
echo "Downloading the latest runner package..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/^v//')

# Download for Linux x64
curl -O -L "https://github.com/actions/runner/releases/download/v${LATEST_VERSION}/actions-runner-linux-x64-${LATEST_VERSION}.tar.gz"
tar xzf "./actions-runner-linux-x64-${LATEST_VERSION}.tar.gz"
rm "./actions-runner-linux-x64-${LATEST_VERSION}.tar.gz"

# Check GitHub CLI authentication
echo "Checking GitHub authentication..."
gh auth status || {
    echo "GitHub CLI is not authenticated. Please run 'gh auth login' first."
    exit 1
}

# Get a runner registration token
echo "Getting runner registration token..."
RUNNER_TOKEN=$(gh api "repos/${GITHUB_ORG}/${GITHUB_REPO}/actions/runners/registration-token" --method POST | jq -r '.token')

if [ -z "$RUNNER_TOKEN" ] || [ "$RUNNER_TOKEN" == "null" ]; then
    echo "Failed to get runner token. Please check your GitHub authentication."
    exit 1
fi

# Configure the runner
echo "Configuring the runner..."
./config.sh --url "https://github.com/${GITHUB_ORG}/${GITHUB_REPO}" \
            --token "$RUNNER_TOKEN" \
            --name "$RUNNER_NAME" \
            --labels "self-hosted,Linux,Docker,X64,genesis" \
            --unattended \
            --replace

# Install as a service
echo "Installing runner as a service..."
sudo ./svc.sh install

# Start the service
echo "Starting the runner service..."
sudo ./svc.sh start

# Create secrets sync script
echo "Creating secrets sync utility script..."
cat > ~/genesis-secrets-sync.sh << 'EOF'
#!/bin/bash
# Script to synchronize secrets between GitHub and local storage

set -e

GITHUB_ORG="dndnordic"
REPOS=("genesis" "origin" "singularity")
SECRETS_DIR="/home/sing/genesis/keys"

function get_repo_secrets() {
  local repo=$1
  echo "Fetching secrets for $repo..."
  gh api repos/$GITHUB_ORG/$repo/actions/secrets --paginate | jq -r '.secrets[].name'
}

function sync_all_secrets() {
  mkdir -p "$SECRETS_DIR"
  
  for repo in "${REPOS[@]}"; do
    echo "Processing $repo repository..."
    get_repo_secrets "$repo" | while read secret_name; do
      if [[ "$secret_name" == *"_KEY"* || "$secret_name" == *"_TOKEN"* || "$secret_name" == *"_PASSWORD"* ]]; then
        echo "Syncing $secret_name to local storage..."
        
        # Create a file for each secret
        secret_filename=$(echo "$secret_name" | tr '[:upper:]' '[:lower:]').txt
        touch "$SECRETS_DIR/$secret_filename"
        
        echo "Secret file created at $SECRETS_DIR/$secret_filename"
        # Note: We don't actually fetch the value as GitHub doesn't expose them via API
        echo "Secret value must be manually entered!"
      fi
    done
  done
  
  echo "Secrets synchronized to $SECRETS_DIR"
  echo "Please manually enter the actual secret values into each file."
}

sync_all_secrets
EOF

chmod +x ~/genesis-secrets-sync.sh

# Create status check script
cat > ~/genesis-runner-status.sh << 'EOF'
#!/bin/bash
echo "==== GitHub Runner Status ===="
cd ~/actions-runner && sudo ./svc.sh status

echo -e "\n==== Docker Status ===="
docker info | grep "Server Version" || echo "Docker not running!"

echo -e "\n==== Genesis Keys Status ===="
ls -la /home/sing/genesis/keys | grep -v "total" | wc -l

echo -e "\n==== Disk Space ===="
df -h /

echo -e "\n==== Memory Usage ===="
free -h
EOF

chmod +x ~/genesis-runner-status.sh

echo "Runner setup complete! You can check its status with ~/genesis-runner-status.sh"
echo "Labels: self-hosted, Linux, Docker, X64, genesis"