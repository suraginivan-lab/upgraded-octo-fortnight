-- Проверки
-- Выборки через курсоры
BEGIN;
CALL bike_rental.proc_clients_by_name('Иван','cur_clients');
FETCH ALL FROM cur_clients;
CALL bike_rental.proc_clients_by_id(1,'cur_client');
FETCH ALL FROM cur_client;
CALL bike_rental.proc_bicycles_by_status('available','cur_bikes');
FETCH ALL FROM cur_bikes;
CALL bike_rental.proc_bicycles_available(NULL,'cur_available');
FETCH ALL FROM cur_available;
CALL bike_rental.proc_rentals_by_client(1,'cur_rentals');
FETCH ALL FROM cur_rentals;
CALL bike_rental.proc_payments_by_rental(1,'cur_payments');
FETCH ALL FROM cur_payments;
CALL bike_rental.proc_report_revenue(DATE '2026-01-01',DATE '2026-12-31','cur_revenue');
FETCH ALL FROM cur_revenue;
CALL bike_rental.proc_report_bicycle_usage(DATE '2026-01-01',DATE '2026-12-31','cur_usage');
FETCH ALL FROM cur_usage;
COMMIT;
-- Проверка OUT/INOUT подсчёта:
CALL bike_rental.proc_rentals_count_by_client(1,NULL);
-- Изолированные проверки создания: ROLLBACK оставляет исходные данные без изменений.
BEGIN;
CALL bike_rental.proc_clients_create('Тестовый Клиент','+79990001234',NULL);
-- Подставьте возвращённый client_id из результата CALL:
-- CALL bike_rental.proc_clients_update_phone(<client_id>, '+79990001235');
-- CALL bike_rental.proc_clients_delete(<client_id>);
ROLLBACK;
-- В ручных тестах проверьте proc_bicycles_create, proc_bicycles_set_status,
-- proc_rentals_start, proc_rentals_finish, proc_payments_create на существующих ID.
-- Запускайте в отдельной транзакции, завершайте ROLLBACK.
-- Негативные сценарии (выполняйте по одному, вне общей транзакции, чтобы ошибка не остановила остальные):
-- CALL bike_rental.proc_clients_create('', '+79990001234', NULL); -- ошибка валидации
-- CALL bike_rental.proc_rentals_start(999999,999999,1,1,NULL); -- велосипед недоступен
-- CALL bike_rental.proc_report_revenue(DATE '2026-12-31',DATE '2026-01-01','bad'); -- неверный период
-- CALL bike_rental.proc_payments_create(999999,100,'card',NULL); -- аренда не завершена
