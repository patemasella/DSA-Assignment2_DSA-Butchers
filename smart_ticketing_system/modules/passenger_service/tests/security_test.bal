import ballerina/test;

@test:Config {}
function testHashPasswordConsistency() {
    string password = "Secret123!";
    string hashed = hashPassword(password);
    test:assertFalse(hashed == password, msg = "Hashed password should differ from the original");
    test:assertTrue(hashed.length() > 0, msg = "Hashed password should not be empty");
    test:assertTrue(verifyPassword(password, hashed), msg = "Valid password should verify");
    test:assertFalse(verifyPassword("WrongPass", hashed), msg = "Invalid password must fail verification");
}

@test:Config {}
function testValidateRegistrationRejectsInvalidEmail() {
    PassengerRegistration invalidRegistration = {
        firstName: "Jane",
        lastName: "Doe",
        email: "not-an-email",
        phone: "+1234567890",
        password: "Sup3rSecret"
    };

    string? validationError = validateRegistration(invalidRegistration);
    test:assertTrue(validationError is string, msg = "Invalid registration should return an error message");
}

@test:Config {}
function testValidateRegistrationAcceptsValidPayload() {
    PassengerRegistration validRegistration = {
        firstName: "Jane",
        lastName: "Doe",
        email: "jane.doe@example.com",
        phone: "+123 456 7890",
        password: "Sup3rSecret"
    };

    string? validationError = validateRegistration(validRegistration);
    test:assertTrue(validationError is (), msg = "Valid registration must not produce an error message");
}

@test:Config {}
function testValidateLoginEnforcesFields() {
    LoginRequest invalidLogin = {
        email: "",
        password: ""
    };

    string? validationError = validateLogin(invalidLogin);
    test:assertTrue(validationError is string, msg = "Missing credentials should yield an error");

    LoginRequest validLogin = {
        email: "user@example.com",
        password: "Sup3rSecret"
    };

    string? validResult = validateLogin(validLogin);
    test:assertTrue(validResult is (), msg = "Valid credentials should pass validation");
}
