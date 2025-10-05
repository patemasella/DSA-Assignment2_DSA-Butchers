-- =============================================
-- TRANSPORT SYSTEM - INITIAL SCHEMA
-- Creates all database tables, types, and indexes
-- =============================================

-- Drop existing types if they exist (for clean setup)
DROP TYPE IF EXISTS user_role CASCADE;
DROP TYPE IF EXISTS vehicle_type CASCADE;
DROP TYPE IF EXISTS trip_status CASCADE;
DROP TYPE IF EXISTS ticket_status CASCADE;
DROP TYPE IF EXISTS ticket_type CASCADE;
DROP TYPE IF EXISTS payment_status CASCADE;

-- Enum types
CREATE TYPE user_role AS ENUM ('admin', 'passenger', 'train_driver', 'bus_driver');
CREATE TYPE vehicle_type AS ENUM ('bus', 'train');
CREATE TYPE trip_status AS ENUM ('scheduled', 'boarding', 'in_progress', 'completed', 'cancelled', 'delayed');
CREATE TYPE ticket_status AS ENUM ('created', 'paid', 'validated', 'expired', 'cancelled');
CREATE TYPE ticket_type AS ENUM ('single_ride', 'multiple_ride', 'daily_pass', 'weekly_pass', 'monthly_pass');
CREATE TYPE payment_status AS ENUM ('pending', 'completed', 'failed', 'refunded');

-- Users table (handles all user types)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role user_role NOT NULL,
    phone_number VARCHAR(20),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Vehicles table
CREATE TABLE vehicles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_number VARCHAR(50) UNIQUE NOT NULL,
    vehicle_type vehicle_type NOT NULL,
    capacity INTEGER NOT NULL,
    model VARCHAR(100),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Routes table
CREATE TABLE routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_code VARCHAR(50) UNIQUE NOT NULL,
    origin VARCHAR(255) NOT NULL,
    destination VARCHAR(255) NOT NULL,
    distance_km DECIMAL(8,2),
    estimated_duration_minutes INTEGER,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trips table
CREATE TABLE trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES routes(id),
    vehicle_id UUID NOT NULL REFERENCES vehicles(id),
    driver_id UUID NOT NULL REFERENCES users(id),
    scheduled_departure TIMESTAMP NOT NULL,
    scheduled_arrival TIMESTAMP NOT NULL,
    actual_departure TIMESTAMP,
    actual_arrival TIMESTAMP,
    current_location VARCHAR(255),
    status trip_status DEFAULT 'scheduled',
    available_seats INTEGER NOT NULL,
    base_price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (scheduled_arrival > scheduled_departure)
);

-- Tickets table
CREATE TABLE tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    passenger_id UUID NOT NULL REFERENCES users(id),
    trip_id UUID NOT NULL REFERENCES trips(id),
    ticket_type ticket_type NOT NULL,
    status ticket_status DEFAULT 'created',
    qr_code_hash VARCHAR(255) UNIQUE,
    purchase_price DECIMAL(10,2) NOT NULL,
    valid_from TIMESTAMP,
    valid_until TIMESTAMP,
    boarding_time TIMESTAMP,
    seat_number VARCHAR(10),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Payments table
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES tickets(id),
    passenger_id UUID NOT NULL REFERENCES users(id),
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    payment_method VARCHAR(50) NOT NULL,
    transaction_id VARCHAR(255) UNIQUE,
    status payment_status DEFAULT 'pending',
    payment_gateway_response JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Notifications table
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    notification_type VARCHAR(50) NOT NULL,
    is_read BOOLEAN DEFAULT false,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trip updates table for disruptions
CREATE TABLE trip_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES trips(id),
    update_type VARCHAR(50) NOT NULL,
    message TEXT NOT NULL,
    delay_minutes INTEGER DEFAULT 0,
    new_departure_time TIMESTAMP,
    new_arrival_time TIMESTAMP,
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Reporting tables for analytics
CREATE TABLE ticket_sales_daily (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_date DATE NOT NULL,
    ticket_type ticket_type NOT NULL,
    hour_slot INTEGER NOT NULL,
    amount_sold DECIMAL(10,2) NOT NULL,
    tickets_count INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(sale_date, ticket_type, hour_slot)
);

-- =============================================
-- PERFORMANCE INDEXES
-- =============================================

-- Users indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_active ON users(is_active) WHERE is_active = true;

-- Trips indexes
CREATE INDEX idx_trips_route_departure ON trips(route_id, scheduled_departure);
CREATE INDEX idx_trips_status ON trips(status);
CREATE INDEX idx_trips_departure_status ON trips(scheduled_departure, status);
CREATE INDEX idx_trips_vehicle ON trips(vehicle_id);
CREATE INDEX idx_trips_driver ON trips(driver_id);

-- Tickets indexes
CREATE INDEX idx_tickets_passenger_status ON tickets(passenger_id, status);
CREATE INDEX idx_tickets_trip ON tickets(trip_id);
CREATE INDEX idx_tickets_qr_code ON tickets(qr_code_hash);
CREATE INDEX idx_tickets_validity ON tickets(valid_until, status);
CREATE INDEX idx_tickets_created ON tickets(created_at);

-- Payments indexes
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_ticket ON payments(ticket_id);
CREATE INDEX idx_payments_passenger ON payments(passenger_id);
CREATE INDEX idx_payments_created ON payments(created_at);

-- Notifications indexes
CREATE INDEX idx_notifications_user ON notifications(user_id, created_at);
CREATE INDEX idx_notifications_read ON notifications(is_read) WHERE is_read = false;

-- Trip updates indexes
CREATE INDEX idx_trip_updates_trip ON trip_updates(trip_id, created_at);

-- Sales reporting indexes
CREATE INDEX idx_sales_date_type ON ticket_sales_daily(sale_date, ticket_type);
CREATE INDEX idx_sales_hour_slot ON ticket_sales_daily(hour_slot);

-- =============================================
-- FUNCTIONS AND TRIGGERS
-- =============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_trips_updated_at BEFORE UPDATE ON trips
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tickets_updated_at BEFORE UPDATE ON tickets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_payments_updated_at BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to handle ticket validation
CREATE OR REPLACE FUNCTION validate_ticket_boarding(
    p_ticket_id UUID,
    p_trip_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
    v_ticket_status ticket_status;
    v_trip_status trip_status;
    v_valid_until TIMESTAMP;
BEGIN
    -- Get ticket and trip status
    SELECT status, valid_into 
    INTO v_ticket_status, v_valid_until 
    FROM tickets 
    WHERE id = p_ticket_id;

    SELECT status INTO v_trip_status 
    FROM trips 
    WHERE id = p_trip_id;

    -- Check if ticket can be validated
    IF v_ticket_status = 'paid' 
       AND v_trip_status IN ('boarding', 'scheduled')
       AND (v_valid_until IS NULL OR v_valid_until > CURRENT_TIMESTAMP) THEN
        -- Update ticket status
        UPDATE tickets 
        SET status = 'validated', boarding_time = CURRENT_TIMESTAMP 
        WHERE id = p_ticket_id;
        
        RETURN true;
    END IF;
    
    RETURN false;
END;
$$ LANGUAGE plpgsql;

-- =============================================
-- SCHEMA VERSION TRACKING
-- =============================================

CREATE TABLE schema_migrations (
    version VARCHAR(50) PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO schema_migrations (version, description) 
VALUES ('1.0.0', 'Initial transport system schema');

-- =============================================
-- GRANT PERMISSIONS (if using multiple database users)
-- =============================================

-- GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO transport_user;
-- GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO transport_user;