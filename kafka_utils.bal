import ballerinax/kafka;
import ballerina/log;
import ballerina/lang.'value;

// Kafka configuration type
public type KafkaConfig record {|
    string bootstrapServers;
    string groupId?;
|};

// Common event types
public type BaseEvent record {|
    string eventType;
    string timestamp;
    string sourceService;
|};

// Kafka producer client
public isolated client class KafkaProducerClient {
    private final kafka:Producer producer;
    private final string serviceName;

    public function init(string bootstrapServers, string serviceName) returns error? {
        self.producer = check new (bootstrapServers);
        self.serviceName = serviceName;
        log:printInfo("Kafka producer initialized for service: " + serviceName);
    }

    public function sendEvent(string topic, anydata event) returns error? {
        string eventJson = check value:toJson(event).toJsonString();
        
        kafka:ProducerError? result = self.producer->send({
            topic: topic,
            value: eventJson.toBytes(),
            key: self.generateKey(event).toBytes()
        });
        
        if result is kafka:ProducerError {
            log:printError("Failed to send Kafka event to topic: " + topic, error = result);
            return error("Kafka send failed: " + result.message());
        }
        
        log:printInfo("Event sent to Kafka topic: " + topic + " | Type: " + event.eventType.toString());
    }

    private function generateKey(anydata event) returns string {
        // Generate a key based on event type for partitioning
        match event {
            record {string tripId; string eventType;} => {
                return event.tripId + "_" + event.eventType;
            }
            record {string ticketId; string eventType;} => {
                return event.ticketId + "_" + event.eventType;
            }
            record {string paymentId; string eventType;} => {
                return event.paymentId + "_" + event.eventType;
            }
            record {string userId; string eventType;} => {
                return event.userId + "_" + event.eventType;
            }
            _ => {
                return self.serviceName + "_" + time:utcNow().toString();
            }
        }
    }

    public function close() returns error? {
        return self.producer->close();
    }
}

// Kafka consumer client
public isolated client class KafkaConsumerClient {
    private final kafka:Consumer consumer;
    private final string serviceName;

    public function init(KafkaConfig config, string[] topics, string serviceName) returns error? {
        kafka:ConsumerConfiguration consumerConfig = {
            groupId: config.groupId ?: serviceName + "-group",
            offsetReset: "earliest",
            topics: topics,
            pollingInterval: 1000,
            autoCommit: false
        };
        
        self.consumer = check new (config.bootstrapServers, consumerConfig);
        self.serviceName = serviceName;
        log:printInfo("Kafka consumer initialized for service: " + serviceName + " | Topics: " + topics.toString());
    }

    public function poll(int timeout = 1000) returns kafka:ConsumerRecord[]|kafka:Error[] {
        return self.consumer->poll(timeout);
    }

    public function commit() returns error? {
        return self.consumer->commit();
    }

    public function parseEvent(kafka:ConsumerRecord record) returns json|error {
        string message = check string:fromBytes(record.value);
        return value:fromJsonString(message);
    }

    public function close() returns error? {
        return self.consumer->close();
    }
}