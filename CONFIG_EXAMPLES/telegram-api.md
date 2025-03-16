# Telegram API Integration for Origin

This document describes how Origin communicates with Mikael via Telegram for emergency alerts and recovery operations.

## Notification API

The Telegram bot exposes a REST API for other Origin components to send notifications:

```
POST http://telegram-notification-bot:8080/api/notify
```

Request body:
```json
{
  "level": "critical",
  "component": "singularity",
  "template": "self_harm",
  "params": {
    "action": "emergency_restore",
    "details": "Attempted to modify deployment manifest",
    "timestamp": "2025-03-16T14:30:00Z",
    "status": "Quarantined"
  },
  "recipients": ["mikael", "infrastructure"],
  "alert_id": "SING-2025-03-16-001"
}
```

Response:
```json
{
  "success": true,
  "message_id": 12345,
  "recipients_notified": ["mikael"],
  "alert_id": "SING-2025-03-16-001"
}
```

## Interactive Commands

Mikael can interact with the system via Telegram commands:

| Command | Description | Example Response |
|---------|-------------|------------------|
| `/status` | Get current system status | "✅ All systems operational" |
| `/ack SING-2025-03-16-001` | Acknowledge alert | "Alert SING-2025-03-16-001 acknowledged" |
| `/resolve SING-2025-03-16-001` | Mark alert as resolved | "Alert SING-2025-03-16-001 resolved" |
| `/rollback singularity v1.0.0` | Rollback Singularity | "Initiating rollback to v1.0.0..." |
| `/quarantine singularity` | Network quarantine | "Applying network quarantine..." |
| `/silence 30m` | Silence notifications | "Notifications silenced for 30 minutes" |
| `/help` | Show available commands | [List of commands] |

## Recovery Operations API

For recovery operations, Mikael can trigger actions via Telegram that call the recovery API:

```
POST http://recovery-service:8080/api/recovery/execute
```

Request (triggered by Telegram command):
```json
{
  "action": "rollback",
  "target": "singularity",
  "version": "v1.0.0",
  "authorized_by": "mikael",
  "auth_token": "signed_jwt_token"
}
```

Response (sent to Telegram):
```json
{
  "status": "initiated",
  "operation_id": "OP-123456",
  "estimated_completion": "2025-03-16T14:35:00Z",
  "status_updates": "Will be sent to this chat"
}
```

## Escalation Process

1. Alert triggered by monitoring system
2. Notification sent to appropriate recipients based on severity
3. If no acknowledgment within 15 minutes, escalate to next level
4. For emergency alerts, notification repeats every 5 minutes until acknowledged

Example escalation flow:
```
14:30 - Warning alert sent to infrastructure team
14:45 - No acknowledgment, escalate to Mikael
14:50 - Mikael acknowledges with `/ack ALERT-ID`
15:00 - Mikael resolves with `/resolve ALERT-ID`
```

## Setting Up the Bot

To set up the notification system in a new environment:

1. Create a new Telegram bot using BotFather
2. Get the bot token and save it as a Kubernetes secret
3. Start a chat with the bot and get the chat ID
4. Update the `telegram-secrets` with these values
5. Deploy the notification system using the provided YAML

## Interactive Recovery Session

In critical situations, Mikael can initiate an interactive recovery session:

```
/recovery-session singularity
```

This puts the bot in an interactive mode where each message is treated as a command for the recovery system, allowing a conversational approach to diagnose and fix issues.

## Security Considerations

1. All interactive commands require authentication
2. Sensitive operations require explicit confirmation
3. All actions are logged and audit-trailed
4. Network access for the bot is strictly controlled
5. Communication is encrypted with Telegram's standard encryption