# Genesis Administration Repository

This repository serves as the administration center for the DND Nordic projects, focused primarily on secret management, permissions, and infrastructure provisioning.

**Managed by:** dnd-genesis (203321379+dnd-genesis@users.noreply.github.com)

## Repository Purpose

Genesis is a privileged repository that only Mikael and authorized systems should have access to. It centrally manages secrets and credentials for all DND Nordic repositories:

- **Centralized API Key Management**: Securely store and distribute API keys
- **Repository Permission Control**: Manage GitHub repository access
- **Tailscale Network Management**: Control secure VPN networking
- **Infrastructure Provisioning**: Tools for deploying and managing infrastructure
- **Administrative Scripts**: Automation for routine administrative tasks

## Directory Structure

```
/
├── config/                 # Configuration files
│   ├── secrets.json        # Maps secrets to repositories
│   ├── permissions.json    # Repository permission settings
│   ├── tailscale.json      # Tailscale network configuration
│   └── users.json          # User accounts and permissions
│
├── keys/                   # Secret keys (not checked into git)
│   ├── .gitignore          # Ensures keys are never committed
│   ├── redundant-services/ # Secrets for redundant multi-cluster services
│   ├── github_token.txt    # GitHub access token
│   ├── tailscale_api_key.txt # Tailscale API key
│   └── ...                 # Other sensitive keys
│
├── scripts/                # Admin scripts
│   ├── sync-secrets.sh     # Syncs secrets to repositories
│   ├── update-permissions.sh # Updates GitHub repo permissions
│   ├── tailscale-auth.sh   # Manages Tailscale authentication
│   ├── manage-users.sh     # Manages user accounts and permissions
│   ├── update-redundant-secrets.sh # Updates multi-cluster service secrets
│   ├── verify-yubikey.sh   # Security key authentication
│   ├── register-security-key.sh # Register new YubiKey/WebAuthn
│   ├── emergency-recovery.sh # Recovery if all security keys are lost
│   └── ...                 # Other administrative scripts
│
├── CONFIG_EXAMPLES/        # Example configurations (non-sensitive)
│   ├── argocd-applicationset.yaml  # GitOps configuration
│   ├── istio-mtls.yaml     # Service mesh mTLS setup
│   ├── flagger-canary.yaml # Canary deployment definitions
│   └── opa-policies/       # OPA policy examples
│
└── .github/                # GitHub workflows
    └── workflows/          # CI/CD workflows
        └── creator.yml     # Admin workflow
```

## Secret Categories

### API Keys and Service Credentials
Standard API keys for various services, stored in `keys/`

### Redundant Services Secrets
Credentials for redundant services deployed across multiple clusters:
- **Keycloak**: Identity provider credentials
- **PostgreSQL**: Database credentials and replication tokens
- **Vault**: Secret management system credentials

## Administrative Tasks

The following tasks can be performed using Genesis:

### Secrets Management

Syncs secrets from the `config/secrets.json` file to the Origin and Singularity repositories:

```bash
# Synchronize all secrets to repositories
./scripts/sync-secrets.sh

# Update redundant services secrets with secure values
./scripts/update-redundant-secrets.sh

# Rotate a specific API key
./scripts/rotate-api-key.sh
```

### Authentication & Security

```bash
# Authenticate with YubiKey or WebAuthn/Passkey
./scripts/verify-yubikey.sh

# Register new security key
./scripts/register-security-key.sh yubikey  # For YubiKey (no prior auth needed)
./scripts/register-security-key.sh          # For any security key (requires auth)

# Emergency recovery (if all security keys are lost)
./scripts/emergency-recovery.sh
```

### Permission Management

Updates GitHub repository permissions based on the `config/permissions.json` file:

```bash
./scripts/update-permissions.sh
```

### Tailscale Network Management

Manages Tailscale VPN authentication and device configuration:

```bash
./scripts/tailscale-auth.sh
```

## GitHub Actions Workflow

The repository includes a GitHub workflow that can perform administrative tasks:

- **Workflow File**: `.github/workflows/creator.yml`
- **Trigger**: Manual workflow dispatch with task selection
- **Environment**: Requires the `admin-control` environment approval

## Security Notes

This repository contains sensitive information and should be treated with the highest level of security:

1. **Never commit sensitive keys** to the repository
2. **Store secrets in the `keys/` directory** (which is gitignored)
3. **Only authorized users** should have access to this repository
4. **All actions are logged** in the audit trail
5. **Use YubiKey or WebAuthn authentication** before accessing sensitive operations
6. **Regularly rotate all credentials** (90-day maximum lifetime)
7. **Use GitHub environment protection** for administrative workflows

### Implementation Guidance

Genesis provides example configurations and non-sensitive values in the `CONFIG_EXAMPLES/` directory. The actual implementation of redundant services should be done in the Origin repository, with secrets injected via the secret synchronization mechanism.

### Long-term Secret Management Strategy

Genesis currently manages all secrets, but the long-term plan is:

1. **Bootstrap Vault** using Genesis-managed credentials
2. **Migrate most secrets to Vault** once it's operational across all clusters
3. **Use Vault's dynamic secret generation** for database access
4. **Keep only bootstrap credentials** in Genesis for disaster recovery
5. **Implement Vault audit logging** for comprehensive access tracking

## Managed Repositories

Genesis manages the following repositories:

- **Origin**: `dndnordic/origin` (dnd-origin, 203493622+dnd-origin@users.noreply.github.com) - Governance system
- **Singularity**: `dndnordic/singularity` (dnd-singularity, 203457483+dnd-singularity@users.noreply.github.com) - AI Engine

## Authorized Accounts

- **dnd-genesis**: 203321379+dnd-genesis@users.noreply.github.com
- **dnd-origin**: 203493622+dnd-origin@users.noreply.github.com
- **dnd-singularity**: 203457483+dnd-singularity@users.noreply.github.com