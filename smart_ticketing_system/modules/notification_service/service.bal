module smart_ticketing_system.notification_service;

import ballerina/http;

listener http:Listener notificationListener = new (9094);

service /notifications on notificationListener {
    resource function post dispatch(@http:Payload json payload) returns json|error {
        return { message: "Notification dispatch stub" };
    }
}
