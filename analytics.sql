-- # 1 Вывести "TransferredPoints" в удобном виде
CREATE OR REPLACE FUNCTION fnc_transferredpoints()
    RETURNS TABLE("Peer1" VARCHAR,
    "Peer2" VARCHAR,
    "PointsAmount" BIGINT) AS $$
    SELECT "TransferredPoints"."CheckingPeer", "TransferredPoints"."CheckedPeer",
           ("TransferredPoints"."PointsAmount" - cte_1."PointsAmount")
    FROM "TransferredPoints" JOIN "TransferredPoints" AS cte_1
    ON "TransferredPoints"."CheckingPeer" = cte_1."CheckedPeer" AND
       "TransferredPoints"."CheckedPeer" = cte_1."CheckingPeer"
    ORDER BY 1, 2;
    $$ LANGUAGE SQL;

-- test select function # 1
SELECT * FROM fnc_transferredpoints();

-- # 2 Вывести имена и успешно выполненние задания
CREATE OR REPLACE FUNCTION  fnc_xp()
    RETURNS TABLE("Peer" VARCHAR,
                  "Task" VARCHAR,
                  "XP" BIGINT) AS $$
    SELECT "Nickname", "Title", "XPAmount"
    FROM "Peers"
         INNER JOIN "Checks" ON "Peers"."Nickname" = "Checks"."Peer"
         INNER JOIN "Tasks" ON "Checks"."Task" = "Tasks"."Title"
         INNER JOIN "XP" ON "Checks"."ID" = "XP"."Check"
    ORDER BY 1,2;
$$ LANGUAGE SQL;

-- test select function # 2
SELECT * FROM fnc_xp();

-- # 3 Вывести людей, которые не выходили из здания в течение всего дня
CREATE OR REPLACE FUNCTION fnc_not_left_campus("pDate" DATE) RETURNS TABLE(
    "Peer" VARCHAR) AS $$
    SELECT "Peer" FROM "TimeTracking"
    WHERE "Date" = "pDate"
    GROUP BY "Peer"
    HAVING COUNT("State") = 2
    $$ LANGUAGE SQL;

-- test select function # 3
SELECT * FROM fnc_not_left_campus("pDate" := '2022-11-11');

-- # 4 Найти процент успешных и неуспешных проверок за всё время
CREATE OR REPLACE PROCEDURE p_success_checks(IN result REFCURSOR = 'procedure_result')
LANGUAGE plpgsql AS $$
    BEGIN
     OPEN result FOR
        SELECT ROUND((SELECT COUNT(*) FROM "XP")/(SELECT COUNT(*) FROM "Checks")::NUMERIC * 100, 0)
        AS "SuccessfulChecks",
            ROUND(((SELECT COUNT(*) FROM "Checks") - (SELECT COUNT(*) FROM "XP")) /
                  (SELECT COUNT(*) FROM "Checks")::NUMERIC * 100, 0)
        AS "UnsuccessfulChecks";
    END;
    $$;

-- test call procedure #4
BEGIN;
   CALL p_success_checks();
   FETCH ALL FROM procedure_result;
END;

-- # 5 Посчитать изменение баллов каждого участника по таблице TransferredPoints
CREATE OR REPLACE PROCEDURE p_points_change_1(IN result REFCURSOR = 'procedure_result')
LANGUAGE plpgsql AS $$
    BEGIN
        OPEN result FOR
        WITH get_points AS (SELECT "CheckingPeer", SUM("PointsAmount") AS total
                            FROM "TransferredPoints"
                            GROUP BY "CheckingPeer" ),
            give_points AS (SELECT "CheckedPeer", SUM("PointsAmount") AS total
                            FROM "TransferredPoints"
                            GROUP BY "CheckedPeer" )
        SELECT "CheckingPeer" AS "Peer",
           (get_points.total - give_points.total) AS "PointsChange"
        FROM get_points JOIN give_points
            ON get_points."CheckingPeer" = give_points."CheckedPeer"
        ORDER BY 2 DESC ;
    END;
    $$;

