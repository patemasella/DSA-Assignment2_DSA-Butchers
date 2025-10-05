module smart_ticketing_system.admin_service;

import ballerina/http;

listener http:Listener adminListener = new (9095);

service /admin on adminListener {
    resource function get dashboard() returns json|error {
        return { message: "Admin dashboard stub" };
    }

    resource function get reports() returns json|error {
        return { message: "Reports stub" };
    }
}
