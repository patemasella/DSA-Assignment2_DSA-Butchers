module smart_ticketing_system.ticketing_service;

import ballerina/http;

listener http:Listener ticketingListener = new (9092);

service /tickets on ticketingListener {
    resource function post request(@http:Payload json payload) returns json|error {
        return { message: "Ticket request stub" };
    }

    resource function post validate(@http:Payload json payload) returns json|error {
        return { message: "Ticket validation stub" };
    }
}
