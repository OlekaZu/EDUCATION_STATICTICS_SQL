-- Процедура добавления P2P проверки
CREATE OR REPLACE FUNCTION func_find_check_in_p2p (checked_peer varchar,
    checking_peer varchar, task_name varchar)
    RETURNS TABLE (found_check_id bigint, found_check_time time ) AS $$
    BEGIN
    RETURN QUERY SELECT "P2P"."Check", "P2P"."Time"
                FROM "P2P" JOIN "Checks" ON "P2P"."Check" = "Checks"."ID"
                AND "State" = 'Start' AND "CheckingPeer" = checking_peer
                AND "Task" = task_name AND "Peer" = checked_peer
                ORDER BY "P2P"."ID" DESC LIMIT 1;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE add_p2p (checked_peer varchar, checking_peer varchar,
task_name varchar, status check_status, check_time time) AS $$
    BEGIN
        IF(status = 'Start') THEN
            INSERT INTO "Checks"
            VALUES ((SELECT MAX("ID") + 1 FROM "Checks"),
                     checked_peer, task_name, current_date);
            INSERT INTO "P2P"
            VALUES ((SELECT MAX("ID") + 1 FROM "P2P"),
                    (SELECT MAX("ID") FROM "Checks"), checking_peer,
                    status, check_time);
        ELSE
            IF(check_time > (SELECT found_check_time
                             FROM func_find_check_in_p2p(checked_peer,
                                 checking_peer, task_name))) THEN
            INSERT INTO "P2P"
            VALUES ((SELECT MAX("ID") + 1 FROM "P2P"),
                    (SELECT found_check_id FROM func_find_check_in_p2p(checked_peer,
                        checking_peer, task_name)),
                    checking_peer, status, check_time);
            ELSE
                RAISE EXCEPTION 'The time of check finish is earlier than check start %', check_time
                USING HINT = 'Check input time parameter';
            END IF;
        END IF;
    END
$$ LANGUAGE plpgsql;

-- Процедура добавления Вертер проверки
CREATE OR REPLACE FUNCTION func_find_check_in_verter (checked_peer varchar, task_name varchar)
    RETURNS TABLE (found_check_id bigint, found_check_time time ) AS $$
    BEGIN
    RETURN QUERY SELECT "Verter"."Check", "Verter"."Time"
                FROM "Verter" JOIN "Checks" ON "Verter"."Check" = "Checks"."ID"
                AND "State" = 'Start' AND "Task" = task_name AND "Peer" = checked_peer
                ORDER BY "Verter"."ID" DESC LIMIT 1;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE add_verter(checked_peer varchar, task_name varchar,
status check_status, check_time time) AS $$
    BEGIN
        IF (task_name NOT LIKE 'C_\_%') THEN
            RAISE EXCEPTION 'The Verter checking stage is not requiered for this task: %', task_name;
        ELSIF(status = 'Start') THEN
            INSERT INTO "Verter"
            VALUES ((SELECT MAX("ID") + 1 FROM "Verter"),
            (SELECT "Check" FROM "P2P" JOIN "Checks" ON "P2P"."Check" = "Checks"."ID"
                AND "Peer" = checked_peer AND "Task" = task_name
                ORDER BY "P2P"."ID" DESC LIMIT 1), status, check_time);
        ELSE
            IF(check_time > (SELECT found_check_time
                             FROM func_find_check_in_verter(checked_peer,
                                 task_name))) THEN
            INSERT INTO "Verter"
            VALUES ((SELECT MAX("ID") + 1 FROM "Verter"),
            (SELECT found_check_id FROM func_find_check_in_verter(checked_peer,
                                 task_name)), status, check_time);
             ELSE
                RAISE EXCEPTION 'The time of check finish is earlier than check start %', check_time
                USING HINT = 'Check input time parameter';
            END IF;
        END IF;
    END
$$ LANGUAGE plpgsql;

-- Триггер-функция: после добавления записи в P2P "Start" - обновить TransferringPoints
CREATE OR REPLACE FUNCTION fnc_trg_add_points() RETURNS TRIGGER AS $add_points$
    BEGIN
      UPDATE "TransferredPoints"
      SET "PointsAmount" = "PointsAmount" + 1
      WHERE "CheckingPeer" = NEW."CheckingPeer" AND "CheckedPeer" =
          (SELECT "Peer" FROM "Checks" JOIN "P2P" P ON "Checks"."ID" = P."Check"
            WHERE P."Check" = NEW."Check");
     RETURN NULL;
    END;
