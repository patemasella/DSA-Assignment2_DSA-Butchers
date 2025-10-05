// modules/passenger_service/main.bal
module smart_ticketing_system.passenger_service;

import ballerina/http;

import ballerina/mongo;

import ballerina/auth;

import ballerina/jwt;

import ballerina/time;

import ballerina/log;

import ballerina/uuid;

import ballerina/crypto;

import ballerina/encoding;

import ballerina/regex;



configurable string passengerDbUri = "mongodb://admin:password@localhost:27017";

configurable string passengerDbName = "smart_ticketing";

configurable string passengersCollection = "passengers";

configurable string ticketsCollection = "tickets";

configurable int accessTokenTtlSeconds = 3600;

configurable string jwtKeyFilePath = "./resources/private.key";

configurable string jwtCertFilePath = "./resources/public.crt";



final regex:RegExp EMAIL_PATTERN = re "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$";

final regex:RegExp PHONE_PATTERN = re "^[0-9+][0-9\\s-]{6,}$";

const int MIN_PASSWORD_LENGTH = 8;



final mongo:Client? passengerDB = initMongoClient(passengersCollection);

final mongo:Client? ticketDB = initMongoClient(ticketsCollection);



// JWT configuration for authentication

final jwt:IssuerConfig jwtConfig = {

    issuer: "smart-ticketing-system",

    audience: "passengers",

    signatureConfig: {

        config: {

            keyFile: jwtKeyFilePath

        }

    }

};



final auth:JwtValidatorConfig jwtValidatorConfig = {

    issuer: "smart-ticketing-system",

    audience: "passengers",

    signatureConfig: {

        certFile: jwtCertFilePath

    }

};



function initMongoClient(string collection) returns mongo:Client? {

    mongo:Client|error result = new (passengerDbUri, database = passengerDbName, collection = collection);

    if result is mongo:Client {

        return result;

    }

    log:printError("Failed to connect to MongoDB collection", 'error = result, collection = collection);

    return ();

}



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

    byte[] hash = crypto:hashSha256(password.toBytes());

    return encoding:byteArrayToHexString(hash);

}



function verifyPassword(string plainPassword, string hashedPassword) returns boolean {
    return hashPassword(plainPassword) == hashedPassword;
}

function generateJwt(string passengerId) returns string|error {

    time:Utc issuedAt = time:utcNow();

    time:Utc expiresAt = time:utcAddSeconds(issuedAt, accessTokenTtlSeconds);

    jwt:Payload payload = {

        issuer: jwtConfig.issuer,

        audience: jwtConfig.audience,

        subject: passengerId,

        issuedAt: issuedAt.time,

        expTime: expiresAt.time

    };

    return jwt:encode(payload, jwtConfig.signatureConfig);

}



function validateRegistration(PassengerRegistration registration) returns string? {

    if registration.firstName.trim().isEmpty() {

        return "First name is required";

    }

    if registration.lastName.trim().isEmpty() {

        return "Last name is required";

    }

    string email = registration.email.trim();

    if email.isEmpty() {

        return "Email address is required";

    }

    if !regex:matches(email, EMAIL_PATTERN) {

        return "Invalid email address";

    }

    string phone = registration.phone.trim();

    if phone.isEmpty() {

        return "Phone number is required";

    }

    if !regex:matches(phone, PHONE_PATTERN) {

        return "Invalid phone number";

    }

    string password = registration.password.trim();

    if password.length() < MIN_PASSWORD_LENGTH {

        return "Password must be at least 8 characters long";

    }

    return ();

}



function validateLogin(LoginRequest loginReq) returns string? {

    string email = loginReq.email.trim();

    if email.isEmpty() {

        return "Email address is required";

    }

    if !regex:matches(email, EMAIL_PATTERN) {

        return "Invalid email address";

    }

    if loginReq.password.trim().isEmpty() {

        return "Password is required";

    }

    return ();

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
            certFile: jwtCertFilePath,
            keyFile: jwtKeyFilePath
        }
    }
});

