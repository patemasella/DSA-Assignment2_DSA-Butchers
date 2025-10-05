# Use official Ballerina runtime
FROM ballerina/ballerina:2201.12.8

# Set working directory
WORKDIR /home/ballerina

# Copy package files
COPY Ballerina.toml .
COPY Config.toml .
COPY src/ ./src/

# Build the Ballerina package
RUN bal build --skip-tests

# Expose the service port
EXPOSE 8081

# Run the service
CMD ["bal", "run", "target/bin/transport_service.jar"]