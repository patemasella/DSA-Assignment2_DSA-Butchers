// modules/passenger_service/main.bal
module smart_ticketing_system.passenger_service;

import ballerina/http;
import ballerina/mongo;
import ballerina/auth;
import ballerina/jwt;
import ballerina/time;
import ballerina/log;
import ballerina/uuid;
import ballerina/io;

// Database configuration
final mongo:Client passengerDB = check new ("mongodb://admin:password@localhost:27017",
    database = "smart_ticketing",
    collection = "passengers");

final mongo:Client ticketDB = check new ("mongodb://admin:password@localhost:27017",
    database = "smart_ticketing", 
    collection = "tickets");

// JWT configuration for authentication
final jwt:IssuerConfig jwtConfig = {
    issuer: "smart-ticketing-system",
    audience: "passengers",
    signatureConfig: {
        config: {
            keyFile: "./resources/private.key"
        }
    }
};

final auth:JwtValidatorConfig jwtValidatorConfig = {
    issuer: "smart-ticketing-system",
    audience: "passengers",
    signatureConfig: {
        certFile: "./resources/public.crt"
    }
};

// Type definitions
public type Passenger record {|
    string id;
    string firstName;
    string lastName;
    string email;
    string phone;
    string passwordHash;
    decimal balance;
    string status; // ACTIVE, INACTIVE, SUSPENDED
    string createdAt;
    string updatedAt;
|};

public type PassengerRegistration record {|
    string firstName;
    string lastName;
    string email;
    string phone;
    string password;
|};

public type PassengerProfile record {|
    string id;
    string firstName;
    string lastName;
    string email;
    string phone;
    decimal balance;
    string status;
    string createdAt;
|};

public type LoginRequest record {|
    string email;
    string password;
|};

public type LoginResponse record {|
    string accessToken;
    string tokenType = "Bearer";
    int expiresIn;
    PassengerProfile passenger;
|};

public type Ticket record {|
    string id;
    string passengerId;
    string tripId;
    string ticketType;
    string status;
    decimal price;
    string purchaseTime;
    string? validationTime;
    string? expiryTime;
    Route? routeInfo;
    Trip? tripInfo;
|};

public type Route record {|
    string id;
    string routeNumber;
    string name;
|};

public type Trip record {|
    string id;
    string routeId;
    string scheduledDeparture;
    string scheduledArrival;
|};

// Utility functions
function hashPassword(string password) returns string {
    // In production, use proper hashing like bcrypt
    return password; // Replace with actual hashing
}

function verifyPassword(string plainPassword, string hashedPassword) returns boolean {
    return hashPassword(plainPassword) == hashedPassword;
}

function generateJwt(string passengerId) returns string|error {
    jwt:Payload payload = {
        issuer: jwtConfig.issuer,
        audience: jwtConfig.audience,
        subject: passengerId,
        issuedAt: time:utcNow().time,
        expTime: time:utcAddSeconds(time:utcNow(), 3600).time // 1 hour
    };
    return jwt:encode(payload, jwtConfig.signatureConfig);
}

// Authentication middleware
class PassengerAuthHandler {
    *http:RequestMiddleware;

    function process(http:RequestContext ctx, http:Request req) returns http:RequestContext|http:Response {
        string|error authHeader = req.getHeader("Authorization");
        
        if authHeader is error {
            return prepareErrorResponse(http:UNAUTHORIZED, "Missing authorization header");
        }
        
        string[] parts = authHeader.split(" ");
        if parts.length() != 2 || parts[0] != "Bearer" {
            return prepareErrorResponse(http:UNAUTHORIZED, "Invalid authorization format");
        }
        
        string token = parts[1];
        jwt:Payload|jwt:Error validationResult = jwt:validate(token, jwtValidatorConfig);
        
        if validationResult is jwt:Error {
            return prepareErrorResponse(http:UNAUTHORIZED, "Invalid token");
        }
        
        // Add passenger ID to request context for downstream use
        ctx.setAttribute("passengerId", validationResult.subject);
        
        return ctx;
    }
}

// HTTP listener with authentication for protected routes
listener http:Listener passengerListener = new (9090, {
    auth: {
        authHandlers: [new PassengerAuthHandler()]
    },
    secureSocket: {
        key: {
            certFile: "./resources/public.crt",
            keyFile: "./resources/private.key"
        }
    }
});

