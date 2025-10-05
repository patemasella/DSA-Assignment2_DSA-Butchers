-- =============================================
-- TRANSPORT SYSTEM - SAMPLE DATA (FIXED)
-- =============================================

-- Note: Using simple password hash for demo - in production use proper hashing
-- Default password for all sample users: 'password123'

-- Admin users
INSERT INTO users (email, password_hash, first_name, last_name, role, phone_number) VALUES
('admin@transport.com', 'demo_hash_admin', 'System', 'Administrator', 'admin', '+1234567890');

-- Train Drivers
INSERT INTO users (email, password_hash, first_name, last_name, role, phone_number) VALUES
('train.driver1@transport.com', 'demo_hash_driver', 'John', 'Trainmaster', 'train_driver', '+1234567801'),
('train.driver2@transport.com', 'demo_hash_driver', 'Sarah', 'Railway', 'train_driver', '+1234567802');

-- Bus Drivers
INSERT INTO users (email, password_hash, first_name, last_name, role, phone_number) VALUES
('bus.driver1@transport.com', 'demo_hash_driver', 'Robert', 'Busdriver', 'bus_driver', '+1234567810'),
('bus.driver2@transport.com', 'demo_hash_driver', 'Lisa', 'Transit', 'bus_driver', '+1234567811');

-- Sample Passengers
INSERT INTO users (email, password_hash, first_name, last_name, role, phone_number) VALUES
('passenger1@example.com', 'demo_hash_passenger', 'Alice', 'Johnson', 'passenger', '+1234567820'),
('passenger2@example.com', 'demo_hash_passenger', 'Bob', 'Smith', 'passenger', '+1234567821');

-- Trains
INSERT INTO vehicles (vehicle_number, vehicle_type, capacity, model) VALUES
('TRAIN-001', 'train', 300, 'Express Train X1'),
('TRAIN-002', 'train', 280, 'Rapid Transit R2');

-- Buses
INSERT INTO vehicles (vehicle_number, vehicle_type, capacity, model) VALUES
('BUS-001', 'bus', 50, 'City Bus C1'),
('BUS-002', 'bus', 45, 'Urban Transit U2');

-- Routes
INSERT INTO routes (route_code, origin, destination, distance_km, estimated_duration_minutes) VALUES
-- Bus Routes
('BUS-001', 'City Center', 'Tura', 25.5, 45),
('BUS-002', 'Tura', 'City Center', 25.5, 45),
-- Train Routes
('TRAIN-001', 'Central Station', 'North District', 42.3, 60),
('TRAIN-002', 'North District', 'Central Station', 42.3, 60);

-- Sample Trips (using subqueries to get actual IDs)
INSERT INTO trips (route_id, vehicle_id, driver_id, scheduled_departure, scheduled_arrival, available_seats, base_price)
SELECT 
    r.id, 
    v.id, 
    u.id, 
    CURRENT_TIMESTAMP + INTERVAL '2 hours',
    CURRENT_TIMESTAMP + INTERVAL '3 hours',
    v.capacity,
    CASE WHEN r.distance_km <= 30 THEN 5.00 ELSE 10.00 END
FROM routes r, vehicles v, users u
WHERE r.route_code = 'BUS-001'
  AND v.vehicle_number = 'BUS-001'
  AND u.email = 'bus.driver1@transport.com';

INSERT INTO trips (route_id, vehicle_id, driver_id, scheduled_departure, scheduled_arrival, available_seats, base_price)
SELECT 
    r.id, 
    v.id, 
    u.id, 
    CURRENT_TIMESTAMP + INTERVAL '3 hours',
    CURRENT_TIMESTAMP + INTERVAL '4 hours',
    v.capacity,
    CASE WHEN r.distance_km <= 30 THEN 5.00 ELSE 10.00 END
FROM routes r, vehicles v, users u
WHERE r.route_code = 'TRAIN-001'
  AND v.vehicle_number = 'TRAIN-001'
  AND u.email = 'train.driver1@transport.com';

-- Sample Tickets with explicit type casting
INSERT INTO tickets (passenger_id, trip_id, ticket_type, status, purchase_price, valid_from, valid_until)
SELECT 
    passenger.id,
    trip.id,
    'single_ride'::ticket_type,
    'paid'::ticket_status,
    trip.base_price,
    trip.scheduled_departure - INTERVAL '1 hour',
    trip.scheduled_arrival + INTERVAL '2 hours'
FROM users passenger, trips trip
WHERE passenger.email = 'passenger1@example.com'
LIMIT 1;

-- Sample Payments
INSERT INTO payments (ticket_id, passenger_id, amount, payment_method, transaction_id, status)
SELECT 
    ticket.id,
    ticket.passenger_id,
    ticket.purchase_price,
    'credit_card',
    'txn_' || substr(md5(random()::text), 1, 16),
    'completed'::payment_status
FROM tickets ticket
LIMIT 1;

-- Sample notifications
INSERT INTO notifications (user_id, title, message, notification_type) 
SELECT 
    id,
    'Welcome to Transport System!',
    'Thank you for registering with our transport service.',
    'welcome'
FROM users 
WHERE email = 'passenger1@example.com';

-- Sample ticket sales data for reporting
INSERT INTO ticket_sales_daily (sale_date, ticket_type, hour_slot, amount_sold, tickets_count) VALUES
(CURRENT_DATE, 'single_ride'::ticket_type, 8, 150.00, 25),
(CURRENT_DATE, 'single_ride'::ticket_type, 12, 200.00, 35),
(CURRENT_DATE, 'daily_pass'::ticket_type, 8, 300.00, 15);