import ballerina/http;
import ballerinax/postgresql;
import ballerina/log;
import ballerinax/kafka;
import ballerina/lang.'value;

configurable int notificationServicePort = 8082;

configurable string dbHost = "localhost";
configurable int dbPort = 5432;
configurable string dbUsername = "transport_user";
configurable string dbPassword = "transport_password";
configurable string dbName = "transport_system";

configurable string kafkaBootstrapServers = "localhost:9092";

listener http:Listener notificationListener = new(notificationServicePort);

// Simple authentication validation
public isolated function validateAuth(string authHeader) returns string|error {
    if !authHeader.startsWith("Bearer ") {
        return error("Invalid authentication");
    }
    // Extract user ID from token (simplified)
    return authHeader.replace("Bearer ", "");
}

service /notification on notificationListener {
    private final NotificationDBClient notificationDB;
    private final kafka:Producer kafkaProducer;
    private final kafka:Consumer kafkaConsumer;

    function init() returns error? {
        postgresql:Client dbClient = check new (
            host = dbHost,
            user = dbUsername,
            password = dbPassword,
            database = dbName,
            port = dbPort
        );
        self.notificationDB = new (dbClient);
        self.kafkaProducer = check new (kafkaBootstrapServers);
        
        // Initialize Kafka consumer for notification events
        kafka:ConsumerConfiguration consumerConfig = {
            groupId: "notification-service",
            offsetReset: "earliest",
            topics: ["notifications", "admin-notifications", "payment-events", "trip-events", "ticket-events"],
            pollingInterval: 1000
        };
        self.kafkaConsumer = check new (kafkaBootstrapServers, consumerConfig);
        
        // Start background Kafka listener
        start self.notificationEventListener();
        
        log:printInfo("Notification Service with Kafka started on port " + notificationServicePort.toString());
    }

    // ===== BACKGROUND KAFKA LISTENER =====
    isolated function notificationEventListener() returns error? {
        log:printInfo("Starting Kafka event listener for Notification Service");
        
        while true {
            var result = self.kafkaConsumer->poll(1000);
            if result is kafka:ConsumerRecord[] {
                foreach var record in result {
                    _ = check self.processNotificationEvent(record);
                }
                _ = check self.kafkaConsumer->commit();
            }
        }
    }

    private function processNotificationEvent(kafka:ConsumerRecord record) returns error? {
        string message = check string:fromBytes(record.value);
        json event = check value:fromJsonString(message);
        
        string eventType = event.eventType.toString();
        
        match eventType {
            "PAYMENT_SUCCESS" => {
                await self.handlePaymentSuccess(event);
            }
            "PAYMENT_FAILED" => {
                await self.handlePaymentFailure(event);
            }
            "TICKET_PURCHASE_SUCCESS" => {
                await self.handleTicketPurchaseSuccess(event);
            }
            "TRIP_UPDATE_NOTIFICATION" => {
                await self.handleTripUpdate(event);
            }
            "USER_REGISTERED" => {
                await self.handleUserRegistered(event);
            }
            "SYSTEM_NOTIFICATION_CREATED" => {
                await self.handleSystemNotification(event);
            }
            _ => {
                log:printDebug("Unknown event type: " + eventType);
            }
        }
    }

    private function handlePaymentSuccess(json event) returns error? {
        log:printInfo("Processing payment success notification for user: " + event.userId.toString());
        
        string|error notificationId = self.notificationDB->createNotification({
            userId: event.userId.toString(),
            title: event.title.toString(),
            message: event.message.toString(),
            notificationType: event.notificationType.toString(),
            metadata: {
                "paymentId": event.paymentId.toString(),
                "amount": event.amount.toString(),
                "sourceService": event.sourceService.toString()
            }
        });
        
        if notificationId is error {
            log:printError("Failed to create payment success notification", error = notificationId);
        } else {
            log:printInfo("Created payment success notification: " + notificationId);
        }
    }

    private function handlePaymentFailure(json event) returns error? {
        log:printInfo("Processing payment failure notification for user: " + event.userId.toString());
        
        string|error notificationId = self.notificationDB->createNotification({
            userId: event.userId.toString(),
            title: event.title.toString(),
            message: event.message.toString(),
            notificationType: event.notificationType.toString(),
            metadata: {
                "paymentId": event.paymentId.toString(),
                "sourceService": event.sourceService.toString()
            }
        });
        
        if notificationId is error {
            log:printError("Failed to create payment failure notification", error = notificationId);
        } else {
            log:printInfo("Created payment failure notification: " + notificationId);
        }
    }

    private function handleTicketPurchaseSuccess(json event) returns error? {
        log:printInfo("Processing ticket purchase success notification for user: " + event.userId.toString());
        
        string|error notificationId = self.notificationDB->createNotification({
            userId: event.userId.toString(),
            title: event.title.toString(),
            message: event.message.toString(),
            notificationType: event.notificationType.toString(),
            metadata: {
                "ticketId": event.ticketId.toString(),
                "sourceService": event.sourceService.toString()
            }
        });
        
        if notificationId is error {
            log:printError("Failed to create ticket purchase notification", error = notificationId);
        } else {
            log:printInfo("Created ticket purchase notification: " + notificationId);
        }
    }

    private function handleTripUpdate(json event) returns error? {
        log:printInfo("Processing trip update notification for user: " + event.userId.toString());
        
        string|error notificationId = self.notificationDB->createNotification({
            userId: event.userId.toString(),
            title: event.title.toString(),
            message: event.message.toString(),
            notificationType: event.notificationType.toString(),
            metadata: {
                "tripId": event.tripId.toString(),
                "ticketId": event.ticketId?.toString(),
                "sourceService": event.sourceService.toString()
            }
        });
        
        if notificationId is error {
            log:printError("Failed to create trip update notification", error = notificationId);
        } else {
            log:printInfo("Created trip update notification: " + notificationId);
        }
    }

    private function handleUserRegistered(json event) returns error? {
        log:printInfo("Processing user registration notification for: " + event.userId.toString());
        
        string|error notificationId = self.notificationDB->createNotification({
            userId: event.userId.toString(),
            title: "Welcome to Transport System!",
            message: "Thank you for registering with our transport service. We're excited to have you on board!",
            notificationType: "welcome",
            metadata: {
                "email": event.email.toString(),
                "firstName": event.firstName.toString(),
                "role": event.role?.toString(),
                "sourceService": event.sourceService.toString()
            }
        });
        
        if notificationId is error {
            log:printError("Failed to create welcome notification", error = notificationId);
        } else {
            log:printInfo("Created welcome notification: " + notificationId);
        }
    }

    private function handleSystemNotification(json event) returns error? {
        log:printInfo("Processing system notification: " + event.title.toString());
        
        // Get all active users to send system notification
        var users = self.notificationDB->getAllActiveUsers();
        if users is string[] {
            foreach string userId in users {
                string|error notificationId = self.notificationDB->createNotification({
                    userId: userId,
                    title: event.title.toString(),
                    message: event.message.toString(),
                    notificationType: event.notificationType.toString(),
                    metadata: {
                        "sourceService": event.sourceService.toString(),
                        "notificationType": "system"
                    }
                });
                
                if notificationId is error {
                    log:printError("Failed to create system notification for user: " + userId, error = notificationId);
                }
            }
            log:printInfo("Created system notifications for " + users.length().toString() + " users");
        }
    }

    // ===== HEALTH CHECK =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/health"
    }
    resource function get health() returns string {
        return "Notification Service is healthy!";
    }

    // ===== NOTIFICATION MANAGEMENT =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/notifications"
    }
    resource function post notifications(@http:Header {name: "Authorization"} string authHeader,
                                        NotificationRequest request) returns SuccessResponse|http:Unauthorized|http:BadRequest|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        log:printInfo("Creating notification for user: " + request.userId);
        
        string|error notificationId = self.notificationDB->createNotification(request);
        if notificationId is error {
            log:printError("Failed to create notification", error = notificationId);
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send Kafka event for notification creation
        _ = self.sendKafkaEvent("notification-events", {
            "eventType": "NOTIFICATION_CREATED",
            "notificationId": notificationId,
            "userId": request.userId,
            "title": request.title,
            "notificationType": request.notificationType,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "notification-service"
        });
        
        return {
            message: "Notification created successfully",
            id: notificationId
        };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/notifications"
    }
    resource function get notifications(@http:Header {name: "Authorization"} string authHeader,
                                       int? limit, int? offset) returns NotificationListResponse|http:Unauthorized|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        int actualLimit = limit ?: 50;
        int actualOffset = offset ?: 0;
        
        var notifications = self.notificationDB->getUserNotifications(userId, actualLimit, actualOffset);
        var unreadCount = self.notificationDB->getUnreadNotificationCount(userId);
        
        if notifications is error || unreadCount is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        NotificationResponse[] notificationList = from var notification in notifications
            select {
                id: notification.id.toString(),
                userId: notification.user_id.toString(),
                title: notification.title.toString(),
                message: notification.message.toString(),
                notificationType: notification.notification_type.toString(),
                isRead: notification.is_read of boolean ? notification.is_read : false,
                createdAt: notification.created_at.toString(),
                metadata: notification.metadata
            };
        
        return {
            notifications: notificationList,
            totalCount: notificationList.length(),
            unreadCount: unreadCount
        };
    }

    @http:ResourceConfig {
        methods: ["PUT"],
        path: "/notifications/read"
    }
    resource function put notifications/read(@http:Header {name: "Authorization"} string authHeader,
                                            MarkAsReadRequest request) returns SuccessResponse|http:Unauthorized|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        var result = self.notificationDB->markNotificationsAsRead(userId, request.notificationIds);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send read status event
        _ = self.sendKafkaEvent("notification-events", {
            "eventType": "NOTIFICATIONS_READ",
            "userId": userId,
            "notificationIds": request.notificationIds,
            "count": request.notificationIds.length(),
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "notification-service"
        });
        
        return {
            message: "Notifications marked as read"
        };
    }

    @http:ResourceConfig {
        methods: ["PUT"],
        path: "/notifications/read-all"
    }
    resource function put notifications/read-all(@http:Header {name: "Authorization"} string authHeader) returns SuccessResponse|http:Unauthorized|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        var result = self.notificationDB->markAllNotificationsAsRead(userId);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send read all event
        _ = self.sendKafkaEvent("notification-events", {
            "eventType": "ALL_NOTIFICATIONS_READ",
            "userId": userId,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "notification-service"
        });
        
        return {
            message: "All notifications marked as read"
        };
    }

    @http:ResourceConfig {
        methods: ["DELETE"],
        path: "/notifications/{notificationId}"
    }
    resource function delete notifications/[string notificationId](@http:Header {name: "Authorization"} string authHeader) returns SuccessResponse|http:Unauthorized|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        var result = self.notificationDB->deleteNotification(notificationId, userId);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send deletion event
        _ = self.sendKafkaEvent("notification-events", {
            "eventType": "NOTIFICATION_DELETED",
            "notificationId": notificationId,
            "userId": userId,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "notification-service"
        });
        
        return {
            message: "Notification deleted successfully"
        };
    }

    // ===== SYSTEM NOTIFICATIONS (Admin Endpoints) =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/system/notifications"
    }
    resource function post system/notifications(@http:Header {name: "Authorization"} string authHeader,
                                               NotificationRequest request) returns SuccessResponse|http:Unauthorized|http:InternalServerError {
        // Simple admin check
        if !authHeader.startsWith("Bearer admin-") {
            return http:UNAUTHORIZED;
        }
        
        log:printInfo("Creating system notification: " + request.title);
        
        var result = self.notificationDB->createSystemNotification(request.title, request.message, request.notificationType);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send system notification event
        _ = self.sendKafkaEvent("admin-notifications", {
            "eventType": "SYSTEM_NOTIFICATION_CREATED",
            "title": request.title,
            "message": request.message,
            "notificationType": request.notificationType,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "notification-service"
        });
        
        return {
            message: result
        };
    }

    // ===== BULK NOTIFICATIONS =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/notifications/bulk"
    }
    resource function post notifications/bulk(@http:Header {name: "Authorization"} string authHeader,
                                              NotificationRequest[] requests) returns SuccessResponse|http:Unauthorized|http:InternalServerError {
        if !authHeader.startsWith("Bearer admin-") {
            return http:UNAUTHORIZED;
        }
        
        log:printInfo("Creating bulk notifications: " + requests.length().toString() + " notifications");
        
        var result = self.notificationDB->createBulkNotifications(requests);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send bulk notification event
        _ = self.sendKafkaEvent("notification-events", {
            "eventType": "BULK_NOTIFICATIONS_CREATED",
            "count": requests.length(),
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "notification-service"
        });
        
        return {
            message: "Created " + result.length().toString() + " notifications"
        };
    }

    // ===== KAFKA HELPER METHODS =====
    private function sendKafkaEvent(string topic, map<json> event) returns error? {
        string eventJson = check value:toJson(event).toJsonString();
        kafka:ProducerError? result = self.kafkaProducer->send({
            topic: topic,
            value: eventJson.toBytes()
        });
        
        if result is kafka:ProducerError {
            log:printError("Failed to send Kafka event to topic: " + topic, error = result);
            return result;
        }
        
        log:printInfo("Event sent to Kafka topic: " + topic + " | Type: " + event.get("eventType").toString());
    }

    private function getCurrentTimestamp() returns string {
        return string `${{time:utcNow().format("yyyy-MM-dd'T'HH:mm:ss'Z'")}}`;
    }
}