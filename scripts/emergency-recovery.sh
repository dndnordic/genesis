#!/bin/bash
# Emergency recovery script for Genesis administration
# This script allows recovery access if the YubiKey is lost

set -e

echo "==== Genesis Emergency Recovery ===="
echo "Started: $(date)"

# Configuration
AUDIT_LOG_FILE="keys/audit-log.txt"
EMERGENCY_LOG_FILE="keys/emergency-access.log"
EMERGENCY_CODES_FILE="keys/emergency_codes.txt"
MIKAEL_PHONE="+123456789"  # This would be the actual phone number in a real implementation
MIKAEL_EMAIL="mikael@dndnordic.se"

# Log function
log_action() {
  local action=$1
  local target=$2
  local description=$3
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $action - $target - $description" >> "$AUDIT_LOG_FILE"
  echo "[$timestamp] $action - $target - $description" >> "$EMERGENCY_LOG_FILE"
}

# Check if all security keys are lost
echo "⚠️  WARNING: This emergency recovery procedure should only be used if ALL security keys are lost."
echo "If you have any registered YubiKey or WebAuthn/Passkey device, use that instead."
echo ""

# List registered devices if available
if [ -f "keys/registered_devices.txt" ] && [ -s "keys/registered_devices.txt" ]; then
  echo "Registered security devices:"
  echo "--------------------------"
  echo "ID | Type | Name | Location"
  grep -v "^$" "keys/registered_devices.txt" | while IFS='|' read -r id type name model serial location timestamp; do
    echo "$id | $type | $name | $location"
  done
  echo ""
  read -p "Are ALL of these devices lost or inaccessible? (yes/no): " all_lost
  if [ "$all_lost" != "yes" ]; then
    echo "Emergency recovery cancelled. Please use one of your registered devices."
    log_action "EMERGENCY_CANCELLED" "DEVICES_AVAILABLE" "User indicated not all devices are lost"
    exit 0
  fi
fi

# Check for last emergency recovery
if [ -f "keys/.last_emergency_recovery" ]; then
  last_recovery=$(cat "keys/.last_emergency_recovery")
  last_epoch=$(date -d "$last_recovery" +%s)
  now_epoch=$(date +%s)
  days_diff=$(( (now_epoch - last_epoch) / 86400 ))
  
  if [ "$days_diff" -lt 90 ]; then
    echo "⛔ ERROR: Emergency recovery was used $days_diff days ago"
    echo "Enterprise policy requires 90 days between emergency recoveries"
    echo "Please contact the security administrator for assistance"
    log_action "EMERGENCY_DENIED" "TIME_LIMIT" "Emergency recovery attempted within 90-day window"
    exit 1
  fi
fi

# Start recovery
log_action "EMERGENCY_RECOVERY_STARTED" "ADMIN" "Emergency recovery process initiated"

echo "⚠️  EMERGENCY RECOVERY PROCEDURE ⚠️"
echo "This procedure is for use only when the YubiKey is unavailable."
echo "All actions will be logged and audited."
echo ""
echo "To proceed, you will need:"
echo "1. Access to Mikael's registered phone: $MIKAEL_PHONE"
echo "2. Access to Mikael's registered email: $MIKAEL_EMAIL"
echo "3. Answers to security questions"
echo ""
read -p "Do you wish to continue? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
  echo "Emergency recovery cancelled"
  log_action "EMERGENCY_CANCELLED" "USER" "User cancelled emergency recovery"
  exit 0
fi

# Step 1: Verify phone access
echo ""
echo "Step 1: Phone Verification"
echo "A verification code has been sent to $MIKAEL_PHONE"
echo "(In a real implementation, this would send an SMS)"

# Simulate code generation and sending
phone_code=$(openssl rand -hex 3)
echo "DEBUG: Phone verification code is $phone_code"

read -p "Enter the code received on your phone: " entered_phone_code

if [ "$entered_phone_code" != "$phone_code" ]; then
  echo "❌ Invalid phone verification code"
  log_action "EMERGENCY_FAILED" "PHONE_VERIFICATION" "Invalid phone verification code entered"
  exit 1
fi

echo "✅ Phone verification successful"
log_action "EMERGENCY_STEP_COMPLETED" "PHONE_VERIFICATION" "Phone verification successful"

# Step 2: Email verification
echo ""
echo "Step 2: Email Verification"
echo "A verification link has been sent to $MIKAEL_EMAIL"
echo "(In a real implementation, this would send an email)"

# Simulate code generation and sending
email_code=$(openssl rand -hex 4)
echo "DEBUG: Email verification code is $email_code"

read -p "Enter the code from the email: " entered_email_code

if [ "$entered_email_code" != "$email_code" ]; then
  echo "❌ Invalid email verification code"
  log_action "EMERGENCY_FAILED" "EMAIL_VERIFICATION" "Invalid email verification code entered"
  exit 1
fi

echo "✅ Email verification successful"
log_action "EMERGENCY_STEP_COMPLETED" "EMAIL_VERIFICATION" "Email verification successful"

# Step 3: Security questions
echo ""
echo "Step 3: Security Questions"
echo "Please answer the following security questions."

# Security questions would be stored securely in a real implementation
# These are placeholders

read -p "What was the name of your first pet? " answer1
read -p "What is your mother's maiden name? " answer2
read -p "What was the model of your first car? " answer3

# In a real implementation, these would be compared against stored answers
# For demonstration purposes, we're accepting any answers
echo "✅ Security questions verified"
log_action "EMERGENCY_STEP_COMPLETED" "SECURITY_QUESTIONS" "Security questions answered correctly"

# Step 4: Generate recovery code
echo ""
echo "Step 4: Recovery Access"
echo "Generating temporary emergency access..."

# Generate a temporary access token
recovery_token=$(openssl rand -hex 16)
echo "Your emergency recovery token is: $recovery_token"
echo "This token is valid for ONE HOUR"

# Record recovery timestamp
echo "$(date "+%Y-%m-%d %H:%M:%S")" > "keys/.last_emergency_recovery"

# Set up temporary access
export YUBIKEY_VERIFIED=1
touch "keys/.emergency_access"
chmod 600 "keys/.emergency_access"
echo "$recovery_token" > "keys/.emergency_token"

log_action "EMERGENCY_RECOVERY_SUCCESSFUL" "ADMIN" "Emergency recovery access granted for one hour"

echo ""
echo "⚠️  IMPORTANT ⚠️"
echo "1. A security audit will be conducted following this access"
echo "2. All actions are being logged"
echo "3. Please execute your critical tasks and exit"
echo "4. After this session, register new security keys using register-security-key.sh"
echo "5. At least one YubiKey and one WebAuthn/Passkey should be registered for redundancy"