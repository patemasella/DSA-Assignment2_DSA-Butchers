# Kafka Setup & Topics for Smart Ticketing System

### Broker Address:
- Internal: `kafka:9092`
- External (for local testing): `localhost:9092`

### Topics:
| Topic | Description | Producer | Consumer |
|-------|--------------|-----------|-----------|
| payments.requested | Payment initiated | Ticketing Service | Payment Service |
| payments.confirmed | Payment success | Payment Service | Ticketing Service |
| tickets.created | Ticket issued | Ticketing Service | Notification, Admin |
| tickets.validated | Ticket used | Validation Service | Notification, Admin |
| trips.updated | Schedule updates | Transport Service | Notification, Passenger |
| notifications.sent | Notification sent | Notification Service | — |

### Example Kafka Message
```json
{
  "eventId": "uuid",
  "timestamp": "2025-10-04T10:00:00Z",
  "eventType": "tickets.created",
  "source": "ticketing-service",
  "payload": {
    "ticketId": "T123",
    "userId": "U45",
    "tripId": "TRIP56",
    "status": "CREATED"
  }
}








