CREATE OR REPLACE PROCEDURE export_data (file_name varchar, table_name varchar, delim varchar)
    AS $$
    DECLARE
    destination_dir varchar;
    destination varchar;
    BEGIN
        destination_dir:= (SELECT setting FROM pg_settings WHERE name = 'data_directory');
        destination:= (SELECT CONCAT(destination_dir, '/export_data/', file_name));
        EXECUTE('COPY ' || table_name || ' TO ''' || destination || ''' DELIMITER '''
                           || delim || ''' CSV HEADER');
    END;
    $$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE import_data (file_name varchar, table_name varchar, delim varchar)
    AS $$
    DECLARE
    destination_dir varchar;
    destination varchar;
    BEGIN
        destination_dir:= (SELECT setting FROM pg_settings WHERE name = 'data_directory');
        destination := (SELECT CONCAT(destination_dir, '/import_data/', file_name));
        EXECUTE('COPY ' || table_name || ' FROM ''' || destination || ''' DELIMITER '''
                           || delim || ''' CSV HEADER');
    END;
    $$ LANGUAGE plpgsql;

CREATE TABLE "Peers" (
    "Nickname" varchar primary key,
    "Birthday" date
);