-- test call procedure # 5
BEGIN;
    CALL p_points_change_1();
    FETCH ALL FROM procedure_result;
END;

-- # 6 Посчитать изменение баллов каждого участника по таблице TransferredPoints(удобный формат)
CREATE OR REPLACE PROCEDURE p_points_change_2(IN result REFCURSOR = 'procedure_result')
LANGUAGE plpgsql AS $$
    BEGIN
        OPEN result FOR
            SELECT "Peer1", SUM("PointsAmount")
            FROM fnc_transferredpoints()
            GROUP BY "Peer1"
            ORDER BY 2 DESC;
    END;
    $$;

-- test call procedure # 6
BEGIN;
    CALL p_points_change_2();
    FETCH ALL FROM procedure_result;
END;

-- # 7 Определить самое часто проверяемое задание за каждый день
CREATE OR REPLACE PROCEDURE p_frequently_checked(IN result REFCURSOR = 'procedure_result')
LANGUAGE plpgsql AS $$
BEGIN
    OPEN result FOR
    SELECT "Date", "Task"
    FROM (
        SELECT "Date", "Task",
               RANK() OVER (PARTITION BY "Date" ORDER BY COUNT("Task") DESC ) AS rating
        FROM "Checks"
        GROUP BY "Date", "Task") query_1
    WHERE rating = 1
    ORDER BY 1 DESC ;
END;
$$;

-- test call procedure # 7
BEGIN;
    CALL p_frequently_checked();
    FETCH ALL FROM procedure_result;
END;

