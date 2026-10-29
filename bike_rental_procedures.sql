SET search_path TO bike_rental, public;

-- 1. Выборка клиентов по префиксу ФИО.
CREATE OR REPLACE PROCEDURE proc_clients_by_name(IN p_prefix text, INOUT p_result refcursor)
LANGUAGE plpgsql AS $$ BEGIN
 OPEN p_result FOR SELECT client_id,full_name,phone,email FROM clients
 WHERE full_name ILIKE coalesce(p_prefix,'') || '%' ORDER BY client_id;
END $$;
-- 2. Клиент по ID.
CREATE OR REPLACE PROCEDURE proc_clients_by_id(IN p_id integer, INOUT p_result refcursor)
LANGUAGE plpgsql AS $$ BEGIN
 OPEN p_result FOR SELECT * FROM clients WHERE client_id=p_id;
END $$;
-- 3. Все велосипеды по фильтру статуса (NULL = все).
CREATE OR REPLACE PROCEDURE proc_bicycles_by_status(IN p_status varchar, INOUT p_result refcursor)
LANGUAGE plpgsql AS $$ BEGIN
 OPEN p_result FOR SELECT bicycle_id, inventory_number,model,station_id,status FROM bicycles
 WHERE p_status IS NULL OR status=p_status ORDER BY bicycle_id;
END $$;
-- 4. Доступные велосипеды пункта (NULL = все пункты).
CREATE OR REPLACE PROCEDURE proc_bicycles_available(IN p_station_id integer, INOUT p_result refcursor)
LANGUAGE plpgsql AS $$ BEGIN
 OPEN p_result FOR SELECT b.bicycle_id,b.inventory_number,b.model,s.name AS station
 FROM bicycles b JOIN stations s ON s.station_id=b.station_id
 WHERE b.status='available' AND (p_station_id IS NULL OR b.station_id=p_station_id)
 AND NOT EXISTS(SELECT 1 FROM rentals r WHERE r.bicycle_id=b.bicycle_id AND r.status='active')
 ORDER BY b.bicycle_id;
END $$;
-- 5. Прокаты клиента.
CREATE OR REPLACE PROCEDURE proc_rentals_by_client(IN p_client_id integer, INOUT p_result refcursor)
LANGUAGE plpgsql AS $$ BEGIN
 OPEN p_result FOR SELECT rental_id,bicycle_id,started_at,finished_at,status,total_cost
 FROM rentals WHERE client_id=p_client_id ORDER BY started_at DESC;
END $$;
-- 6. Платежи по конкретному прокату.
CREATE OR REPLACE PROCEDURE proc_payments_by_rental(IN p_rental_id bigint, INOUT p_result refcursor)
LANGUAGE plpgsql AS $$ BEGIN
 OPEN p_result FOR SELECT payment_id,paid_at,amount,method,status
 FROM payments WHERE rental_id=p_rental_id ORDER BY paid_at;
END $$;

-- 7. Создание клиента; INOUT возвращает ID.
CREATE OR REPLACE PROCEDURE proc_clients_create(IN p_full_name varchar, IN p_phone varchar, INOUT p_client_id integer)
LANGUAGE plpgsql AS $$ BEGIN
 IF nullif(btrim(p_full_name),'') IS NULL OR nullif(btrim(p_phone),'') IS NULL THEN
  RAISE EXCEPTION 'Имя и телефон обязательны' USING ERRCODE='22023';
 END IF;
 INSERT INTO clients(full_name,phone) VALUES(p_full_name,p_phone)
 RETURNING client_id INTO p_client_id;
END $$;
-- 8. Изменить телефон клиента.
CREATE OR REPLACE PROCEDURE proc_clients_update_phone(IN p_client_id integer, IN p_phone varchar)
LANGUAGE plpgsql AS $$ BEGIN
 IF nullif(btrim(p_phone),'') IS NULL THEN RAISE EXCEPTION 'Телефон обязателен'; END IF;
 UPDATE clients SET phone=p_phone WHERE client_id=p_client_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Клиент % не найден',p_client_id; END IF;
