import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

// Shared database types and client for all services
public type User record {
    string id;
    string email;
    // ... other fields
};

public isolated client class DatabaseClient {
    private final postgresql:Client dbClient;

    public function init() returns error? {
        self.dbClient = check new (
            host = "postgres", 
            user = "transport_user",
            password = "transport_password",
            database = "transport_system",
            port = 5432,
            options = {
                connectTimeout: 10,  // 10 seconds
                socketTimeout: 30    // 30 seconds
            }
        );
    }

    public function getClient() returns postgresql:Client {
        return self.dbClient;
    }

    public function close() returns error? {
        return self.dbClient.close();
    }
}