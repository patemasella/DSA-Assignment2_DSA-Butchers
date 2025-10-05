#!/bin/bash

echo "📊 Kafka Topics Monitoring"
echo "=========================="

# List all topics
echo "Topics:"
kafka-topics --bootstrap-server localhost:9092 --list

echo ""
echo "Topic Details:"
echo "--------------"

# Get details for each topic
for topic in $(kafka-topics --bootstrap-server localhost:9092 --list); do
    echo "Topic: $topic"
    kafka-topics --bootstrap-server localhost:9092 --describe --topic $topic
    echo ""
done

# Show consumer groups
echo "Consumer Groups:"
echo "----------------"
kafka-consumer-groups --bootstrap-server localhost:9092 --list

echo ""
echo "Messages in Topics:"
echo "-------------------"

# Count messages in each topic (approximate)
for topic in $(kafka-topics --bootstrap-server localhost:9092 --list); do
    count=$(kafka-run-class kafka.tools.GetOffsetShell --bootstrap-server localhost:9092 --topic $topic --time -1 | awk -F ":" '{sum += $3} END {print sum}')
    echo "$topic: $count messages"
done