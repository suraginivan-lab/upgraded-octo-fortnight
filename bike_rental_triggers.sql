-- PostgreSQL 16.
SET search_path TO bike_rental, public;

CREATE TABLE IF NOT EXISTS bike_rental.audit_changes (
 audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 table_name text NOT NULL,
 operation text NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
 row_key text NOT NULL,
 old_data jsonb,
 new_data jsonb,
 changed_by text NOT NULL DEFAULT current_user,
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS ix_audit_changes_table_time ON bike_rental.audit_changes(table_name,changed_at DESC);

CREATE OR REPLACE FUNCTION bike_rental.trg_bicycles_audit_insert_fn()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO bike_rental.audit_changes(table_name,operation,row_key,new_data)
 SELECT 'bicycles','INSERT',n.bicycle_id::text,to_jsonb(n)
 FROM new_rows AS n;
 RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION bike_rental.trg_bicycles_audit_update_fn()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO bike_rental.audit_changes(table_name,operation,row_key,old_data,new_data)
 SELECT 'bicycles','UPDATE',n.bicycle_id::text,to_jsonb(o),to_jsonb(n)
 FROM new_rows AS n JOIN old_rows AS o USING(bicycle_id)
 WHERE to_jsonb(o) IS DISTINCT FROM to_jsonb(n);
 RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION bike_rental.trg_bicycles_audit_delete_fn()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO bike_rental.audit_changes(table_name,operation,row_key,old_data)
 SELECT 'bicycles','DELETE',o.bicycle_id::text,to_jsonb(o)
 FROM old_rows AS o;
 RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_bicycles_audit_insert ON bike_rental.bicycles;
CREATE TRIGGER trg_bicycles_audit_insert
 AFTER INSERT ON bike_rental.bicycles REFERENCING NEW TABLE AS new_rows
 FOR EACH STATEMENT EXECUTE FUNCTION bike_rental.trg_bicycles_audit_insert_fn();
DROP TRIGGER IF EXISTS trg_bicycles_audit_update ON bike_rental.bicycles;
CREATE TRIGGER trg_bicycles_audit_update
 AFTER UPDATE ON bike_rental.bicycles REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
 FOR EACH STATEMENT EXECUTE FUNCTION bike_rental.trg_bicycles_audit_update_fn();
DROP TRIGGER IF EXISTS trg_bicycles_audit_delete ON bike_rental.bicycles;
CREATE TRIGGER trg_bicycles_audit_delete
 AFTER DELETE ON bike_rental.bicycles REFERENCING OLD TABLE AS old_rows
 FOR EACH STATEMENT EXECUTE FUNCTION bike_rental.trg_bicycles_audit_delete_fn();

-- Контроль бизнес-правила: нельзя открыть активную аренду велосипеда,
-- который недоступен (maintenance/rented/retired). CHECK не может обратиться к другой таблице.
-- FOR UPDATE сериализует конкурирующие выдачи одного велосипеда.
CREATE OR REPLACE FUNCTION bike_rental.trg_rentals_check_availability_fn()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status varchar(20);
BEGIN
 IF NEW.status = 'active' THEN
  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND
      (OLD.status IS DISTINCT FROM 'active' OR NEW.bicycle_id IS DISTINCT FROM OLD.bicycle_id)) THEN
   SELECT status INTO v_status FROM bike_rental.bicycles
   WHERE bicycle_id=NEW.bicycle_id FOR UPDATE;
   IF NOT FOUND THEN
     RAISE EXCEPTION 'Велосипед с id % не найден', NEW.bicycle_id USING ERRCODE='23503';
   END IF;
   IF v_status <> 'available' THEN
     RAISE EXCEPTION 'Нельзя выдать велосипед %, текущий статус: %', NEW.bicycle_id,v_status
       USING ERRCODE='P0001';
   END IF;
  END IF;
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_rentals_check_availability ON bike_rental.rentals;
CREATE TRIGGER trg_rentals_check_availability
 BEFORE INSERT OR UPDATE ON bike_rental.rentals
 FOR EACH ROW EXECUTE FUNCTION bike_rental.trg_rentals_check_availability_fn();

-- INSTEAD OF допустим на VIEW, а не на обычной таблице PostgreSQL.
-- DELETE по представлению означает логическое удаление: status='retired'.
CREATE OR REPLACE VIEW bike_rental.v_bicycle_archive AS
 SELECT bicycle_id, inventory_number, model, category_id, station_id, status, purchase_date
 FROM bike_rental.bicycles;
CREATE OR REPLACE FUNCTION bike_rental.trg_bicycle_soft_delete_fn()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM bike_rental.rentals
           WHERE bicycle_id=OLD.bicycle_id AND status='active') THEN
   RAISE EXCEPTION 'Нельзя архивировать велосипед % с активной арендой',OLD.bicycle_id
      USING ERRCODE='P0001';
 END IF;
 UPDATE bike_rental.bicycles SET status='retired' WHERE bicycle_id=OLD.bicycle_id;
 RETURN OLD;
END $$;
DROP TRIGGER IF EXISTS trg_bicycle_soft_delete ON bike_rental.v_bicycle_archive;
CREATE TRIGGER trg_bicycle_soft_delete
 INSTEAD OF DELETE ON bike_rental.v_bicycle_archive
 FOR EACH ROW EXECUTE FUNCTION bike_rental.trg_bicycle_soft_delete_fn();

-- Контроль перечня объектов:
-- SELECT event_object_table, trigger_name, action_timing
-- FROM information_schema.triggers WHERE trigger_schema='bike_rental';
