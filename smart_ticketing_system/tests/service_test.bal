import ballerina/http;
import ballerina/test;

http:Client testClient = check new ("http://localhost:8080");

@test:Config {}
function testHealthEndpoint() returns error? {
    http:Response response = check testClient->/system/health;
    test:assertEquals(response.statusCode, 200);
}
