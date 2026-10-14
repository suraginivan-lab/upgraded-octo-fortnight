-- PostgreSQL 16
BEGIN;
CREATE SCHEMA IF NOT EXISTS bike_rental;
SET search_path TO bike_rental, public;

CREATE TABLE stations (
 station_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 name varchar(100) NOT NULL UNIQUE,
 address varchar(200) NOT NULL,
 capacity integer NOT NULL CHECK (capacity > 0)
);
CREATE TABLE categories (
 category_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 name varchar(60) NOT NULL UNIQUE,
 description varchar(200)
);
CREATE TABLE tariffs (
 tariff_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 name varchar(80) NOT NULL UNIQUE,
 hourly_rate numeric(10,2) NOT NULL CHECK (hourly_rate > 0),
 deposit numeric(10,2) NOT NULL DEFAULT 0 CHECK (deposit >= 0)
);
CREATE TABLE clients (
 client_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 full_name varchar(120) NOT NULL,
 phone varchar(20) NOT NULL UNIQUE,
 email varchar(120) UNIQUE,
 registered_at date NOT NULL DEFAULT CURRENT_DATE,
 CONSTRAINT ck_client_phone CHECK (length(trim(phone)) >= 10)
);
CREATE TABLE employees (
 employee_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 full_name varchar(120) NOT NULL,
 position varchar(60) NOT NULL,
 station_id integer NOT NULL REFERENCES stations(station_id) ON DELETE RESTRICT
);
CREATE TABLE bicycles (
 bicycle_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 inventory_number varchar(25) NOT NULL UNIQUE,
 model varchar(100) NOT NULL,
 category_id integer NOT NULL REFERENCES categories(category_id) ON DELETE RESTRICT,
 station_id integer NOT NULL REFERENCES stations(station_id) ON DELETE RESTRICT,
 status varchar(20) NOT NULL DEFAULT 'available'
   CHECK (status IN ('available','rented','maintenance','retired')),
 purchase_date date NOT NULL
);
CREATE TABLE rentals (
 rental_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 client_id integer NOT NULL REFERENCES clients(client_id) ON DELETE RESTRICT,
 bicycle_id integer NOT NULL REFERENCES bicycles(bicycle_id) ON DELETE RESTRICT,
 tariff_id integer NOT NULL REFERENCES tariffs(tariff_id) ON DELETE RESTRICT,
 issued_by integer NOT NULL REFERENCES employees(employee_id) ON DELETE RESTRICT,
 start_station_id integer NOT NULL REFERENCES stations(station_id) ON DELETE RESTRICT,
 end_station_id integer REFERENCES stations(station_id) ON DELETE RESTRICT,
 started_at timestamp NOT NULL,
 finished_at timestamp,
 hourly_rate_at_start numeric(10,2) NOT NULL CHECK (hourly_rate_at_start > 0),
 total_cost numeric(10,2) CHECK (total_cost IS NULL OR total_cost >= 0),
 status varchar(15) NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','cancelled')),
 CONSTRAINT ck_rental_dates CHECK (finished_at IS NULL OR finished_at > started_at),
 CONSTRAINT ck_rental_status CHECK (
   (status = 'active' AND finished_at IS NULL AND end_station_id IS NULL AND total_cost IS NULL)
   OR (status = 'completed' AND finished_at IS NOT NULL AND end_station_id IS NOT NULL AND total_cost IS NOT NULL)
   OR (status = 'cancelled' AND total_cost IS NULL)
 )
);
CREATE TABLE payments (
 payment_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 rental_id bigint NOT NULL REFERENCES rentals(rental_id) ON DELETE RESTRICT,
 paid_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
 amount numeric(10,2) NOT NULL CHECK (amount > 0),
 method varchar(15) NOT NULL CHECK (method IN ('card','cash','transfer')),
 status varchar(15) NOT NULL DEFAULT 'paid' CHECK (status IN ('paid','refunded'))
);
CREATE TABLE maintenance (
 maintenance_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 bicycle_id integer NOT NULL REFERENCES bicycles(bicycle_id) ON DELETE RESTRICT,
 employee_id integer NOT NULL REFERENCES employees(employee_id) ON DELETE RESTRICT,
 serviced_at date NOT NULL,
 description varchar(300) NOT NULL,
 cost numeric(10,2) NOT NULL DEFAULT 0 CHECK (cost >= 0)
);

CREATE INDEX ix_bicycles_station_status ON bicycles(station_id, status);
CREATE INDEX ix_rentals_client_started ON rentals(client_id, started_at DESC);
CREATE INDEX ix_rentals_started ON rentals(started_at);
CREATE INDEX ix_payments_rental ON payments(rental_id);
CREATE INDEX ix_maintenance_bicycle_date ON maintenance(bicycle_id, serviced_at DESC);
CREATE UNIQUE INDEX ux_rentals_one_active_bicycle ON rentals(bicycle_id) WHERE status = 'active';

CREATE VIEW v_available_bicycles AS
 SELECT b.bicycle_id, b.inventory_number, b.model, c.name AS category,
        s.name AS station, s.address
 FROM bicycles b JOIN categories c USING(category_id)
 JOIN stations s USING(station_id)
 WHERE b.status = 'available'
   AND NOT EXISTS (SELECT 1 FROM rentals r WHERE r.bicycle_id=b.bicycle_id AND r.status='active');
CREATE VIEW v_client_rentals AS
 SELECT r.rental_id, cl.full_name AS client, b.inventory_number,
        r.started_at, r.finished_at, r.status, r.total_cost,
        t.name AS tariff
 FROM rentals r JOIN clients cl USING(client_id)
 JOIN bicycles b USING(bicycle_id) JOIN tariffs t USING(tariff_id);
CREATE VIEW v_daily_revenue AS
 SELECT paid_at::date AS payment_day, count(*) AS payment_count,
        sum(CASE WHEN status='paid' THEN amount ELSE -amount END) AS net_revenue
 FROM payments GROUP BY paid_at::date;
COMMIT;
