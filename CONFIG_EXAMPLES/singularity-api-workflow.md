# Singularity Code Review and Deployment API Workflow

This document describes how Singularity code is reviewed, approved, and deployed through the Origin governance system.

## Code Review and Approval Flow

```
┌─────────────┐      ┌───────────────┐      ┌────────────────┐      ┌──────────────┐
│ Singularity │      │GitHub Webhooks │      │Origin          │      │Origin        │
│ Repository  │──1──▶│ Service        │──2──▶│Governance      │──3──▶│Deployment    │
└─────────────┘      └───────────────┘      │Service         │      │System        │
       ▲                                     └────────────────┘      └──────────────┘
       │                                            │                       │
       │                                            │                       │
       └────────────────────6───────────────────────┴───────────5──────────┘
```

## Step-by-Step Process

### 1. Pull Request Creation

When Singularity creates a PR:

```
POST https://github.com/dndnordic/singularity/pulls
```

GitHub sends a webhook to Origin's webhook service:

```
POST https://webhook.origin.internal/api/v1/webhook
{
  "action": "opened",
  "pull_request": {
    "number": 123,
    "title": "Add new feature",
    "body": "This PR adds a new feature",
    ...
  }
}
```

### 2. Governance Service Review

The Origin governance service initiates the review process:

```
POST http://governance-service:8080/api/v1/review
{
  "repository": "dndnordic/singularity",
  "pr_number": 123,
  "commit_sha": "abc123",
  "request_type": "initiate_review"
}
```

The governance service creates GitHub status checks:

```
POST https://api.github.com/repos/dndnordic/singularity/statuses/abc123
{
  "state": "pending",
  "description": "Origin governance review in progress",
  "context": "origin/governance-check"
}
```

### 3. Automated Checks

The governance service triggers and monitors automated checks:

- Static code analysis
- Security scans
- Unit tests
- Policy compliance checks

### 4. API for Singularity to Request Status

Singularity can query the status of its PR:

```
GET http://governance-service:8080/api/v1/status?repository=dndnordic/singularity&pr=123
```

Response:
```json
{
  "repository": "dndnordic/singularity",
  "pr_number": 123,
  "status": "in_progress",
  "checks": [
    {
      "name": "static-analysis",
      "status": "success",
      "details_url": "https://checks.origin.internal/static/123"
    },
    {
      "name": "security-scan",
      "status": "pending",
      "details_url": "https://checks.origin.internal/security/123"
    },
    {
      "name": "unit-tests",
      "status": "pending",
      "details_url": "https://checks.origin.internal/tests/123"
    }
  ],
  "required_actions": [],
  "last_updated": "2025-03-16T12:34:56Z"
}
```

### 5. Origin Approval and Deployment

When all checks pass and Origin approves:

```
PATCH http://governance-service:8080/api/v1/review
{
  "repository": "dndnordic/singularity",
  "pr_number": 123,
  "status": "approved",
  "approval_key": "signed_approval_token"
}
```

The governance service updates the status on GitHub:

```
POST https://api.github.com/repos/dndnordic/singularity/statuses/abc123
{
  "state": "success",
  "description": "Origin governance approved",
  "context": "origin/governance-check"
}
```

When the PR is merged, the deployment system is triggered:

```
POST http://deployment-service:8080/api/v1/deploy
{
  "repository": "dndnordic/singularity",
  "branch": "main",
  "commit_sha": "abc123",
  "environments": ["dev", "stage", "regression", "production"],
  "approval_token": "signed_approval_token"
}
```

### 6. API for Deployment Status

Singularity can check deployment status:

```
GET http://deployment-service:8080/api/v1/deploy/status?repository=dndnordic/singularity&commit=abc123
```

Response:
```json
{
  "repository": "dndnordic/singularity",
  "commit_sha": "abc123",
  "status": "in_progress",
  "environments": [
    {
      "name": "dev",
      "status": "success",
      "url": "https://singularity-dev.origin.internal",
      "deployed_at": "2025-03-16T13:30:00Z"
    },
    {
      "name": "stage",
      "status": "in_progress",
      "url": "https://singularity-stage.origin.internal"
    },
    {
      "name": "regression",
      "status": "pending"
    },
    {
      "name": "production",
      "status": "pending"
    }
  ]
}
```

## Authentication

For all API calls, Singularity must provide:

1. Service account token in the `Authorization` header
2. Proper mTLS client certificate for service identity

Example:
```
Authorization: Bearer ${SINGULARITY_SERVICE_TOKEN}
X-API-Key: ${GOVERNANCE_API_TOKEN}
```

## Error Handling

All failed approvals include detailed reasons:

```json
{
  "status": "rejected",
  "reason": "security_policy_violation",
  "details": [
    {
      "type": "vulnerability",
      "severity": "high",
      "file": "src/dependencies.py",
      "description": "Using vulnerable package version"
    }
  ],
  "remediation_steps": [
    "Update package X to version Y or later",
    "Run security scan again"
  ]
}
```

## Deployment Stages

1. **Dev**: Automatic after approval
2. **Stage**: Automatic after dev success
3. **Regression**: Automatic after stage success & regression tests pass
4. **Production**: Requires explicit manual approval

## Rollback Process

If issues are detected, Singularity can request rollback:

```
POST http://deployment-service:8080/api/v1/rollback
{
  "repository": "dndnordic/singularity",
  "environment": "production",
  "target_commit": "previous_stable_commit_sha"
}
```