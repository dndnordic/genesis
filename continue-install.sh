#!/bin/bash
# Helper script to install wget and continue Genesis installation

set -e

echo "Installing wget..."
# Try different package managers as we don't know the exact distro
if command -v apt-get &> /dev/null; then
    apt-get update && apt-get install -y wget
elif command -v yum &> /dev/null; then
    yum install -y wget
elif command -v dnf &> /dev/null; then
    dnf install -y wget
elif command -v zypper &> /dev/null; then
    zypper install -y wget
elif command -v apk &> /dev/null; then
    apk add wget
else
    echo "Could not determine package manager. Please install wget manually."
    exit 1
fi

echo "wget installed successfully."

# Continue with Gitea installation
cd /root
echo "Continuing Genesis installation..."
cd genesis && sh install.sh

echo "Installation continued. Check for any additional errors."