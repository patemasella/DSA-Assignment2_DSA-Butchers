#!/bin/bash
set -e

topics=(
  "passenger-events"
  "passengers.registered"
  "payment-events"
  "payments.requested"
  "payments.confirmed"
  "ticket-events"
  "tickets.created"
  "tickets.validated"
  "trip-events"
  "trips.updated"
  "notification-events"
  "notifications.sent"
)

for t in "${topics[@]}"; do
  kafka-topics --bootstrap-server kafka:9092 --create --if-not-exists --topic "$t" --partitions 3 --replication-factor 1
done

echo "All topics created successfully!"