-- # 8 Определить длительность последней P2P проверки
CREATE OR REPLACE PROCEDURE p_duration_last_check(IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
BEGIN
    OPEN result FOR
        WITH cte_last_p2p AS (SELECT "P2P"."Check"
                        FROM "Checks"
                        INNER JOIN "P2P" ON "Checks"."ID" = "P2P"."Check"
                        ORDER BY "Date" DESC, "Time" DESC
                        LIMIT 1)
    SELECT ((SELECT "P2P"."Time" FROM "P2P" JOIN cte_last_p2p
            ON "P2P"."Check" = cte_last_p2p."Check"
             WHERE "State" != 'Start') -
            (SELECT "P2P"."Time" FROM "P2P" JOIN cte_last_p2p
            ON "P2P"."Check" = cte_last_p2p."Check"
            WHERE "State" = 'Start'))::time AS delta_time;
END;
$$;

-- test call procedure # 8
BEGIN;
    CALL p_duration_last_check();
    FETCH ALL FROM procedure_result;
END;

-- # 9 Найти всех учащихся, выполнивших весь блок заданий и дату завершения последнего задания
CREATE OR REPLACE PROCEDURE p_completed_block(IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
BEGIN
    OPEN result FOR
        WITH cte_task AS (
          SELECT
                CASE
                    WHEN "Title" LIKE 'CPP_\_%' THEN 'CPP'
                    WHEN "Title" LIKE 'C_\_%' THEN 'C'
                    WHEN "Title" LIKE 'DO_\_%' THEN 'DO'
                    WHEN "Title" LIKE 'A_\_%' THEN 'A'
                    WHEN "Title" LIKE 'SQL_\_%' THEN 'SQL'
                END AS prefiks,
                COUNT(*) AS count_prefiks
                FROM "Tasks"
                GROUP BY "prefiks"
                ORDER BY 2),
          cte_check AS (
          SELECT "Peer",
          CASE
              WHEN "Task" LIKE 'CPP_\_%' THEN 'CPP'
              WHEN "Task" LIKE 'C_\_%' THEN 'C'
              WHEN "Task" LIKE 'DO_\_%' THEN 'DO'
              WHEN "Task" LIKE 'A_\_%' THEN 'A'
              WHEN "Task" LIKE 'SQL_\_%' THEN 'SQL'
          END AS prefiks,
          COUNT(*) AS count_prefiks
          FROM "Checks"
               INNER JOIN "XP" ON "Checks"."ID" = "XP"."Check"
          GROUP BY "Peer", prefiks
          ORDER BY 2 DESC),
          cte_date AS (
          SELECT "Date", "Peer",
                 RANK() OVER (ORDER BY "Date" DESC ) AS rating
          FROM "Checks")
          SELECT DISTINCT cte_check."Peer", cte_date."Date"
          FROM cte_check
               INNER JOIN cte_task ON cte_check.count_prefiks = cte_task.count_prefiks
               INNER JOIN cte_date ON cte_check."Peer" = cte_date."Peer"
          WHERE rating = 1;
END;
$$;

-- test call procedure # 9
BEGIN;
    CALL p_completed_block();
    FETCH ALL FROM procedure_result;
END;

-- # 10 Определить самого рекомендуемого учащегося
CREATE OR REPLACE PROCEDURE p_recommended(IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
BEGIN
    OPEN result FOR
        WITH cte_recommended AS (
            WITH cte_tmp AS (SELECT DISTINCT "Nickname", "Peer2", "RecommendedPeer",
                    COUNT("RecommendedPeer") OVER (PARTITION BY "Nickname", "RecommendedPeer")  AS rating
            FROM "Peers"
            INNER JOIN "Friends" ON "Peers"."Nickname" = "Friends"."Peer1"
            INNER JOIN "Recommendations" ON "Recommendations"."Peer" = "Friends"."Peer2" AND
         "Peers"."Nickname" != "Recommendations"."RecommendedPeer")
       SELECT "Nickname", "RecommendedPeer", cte_tmp.rating,
           ROW_NUMBER() OVER (PARTITION BY "Nickname" ORDER BY cte_tmp.rating DESC ) AS rating_value
           FROM cte_tmp)
    SELECT "Nickname", "RecommendedPeer"
    FROM cte_recommended
    WHERE rating_value = 1;
END;
$$;

-- test call procedure # 10
BEGIN;
    CALL p_recommended();
    FETCH ALL FROM procedure_result;
END;

-- # 11 Определить процент пиров, которые: приступили к блоку заданий 1, приступили к блоку заданий 2,
-- приступили к обоим, не приступили ни к одному
CREATE OR REPLACE PROCEDURE p_percentage(block_1 VARCHAR, block_2 VARCHAR,
    IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
BEGIN
    OPEN result FOR
        WITH cte_peer_block AS (SELECT DISTINCT "Peer", CASE
                                            WHEN "Task" LIKE 'CPP_\_%' THEN 'CPP'
                                            WHEN "Task" LIKE 'C_\_%'  THEN 'C'
                                            WHEN "Task" LIKE 'DO_\_%' THEN 'DO'
                                            WHEN "Task" LIKE 'A_\_%' THEN 'A'
                                            WHEN "Task" LIKE 'SQL_\_%' THEN 'SQL'
                                            ELSE ''
                                        END AS block_project
                                FROM "Checks" ),
            cte_block_1 AS (SELECT COUNT(block_project) AS count_block_1, 1 AS id_value
                            FROM cte_peer_block
                            WHERE block_project != '' AND block_project = block_1
                            GROUP BY block_project),
            cte_block_2 AS (SELECT COUNT(block_project) AS count_block_2, 1 AS id_value
                            FROM cte_peer_block
                            WHERE block_project != '' AND block_project = block_2
                            GROUP BY block_project),
            cte_both AS (SELECT COUNT(DISTINCT "Peer") AS count_bouth, 1 AS id_value
                        FROM cte_peer_block
                        WHERE block_project != '' AND (block_project = block_1 OR block_project = block_2)),
            cte_peers AS (SELECT COUNT("Nickname") AS count_all, 1 AS id_value
                          FROM "Peers")
    SELECT ROUND((cte_block_1.count_block_1 / cte_peers.count_all::NUMERIC) * 100, 0) AS "StartedBlock1",
    ROUND((cte_block_2.count_block_2 / cte_peers.count_all::NUMERIC) * 100, 0) AS "StartedBlock2",
    ROUND((cte_both.count_bouth / cte_peers.count_all::NUMERIC) * 100, 0) AS "StartedBothBlocks",
    ROUND((cte_peers.count_all - cte_both.count_bouth) / cte_peers.count_all::NUMERIC * 100, 0) AS "DidntStartAnyBlock"
    FROM cte_block_1
        INNER JOIN  cte_block_2 ON cte_block_1.id_value = cte_block_2.id_value
        INNER JOIN  cte_peers ON cte_peers.id_value = cte_block_2.id_value
        INNER JOIN cte_both ON cte_both.id_value = cte_peers.id_value;
    END;
$$;

-- test call procedure # 11
BEGIN;
    CALL p_percentage('A', 'DO');
    FETCH ALL FROM procedure_result;
END;

-- # 12 Определить *N* учащихся с наибольшим числом друзей
CREATE OR REPLACE PROCEDURE p_friendscount( limit_value INT,
    IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
BEGIN
    OPEN result FOR
        SELECT "Nickname" AS "Peer", COUNT("Peer2") AS "FriendsCount"
        FROM "Peers"
        INNER JOIN "Friends" ON "Peers"."Nickname" = "Friends"."Peer1"
        GROUP BY "Nickname"
        ORDER BY 2 DESC
        LIMIT limit_value;
END;
$$;

-- test call procedure # 12
BEGIN;
    CALL p_friendscount(4);
    FETCH ALL FROM procedure_result;
END;

-- # 13  Определить процент учащихся, которые успешно проходили проверку в свой день рождения
CREATE OR REPLACE PROCEDURE p_birthday_success(IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
BEGIN
    OPEN result FOR
        WITH cte_find_dates AS (SELECT "Nickname",
                CONCAT(DATE_PART('day', "Birthday"), '_', DATE_PART('month', "Birthday")) AS "Birthday",
                CONCAT(DATE_PART('day', "Date"), '_', DATE_PART('month', "Date")) AS "Date",
                "P2P"."State" AS p2p_state, "Verter"."State" AS verter_state
                  FROM "Peers" INNER JOIN "Checks" ON "Peers"."Nickname" = "Checks"."Peer"
                      INNER JOIN "P2P" ON "Checks"."ID" = "P2P"."Check"
                      LEFT JOIN "Verter" ON "Checks"."ID" = "Verter"."Check"),
            cte_success AS (SELECT COUNT("Nickname") AS count_peers, 1 AS id_value
                            FROM cte_find_dates
                            WHERE "Birthday" = "Date" AND (p2p_state = 'Success' OR verter_state = 'Success')),
            cte_failure AS (SELECT COUNT("Nickname") AS count_peers, 1 AS id_value
                            FROM cte_find_dates
                            WHERE "Birthday" = "Date" AND (p2p_state = 'Failure' OR verter_state = 'Failure')),
            cte_all AS (SELECT COUNT("Nickname") AS count_peers, 1 AS id_value FROM "Peers")
    SELECT ROUND((cte_success.count_peers / cte_all.count_peers::NUMERIC) * 100, 0) AS "SuccessfulChecks",
            ROUND((cte_failure.count_peers / cte_all.count_peers::NUMERIC) * 100, 0) AS "UnsuccessfulChecks"
    FROM cte_success
        INNER JOIN cte_failure ON cte_success.id_value = cte_failure.id_value
        INNER JOIN cte_all ON cte_failure.id_value = cte_all.id_value;
END;
$$;

-- test call procedure # 13
BEGIN;
    CALL p_birthday_success();
    FETCH ALL FROM procedure_result;
END;

-- # 14 Определить количество баллов в сумме по каждому учащемуся
CREATE OR REPLACE PROCEDURE p_max_xp(IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
BEGIN
    OPEN result FOR
        SELECT "Nickname" AS "Peer", SUM("XPAmount") AS "XP"
        FROM (SELECT "Nickname", "Task", "XPAmount",
            ROW_NUMBER() OVER (PARTITION BY "Task", "Nickname" ORDER BY "Task" DESC ) AS rating
              FROM "Checks" INNER JOIN "XP" ON "Checks"."ID" = "XP"."Check"
                  INNER JOIN "Peers" ON "Checks"."Peer" = "Peers"."Nickname") query_xp
        WHERE rating = 1
        GROUP BY "Nickname"
        ORDER BY 2;
END;
$$;

-- test call procedure # 14
BEGIN;
    CALL p_max_xp();
    FETCH ALL FROM procedure_result;
END;

-- # 15 Определить всех учащихся, которые сдали задания 1 и 2, но не сдали задание 3
CREATE OR REPLACE PROCEDURE p_tasks_1_2_3( task_1 VARCHAR, task_2 VARCHAR, task_3 VARCHAR,
    IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
BEGIN
    OPEN result FOR
        WITH cte_success AS (SELECT "Checks"."ID",  "Task", "Nickname", 'success' AS type
                         FROM "Peers" INNER JOIN "Checks" ON "Peers"."Nickname" = "Checks"."Peer"
                             INNER JOIN "XP" ON "Checks"."ID" = "XP"."Check"),
            cte_not_start AS (SELECT "Checks"."ID", "Task", "Nickname", 'not_start' AS type
                              FROM "Checks" LEFT JOIN "XP" ON "Checks"."ID" = "XP"."Check"
                                  INNER JOIN "Peers" ON "Checks"."Peer" = "Peers"."Nickname"
                              WHERE "Check" IS NULL)
    SELECT cte_success."Nickname" AS "Peers"
    FROM cte_success
        INNER JOIN cte_success AS cte_s_2 USING("Nickname")
        INNER JOIN cte_not_start USING ("Nickname")
    WHERE cte_success."Task" = task_1 AND cte_s_2."Task" = task_2 AND cte_not_start."Task" = task_3;
END;
$$;

-- test call procedure # 15
BEGIN;
    CALL p_tasks_1_2_3('CPP3_SmartCalc_v2.0', 'CPP2_s21_containers', 'C7_SmartCalc_v1.0');
    FETCH ALL FROM procedure_result;
END;

-- # 16 Для каждой задания вывести количество предшествующих ей заданий
CREATE OR REPLACE PROCEDURE p_prevcount(IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
    BEGIN
    OPEN result FOR
        WITH RECURSIVE count_prev_task AS (
          SELECT "Title", 0 AS "PrevCount"
          FROM "Tasks"
          WHERE "ParentTask" IS NULL
          UNION
          SELECT "Tasks"."Title" AS "Title", (1 + "PrevCount") AS "PrevCount"
          FROM "Tasks"
                INNER JOIN count_prev_task ON count_prev_task."Title" != "Tasks"."Title"
          WHERE "Tasks"."ParentTask" = count_prev_task."Title")
        SELECT * FROM count_prev_task;
    END;
$$;

-- test call procedure # 16
BEGIN;
    CALL p_prevcount();
    FETCH ALL FROM procedure_result;
END;

-- # 17  Найти "удачные" для проверок дни (если в нем есть хотя бы *N* идущих подряд успешных проверок)
CREATE OR REPLACE PROCEDURE p_count_lucky_days(count_success INT, IN result REFCURSOR = 'procedure_result'
) LANGUAGE plpgsql AS $$
    BEGIN
        OPEN result FOR
            WITH cte_lucky AS (
                    SELECT "Date", "Checks"."ID", "P2P"."Time", "State", 'check_2_p2p' AS type, "MaxXP"
                    FROM "P2P" INNER JOIN "Checks" ON "P2P"."Check" = "Checks"."ID"
                        INNER JOIN "Tasks" ON "Checks"."Task" = "Tasks"."Title"
                    UNION
                    SELECT "Date", "Checks"."ID", "Verter"."Time", "State", 'check_1_verter' AS type, "MaxXP"
                    FROM "Verter" INNER JOIN "Checks" ON "Verter"."Check" = "Checks"."ID"
                        INNER JOIN "Tasks" ON "Checks"."Task" = "Tasks"."Title" ),
                query_lucky AS (
                    SELECT "Date", "ID", "Time", "State", type, "MaxXP",
                           ROW_NUMBER() OVER (PARTITION BY "Date", cte_lucky."ID" ORDER BY type, "State" DESC) as rating
                    FROM cte_lucky),
                query_final AS (
                    SELECT CASE
                        WHEN COALESCE(ROUND(("XPAmount" / "MaxXP"::NUMERIC) * 100, 0), 0) >= 80
                        THEN "State"
                        ELSE 'Failure' END AS State_value,
                        type, "Date", query_lucky."ID", "Time",
                                   COALESCE(ROUND(("XPAmount" / "MaxXP"::NUMERIC) * 100, 0), 0) AS count_xp
                    FROM query_lucky LEFT JOIN "XP" ON "XP"."Check" = query_lucky."ID"
                    WHERE rating = 1
                )
        SELECT DISTINCT "Date"
        FROM (
        SELECT "Date", query_final."ID", "Time", State_value, type, count_xp,
               ROW_NUMBER() OVER (PARTITION BY "Date", State_value ORDER BY "Date", "Time", "ID") AS rating_fail,
               ROW_NUMBER() OVER (PARTITION BY "Date" ORDER BY "Date", "Time", "ID") AS rating_query
        FROM query_final
        ORDER BY 1, 3) query_common
        WHERE rating_fail = rating_query AND State_value != 'Failure' AND rating_query = count_success;
    END;
    $$;

-- test call procedure # 17
BEGIN;
    CALL p_count_lucky_days(2);
    FETCH ALL FROM procedure_result;
END;

-- # 18 Определить учащегося с наибольшим числом выполненных заданий
CREATE OR REPLACE PROCEDURE p_peer_max_count_task(IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
    BEGIN
       OPEN result FOR
        WITH max_count AS (SELECT COUNT("XPAmount")
                           FROM "XP" JOIN "Checks" ON "XP"."Check" = "Checks"."ID"
                               JOIN "Peers" ON "Checks"."Peer" = "Peers"."Nickname"
                           GROUP BY "Peer"
                           ORDER BY 1 DESC
                           LIMIT 1)
        SELECT "Peer", COUNT("XPAmount") AS "XP"
        FROM "XP" JOIN "Checks" ON "XP"."Check" = "Checks"."ID"
            JOIN "Peers" ON "Checks"."Peer" = "Peers"."Nickname"
        GROUP BY "Peer"
        HAVING COUNT("XPAmount") = (SELECT * FROM max_count);
       END
    $$;

-- test call procedure # 18
BEGIN;
    CALL p_peer_max_count_task();
    FETCH ALL FROM procedure_result;
END;

-- # 19 Определить учащегося с наибольшим количеством баллов
CREATE OR REPLACE PROCEDURE p_peer_max_xp(IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
    BEGIN
       OPEN result FOR
        WITH max_xp AS (SELECT SUM("XPAmount")
                        FROM "XP" JOIN "Checks" ON "XP"."Check" = "Checks"."ID"
                            JOIN "Peers" ON "Checks"."Peer" = "Peers"."Nickname"
                        GROUP BY "Peer"
                        ORDER BY 1 DESC
                        LIMIT 1)
        SELECT "Peer", SUM("XPAmount") AS "XP"
        FROM "XP" JOIN "Checks" ON "XP"."Check" = "Checks"."ID"
            JOIN "Peers" ON "Checks"."Peer" = "Peers"."Nickname"
        GROUP BY "Peer"
        HAVING SUM("XPAmount") = (SELECT * FROM max_xp);
       END
    $$;

-- test call procedure # 19
BEGIN;
    CALL p_peer_max_xp();
    FETCH ALL FROM procedure_result;
END;

-- inserts for 20-24 tasks: today
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'acadi', current_date,'12:02', 1);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'acadi', current_date,'14:12', 2);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'acadi', current_date,'16:00', 1);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'acadi', current_date,'19:17', 2);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'ceramon', current_date,'10:12', 1);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'ceramon', current_date,'18:11', 2);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'karving', current_date,'08:05', 1);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'karving', current_date,'12:12', 2);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'karving', current_date,'14:35', 1);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'karving', current_date,'20:22', 2);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'sarash', current_date,'16:05', 1);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'sarash', current_date,'22:33', 2);
-- inserts for 20-24 tasks: yesterday
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'acadi', current_date - 1 ,'10:58', 1);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'acadi', current_date - 1 ,'11:05', 2);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'acadi', current_date - 1, '17:38', 1);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'acadi', current_date - 1, '20:27', 2);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'ceramon', current_date - 1,'09:14', 1);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'ceramon', current_date - 1,'19:01', 2);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'karving', current_date - 1,'09:03', 1);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'karving', current_date - 1,'13:13', 2);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'karving', current_date - 1,'15:15', 1);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'karving', current_date - 1,'21:18', 2);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'sarash', current_date - 1,'15:35', 1);
INSERT INTO "TimeTracking"
VALUES ((SELECT MAX("ID")+1 FROM "TimeTracking"), 'sarash', current_date - 1,'20:48', 2);

