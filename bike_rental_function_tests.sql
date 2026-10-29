-- Запуск после этапов 1–3. Эти запросы демонстрационные; результаты зависят от тестовых данных.
SET search_path TO bike_rental, public;
-- Скалярные: известные эталонные результаты
SELECT fn_rate_with_markup(100,20) AS expected_120;
SELECT fn_rate_with_markup(NULL,20) IS NULL AS expected_true;
SELECT fn_billable_hours('2026-10-01 10:00','2026-10-01 11:30') AS expected_2;
SELECT fn_rental_cost('2026-10-01 10:00','2026-10-01 11:30',150) AS expected_300;
SELECT fn_billable_hours(NULL,now()::timestamp) IS NULL AS expected_true;
-- Использование в SELECT, WHERE, ORDER BY
SELECT rental_id,fn_rental_cost(started_at,finished_at,hourly_rate_at_start) AS calculated_cost
FROM rentals ORDER BY calculated_cost NULLS LAST;
SELECT rental_id FROM rentals WHERE fn_billable_hours(started_at,finished_at) >= 2;
-- Табличные функции в JOIN, подзапросах
SELECT c.full_name, t.rental_id,t.status FROM clients c
JOIN LATERAL fn_client_rentals(c.client_id, DATE '2026-01-01', DATE '2027-12-31') t ON TRUE;
SELECT s.name, a.bicycle_id,a.model FROM stations s
JOIN LATERAL fn_available_bicycles(s.station_id) a ON TRUE;
SELECT * FROM fn_client_rentals(1,DATE '2035-01-01',DATE '2035-12-31'); -- пустой период
SELECT * FROM fn_station_load(80);
SELECT fn_client_rental_count(1);
SELECT * FROM v_rental_calculations LIMIT 10;
-- Процедура с INOUT: требуется передать NULL (pgAdmin / psql).
CALL proc_rentals_count_by_client(1, NULL);
-- Отрицательный тест выполнить отдельно: ожидаем SQLSTATE 22023.
-- SELECT * FROM fn_station_load(120);
-- Производительность: сравнение планов без неподтверждённых цифр.
EXPLAIN (ANALYZE, BUFFERS) SELECT fn_client_rental_count(client_id) FROM clients;
EXPLAIN (ANALYZE, BUFFERS) SELECT client_id, count(*) FROM rentals GROUP BY client_id;
