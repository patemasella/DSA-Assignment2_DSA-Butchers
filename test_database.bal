import ballerinax/postgresql;
import ballerina/io;

public function main() returns error? {
    io:println("🚀 Testing Ballerina Database Connection...");
    
    postgresql:Client dbClient = check new (
        host = "localhost",
        user = "transport_user",
        password = "transport_password",
        database = "transport_system",
        port = 5432
    );
    
    io:println("Testing database connection...");
    
    // Simple test query
    stream<record {}, error?> result = dbClient->query(`SELECT COUNT(*) as count FROM users`);
    
    int userCount = 0;
    check result.forEach(function(record {} row) {
        userCount = <int>row["count"];
    });
    
    io:println("✅ Database connection successful!");
    io:println("✅ Total users: " + userCount.toString());
    
    check dbClient.close();
    io:println("🎉 Database is ready for microservices!");
}