import ballerinax/kafka;
import ballerina/log;
import ballerina/lang.'value;

configurable string kafkaBootstrapServers = "localhost:9092";
configurable string notificationTopic = "notifications";

// Kafka consumer for notification events
public isolated client class NotificationConsumer {
    private final kafka:Consumer kafkaConsumer;
    private final NotificationDBClient notificationDB;

    public function init(NotificationDBClient notificationDB) returns error? {
        kafka:ConsumerConfiguration consumerConfig = {
            groupId: "notification-service",
            offsetReset: "earliest",
            topics: [notificationTopic],
            pollingInterval: 1000
        };
        
        self.kafkaConsumer = check new (kafkaBootstrapServers, consumerConfig);
        self.notificationDB = notificationDB;
        
        log:printInfo("Kafka consumer initialized for topic: " + notificationTopic);
    }

    public function startConsuming() returns error? {
        while true {
            var result = self.kafkaConsumer->poll(1000);
            if result is kafka:Error[] {
                log:printError("Error polling Kafka", error = result[0]);
            } else if result is kafka:ConsumerRecord[] {
                foreach var record in result {
                    _ = check self.processNotification(record);
                }
                _ = check self.kafkaConsumer->commit();
            }
        }
    }

    private function processNotification(kafka:ConsumerRecord record) returns error? {
        string message = check string:fromBytes(record.value);
        log:printInfo("Received Kafka message: " + message);
        
        // Parse the message as JSON
        json parsedMessage = check value:fromJsonString(message);
        
        match parsedMessage {
            record {string eventType; string userId; string title; string message; string notificationType; anydata metadata;} => {
                if eventType == "USER_NOTIFICATION") {
                    var notificationId = self.notificationDB->createNotification({
                        userId: userId,
                        title: title,
                        message: message,
                        notificationType: notificationType,
                        metadata: metadata
                    });
                    
                    if notificationId is string {
                        log:printInfo("Created notification: " + notificationId + " for user: " + userId);
                    }
                }
            }
            _ => {
                log:printWarn("Unknown event type in Kafka message");
            }
        }
    }

    public function close() returns error? {
        return self.kafkaConsumer->close();
    }
}