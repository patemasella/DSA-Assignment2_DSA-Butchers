import ballerina/http;

listener http:Listener gatewayListener = new (8080);

service /system on gatewayListener {
    resource function get health() returns json {
        return { status: "UP", message: "Smart ticketing platform skeleton" };
    }
}
