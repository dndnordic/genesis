# Implementation Notes for Genesis Architecture

## Internal Certificate Authority (CA)

We have implemented an internal Certificate Authority (CA) for all services across our three Kubernetes clusters (Frankfurt, Amsterdam, Paris). This approach provides several advantages:

1. **Independence from public internet connectivity**: Services don't need to validate with Let's Encrypt servers
2. **Control over certificate lifecycle**: We manage the entire certificate lifecycle internally
3. **Support for internal service names**: We can issue certificates for internal DNS names that aren't publicly resolvable
4. **Simplified certificate management**: Single issuer for all certificates

### Implementation Details

1. **Certificate Generation**:
   - CA key pair generated using 4096-bit RSA key
   - 10-year expiration period to minimize maintenance
   - Full certificate chain stored in Genesis

2. **Kubernetes Integration**:
   - CA certificate and private key stored in a cert-manager secret
   - ClusterIssuer created to allow certificate issuance
   - ConfigMap exposes the CA certificate for trust store installation

3. **Trust Store Integration**:
   - DaemonSet automatically installs CA certificate on all nodes
   - Certificates installed in `/usr/local/share/ca-certificates/`
   - `update-ca-certificates` runs on all nodes to update trust stores

4. **Certificate Issuance**:
   - `Certificate` resources reference the internal CA ClusterIssuer
   - Service pods mount certificates from standard cert-manager secrets
   - Automatic renewal handled by cert-manager

5. **Rotation Procedure**:
   - CA certificate renewal handled through Genesis
   - `update-redundant-secrets.sh` script provides CA renewal capability
   - After renewal, sync-secrets.sh distributes the new CA to all clusters
   - Trust store updates happen automatically via DaemonSet

### Security Considerations

1. **CA Private Key Protection**:
   - CA private key accessible only in Genesis
   - Requires YubiKey/WebAuthn authentication for access
   - Never exposed to application services

2. **Certificate Visibility**:
   - Public CA certificate distributed to all nodes
   - Private keys only available to their respective services

3. **Expiration Monitoring**:
   - Prometheus alerts for certificates nearing expiration
   - Central expiration tracking through Genesis

### Usage Examples

**Issuing a Certificate for a Service**:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: keycloak-tls
  namespace: origin-system
spec:
  secretName: keycloak-tls-secret
  duration: 2160h  # 90 days
  renewBefore: 360h  # 15 days
  subject:
    organizations:
      - DND Nordic
  commonName: keycloak.origin-system.svc.cluster.local
  dnsNames:
  - keycloak.origin-system.svc.cluster.local
  - keycloak.origin-system.svc
  - keycloak
  issuerRef:
    name: internal-ca
    kind: ClusterIssuer
```

**Service using the Certificate**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: origin-system
spec:
  template:
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:latest
        volumeMounts:
        - name: tls
          mountPath: /opt/keycloak/conf/tls
      volumes:
      - name: tls
        secret:
          secretName: keycloak-tls-secret
```

### Integration with Service Mesh

Our internal CA also integrates with Istio service mesh for mTLS:

1. **Istio Integration**:
   - CA certificate provided to Istio for workload certificate validation
   - Istio uses CA to validate service identities

2. **mTLS Configuration**:
   - All service-to-service communication secured with mTLS
   - Mutual authentication using certificates issued by our CA

## Critical Infrastructure Components

### GitOps Implementation
- Deploy ArgoCD to each cluster
- Setup ApplicationSets for Origin and Singularity workloads
- Create Git repository structure:
  ```
  /clusters/
    /alpha/  # Frankfurt
      /origin-system/
      /singularity-system/
    /beta/   # Amsterdam
      /origin-system/
      /singularity-system/
    /gamma/  # Paris
      /origin-system/
      /singularity-system/
  ```
- Configure progressive delivery across clusters
- Implement environment promotion workflows

### Service Mesh (Istio)
- Deploy Istio control plane to each cluster
- Configure multicluster federation
- Setup east-west gateways for cross-cluster communication
- Enable mTLS by default in all namespaces
- Deploy monitoring stack (Kiali, Jaeger, Prometheus)
- Create service entries for external services
- Implement authorization policies for service-to-service access

### Policy as Code (OPA/Gatekeeper)
- Deploy OPA Gatekeeper to all clusters
- Create ConstraintTemplates for common policy patterns
- Implement policies for:
  - Pod Security Standards (restricted profile)
  - Network Policy validation
  - Resource limits enforcement
  - Image source verification
  - Secret usage validation
- Setup CI integration for policy validation
- Configure validation webhooks

### Canary Deployments (Flagger)
- Deploy Flagger controller to each cluster
- Configure metric providers (Prometheus)
- Setup canary resources for critical services
- Define promotion criteria:
  - Error rate thresholds
  - Latency requirements
  - Throughput expectations
- Implement alerting for failed promotions

## Security Considerations

### Secret Management
- YubiKey is the master security control
- All API keys stored only in Genesis repository
- API key distribution follows strict need-to-know access
- Implement automatic key rotation
- Audit all secret access

### Network Security
- Isolate clusters with dedicated firewalls
- Headscale VPN for secure cluster communication
- Service Mesh mTLS for all service traffic
- Strict network policies between namespaces
- Egress filtering for all outbound traffic

### Resource Protection
- Origin has absolute resource priority
- Configure preemption for Singularity workloads
- Implement strict resource quotas
- Set appropriate QoS classes per workload

## Todo List

### Phase 1: Initial Setup
- [ ] Deploy ArgoCD to all clusters
- [ ] Setup initial Git repository structure
- [ ] Deploy Istio control planes
- [ ] Configure basic network policies

### Phase 2: Enhanced Security
- [ ] Deploy OPA Gatekeeper
- [ ] Implement policy library
- [ ] Configure mTLS across all services
- [ ] Setup cross-cluster service mesh

### Phase 3: Advanced Deployments
- [ ] Deploy Flagger controllers
- [ ] Setup canary CustomResources
- [ ] Implement promotion criteria
- [ ] Test progressive delivery

### Phase 4: Monitoring & Observability
- [ ] Deploy monitoring stack
- [ ] Configure alerting
- [ ] Setup distributed tracing
- [ ] Implement cost monitoring