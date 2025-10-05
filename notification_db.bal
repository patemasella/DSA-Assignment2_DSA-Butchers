import ballerinax/postgresql;
import ballerina/log;

public isolated client class NotificationDBClient {
    private final postgresql:Client dbClient;

    public function init(postgresql:Client dbClient) {
        self.dbClient = dbClient;
    }

    // ===== NOTIFICATION MANAGEMENT =====
    public function createNotification(NotificationRequest notification) returns string|error {
        string query = `INSERT INTO notifications (user_id, title, message, notification_type, metadata) 
                        VALUES ($1, $2, $3, $4, $5) RETURNING id`;
        
        var result = self.dbClient->query(query, notification.userId, notification.title, 
                                         notification.message, notification.notificationType, 
                                         notification.metadata);
        
        record {|string id;|}[] rows = check result.toArray();
        if rows.length() == 0 {
            return error("Failed to create notification");
        }
        return rows[0].id;
    }

    public function getUserNotifications(string userId, int limit = 50, int offset = 0) returns map<anydata>[]|error {
        string query = `SELECT 
            id, user_id, title, message, notification_type, is_read, metadata, created_at
            FROM notifications 
            WHERE user_id = $1 
            ORDER BY created_at DESC 
            LIMIT $2 OFFSET $3`;
        
        return self.dbClient->query(query, userId, limit, offset);
    }

    public function getUnreadNotificationCount(string userId) returns int|error {
        string query = `SELECT COUNT(*) as unread_count 
                        FROM notifications 
                        WHERE user_id = $1 AND is_read = false`;
        
        var result = self.dbClient->query(query, userId);
        record {|int unread_count;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return 0;
        }
        return rows[0].unread_count;
    }

    public function markNotificationsAsRead(string userId, string[] notificationIds) returns error? {
        if notificationIds.length() == 0 {
            return;
        }
        
        // Create placeholders for IN clause
        string[] placeholders = [];
        foreach int i in 0 ... notificationIds.length() - 1 {
            placeholders.push("$" + (i + 2).toString());
        }
        
        string query = `UPDATE notifications 
                        SET is_read = true 
                        WHERE user_id = $1 AND id IN (${placeholders.join(",")})`;
        
        _ = check self.dbClient->execute(query, userId, ...notificationIds);
    }

    public function markAllNotificationsAsRead(string userId) returns error? {
        string query = `UPDATE notifications 
                        SET is_read = true 
                        WHERE user_id = $1 AND is_read = false`;
        
        _ = check self.dbClient->execute(query, userId);
    }

    public function deleteNotification(string notificationId, string userId) returns error? {
        string query = `DELETE FROM notifications 
                        WHERE id = $1 AND user_id = $2`;
        
        _ = check self.dbClient->execute(query, notificationId, userId);
    }

    // ===== BULK NOTIFICATIONS =====
    public function createBulkNotifications(NotificationRequest[] notifications) returns string[]|error {
        string[] notificationIds = [];
        
        foreach var notification in notifications {
            string|error notificationId = self.createNotification(notification);
            if notificationId is error {
                log:printError("Failed to create bulk notification", error = notificationId);
            } else {
                notificationIds.push(notificationId);
            }
        }
        
        return notificationIds;
    }

    // ===== SYSTEM NOTIFICATIONS =====
    public function createSystemNotification(string title, string message, string notificationType) returns string|error {
        // Get all active users
        string getUserQuery = `SELECT id FROM users WHERE is_active = true`;
        var usersResult = self.dbClient->query(getUserQuery);
        record {|string id;|}[] users = check usersResult.toArray();
        
        string[] notificationIds = [];
        foreach var user in users {
            var notificationId = self.createNotification({
                userId: user.id,
                title: title,
                message: message,
                notificationType: notificationType,
                metadata: {}
            });
            if notificationId is string {
                notificationIds.push(notificationId);
            }
        }
        
        return "Created " + notificationIds.length().toString() + " notifications";
    }
}