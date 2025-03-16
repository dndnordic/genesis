# Origin Kubernetes Infrastructure

This directory contains the Kubernetes manifests for deploying Origin components across multiple clusters using a GitOps approach.

## Redundant Services

The following services are configured for redundancy across all three Origin clusters:

### Keycloak (Identity Provider)

- **Implementation**: Active-active deployment with shared database
- **Locations**: Frankfurt, Amsterdam, Paris
- **High Availability**:
  - Multiple replicas in each cluster
  - Shared database with PostgreSQL replication
  - Infinispan clustering for session replication
  - Auto-failover between instances
- **Usage**:
  - Central identity provider for all Origin components
  - SSO provider for Singularity applications
  - Authorization server for OAuth/OIDC

### PostgreSQL (Database)

- **Implementation**: Multi-master with synchronous replication using CloudNativePG operator
- **Locations**: Frankfurt, Amsterdam, Paris
- **High Availability**:
  - Primary in each cluster with auto-failover
  - Cross-cluster replication for redundancy
  - Automated backup and point-in-time recovery
- **Usage**:
  - Storage for Keycloak
  - Configuration storage for Origin components
  - Audit logging

### Vault (Secret Management)

- **Implementation**: HA mode with Integrated Storage (Raft)
- **Locations**: Frankfurt, Amsterdam, Paris
- **High Availability**:
  - 3+ nodes per cluster
  - Cross-cluster replication
  - Auto-unsealing and disaster recovery
- **Usage**:
  - Centralized API key storage
  - Dynamic secret generation
  - Encryption as a service
  - Secret access audit logging

## Deployment Model

Each component is deployed following these principles:

1. **Base Configuration**: Common configuration shared across all clusters
2. **Overlay Configuration**: Cluster-specific settings (hostnames, certificates, etc.)
3. **Cross-Cluster Communication**: Service mesh (Istio) for secure cross-cluster traffic
4. **GitOps-based Deployment**: ArgoCD for automated deployment from Git

## Deployment Instructions

```bash
# Deploy to all clusters
kubectl apply -k overlays/all

# Deploy to a specific cluster
kubectl apply -k overlays/alpha
kubectl apply -k overlays/beta
kubectl apply -k overlays/gamma
```