END $$;
-- 9. Удалить клиента без прокатов (FK запрещает удалять связанного клиента).
CREATE OR REPLACE PROCEDURE proc_clients_delete(IN p_client_id integer)
LANGUAGE plpgsql AS $$ BEGIN
 IF EXISTS(SELECT 1 FROM rentals WHERE client_id=p_client_id) THEN
  RAISE EXCEPTION 'Нельзя удалить клиента с историей прокатов';
 END IF;
 DELETE FROM clients WHERE client_id=p_client_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Клиент % не найден',p_client_id; END IF;
END $$;
-- 10. Добавление велосипеда.
CREATE OR REPLACE PROCEDURE proc_bicycles_create(IN p_inventory varchar,IN p_model varchar,IN p_category_id integer,
 IN p_station_id integer,IN p_purchase_date date,INOUT p_bicycle_id integer)
LANGUAGE plpgsql AS $$ BEGIN
 IF nullif(btrim(p_inventory),'') IS NULL OR nullif(btrim(p_model),'') IS NULL THEN
 RAISE EXCEPTION 'Номер и модель обязательны'; END IF;
 INSERT INTO bicycles(inventory_number,model,category_id,station_id,purchase_date)
 VALUES(p_inventory,p_model,p_category_id,p_station_id,p_purchase_date)
 RETURNING bicycle_id INTO p_bicycle_id;
END $$;
-- 11. Изменение статуса велосипеда; запрещается вручную менять статус арендованного.
CREATE OR REPLACE PROCEDURE proc_bicycles_set_status(IN p_bicycle_id integer,IN p_status varchar)
LANGUAGE plpgsql AS $$ BEGIN
 IF p_status NOT IN ('available','maintenance','retired') THEN
  RAISE EXCEPTION 'Недопустимый ручной статус'; END IF;
 IF EXISTS(SELECT 1 FROM rentals WHERE bicycle_id=p_bicycle_id AND status='active') THEN
  RAISE EXCEPTION 'Велосипед сейчас находится в прокате'; END IF;
 UPDATE bicycles SET status=p_status WHERE bicycle_id=p_bicycle_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Велосипед % не найден',p_bicycle_id; END IF;
END $$;

-- 12. Многотабличная операция: начать аренду и занять велосипед.
-- EXCEPTION обеспечивает откат всех операций внутри блока при ошибке.
CREATE OR REPLACE PROCEDURE proc_rentals_start(IN p_client_id integer,IN p_bicycle_id integer,
 IN p_tariff_id integer,IN p_employee_id integer,INOUT p_rental_id bigint)
LANGUAGE plpgsql AS $$
DECLARE v_station integer; v_rate numeric(10,2); v_employee_station integer;
BEGIN
 SELECT station_id INTO v_station FROM bicycles WHERE bicycle_id=p_bicycle_id AND status='available' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Велосипед недоступен'; END IF;
 SELECT hourly_rate INTO v_rate FROM tariffs WHERE tariff_id=p_tariff_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Тариф не найден'; END IF;
 SELECT station_id INTO v_employee_station FROM employees WHERE employee_id=p_employee_id;
 IF NOT FOUND OR v_employee_station<>v_station THEN RAISE EXCEPTION 'Сотрудник не относится к пункту выдачи'; END IF;
 INSERT INTO rentals(client_id,bicycle_id,tariff_id,issued_by,start_station_id,started_at,hourly_rate_at_start,status)
 VALUES(p_client_id,p_bicycle_id,p_tariff_id,p_employee_id,v_station,clock_timestamp(),v_rate,'active')
 RETURNING rental_id INTO p_rental_id;
 UPDATE bicycles SET status='rented' WHERE bicycle_id=p_bicycle_id;
EXCEPTION WHEN OTHERS THEN
 RAISE EXCEPTION 'Ошибка начала проката: %',SQLERRM USING ERRCODE=SQLSTATE;
END $$;