service /passengers on passengerListener {

    // Public endpoint - passenger registration
    resource function post register(@http:Payload PassengerRegistration registration)

    returns json|http:BadRequest|http:InternalServerError {

        string? validationError = validateRegistration(registration);

        if validationError is string {

            return prepareErrorResponse(http:BAD_REQUEST, validationError);

        }



        if passengerDB is () {

            log:printError("Passenger database client unavailable");

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Passenger store is currently unavailable");

        }



        string firstName = registration.firstName.trim();

        string lastName = registration.lastName.trim();

        string email = registration.email.trim().toLowerAscii();

        string phone = registration.phone.trim();

        string password = registration.password.trim();



        var existingResult = passengerDB->find(`{"email": "${email}"}`, Passenger);

        if existingResult is error {

            log:printError("Failed to query passenger store", 'error = existingResult);

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Unable to verify passenger uniqueness");

        }



        boolean emailExists = false;

        foreach var passenger in existingResult {

            emailExists = true;

            break;

        }



        if emailExists {

            return prepareErrorResponse(http:BAD_REQUEST, "Email already registered");

        }



        string passengerId = uuid:createType1AsString();

        string currentTime = time:utcToString(time:utcNow());

        Passenger newPassenger = {

            id: passengerId,

            firstName: firstName,

            lastName: lastName,

            email: email,

            phone: phone,

            passwordHash: hashPassword(password),

            balance: 0.0,

            status: "ACTIVE",

            createdAt: currentTime,

            updatedAt: currentTime

        };



        var insertResult = passengerDB->insert(newPassenger);

        if insertResult is error {

            log:printError("Failed to insert passenger", 'error = insertResult);

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Could not complete registration");

        }



        log:printInfo("Passenger registered successfully", passengerId = passengerId);



        return {

            id: passengerId,

            message: "Passenger registered successfully",

            status: "ACTIVE"

        };

    }



    resource function post login(@http:Payload LoginRequest loginReq)

    returns LoginResponse|http:Unauthorized|http:InternalServerError {

        string? validationError = validateLogin(loginReq);

        if validationError is string {

            return prepareErrorResponse(http:BAD_REQUEST, validationError);

        }



        if passengerDB is () {

            log:printError("Passenger database client unavailable");

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Passenger store is currently unavailable");

        }



        string email = loginReq.email.trim().toLowerAscii();

        var result = passengerDB->find(`{"email": "${email}"}`, Passenger);

        if result is error {

            log:printError("Failed to query passenger store for login", 'error = result);

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Unable to process login");

        }



        Passenger? passenger = ();

        foreach var p in result {

            passenger = p;

            break;

        }



        if passenger is () {

            return http:UNAUTHORIZED;

        }



        if !verifyPassword(loginReq.password, passenger.passwordHash) {

            return http:UNAUTHORIZED;

        }



        if passenger.status != "ACTIVE" {

            return prepareErrorResponse(http:UNAUTHORIZED, "Account is not active");

        }



        string accessToken = check generateJwt(passenger.id);

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

            expiresIn: accessTokenTtlSeconds,

            passenger: profile

        };

    }



    resource function get profiles/[string id]()

    returns PassengerProfile|http:NotFound|http:Forbidden|http:InternalServerError {

        string|error passengerId = getCallerPassengerId();

        if passengerId is error || passengerId != id {

            return http:FORBIDDEN;

        }



        if passengerDB is () {

            log:printError("Passenger database client unavailable");

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Passenger store is currently unavailable");

        }



        var findResult = passengerDB->findById(id, Passenger);

        if findResult is error {

            log:printError("Failed to retrieve passenger profile", 'error = findResult, passengerId = id);

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Unable to load passenger profile");

        }



        Passenger? passenger = findResult;

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



    resource function get tickets/[string id]()

    returns Ticket[]|http:NotFound|http:Forbidden|http:InternalServerError {

        string|error passengerId = getCallerPassengerId();

        if passengerId is error || passengerId != id {

            return http:FORBIDDEN;

        }



        if passengerDB is () || ticketDB is () {

            log:printError("Database client unavailable when loading tickets", passengerId = id);

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Ticket store is currently unavailable");

        }



        var passengerResult = passengerDB->findById(id, Passenger);

        if passengerResult is error {

            log:printError("Failed to verify passenger existence", 'error = passengerResult, passengerId = id);

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Unable to load tickets");

        }

        if passengerResult is () {

            return http:NOT_FOUND;

        }



        var ticketsStreamResult = ticketDB->find(`{"passengerId": "${id}"}`, Ticket);

        if ticketsStreamResult is error {

            log:printError("Failed to query tickets", 'error = ticketsStreamResult, passengerId = id);

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Unable to load tickets");

        }



        Ticket[] tickets = [];

        foreach var ticket in ticketsStreamResult {

            tickets.push(ticket);

        }



        tickets.sort(sortTicketsByPurchaseTime);



        log:printInfo("Retrieved passenger tickets", passengerId = id, ticketCount = tickets.length().toString());



        return tickets;

    }



    resource function put profiles/[string id](@http:Payload {

        string? firstName;

        string? lastName;

        string? phone;

    |} updates) returns PassengerProfile|http:NotFound|http:Forbidden|http:InternalServerError {

        string|error passengerId = getCallerPassengerId();

        if passengerId is error || passengerId != id {

            return http:FORBIDDEN;

        }



        if passengerDB is () {

            log:printError("Passenger database client unavailable");

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Passenger store is currently unavailable");

        }



        var existingPassengerResult = passengerDB->findById(id, Passenger);

        if existingPassengerResult is error {

            log:printError("Failed to retrieve passenger for update", 'error = existingPassengerResult, passengerId = id);

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Unable to update profile");

        }



        Passenger? existingPassenger = existingPassengerResult;

        if existingPassenger is () {

            return http:NOT_FOUND;

        }



        json updateDoc = {};

        if updates.firstName is string firstNameUpdate {

            updateDoc.firstName = firstNameUpdate.trim();

        }

        if updates.lastName is string lastNameUpdate {

            updateDoc.lastName = lastNameUpdate.trim();

        }

        if updates.phone is string phoneUpdate {

            updateDoc.phone = phoneUpdate.trim();

        }

        updateDoc.updatedAt = time:utcToString(time:utcNow());



        var updateResult = passengerDB->update(`{"_id": "${id}"}`, `{"$set": ${updateDoc.toJsonString()}}`);

        if updateResult is error {

            log:printError("Failed to update passenger profile", 'error = updateResult, passengerId = id);

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Unable to update profile");

        }



        var refreshedPassengerResult = passengerDB->findById(id, Passenger);

        if refreshedPassengerResult is error {

            log:printError("Failed to reload passenger profile after update", 'error = refreshedPassengerResult, passengerId = id);

            return prepareErrorResponse(http:INTERNAL_SERVER_ERROR, "Unable to load updated profile");

        }



        Passenger? updatedPassengerOpt = refreshedPassengerResult;

        if updatedPassengerOpt is () {

            return http:NOT_FOUND;

        }



        Passenger updatedPassenger = updatedPassengerOpt;



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
