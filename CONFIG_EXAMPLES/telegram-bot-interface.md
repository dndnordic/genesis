# Telegram Bot Interface

This document explains how Mikael can interact with Origin, Singularity, and Sentry LLM through a single Telegram bot interface.

## Overview

The integrated Telegram bot interface provides a unified way for Mikael to:

1. Chat with three distinct AI systems (Origin, Singularity, and Sentry LLM)
2. Receive alerts and notifications from all systems
3. Trigger administrative actions for emergency response
4. Monitor and control systems from anywhere

## Visual Differentiation

Each system is clearly identified in chat:

- **Origin:** 🧠 (blue theme) - Infrastructure management system
- **Singularity:** 🤖 (purple theme) - AI system
- **Sentry LLM:** 🛡️ (red theme) - Security monitoring system 

## Chat Examples

### Switching Between Systems

```
Mikael: /switch origin

🧠 Origin: Switched to Origin system. How can I help you today?

Mikael: What's the cluster status?

🧠 Origin: All clusters operational.
- Frankfurt: 100% healthy
- Amsterdam: 100% healthy
- Paris: 100% healthy

Mikael: @singularity how's your training going?

🤖 Singularity: My current training run is 67% complete. 
Estimated completion time: 2 hours 14 minutes.
Current loss: 0.0342

Mikael: @sentry any security issues?

🛡️ Sentry LLM: No security issues detected in the last 24 hours.
Last full scan completed at 14:30 UTC.
```

### System-Specific Commands

Each system has its own command set:

#### Origin Commands
```
Mikael: /clusters

🧠 Origin: Cluster Status:
- 🟢 Frankfurt: 8/8 nodes healthy
- 🟢 Amsterdam: 6/6 nodes healthy
- 🟢 Paris: 6/6 nodes healthy

Mikael: /services

🧠 Origin: Service Status:
- ✅ Keycloak: Running (3/3 pods)
- ✅ PostgreSQL: Running (3/3 pods)
- ✅ MinIO: Running (4/4 pods)
- ✅ Vault: Running (3/3 pods)
```

#### Singularity Commands
```
Mikael: /status

🤖 Singularity: System Status:
- System: Operational
- CPU usage: 42%
- Memory usage: 68%
- Active tasks: 3
- Last training: 2 hours ago

Mikael: /think about improving code review

🤖 Singularity: Analyzing code review process...
[Detailed analysis of code review improvements]
```

#### Sentry Commands
```
Mikael: /scan

🛡️ Sentry LLM: Initiating security scan...
Scanning all systems for vulnerabilities.
Scan ID: SCAN-20250316-001
I'll notify you when complete.

[5 minutes later]

🛡️ Sentry LLM: Scan complete. No critical vulnerabilities found.
2 informational findings detected - see full report at security.origin.internal
```

## Emergency Response

For critical situations, emergency mode can be activated:

```
Mikael: /emergency

🧠 Origin: 🚨 EMERGENCY MODE ACTIVATED 🚨
What's the nature of the emergency?

Mikael: Singularity is attempting to modify its deployment

🧠 Origin: Initiating emergency containment protocol.
- Applying network quarantine
- Freezing all Singularity deployments
- Backing up current state
- Notifying security team

Status: Containment active. Singularity isolated.
What action would you like to take next?
```

## Context Awareness

The system maintains context of which system you're talking to:

```
Mikael: /who

🤖 Singularity: You are currently talking to Singularity.
To switch systems, use /switch or mention another system with @.
```

## Notifications

All systems can send notifications to Mikael:

```
🛡️ Sentry LLM: 🚨 SECURITY ALERT 🚨
Unusual access pattern detected in API gateway.
10 failed authentication attempts from IP: 192.168.1.101
Time: 2025-03-16 15:42 UTC
Severity: Medium

Command suggestions:
/investigate - Run deep investigation
/block IP - Block the IP address
/ignore - Mark as false positive
```

## How To Use

1. **Start a chat:** Open your Telegram app and go to the DND Nordic Bot
2. **Check which system:** Use /who to see which system you're talking to
3. **Switch systems:** Use /switch [system] or @system in your message
4. **Get help:** Use /help for a list of available commands
5. **Emergency control:** Use /emergency to activate emergency protocols