-- # 20 Определить учащегося, который провел сегодня в здании больше всего времени
CREATE OR REPLACE PROCEDURE p_peer_max_time_today(IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
    BEGIN
       OPEN result FOR
       WITH time_arrive AS (SELECT ROW_NUMBER() OVER () AS ID,  "Peer", "Time" as arrive
                            FROM "TimeTracking"
                            WHERE "Date" = current_date AND "State" = 1
                            ORDER BY 1, 2),
           time_departure AS (SELECT ROW_NUMBER() OVER () AS ID,  "Peer", "Time" as departure
                            FROM "TimeTracking"
                            WHERE "Date" = current_date AND "State" = 2
                            ORDER BY 1, 2),
           time_by_peer AS (SELECT time_arrive."Peer" AS Peer,
                                   SUM(departure - arrive)::time AS campus_time
                            FROM time_arrive JOIN time_departure
                                ON time_arrive.ID = time_departure.ID
                            GROUP BY time_arrive."Peer")
       SELECT Peer FROM time_by_peer
       WHERE campus_time =
        (SELECT MAX(campus_time) FROM time_by_peer);
       END;
    $$;

-- test call procedure # 20
BEGIN;
    CALL p_peer_max_time_today();
    FETCH ALL FROM procedure_result;
END;

-- # 21 Определить учащихся, приходивших раньше заданного времени не менее *N* раз за всё время
CREATE OR REPLACE PROCEDURE p_peer_come_ealier(IN result REFCURSOR, IN time_arrive time, IN number int)
    LANGUAGE plpgsql
AS $$
    BEGIN
       OPEN result FOR
        SELECT "Peer" FROM "TimeTracking"
        WHERE "State" = 1 AND "Time" < time_arrive
        GROUP BY "Peer"
        HAVING COUNT("Peer") >= number
       ORDER BY 1;
       END;
    $$;

-- test call procedure # 21
BEGIN;
    CALL p_peer_come_ealier('procedure_result', '12:00', 3);
    FETCH ALL FROM procedure_result;
END;
BEGIN;
    CALL p_peer_come_ealier('procedure_result', '08:00', 1);
    FETCH ALL FROM procedure_result;
END;

-- # 22 Определить учащихся, выходивших за последние *N* дней из здания больше *M* раз
CREATE OR REPLACE PROCEDURE p_peer_leave(IN result REFCURSOR, IN days int, IN number int)
    LANGUAGE plpgsql
AS $$
    BEGIN
       OPEN result FOR
        SELECT "Peer" FROM "TimeTracking"
        WHERE "State" = 2 AND "Date" >= (current_date - days)
        GROUP BY "Peer"
        HAVING COUNT("Peer") > number
       ORDER BY 1;
       END;
    $$;

-- test call procedure # 22
BEGIN;
    CALL p_peer_leave('procedure_result', 3, 3);
    FETCH ALL FROM procedure_result;
END;
BEGIN;
    CALL p_peer_leave('procedure_result', 1, 1);
    FETCH ALL FROM procedure_result;
END;

-- # 23 Определить учащегося, который пришел сегодня последним
CREATE OR REPLACE PROCEDURE p_peer_the_last_arrive_today(IN result REFCURSOR = 'procedure_result')
    LANGUAGE plpgsql AS $$
    BEGIN
       OPEN result FOR
        WITH latiest_time AS (SELECT MAX("Time")
                              FROM "TimeTracking"
                               WHERE "State" = 1 AND "Date" = current_date
        )
        SELECT "Peer" FROM "TimeTracking"
        WHERE "State" = 1 AND "Time" =
                              (SELECT * FROM latiest_time);
       END;
    $$;

-- test call procedure # 23
BEGIN;
    CALL p_peer_the_last_arrive_today();
    FETCH ALL FROM procedure_result;
END;

-- # 24 Определить учащихся, которые выходили вчера из здания больше чем на *N* минут
CREATE OR REPLACE PROCEDURE p_peer_absent_yesterday(IN result REFCURSOR, IN time_absent interval MINUTE)
    LANGUAGE plpgsql AS $$
    BEGIN
       OPEN result FOR
       WITH time_arrive AS (SELECT ROW_NUMBER() OVER () AS ID,  "Peer", "Time" as arrive
                            FROM "TimeTracking"
                            WHERE "Date" = current_date - 1 AND "State" = 1
                            ORDER BY 1, 2),
           time_departure AS (SELECT ROW_NUMBER() OVER () AS ID,  "Peer", "Time" as departure
                            FROM "TimeTracking"
                            WHERE "Date" = current_date - 1 AND "State" = 2
                            ORDER BY 1, 2),
           time_by_peer AS (SELECT time_arrive."Peer" AS Peer,
                                   SUM(departure - arrive)::time AS campus_time
                            FROM time_arrive JOIN time_departure
                                ON time_arrive.ID = time_departure.ID
                            GROUP BY time_arrive."Peer"),
           total_time_by_peer AS (SELECT time_arrive."Peer" AS Peer,
                                   (MAX(departure) - MIN(arrive))::time AS campus_time
                            FROM time_arrive JOIN time_departure
                                ON time_arrive.ID = time_departure.ID
                            GROUP BY time_arrive."Peer")
        SELECT time_by_peer.Peer AS "Peers"
        FROM time_by_peer JOIN total_time_by_peer USING(Peer)
        WHERE (total_time_by_peer.campus_time - time_by_peer.campus_time) > time_absent;
       END;
    $$;

-- test call procedure # 24
BEGIN;
    CALL  p_peer_absent_yesterday('procedure_result', '00:20');
    FETCH ALL FROM procedure_result;
END;

DELETE FROM "TimeTracking" WHERE "ID" BETWEEN 65 AND 88;

-- Remove functions and procedures
DROP FUNCTION IF EXISTS fnc_transferredpoints;
DROP FUNCTION IF EXISTS fnc_xp;
DROP FUNCTION IF EXISTS fnc_not_left_campus;
DROP PROCEDURE IF EXISTS p_success_checks;
DROP PROCEDURE IF EXISTS p_points_change_1;
DROP PROCEDURE IF EXISTS p_points_change_2;
DROP PROCEDURE IF EXISTS p_frequently_checked;
DROP PROCEDURE IF EXISTS p_duration_last_check;
DROP PROCEDURE IF EXISTS p_completed_block;
DROP PROCEDURE IF EXISTS p_recommended;
DROP PROCEDURE IF EXISTS p_percentage;
DROP PROCEDURE IF EXISTS p_friendscount;
DROP PROCEDURE IF EXISTS p_birthday_success;
DROP PROCEDURE IF EXISTS p_max_xp;
DROP PROCEDURE IF EXISTS p_tasks_1_2_3;
DROP PROCEDURE IF EXISTS p_prevcount;
DROP PROCEDURE IF EXISTS p_count_lucky_days;
DROP PROCEDURE IF EXISTS p_peer_max_count_task;
DROP PROCEDURE IF EXISTS p_peer_max_xp;
DROP PROCEDURE IF EXISTS p_peer_max_time_today;
DROP PROCEDURE IF EXISTS p_peer_come_ealier;
DROP PROCEDURE IF EXISTS p_peer_leave;
DROP PROCEDURE IF EXISTS p_peer_the_last_arrive_today;
DROP PROCEDURE IF EXISTS p_peer_absent_yesterday;
