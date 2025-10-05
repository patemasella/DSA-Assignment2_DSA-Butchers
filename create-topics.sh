#!/bin/bash

# Wait for Kafka to be ready
echo "Waiting for Kafka to be ready..."
sleep 30

# Create Kafka topics
echo "Creating Kafka topics..."

kafka-topics --bootstrap-server kafka:9092 --create --topic payment-events --partitions 3 --replication-factor 1
kafka-topics --bootstrap-server kafka:9092 --create --topic ticket-events --partitions 3 --replication-factor 1
kafka-topics --bootstrap-server kafka:9092 --create --topic trip-events --partitions 3 --replication-factor 1
kafka-topics --bootstrap-server kafka:9092 --create --topic vehicle-updates --partitions 3 --replication-factor 1
kafka-topics --bootstrap-server kafka:9092 --create --topic notifications --partitions 3 --replication-factor 1
kafka-topics --bootstrap-server kafka:9092 --create --topic admin-notifications --partitions 3 --replication-factor 1

echo "Kafka topics created successfully!"

# List topics to verify
echo "Listing all topics:"
kafka-topics --bootstrap-server kafka:9092 --list