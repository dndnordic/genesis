# Emergency Recovery Procedures for Singularity

This document outlines the automated and manual procedures for recovering from situations where Singularity has damaged itself or entered an unstable state.

## Automated Detection and Recovery

The Origin system continuously monitors Singularity's health and automatically initiates recovery procedures when certain conditions are detected:

### Detection Mechanisms

1. **Pod Health Monitoring**:
   - CrashLoopBackOff detection
   - Memory/CPU threshold violations
   - Zero-ready pods for critical components

2. **Behavioral Anomaly Detection**:
   - Self-modification of deployments
   - Unusual API request patterns
   - Resource consumption spikes

3. **API Gateway Circuit Breakers**:
   - Request failure rate exceeding thresholds
   - Latency increases beyond baseline
   - Unexpected response patterns

### Automatic Recovery Actions

| Condition | Action | Notification |
|-----------|--------|--------------|
| Pod CrashLoopBackOff | Rollback deployment | Critical Alert |
| Memory Leak | Restart affected pods | Warning |
| CPU Spike | Apply throttling | Warning |
| Deployment Failure | Rollback to last known good | Critical Alert |
| Zero Ready Pods | Emergency restore | Critical Alert |
| Self-Modification | Freeze and restore | Critical Alert + Human Notification |

## Manual Recovery Procedures

If automatic recovery fails, these manual procedures can be initiated:

### Level 1 Recovery: Rollback to Last Known Good State

```bash
# Identify the deployment
kubectl get deployments -n singularity-system

# Rollback to previous version
kubectl rollout undo deployment/singularity-core -n singularity-system

# Verify recovery
kubectl rollout status deployment/singularity-core -n singularity-system
```

### Level 2 Recovery: Restore from Known Good Tag

```bash
# Scale down current deployment
kubectl scale deployment singularity-core -n singularity-system --replicas=0

# Update to known good image tag
kubectl set image deployment/singularity-core -n singularity-system \
  singularity-core=dndnordic/singularity:v1.0.0-stable

# Scale back up
kubectl scale deployment singularity-core -n singularity-system --replicas=2
```

### Level 3 Recovery: Network Quarantine and Complete Rebuild

```bash
# Apply emergency network policy
kubectl apply -f /home/sing/genesis/CONFIG_EXAMPLES/emergency-recovery.yaml

# Scale down all Singularity components
kubectl scale deployment --all -n singularity-system --replicas=0

# Redeploy from scratch using known good manifests
kubectl apply -k /path/to/known-good-manifests
```

## Recovery Verification

After any recovery action, verify:

1. All pods are in Running state with Ready status
2. Core API endpoints respond correctly
3. No unusual activity in logs
4. Resource usage has normalized

## Root Cause Analysis

Following any recovery event:

1. Preserve logs and state information
2. Conduct post-mortem analysis
3. Update known-good state registry
4. Implement preventative measures

## Emergency Contacts

For critical failures requiring human intervention:

- Primary: Mikael (mikael@dndnordic.se)
- Secondary: Infrastructure Team (infrastructure-team@dndnordic.se)
- Emergency Hotline: +46-XXX-XXXX

## Post-Recovery Actions

1. Update the known-good-states registry with verified stable versions
2. Apply additional runtime constraints if necessary
3. Schedule thorough security review
4. Document incident and recovery process

## Rollback Decision Criteria

| Metric | Warning Threshold | Critical Threshold |
|--------|-------------------|-------------------|
| CPU Usage | >85% for 5 min | >95% for 2 min |
| Memory Usage | >80% for 5 min | >90% for 2 min |
| Pod Restarts | >3 in 10 min | >5 in 5 min |
| Request Latency | >1s for 5 min | >2s for 2 min |
| Error Rate | >2% for 5 min | >5% for 1 min |