-- 13. Многотабличная операция: завершить прокат, расчёт оплаты и возврат велосипеда.
CREATE OR REPLACE PROCEDURE proc_rentals_finish(IN p_rental_id bigint,IN p_end_station_id integer)
LANGUAGE plpgsql AS $$
DECLARE v_bicycle_id integer; v_started timestamp; v_rate numeric(10,2); v_total numeric(10,2);
BEGIN
 SELECT bicycle_id,started_at,hourly_rate_at_start INTO v_bicycle_id,v_started,v_rate
 FROM rentals WHERE rental_id=p_rental_id AND status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Активный прокат не найден'; END IF;
 IF NOT EXISTS(SELECT 1 FROM stations WHERE station_id=p_end_station_id) THEN
 RAISE EXCEPTION 'Пункт возврата не найден'; END IF;
 v_total:=greatest(1,ceil(extract(epoch FROM (clock_timestamp()-v_started))/3600)) * v_rate;
 UPDATE rentals SET finished_at=clock_timestamp(),end_station_id=p_end_station_id,
 total_cost=v_total,status='completed' WHERE rental_id=p_rental_id;
 UPDATE bicycles SET status='available',station_id=p_end_station_id WHERE bicycle_id=v_bicycle_id;
EXCEPTION WHEN OTHERS THEN
 RAISE EXCEPTION 'Ошибка завершения проката: %',SQLERRM USING ERRCODE=SQLSTATE;
END $$;

-- 14. Сколько всего прокатов у клиента (второй пример INOUT).
CREATE OR REPLACE PROCEDURE proc_rentals_count_by_client(IN p_client_id integer,INOUT p_count integer)
LANGUAGE plpgsql AS $$ BEGIN
 SELECT count(*)::integer INTO p_count FROM rentals WHERE client_id=p_client_id;
END $$;
-- 15. Оплата завершённого проката.
CREATE OR REPLACE PROCEDURE proc_payments_create(IN p_rental_id bigint,IN p_amount numeric,
 IN p_method varchar,INOUT p_payment_id bigint)
LANGUAGE plpgsql AS $$ BEGIN
 IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'Сумма должна быть положительной'; END IF;
 IF NOT EXISTS(SELECT 1 FROM rentals WHERE rental_id=p_rental_id AND status='completed') THEN
  RAISE EXCEPTION 'Для оплаты требуется завершённый прокат'; END IF;
 INSERT INTO payments(rental_id,amount,method) VALUES(p_rental_id,p_amount,p_method)
 RETURNING payment_id INTO p_payment_id;
END $$;

-- 16. Отчёт: выручка по дням (через refcursor).
CREATE OR REPLACE PROCEDURE proc_report_revenue(IN p_from date,IN p_to date,INOUT p_result refcursor)
LANGUAGE plpgsql AS $$ BEGIN
 IF p_from IS NULL OR p_to IS NULL OR p_from>p_to THEN RAISE EXCEPTION 'Некорректный период'; END IF;
 OPEN p_result FOR
 SELECT p.paid_at::date AS day,count(*) AS payments_count,sum(CASE WHEN p.status='paid' THEN p.amount ELSE -p.amount END) AS net_revenue
 FROM payments p JOIN rentals r ON r.rental_id=p.rental_id
 WHERE p.paid_at::date BETWEEN p_from AND p_to GROUP BY p.paid_at::date ORDER BY day;
END $$;
-- 17. Отчёт: популярность велосипедов.
CREATE OR REPLACE PROCEDURE proc_report_bicycle_usage(IN p_from date,IN p_to date,INOUT p_result refcursor)
LANGUAGE plpgsql AS $$ BEGIN
 IF p_from IS NULL OR p_to IS NULL OR p_from>p_to THEN RAISE EXCEPTION 'Некорректный период'; END IF;
 OPEN p_result FOR
 SELECT b.bicycle_id,b.inventory_number,b.model,count(r.rental_id) AS rentals_count,
 coalesce(sum(r.total_cost) FILTER(WHERE r.status='completed'),0) AS billed_total
 FROM bicycles b LEFT JOIN rentals r ON r.bicycle_id=b.bicycle_id AND r.started_at::date BETWEEN p_from AND p_to
 GROUP BY b.bicycle_id,b.inventory_number,b.model ORDER BY rentals_count DESC,b.bicycle_id;
END $$;
