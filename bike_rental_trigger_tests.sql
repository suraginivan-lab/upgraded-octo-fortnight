-- Тесты запускать ПОСЛЕ bike_rental_triggers.sql.
-- Все изменения из тестов откатываются. pgAdmin: выполнить скрипт целиком.
SET search_path TO bike_rental, public;
BEGIN;
-- Положительный кейс: многострочный UPDATE -> по одной записи аудита на строку.
-- Сохранённая точка позволяет откатить только выбранный сценарий.
SAVEPOINT audit_update;
UPDATE bike_rental.bicycles SET model=model || ' [тест]'
WHERE bicycle_id IN (SELECT bicycle_id FROM bike_rental.bicycles ORDER BY bicycle_id LIMIT 2);
SELECT operation, row_key, old_data->>'model' AS old_model,
       new_data->>'model' AS new_model
FROM bike_rental.audit_changes WHERE table_name='bicycles' AND operation='UPDATE'
ORDER BY audit_id DESC LIMIT 5;
ROLLBACK TO SAVEPOINT audit_update;

-- INSERT и DELETE с многострочной обработкой в одной транзакции.
-- Берём существующие FK-значения; тест пропускается, если справочники пусты.
SAVEPOINT audit_insert_delete;
DO $$
DECLARE v_cat integer; v_station integer;
BEGIN
 SELECT category_id INTO v_cat FROM bike_rental.categories LIMIT 1;
 SELECT station_id INTO v_station FROM bike_rental.stations LIMIT 1;
 IF v_cat IS NULL OR v_station IS NULL THEN
    RAISE NOTICE 'Для INSERT/DELETE нужны хотя бы одна категория и станция'; RETURN;
 END IF;
 INSERT INTO bike_rental.bicycles(inventory_number,model,category_id,station_id,status,purchase_date)
 VALUES ('ST4-TEST-001','Тест 1',v_cat,v_station,'available',CURRENT_DATE),
        ('ST4-TEST-002','Тест 2',v_cat,v_station,'available',CURRENT_DATE);
 DELETE FROM bike_rental.bicycles WHERE inventory_number IN ('ST4-TEST-001','ST4-TEST-002');
END $$;
SELECT operation,count(*) FROM bike_rental.audit_changes
WHERE COALESCE(new_data->>'inventory_number',old_data->>'inventory_number') LIKE 'ST4-TEST-%'
GROUP BY operation ORDER BY operation; -- ожидаются INSERT=2, DELETE=2
ROLLBACK TO SAVEPOINT audit_insert_delete;

-- Негативный сценарий: запрет новой аренды велосипеда в статусе maintenance.
-- Тест ловит ожидаемую ошибку; изменения от теста не сохраняются.
DO $$
DECLARE v_b integer; v_client integer; v_tariff integer; v_employee integer; v_station integer; v_rate numeric;
BEGIN
 SELECT bicycle_id,station_id INTO v_b,v_station FROM bike_rental.bicycles
 WHERE NOT EXISTS(SELECT 1 FROM bike_rental.rentals r WHERE r.bicycle_id=bicycles.bicycle_id AND r.status='active')
 LIMIT 1;
 SELECT client_id INTO v_client FROM bike_rental.clients LIMIT 1;
 SELECT tariff_id,hourly_rate INTO v_tariff,v_rate FROM bike_rental.tariffs LIMIT 1;
 SELECT employee_id INTO v_employee FROM bike_rental.employees LIMIT 1;
 IF v_b IS NULL OR v_client IS NULL OR v_tariff IS NULL OR v_employee IS NULL THEN
   RAISE NOTICE 'Недостаточно справочных записей для негативного теста'; RETURN;
 END IF;
 UPDATE bike_rental.bicycles SET status='maintenance' WHERE bicycle_id=v_b;
 BEGIN
   INSERT INTO bike_rental.rentals(client_id,bicycle_id,tariff_id,issued_by,start_station_id,
       started_at,hourly_rate_at_start,status)
   VALUES (v_client,v_b,v_tariff,v_employee,v_station,clock_timestamp()::timestamp,v_rate,'active');
   RAISE EXCEPTION 'ОШИБКА ТЕСТА: аренда недоступного велосипеда разрешена';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
   IF SQLERRM LIKE 'Нельзя выдать велосипед %' THEN
     RAISE NOTICE 'OK: запрет выдачи сработал: %',SQLERRM;
   ELSE RAISE; END IF;
 END;
END $$;

-- INSTEAD OF DELETE: строка остаётся, статус становится retired.
SAVEPOINT soft_delete;
DELETE FROM bike_rental.v_bicycle_archive WHERE bicycle_id IN
 (SELECT b.bicycle_id FROM bike_rental.bicycles b
  WHERE NOT EXISTS (SELECT 1 FROM bike_rental.rentals r
                    WHERE r.bicycle_id=b.bicycle_id AND r.status='active') LIMIT 2);
SELECT bicycle_id,status FROM bike_rental.bicycles WHERE status='retired' ORDER BY bicycle_id LIMIT 10;
ROLLBACK TO SAVEPOINT soft_delete;

ROLLBACK; -- тестовые изменения не сохраняются; исходные данные неизменны.
