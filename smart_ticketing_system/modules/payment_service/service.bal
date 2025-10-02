module smart_ticketing_system.payment_service;

import ballerina/http;

listener http:Listener paymentListener = new (9093);

service /payments on paymentListener {
    resource function post simulate(@http:Payload json payload) returns json|error {
        return { message: "Payment simulation stub" };
    }
}
