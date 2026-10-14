-- Запускать однократно после 01_schema.sql в базе bike_rental_db.
BEGIN;
SET search_path TO bike_rental, public;
INSERT INTO stations(name,address,capacity) VALUES
 ('Парк Горького','Москва, Крымский Вал, 9',40),('ВДНХ','Москва, проспект Мира, 119',50),
 ('Сокольники','Москва, Сокольнический Вал, 1',35),('Измайлово','Москва, аллея Большого Круга, 7',30),
 ('Лужники','Москва, Лужнецкая наб., 24',45);
INSERT INTO categories(name,description) VALUES
 ('Городской','Для спокойных поездок'),('Горный','Для грунтовых маршрутов'),
 ('Шоссейный','Для асфальтовых дорог'),('Электровелосипед','С электрическим ассистентом'),
 ('Детский','Для детей');
INSERT INTO tariffs(name,hourly_rate,deposit) VALUES
 ('Базовый',200,1000),('Стандарт',250,1000),('Спорт',300,1500),
 ('Электро',450,3000),('Детский',150,500);
INSERT INTO clients(full_name,phone,email,registered_at)
 SELECT 'Клиент '||lpad(g::text,2,'0'), '+7900000'||lpad(g::text,4,'0'),
        'client'||g||'@example.test', DATE '2026-08-01' + g
 FROM generate_series(1,10) AS g;
INSERT INTO employees(full_name,position,station_id) VALUES
 ('Алексей Иванов','Администратор',1),('Мария Петрова','Администратор',2),
 ('Олег Сидоров','Механик',3),('Анна Смирнова','Администратор',4),
 ('Игорь Кузнецов','Механик',5);
INSERT INTO bicycles(inventory_number,model,category_id,station_id,status,purchase_date)
 SELECT 'BIKE-'||lpad(g::text,3,'0'), 'Модель '||g,
        ((g-1)%5)+1, ((g-1)%5)+1, 'available',DATE '2025-05-01'+g
 FROM generate_series(1,30) AS g;
-- 25 завершённых аренд с зафиксированной ставкой и суммой за 2 часа.
INSERT INTO rentals(client_id,bicycle_id,tariff_id,issued_by,start_station_id,
 end_station_id,started_at,finished_at,hourly_rate_at_start,total_cost,status)
SELECT ((g-1)%10)+1,g,((g-1)%5)+1,((g-1)%5)+1,((g-1)%5)+1,
       ((g-1)%5)+1,
       TIMESTAMP '2026-09-01 10:00:00' + (g-1)*INTERVAL '1 day',
       TIMESTAMP '2026-09-01 12:00:00' + (g-1)*INTERVAL '1 day',
       (ARRAY[200,250,300,450,150]::numeric[])[((g-1)%5)+1],
       2*(ARRAY[200,250,300,450,150]::numeric[])[((g-1)%5)+1],
       'completed'
FROM generate_series(1,25) AS g;
INSERT INTO payments(rental_id,paid_at,amount,method,status)
 SELECT rental_id,finished_at + INTERVAL '5 minutes',total_cost,
        CASE rental_id%3 WHEN 0 THEN 'cash' WHEN 1 THEN 'card' ELSE 'transfer' END,'paid'
 FROM rentals;
INSERT INTO maintenance(bicycle_id,employee_id,serviced_at,description,cost)
 SELECT g,CASE WHEN g%2=0 THEN 3 ELSE 5 END, DATE '2026-08-01'+g,
        'Плановый осмотр и настройка тормозов',100+g*10
 FROM generate_series(1,20) AS g;
COMMIT;
