CREATE TABLE "Tasks" (
    "Title" varchar primary key,
    "ParentTask" varchar default NULL,
    "MaxXP" bigint default NULL,
    constraint ch_Title check ("Title" LIKE 'C_\_%' OR "Title" LIKE 'CPP_\_%'
                                   OR "Title" LIKE 'A_\_%' OR "Title" LIKE 'DO_\_%'
                                   OR "Title" LIKE'SQL_\_%'),
    constraint ch_ParentTask check ("ParentTask" LIKE 'C_\_%' OR "ParentTask" LIKE 'CPP_\_%'
                                   OR "ParentTask" LIKE 'A_\_%' OR "ParentTask" LIKE 'DO_\_%'
                                   OR "ParentTask" LIKE'SQL_\_%' OR "ParentTask" IS NULL )
);

CREATE TYPE check_status AS ENUM ('Start', 'Success', 'Failure');

CREATE TABLE "Checks" (
    "ID" bigint primary key,
    "Peer" varchar NOT NULL,
    "Task" varchar NOT NULL,
    "Date" date,
    constraint uk_Checks unique ("Peer", "Task", "Date"),
    constraint fk_Checks_Peer foreign key ("Peer") references "Peers"("Nickname") ON DELETE CASCADE,
    constraint fk_Checks_Task foreign key ("Task") references "Tasks"("Title") ON DELETE CASCADE
);

CREATE TABLE "P2P" (
    "ID" bigint primary key,
    "Check" bigint NOT NULL,
    "CheckingPeer" varchar NOT NULL,
    "State" check_status,
    "Time" time,
    constraint uk_P2P unique ("Check", "CheckingPeer", "State", "Time"),
    constraint fk_P2P_Check foreign key ("Check") references "Checks"("ID") ON DELETE CASCADE,
    constraint fk_P2P_CheckingPeer foreign key ("CheckingPeer") references "Peers"("Nickname") ON DELETE CASCADE
);

CREATE FUNCTION func_for_creation_Verter(pCheck bigint)
    RETURNS boolean AS $$
    SELECT $1 IN (SELECT "Check" FROM "P2P" WHERE "State" = 'Success');
    $$ LANGUAGE sql;

CREATE TABLE "Verter" (
    "ID" bigint primary key,
    "Check" bigint NOT NULL,
    "State" check_status,
    "Time" time,
    constraint uk_Verter unique ("Check", "State", "Time"),
    constraint fk_Verter_Check foreign key ("Check") references "Checks"("ID") ON DELETE CASCADE,
    constraint ch_Check check (func_for_creation_Verter(pCheck := "Check") = true)
);

CREATE TABLE "TransferredPoints" (
    "ID" bigint primary key,
    "CheckingPeer" varchar NOT NULL,
    "CheckedPeer" varchar NOT NULL,
    "PointsAmount" bigint DEFAULT 0,
    constraint fk_TransferredPoints_CheckingPeer foreign key ("CheckingPeer") references "Peers"("Nickname") ON DELETE CASCADE,
    constraint fk_TransferredPoints_CheckedPeer foreign key ("CheckedPeer") references "Peers"("Nickname") ON DELETE CASCADE
);

CREATE TABLE "Friends" (
    "ID" bigint primary key,
    "Peer1" varchar NOT NULL,
    "Peer2" varchar NOT NULL,
    constraint fk_Friends_CheckingPeer foreign key ("Peer1") references "Peers"("Nickname") ON DELETE CASCADE,
    constraint fk_Friends_CheckedPeer foreign key ("Peer2") references "Peers"("Nickname") ON DELETE CASCADE
);

CREATE TABLE "Recommendations" (
    "ID" bigint  primary key,
    "Peer" varchar NOT NULL,
    "RecommendedPeer" varchar NOT NULL,
    constraint fk_Friends_Peer foreign key ("Peer") references "Peers"("Nickname") ON DELETE CASCADE,
    constraint fk_Friends_RecommendedPeer foreign key ("RecommendedPeer") references "Peers"("Nickname") ON DELETE CASCADE
);

CREATE FUNCTION func_for_creation_XP_Check(pCheck bigint)
    RETURNS boolean AS $$
    SELECT $1 IN  (SELECT "Checks"."ID"
       FROM "Checks" JOIN "P2P" ON "Checks"."ID" = "P2P"."Check" AND "P2P"."State" = 'Success'
        LEFT JOIN "Verter" ON "P2P"."Check" = "Verter"."Check"
        AND "Verter"."State" != 'Start'
       WHERE "Verter"."State" = 'Success' OR "Verter"."State" IS NULL);
    $$ LANGUAGE sql;

CREATE FUNCTION func_for_creation_XP_Amount(pCheck bigint, pAmount bigint)
    RETURNS boolean AS $$
    SELECT $2 <=
    (SELECT "MaxXP" FROM "Checks" JOIN "Tasks" ON "Checks"."Task" = "Tasks"."Title"
     WHERE $1 = "Checks"."ID");
    $$ LANGUAGE sql;

CREATE TABLE "XP" (
    "ID" bigint primary key,
    "Check" bigint NOT NULL,
    "XPAmount" bigint NOT NULL,
    constraint fk_XP_Check foreign key ("Check") references "Checks"("ID") ON DELETE CASCADE,
    constraint ch_Check check (func_for_creation_XP_Check(pCheck := "Check") = true),
    constraint ch_XPAmount check (func_for_creation_XP_Amount(pCheck := "Check", pAmount := "XP"."XPAmount") = true),
    constraint uk_XP unique ("Check", "XPAmount")
);