service /passengers on passengerListener {

    // Public endpoint - passenger registration
    resource function post register(@http:Payload PassengerRegistration registration) 
    returns json|http:BadRequest|http:InternalServerError {
        
        // Validate input
        if registration.firstName == "" || registration.lastName == "" || 
           registration.email == "" || registration.password == "" {
            return http:BAD_REQUEST;
        }

        // Check if email already exists
        stream<Passenger, error?> existingPassenger = check passengerDB->find(
            `{"email": "${registration.email}"}`, Passenger
        );
        
        int count = 0;
        foreach var passenger in existingPassenger {
            count += 1;
        }
        
        if count > 0 {
            return prepareErrorResponse(http:BAD_REQUEST, "Email already registered");
        }

        // Create new passenger
        string passengerId = uuid:createType1AsString();
        string currentTime = time:utcToString(time:utcNow());
        
        Passenger newPassenger = {
            id: passengerId,
            firstName: registration.firstName,
            lastName: registration.lastName,
            email: registration.email,
            phone: registration.phone,
            passwordHash: hashPassword(registration.password),
            balance: 0.0,
            status: "ACTIVE",
            createdAt: currentTime,
            updatedAt: currentTime
        };

        // Save to database
        _ = check passengerDB->insert(newPassenger);
        
        log:printInfo("Passenger registered successfully", passengerId = passengerId);
        
        return {
            id: passengerId,
            message: "Passenger registered successfully",
            status: "ACTIVE"
        };
    }

    // Public endpoint - passenger login
    resource function post login(@http:Payload LoginRequest loginReq) 
    returns LoginResponse|http:Unauthorized|http:InternalServerError {
        
        // Find passenger by email
        stream<Passenger, error?> result = check passengerDB->find(
            `{"email": "${loginReq.email}"}`, Passenger
        );
        
        Passenger? passenger = ();
        foreach var p in result {
            passenger = p;
            break;
        }
        
        if passenger is () {
            return http:UNAUTHORIZED;
        }
        
        // Verify password
        if !verifyPassword(loginReq.password, passenger.passwordHash) {
            return http:UNAUTHORIZED;
        }
        
        // Check if passenger is active
        if passenger.status != "ACTIVE" {
            return prepareErrorResponse(http:UNAUTHORIZED, "Account is not active");
        }
        
        // Generate JWT token
        string accessToken = check generateJwt(passenger.id);
        
        // Create profile response
        PassengerProfile profile = {
            id: passenger.id,
            firstName: passenger.firstName,
            lastName: passenger.lastName,
            email: passenger.email,
            phone: passenger.phone,
            balance: passenger.balance,
            status: passenger.status,
            createdAt: passenger.createdAt
        };
        
        log:printInfo("Passenger logged in successfully", passengerId = passenger.id);
        
        return {
            accessToken: accessToken,
            expiresIn: 3600,
            passenger: profile
        };
    }

    // Protected endpoint - get passenger profile
    resource function get profiles/[string id]() 
    returns PassengerProfile|http:NotFound|http:Forbidden|http:InternalServerError {
        
        string|error passengerId = getCallerPassengerId();
        if passengerId is error || passengerId != id {
            return http:FORBIDDEN;
        }
        
        // Find passenger by ID
        Passenger? passenger = check passengerDB->findById(id, Passenger);
        
        if passenger is () {
            return http:NOT_FOUND;
        }
        
        return {
            id: passenger.id,
            firstName: passenger.firstName,
            lastName: passenger.lastName,
            email: passenger.email,
            phone: passenger.phone,
            balance: passenger.balance,
            status: passenger.status,
            createdAt: passenger.createdAt
        };
    }

    // Protected endpoint - get passenger tickets
    resource function get tickets/[string id]() 
    returns Ticket[]|http:NotFound|http:Forbidden|http:InternalServerError {
        
        string|error passengerId = getCallerPassengerId();
        if passengerId is error || passengerId != id {
            return http:FORBIDDEN;
        }
        
        // Verify passenger exists
        Passenger? passenger = check passengerDB->findById(id, Passenger);
        if passenger is () {
            return http:NOT_FOUND;
        }
        
        // Find tickets for this passenger
        stream<Ticket, error?> ticketsStream = check ticketDB->find(
            `{"passengerId": "${id}"}`, Ticket
        );
        
        Ticket[] tickets = [];
        foreach var ticket in ticketsStream {
            tickets.push(ticket);
        }
        
        // Sort by purchase time (newest first)
        tickets.sort(sortTicketsByPurchaseTime);
        
        log:printInfo("Retrieved passenger tickets", 
            passengerId = id, 
            ticketCount = tickets.length().toString()
        );
        
        return tickets;
    }

    // Protected endpoint - update passenger profile
    resource function put profiles/[string id](@http:Payload {|
        string? firstName;
        string? lastName;
        string? phone;
    |} updates) returns PassengerProfile|http:NotFound|http:Forbidden|http:InternalServerError {
        
        string|error passengerId = getCallerPassengerId();
        if passengerId is error || passengerId != id {
            return http:FORBIDDEN;
        }
        
        // Find existing passenger
        Passenger? existingPassenger = check passengerDB->findById(id, Passenger);
        if existingPassenger is () {
            return http:NOT_FOUND;
        }
        
        // Build update document
        json updateDoc = {};
        if updates.firstName is () {} else {
            updateDoc.firstName = updates.firstName;
        }
        if updates.lastName is () {} else {
            updateDoc.lastName = updates.lastName;
        }
        if updates.phone is () {} else {
            updateDoc.phone = updates.phone;
        }
        updateDoc.updatedAt = time:utcToString(time:utcNow());
        
        // Update in database
        _ = check passengerDB->update(
            `{"_id": "${id}"}`, 
            `{"$set": ${updateDoc.toJsonString()}}`
        );
        
        // Fetch updated passenger
        Passenger? updatedPassenger = check passengerDB->findById(id, Passenger);
        
        return {
            id: updatedPassenger.id,
            firstName: updatedPassenger.firstName,
            lastName: updatedPassenger.lastName,
            email: updatedPassenger.email,
            phone: updatedPassenger.phone,
            balance: updatedPassenger.balance,
            status: updatedPassenger.status,
            createdAt: updatedPassenger.createdAt
        };
    }

    // Health check endpoint
    resource function get health() returns json {
        return {
            status: "HEALTHY",
            service: "passenger-service",
            timestamp: time:utcToString(time:utcNow())
        };
    }
}

// Helper functions
function getCallerPassengerId() returns string|error {
    http:RequestContext ctx = http:getContext();
    var passengerId = ctx.getAttribute("passengerId");
    
    if passengerId is string {
        return passengerId;
    }
    return error("Passenger ID not found in context");
}

function prepareErrorResponse(http:StatusCode status, string message) returns http:Response {
    return new (status, {
        message: message
    });
}

function sortTicketsByPurchaseTime(Ticket a, Ticket b) returns decimal {
    time:Utc timeA = check time:utcFromString(a.purchaseTime);
    time:Utc timeB = check time:utcFromString(b.purchaseTime);
    return timeB.time - timeA.time; // Descending order
}
