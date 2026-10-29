-- PostgreSQL 16. Выполнять после схемы этапа 1.
SET search_path TO bike_rental, public;

-- 1. Скалярная: цена часа с наценкой, NULL сохраняется.
CREATE OR REPLACE FUNCTION fn_rate_with_markup(p_rate numeric, p_percent numeric)
RETURNS numeric(10,2) LANGUAGE sql IMMUTABLE
AS $$ SELECT round((p_rate * (1 + p_percent / 100.0))::numeric, 2)::numeric(10,2) $$;

-- 2. Скалярная: длительность аренды в оплачиваемых часах (округление вверх).
CREATE OR REPLACE FUNCTION fn_billable_hours(p_start timestamp, p_finish timestamp)
RETURNS integer LANGUAGE sql IMMUTABLE
AS $$ SELECT CASE WHEN p_start IS NULL OR p_finish IS NULL THEN NULL
  WHEN p_finish <= p_start THEN 0
  ELSE ceil(extract(epoch FROM (p_finish - p_start)) / 3600.0)::integer END $$;

-- 3. Скалярная: стоимость аренды.
CREATE OR REPLACE FUNCTION fn_rental_cost(p_start timestamp, p_finish timestamp, p_rate numeric)
RETURNS numeric(10,2) LANGUAGE sql IMMUTABLE
AS $$ SELECT CASE WHEN p_rate IS NULL OR p_rate < 0 THEN NULL
 ELSE (fn_billable_hours(p_start,p_finish) * p_rate)::numeric(10,2) END $$;

-- 4. Inline таблица: аренды клиента за период.
CREATE OR REPLACE FUNCTION fn_client_rentals(p_client_id integer, p_from date, p_to date)
RETURNS TABLE(rental_id bigint, bicycle_id integer, started_at timestamp, status varchar(15), total_cost numeric(10,2))
LANGUAGE sql STABLE AS $$
 SELECT r.rental_id,r.bicycle_id,r.started_at,r.status,r.total_cost
 FROM bike_rental.rentals r
 WHERE r.client_id=p_client_id AND r.started_at >= p_from::timestamp
   AND r.started_at < (p_to + 1)::timestamp
 ORDER BY r.started_at DESC
$$;

-- 5. Inline таблица: свободные велосипеды указанной станции.
CREATE OR REPLACE FUNCTION fn_available_bicycles(p_station_id integer)
RETURNS TABLE(bicycle_id integer, inventory_number varchar(25), model varchar(100), category varchar(60))
LANGUAGE sql STABLE AS $$
 SELECT b.bicycle_id,b.inventory_number,b.model,c.name
 FROM bike_rental.bicycles b JOIN bike_rental.categories c ON c.category_id=b.category_id
 WHERE b.station_id=p_station_id AND b.status='available'
   AND NOT EXISTS (SELECT 1 FROM bike_rental.rentals r WHERE r.bicycle_id=b.bicycle_id AND r.status='active')
 ORDER BY b.bicycle_id
$$;

-- 6. Многооператорная табличная PL/pgSQL: загрузка станций и категории загрузки.
CREATE OR REPLACE FUNCTION fn_station_load(p_threshold integer DEFAULT 80)
RETURNS TABLE(station_id integer, station_name varchar(100), capacity integer, bicycle_count bigint, load_percent numeric(6,2), load_status text)
LANGUAGE plpgsql STABLE AS $$
BEGIN
 IF p_threshold IS NULL OR p_threshold < 0 OR p_threshold > 100 THEN
  RAISE EXCEPTION 'Порог должен быть от 0 до 100' USING ERRCODE='22023';
 END IF;
 RETURN QUERY
 SELECT s.station_id,s.name,s.capacity,count(b.bicycle_id),
        round(100.0*count(b.bicycle_id)/s.capacity,2)::numeric(6,2),
        CASE WHEN count(b.bicycle_id)=0 THEN 'пустая'
             WHEN (100.0*count(b.bicycle_id)/s.capacity)>=p_threshold THEN 'загружена'
             ELSE 'есть места' END
 FROM bike_rental.stations s
 LEFT JOIN bike_rental.bicycles b ON b.station_id=s.station_id AND b.status <> 'retired'
 GROUP BY s.station_id,s.name,s.capacity
 ORDER BY s.station_id;
END $$;

-- 7. Скалярная выборка числа аренд клиента, для использования в процедуре этапа 2.
CREATE OR REPLACE FUNCTION fn_client_rental_count(p_client_id integer)
RETURNS integer LANGUAGE sql STABLE AS $$
 SELECT count(*)::integer FROM bike_rental.rentals WHERE client_id=p_client_id
$$;

-- Рефакторинг существующей процедуры этапа 2 с сохранением сигнатуры.
CREATE OR REPLACE PROCEDURE proc_rentals_count_by_client(IN p_client_id integer, INOUT p_count integer)
LANGUAGE plpgsql AS $$
BEGIN
 SELECT fn_client_rental_count(p_client_id) INTO p_count;
END $$;

-- Демонстрационное представление с применением функции.
CREATE OR REPLACE VIEW v_rental_calculations AS
 SELECT r.rental_id,r.client_id,r.bicycle_id,r.started_at,r.finished_at,
        bike_rental.fn_billable_hours(r.started_at,r.finished_at) AS billable_hours,
        bike_rental.fn_rental_cost(r.started_at,r.finished_at,r.hourly_rate_at_start) AS estimated_cost
 FROM bike_rental.rentals r;