CREATE TABLE "TimeTracking" (
    "ID" bigint primary key,
    "Peer" varchar NOT NULL,
    "Date" date,
    "Time" time,
    "State" int,
    constraint fk_TimeTracking_Peer foreign key ("Peer") references "Peers"("Nickname") ON DELETE CASCADE,
    constraint ch_State check ("State" IN (1, 2))
);

-- !!! Дополнительно. Проверка перед вставкой в таблицу TimeTracking
CREATE FUNCTION func_for_creation_TimeTracking(pState int, pDate date, pTime time, pPeer varchar)
    RETURNS boolean AS $$
    DECLARE
    result boolean;
    count_row int;
    arrivе_time time;
    departure_time time;
    BEGIN
    count_row := (SELECT COUNT(*) FROM "TimeTracking" tt
    WHERE tt."Peer" = pPeer AND tt."Date" = pDate);
    arrivе_time := (SELECT "Time" FROM "TimeTracking" tt
             WHERE  tt."Peer" = pPeer AND tt."Date" = pDate AND tt."State" = 1
             ORDER BY 1 DESC LIMIT 1);
    departure_time := (SELECT "Time" FROM "TimeTracking" tt
             WHERE  tt."Peer" = pPeer AND tt."Date" = pDate AND tt."State" = 2
             ORDER BY 1 DESC LIMIT 1);
        CASE
        WHEN $1 = 1 THEN
            result := (count_row % 2) = 0
             AND (pTime > departure_time OR departure_time IS NULL);
        ELSE
            result := ((count_row % 2) % 2) != 0 AND pTime > arrivе_time;
        END CASE;
    RETURN result;
    END
    $$ LANGUAGE plpgsql;

-- trigger function for time tracking
CREATE OR REPLACE FUNCTION fnc_trg_insert_tt()  RETURNS TRIGGER AS $insert_tt$
    BEGIN
        IF (func_for_creation_TimeTracking(NEW."State", NEW."Date",
        NEW."Time", NEW."Peer") = true)
        THEN
            RETURN NEW;
        ELSE
             RAISE EXCEPTION 'Wrong order of adding time';
        END IF;
    END
$insert_tt$ LANGUAGE plpgsql;

--trigger on time_tracking  insert
CREATE OR REPLACE TRIGGER trg_insert_tt
BEFORE INSERT ON "TimeTracking"
   FOR EACH ROW EXECUTE FUNCTION fnc_trg_insert_tt();

CALL import_data('Peers.csv', '"Peers"', delim := ',');
CALL import_data('Tasks.csv', '"Tasks"', delim := ',');
CALL import_data('Checks.csv', '"Checks"', delim := ',');
CALL import_data('P2P.csv', '"P2P"', delim := ',');
CALL import_data('Verter.csv', '"Verter"', delim := ',');
CALL import_data('TransferredPoints.csv', '"TransferredPoints"', delim := ',');
CALL import_data('Friends.csv', '"Friends"', delim := ',');
CALL import_data('Recommendations.csv', '"Recommendations"', delim := ',');
CALL import_data('XP.csv', '"XP"', delim := ',');
CALL import_data('TimeTracking.csv', '"TimeTracking"', delim := ',');

CALL export_data('Peers.csv', '"Peers"', delim := ',');
CALL export_data('Tasks.csv', '"Tasks"', delim := ',');
CALL export_data('Checks.csv', '"Checks"', delim := ',');
CALL export_data('P2P.csv', '"P2P"', delim := ',');
CALL export_data('Verter.csv', '"Verter"', delim := ',');
CALL export_data('TransferredPoints.csv', '"TransferredPoints"', delim := ',');
CALL export_data('Friends.csv', '"Friends"', delim := ',');
CALL export_data('Recommendations.csv', '"Recommendations"', delim := ',');
CALL export_data('XP.csv', '"XP"', delim := ',');
CALL export_data('TimeTracking.csv', '"TimeTracking"', delim := ',');

-- !!! Дополнительно. Добавление новых строк в TransferredPoints при добавление нового пира в Peers
-- trigger function adds rows in TransferredPoint if new Peer inserts
CREATE OR REPLACE FUNCTION fnc_trg_after_insert_peer() RETURNS TRIGGER AS $insert_peer$
    BEGIN
        INSERT INTO "TransferredPoints"
        (SELECT ROW_NUMBER() OVER () + (SELECT MAX("ID") FROM "TransferredPoints"), peer1."Nickname", peer2."Nickname", 0
        FROM "Peers" AS peer1 CROSS JOIN "Peers" AS peer2
        WHERE  (peer1."Nickname" = NEW."Nickname" OR peer2."Nickname" = NEW."Nickname")
          AND peer1."Nickname" != peer2."Nickname");
     RETURN NULL;
    END
$insert_peer$ LANGUAGE plpgsql;

-- trigger on Peer insert
CREATE OR REPLACE TRIGGER trg_after_insert_peer
AFTER INSERT ON "Peers"
   FOR EACH ROW EXECUTE FUNCTION fnc_trg_after_insert_peer();