$add_points$ LANGUAGE plpgsql;
--trigger on p2p insert (Start check)
CREATE OR REPLACE TRIGGER trg_add_points
AFTER INSERT ON "P2P"
   FOR EACH ROW WHEN (NEW."State" = 'Start')
        EXECUTE FUNCTION fnc_trg_add_points();

-- Триггер-функция перед добавлением записи в XP - проверить сданы ли задания успешно.
CREATE OR REPLACE FUNCTION fnc_trg_insert_xp()  RETURNS TRIGGER AS $insert_xp$
    BEGIN
        IF (func_for_creation_XP_Check(NEW."Check") = true
            AND func_for_creation_XP_Amount(NEW."Check",
                NEW."XPAmount") = true)
        THEN
            RETURN NEW;
        ELSE
             RAISE EXCEPTION 'The task is not completed successfully or xp_amount is exceeded max_amount';
        END IF;
    END
$insert_xp$ LANGUAGE plpgsql;
--trigger on XP insert
CREATE OR REPLACE TRIGGER trg_insert_xp
BEFORE INSERT ON "XP"
   FOR EACH ROW EXECUTE FUNCTION fnc_trg_insert_xp();

-- !!! TESTING !!!
-- Testing add_p2p and fnc_trg_add_points
-- will be added (point is added)
CALL add_p2p('karving', 'electroux',
    'CPP2_s21_containers', 'Start','12:30' );
-- will be added
CALL add_p2p('karving', 'electroux',
    'CPP2_s21_containers', 'Success','13:00' );
-- will be added (point is added)
CALL add_p2p('patison', 'brolyx',
    'C5_s21_Decimal', 'Start','17:25' );
-- won't be added(Time finish is earlier than start)
CALL add_p2p('patison', 'brolyx',
    'C5_s21_Decimal', 'Failure','16:50' );
-- will be added
CALL add_p2p('patison', 'brolyx',
    'C5_s21_Decimal', 'Failure','17:50' );
-- will be added (point is added)
CALL add_p2p('alabile', 'karving',
    'C7_SmartCalc_v1.0', 'Start','10:00' );
-- will be added
CALL add_p2p('alabile', 'karving',
    'C7_SmartCalc_v1.0', 'Success','10:30' );
-- add p2p for karving(missing the second check)
CALL add_p2p('karving', 'acadi',
    'CPP1_s21_matrix+', 'Success', '12:00');


-- Testing add_verter
-- won't be added(Verter is absent for this task)
CALL add_verter('karving',
    'CPP2_s21_containers', 'Start','13:01' );
-- won't be added (Not success in p2p)
CALL add_verter('patison',
    'C5_s21_Decimal', 'Start','17:51' );
-- will be added
CALL add_verter('alabile',
    'C7_SmartCalc_v1.0', 'Start','10:31' );
-- won't be added (Time finish is earlier than start)
CALL add_verter('alabile',
    'C7_SmartCalc_v1.0', 'Success','10:30' );
-- will be added
CALL add_verter('alabile',
    'C7_SmartCalc_v1.0', 'Success','10:35' );

-- Testing fnc_trg_insert_xp
-- won't be added (max_amount is exceeded)
INSERT INTO "XP" VALUES ((SELECT MAX("ID") + 1 FROM "XP"), 40, 600);
-- will be added (p2p and verter success)
INSERT INTO "XP" VALUES ((SELECT MAX("ID") + 1 FROM "XP"), 40, 500);
-- will be added (only p2p success, amount is less)
INSERT INTO "XP" VALUES ((SELECT MAX("ID") + 1 FROM "XP"), 38, 335);
-- will be added (only p2p success)
INSERT INTO "XP" VALUES ((SELECT MAX("ID") + 1 FROM "XP"), 4, 300);
-- won't be added (p2p failure)
INSERT INTO "XP" VALUES ((SELECT MAX("ID") + 1 FROM "XP"), 39, 350);


DELETE FROM "Verter" WHERE "ID" IN (18, 19);
DELETE FROM "P2P" WHERE "ID" IN (74, 75, 76, 77, 78, 79, 80);
DELETE FROM "XP" WHERE "ID" IN (31, 32, 33);
DELETE FROM "Checks" WHERE "ID" IN (38, 39, 40);
