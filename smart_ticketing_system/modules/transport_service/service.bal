module smart_ticketing_system.transport_service;

import ballerina/http;

listener http:Listener transportListener = new (9091);

service /transport on transportListener {
    resource function post routes(@http:Payload json payload) returns json|error {
        return { message: "Create route stub" };
    }

    resource function get routes() returns json|error {
        return { message: "List routes stub" };
    }

    resource function post trips(@http:Payload json payload) returns json|error {
        return { message: "Create trip stub" };
    }
}
