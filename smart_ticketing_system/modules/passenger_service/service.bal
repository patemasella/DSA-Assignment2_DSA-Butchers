module smart_ticketing_system.passenger_service;

import ballerina/http;

listener http:Listener passengerListener = new (9090);

service /passengers on passengerListener {
    resource function post register(@http:Payload json payload) returns json|error {
        // TODO: integrate with persistence layer.
        return { message: "Passenger registration stub" };
    }

    resource function get profiles/[string id]() returns json|error {
        return { id, message: "Fetch passenger profile stub" };
    }

    resource function get tickets/[string id]() returns json|error {
        return { id, message: "List passenger tickets stub" };
    }
}
