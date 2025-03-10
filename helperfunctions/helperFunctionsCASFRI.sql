------------------------------------------------------------------------------
-- CASFRI - Helper functions installation script for CASFRI v5
-- For use with PostgreSQL Table Tranlation Framework v2.0.1 for PostgreSQL 13.x
-- https://github.com/CASFRI/PostgreSQL-Table-Translation-Framework
-- https://github.com/CASFRI/CASFRI
--
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
--
-- Copyright (C) 2018-2021 Pierre Racine <pierre.racine@sbf.ulaval.ca>,
--                         Marc Edwards <medwards219@gmail.com>,
--                         Pierre Vernier <pierre.vernier@gmail.com>
--                         Melina Houle <melina.houle@sbf.ulaval.ca>
-------------------------------------------------------------------------------
-- Begin Tools View Definitions...
-------------------------------------------------------------------------------
CREATE OR REPLACE VIEW TT_Queries AS
SELECT
    act.query AS query,
    act.pid AS pid,
    act.datname AS database,
    act.xact_start::timestamp(0) AS start_time,
    TT_PrettyDuration(EXTRACT(EPOCH FROM now() - act.xact_start)::int) process_time,
    act.wait_event_type waiting_for,
    act.wait_event,
    CASE WHEN NOT act.wait_event_type IS NULL THEN TT_PrettyDuration(EXTRACT(EPOCH FROM now()::time - act.state_change::time)::int) ELSE NULL END AS waiting_time,
    lockact.query AS locking_query,
    lockact.pid AS locking_pid,
    t.schemaname || '.' || t.relname AS locked_table,
    'SELECT pg_terminate_backend(' || act.pid || ');' kill_query
 FROM (((pg_stat_activity act
      LEFT JOIN pg_locks l1 ON act.pid = l1.pid AND NOT l1.granted)
      LEFT JOIN pg_locks l2 ON l1.relation = l2.relation AND l2.granted)
      LEFT JOIN pg_stat_activity lockact ON l2.pid = lockact.pid)
      LEFT JOIN pg_stat_user_tables t ON l1.relation = t.relid
WHERE act.state != 'idle';
-------------------------------------------------------------------------------
-- Begin Tools Function Definitions...
-------------------------------------------------------------------------------
-- TT_IsMissingOrInvalidText
-- TT_IsMissingOrNotInSetCode
-- TT_IsMissingOrInvalidNumber
-- TT_IsMissingOrInvalidRange
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_IsMissingOrInvalidText();
CREATE OR REPLACE FUNCTION TT_IsMissingOrInvalidText()
RETURNS text[] AS $$
  SELECT ARRAY['NULL_VALUE',
               'EMPTY_STRING',
               'NOT_APPLICABLE',
               'UNKNOWN_VALUE',
               'INVALID_VALUE'];
$$ LANGUAGE sql IMMUTABLE;
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_IsMissingOrNotInSetCode();
CREATE OR REPLACE FUNCTION TT_IsMissingOrNotInSetCode()
RETURNS text[] AS $$
  SELECT ARRAY['NULL_VALUE',
               'EMPTY_STRING',
               'NOT_APPLICABLE',
               'UNKNOWN_VALUE',
               'NOT_IN_SET',
               'UNUSED_VALUE',
               'INVALID_VALUE'];
$$ LANGUAGE sql IMMUTABLE;
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_IsMissingOrInvalidNumber();
CREATE OR REPLACE FUNCTION TT_IsMissingOrInvalidNumber()
RETURNS int[] AS $$
  SELECT ARRAY[-8888, -- NULL_VALUE
               -8887, -- NOT_APPLICABLE
               -8886, -- UNKNOWN_VALUE
               -9997] -- INVALID_VALUE
$$ LANGUAGE sql IMMUTABLE;
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_IsMissingOrInvalidRange();
CREATE OR REPLACE FUNCTION TT_IsMissingOrInvalidRange()
RETURNS int[] AS $$
  SELECT ARRAY[-8888, -- NULL_VALUE
               -8887, -- NOT_APPLICABLE
               -8886, -- UNKNOWN_VALUE
               -9997, -- INVALID_VALUE
               -9999, -- OUT_OF_RANGE
               -9995] -- WRONG_TYPE
$$ LANGUAGE sql IMMUTABLE;
------------------------------------------------------------

------------------------------------------------------------
-- TT_Count
--
-- Count the number of rows in a table without failing if the table does not exist
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_Count(name, name);
CREATE OR REPLACE FUNCTION TT_Count(
  schemaName name,
  tableName name
) RETURNS int AS $$
  DECLARE
    queryStr text;
    returnCnt bigint;
  BEGIN
    RAISE NOTICE 'Counting rows in %.%', schemaName, tableName;
    IF NOT TT_TableExists(schemaName, tableName) THEN
      RETURN 0;
    END IF;
    queryStr = 'SELECT count(*) FROM ' || schemaName || '.' || tableName;
    EXECUTE queryStr INTO returnCnt;
    RETURN returnCnt;
  END
$$ LANGUAGE plpgsql VOLATILE;
------------------------------------------------------------

------------------------------------------------------------
-- TT_TableColumnType
--
--   tableSchema name - Name of the schema containing the table.
--   table name       - Name of the table.
--   column name      - Name of the column.
--
--   RETURNS text     - Type.
--
-- Return the column names for the specified table.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_TableColumnType(name, name, name);
CREATE OR REPLACE FUNCTION TT_TableColumnType(
  schemaName name,
  tableName name,
  columnName name
)
RETURNS text AS $$
  SELECT data_type FROM information_schema.columns
  WHERE table_schema = schemaName AND table_name = tableName AND column_name = columnName;
$$ LANGUAGE sql STABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_TableColumnNames
--
--   tableSchema name - Name of the schema containing the table.
--   table name       - Name of the table.
--
--   RETURNS text[]   - ARRAY of column names.
--
-- Return the column names for the speficied table.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_TableColumnNames(name, name);
CREATE OR REPLACE FUNCTION TT_TableColumnNames(
  schemaName name,
  tableName name
)
RETURNS text[] AS $$
  DECLARE
    colNames text[];
  BEGIN
    SELECT array_agg(column_name::text)
    FROM information_schema.columns
    WHERE table_schema = schemaName AND table_name = tableName
    INTO STRICT colNames;

    RETURN colNames;
  END;
$$ LANGUAGE plpgsql VOLATILE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_TableColumnIsUnique
--
-- Return TRUE if the column values are unique.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_TableColumnIsUnique(name, name, name);
CREATE OR REPLACE FUNCTION TT_TableColumnIsUnique(
  schemaName name,
  tableName name,
  columnName name
)
RETURNS boolean AS $$
  DECLARE
    isUnique boolean;
  BEGIN
    EXECUTE 'SELECT (SELECT ' || columnName ||
           ' FROM ' || TT_FullTableName(schemaName, tableName) ||
           ' GROUP BY ' || columnName ||
           ' HAVING count(*) > 1
             LIMIT 1) IS NULL;'
    INTO isUnique;
    RETURN isUnique;
  END;
$$ LANGUAGE plpgsql VOLATILE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_TableColumnIsUnique
--
-- Return the list of column for a table and their uniqueness.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_TableColumnIsUnique(name, name);
CREATE OR REPLACE FUNCTION TT_TableColumnIsUnique(
  schemaName name,
  tableName name
)
RETURNS TABLE (col_name text, is_unique boolean) AS $$
  WITH column_names AS (
    SELECT unnest(TT_TableColumnNames(schemaName, tableName)) cname
  )
  SELECT cname, TT_TableColumnIsUnique(schemaName, tableName, cname) is_unique
FROM column_names;
$$ LANGUAGE sql VOLATILE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_ColumnExists
--
-- Returns true if a column exist in a table. Mainly defined to be used by
-- ST_AddUniqueID().
-----------------------------------------------------------
-- Self contained example:
--
-- SELECT TT_ColumnExists('public', 'spatial_ref_sys', 'srid') ;
-----------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ColumnExists(name, name, name);
CREATE OR REPLACE FUNCTION TT_ColumnExists(
  schemaname name,
  tablename name,
  columnname name
)
RETURNS BOOLEAN AS $$
  DECLARE
  BEGIN
    PERFORM 1 FROM information_schema.COLUMNS
    WHERE lower(table_schema) = lower(schemaname) AND lower(table_name) = lower(tablename) AND lower(column_name) = lower(columnname);
    RETURN FOUND;
  END;
$$ LANGUAGE plpgsql VOLATILE STRICT;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_IsJsonGeometry
--
-- Return TRUE if jsonbstr is a jsonb geometry.
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_IsJsonGeometry(text);
CREATE OR REPLACE FUNCTION TT_IsJsonGeometry(
  jsonbstr text
)
RETURNS boolean AS $$
  SELECT jsonb_typeof(jsonbstr::jsonb) = 'object' AND left(jsonbstr::text, 8) = '{"type":';
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_CompareRows
--
-- Return all different attribute values with values from row1 and row2.
-- Does not return anything when rows are identical.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_CompareRows(jsonb, jsonb, boolean);
CREATE OR REPLACE FUNCTION TT_CompareRows(
  row1 jsonb,
  row2 jsonb,
  softGeomCmp boolean DEFAULT FALSE
)
RETURNS TABLE (attribute text,
               row_1 text,
               row_2 text) AS $$
  DECLARE
    i int = 0;
    keys text[];
    row1val text;
    row2val text;
    newrow1val numeric;
    newrow2val numeric;
    roundDigits int;
  BEGIN
    attribute = 'row';

    IF row1 IS NULL THEN
        row_1 = 'do not exist';
        row_2 = 'exists';
        RETURN NEXT;
        RETURN;
    END IF;
    IF row2 IS NULL THEN
        row_1 = 'exists';
        row_2 = 'do not exist';
        RETURN NEXT;
        RETURN;
    END IF;
    SELECT array_agg(k) INTO keys
    FROM (SELECT jsonb_object_keys(row1) k) foo;

    FOR i IN 1..cardinality(keys) LOOP
      row1val = row1 -> keys[i];
      row2val = row2 -> keys[i];
      IF TT_IsNumeric(row1val) AND TT_IsNumeric(row2val) AND row1val != row2val THEN
        -- Try truncating both values to the same number of digits (up to 6)
        roundDigits = greatest(least(scale(row1val::numeric), scale(row2val::numeric)), 6);
        newrow1val = rtrim(rtrim(trunc(row1val::numeric, roundDigits)::text, '0'), '.')::numeric;
        newrow2val = rtrim(rtrim(trunc(row2val::numeric, roundDigits)::text, '0'), '.')::numeric;
        -- If truncating does not make them equal, round them
        IF newrow1val != newrow2val THEN
          row1val = rtrim(rtrim(round(row1val::numeric, roundDigits)::text, '0'), '.');
          row2val = rtrim(rtrim(round(row2val::numeric, roundDigits)::text, '0'), '.');
        ELSE
           row1val = newrow1val::text;
           row2val = newrow2val::text;
        END IF;
      END IF;
      IF (softGeomCmp AND TT_IsJsonGeometry(row1val) AND TT_IsJsonGeometry(row2val) AND
          NOT ST_Equals(ST_GeomFromGeoJSON(row1val), ST_GeomFromGeoJSON(row2val))) OR
          (NOT softGeomCmp AND row1val != row2val) THEN
        attribute = keys[i];
        row_1 = row1val::text;
        row_2 = row2val::text;
        RETURN NEXT;
      END IF;
    END LOOP;
    RETURN;
  END;
$$ LANGUAGE plpgsql VOLATILE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_CompareTables
--
-- Return all different attribute values with values from table 1 and table 2.
-- Does not return anything when tables are identical.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_CompareTables(name, name, name, name, name, boolean, boolean);
CREATE OR REPLACE FUNCTION TT_CompareTables(
  schemaName1 name,
  tableName1 name,
  schemaName2 name,
  tableName2 name,
  uniqueIDCol name DEFAULT NULL,
  ignoreColumnOrder boolean DEFAULT TRUE,
  softGeomCmp boolean DEFAULT FALSE
)
RETURNS TABLE (row_id text,
               attribute text,
               value_table_1 text,
               value_table_2 text) AS $$
  DECLARE
    columnName text;
    cols1 text[];
    cols2 text[];
    type1 text;
    type2 text;
    stop boolean := FALSE;
    query text;
  BEGIN
    IF NOT TT_TableExists(schemaName1, tableName1) THEN
      RAISE EXCEPTION 'Table %.% does not exists...', schemaName1, tableName1;
    END IF;
    IF NOT TT_TableExists(schemaName2, tableName2) THEN
      RAISE EXCEPTION 'Table %.% does not exists...', schemaName2, tableName2;
    END IF;
    cols1 = TT_TableColumnNames(schemaName1, tableName1);
    cols2 = TT_TableColumnNames(schemaName2, tableName2);
    -- Check that every column in table1 exists in table2
    FOREACH columnName IN ARRAY cols1 LOOP
      IF columnName != ALL(cols2) THEN
        RAISE EXCEPTION 'Column ''%'' does not exist in %.%...', columnName, schemaName2, tableName2;
        stop = TRUE;
      ELSE
        type1 = TT_TableColumnType(schemaName1, tableName1, columnName);
        type2 = TT_TableColumnType(schemaName2, tableName2, columnName);
        IF type1 != type2 THEN
          RAISE EXCEPTION 'Column ''%'' is of type ''%'' in %.% and of type ''%'' in table %.%...', columnName, type1, schemaName1, tableName1, type2, schemaName2, tableName2;
          stop = TRUE;
        END IF;
      END IF;
    END LOOP;
    -- Check that every column in table2 exists in table1
    FOREACH columnName IN ARRAY cols2 LOOP
      IF columnName != ALL(cols1) THEN
        RAISE EXCEPTION 'Column ''%'' does not exist in %.%...', columnName, schemaName1, tableName1;
        stop = TRUE;
      END IF;
    END LOOP;
    -- Stop for now
    IF stop THEN
      RETURN;
    END IF;
    -- Now that we know both tables have the same columns, check that they are in the same order
    IF NOT ignoreColumnOrder AND cols1 != cols2 THEN
      RAISE EXCEPTION 'Columns with the same names and types exist in both tables but are not in the same order...';
      RETURN;
    END IF;
  
    -- Check that uniqueIDCol is not NULL and exists
    IF uniqueIDCol IS NULL OR uniqueIDCol = '' THEN
      RAISE EXCEPTION 'Table have same structure. In order to report different rows, uniqueIDCol should not be NULL...';
    END IF;
    FOREACH columnName IN ARRAY regexp_split_to_array(uniqueIDCol, '\s*,\s*') LOOP
      IF NOT TT_ColumnExists(schemaName1, tableName1, columnName) THEN
        RAISE EXCEPTION 'Table have same structure. In order to report different rows, all columns from uniqueIDCol (%) should exist in both tables. % does  not exists...', uniqueIDCol, columnName;
      END IF;
    END LOOP;
  
    --SELECT regexp_replace(regexp_replace('aa, bb', '\s*,\s*', '::text || ''_'' || ', 'g'), '$', '::text ', 'g')
    query = 'SELECT ' || regexp_replace(regexp_replace(uniqueIDCol, '\s*,\s*', '::text || ''_'' || ', 'g'), '$', '::text', 'g') || ' row_id, (TT_CompareRows(to_jsonb(a), to_jsonb(b), ' || softGeomCmp::text || ')).* ' || CHR(10) ||
            'FROM ' || schemaName1 || '.' || tableName1 || ' a ' || CHR(10) ||
            'FULL OUTER JOIN ' || schemaName2 || '.' || tableName2 || ' b USING (' || uniqueIDCol || ')' || CHR(10) ||
            'WHERE NOT coalesce(ROW(a.*) = ROW(b.*), FALSE);';
RAISE NOTICE 'query=%', query;
    RETURN QUERY EXECUTE query;
  END;
$$ LANGUAGE plpgsql VOLATILE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_RandomInt
--
-- Return a list of random nb integer from val_min to val_max (both inclusives).
-- Seed can be set to get always the same repeated list.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_RandomInt(int, int, int, double precision);
CREATE OR REPLACE FUNCTION TT_RandomInt(
  nb int,
  val_min int,
  val_max int,
  seed double precision
)
RETURNS TABLE (id int) AS $$
  DECLARE
    newnb int;
  BEGIN
    IF nb < 0 THEN
      RAISE EXCEPTION 'ERROR random_int_id(): nb (%) must be greater than 0...', nb;
    END IF;
    IF nb = 0 THEN
      RETURN;
    END IF;
    IF val_max < val_min THEN
      RAISE EXCEPTION 'ERROR TT_RandomInt(): val_max (%) must be greater or equal to val_min (%)...', val_max, val_min;
    END IF;
    IF nb > (val_max - val_min + 1) THEN
      RAISE EXCEPTION 'ERROR TT_RandomInt(): nb (%) must be smaller or equal to the range of values (%)...', nb, val_max - val_min + 1;
    END IF;
    IF nb = (val_max - val_min + 1) THEN
       RAISE NOTICE 'nb is equal to the range of requested values. Returning a series from % to %...', val_min, val_min + nb - 1;
       RETURN QUERY SELECT val_min + generate_series(0, nb - 1);
       RETURN;
    END IF;
    IF nb > (val_max - val_min + 1) / 2 THEN
       RAISE NOTICE 'nb is greater than half the range of requested values. Returning a % to % series EXCEPT TT_RandomInt(%, %, %, %)...', val_min, val_min + val_max - val_min, (val_max - val_min + 1) - nb, val_min, val_max, seed;
       RETURN QUERY SELECT * FROM (
                      SELECT val_min + generate_series(0, val_max - val_min) id
                      EXCEPT
                      SELECT TT_RandomInt((val_max - val_min + 1) - nb, val_min, val_max, seed)
                    ) foo ORDER BY id;
       RETURN;
    END IF;
    newnb = nb * (1 + 3 * nb::double precision / (val_max - val_min + 1));
--RAISE NOTICE 'newnb = %', newnb;
--RAISE NOTICE 'seed = %', nb / (nb + abs(seed) + 1);
    PERFORM setseed(nb / (nb + abs(seed) + 1));
    RETURN QUERY WITH rd AS (
                   SELECT (val_min + floor((val_max - val_min + 1) * foo.rd))::int id, foo.rd
                   FROM (SELECT generate_series(1, newnb), random() rd) foo
                 ), list AS (
                   SELECT DISTINCT rd.id
                   FROM rd LIMIT nb
                 ) SELECT * FROM list ORDER BY id;
  END;
$$ LANGUAGE plpgsql VOLATILE;
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_RandomInt(int, int, int);
CREATE OR REPLACE FUNCTION TT_RandomInt(
  nb int,
  val_min int,
  val_max int
)
RETURNS SETOF int AS $$
  SELECT TT_RandomInt(nb, val_min, val_max, random());
$$ LANGUAGE sql VOLATILE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_Histogram
--
-- Set function returnings a table representing an histogram of the values
-- for the specifed column.
--
-- The return table contains 3 columns:
--
--   'intervals' is a text column specifiing the lower and upper bounds of the
--               intervals (or bins). Start with '[' when the lower bound is
--               included in the interval and with ']' when the lowerbound is
--               not included in the interval. Complementarily ends with ']'
--               when the upper bound is included in the interval and with '['
--               when the upper bound is not included in the interval.
--
--   'cnt' is a integer column specifying the number of occurrence of the value
--         in this interval (or bin).
--
--   'query' is the query you can use to generate the rows accounted for in this
--           interval.
--
-- Self contained and typical example:
--
-- CREATE TABLE histogramtest AS
-- SELECT * FROM (VALUES (1), (2), (2), (3), (4), (5), (6), (7), (8), (9), (10)) AS t (val);
--
-- SELECT * FROM TT_Histogram('test', 'histogramtest1', 'val');
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_Histogram(text, text, text, int, text);
CREATE OR REPLACE FUNCTION TT_Histogram(
    schemaname text,
    tablename text,
    columnname text,
    nbinterval int DEFAULT 10, -- number of bins
    whereclause text DEFAULT NULL -- additional where clause
)
RETURNS TABLE (intervals text, cnt int, query text) AS $$
    DECLARE
    fqtn text;
    query text;
    newschemaname name;
    findnewcolumnname boolean := FALSE;
    newcolumnname text;
    columnnamecnt int := 0;
    whereclausewithwhere text := '';
    minval double precision := 0;
    maxval double precision := 0;
    columntype text;
    BEGIN
        IF nbinterval IS NULL THEN
            nbinterval = 10;
        END IF;
        IF nbinterval <= 0 THEN
            RAISE NOTICE 'nbinterval is smaller or equal to zero. Returning nothing...';
            RETURN;
        END IF;
        IF whereclause IS NULL OR whereclause = '' THEN
            whereclause = '';
        ELSE
            whereclausewithwhere = ' WHERE ' || whereclause || ' ';
            whereclause = ' AND (' || whereclause || ')';
        END IF;
        newschemaname := '';
        IF length(schemaname) > 0 THEN
            newschemaname := schemaname;
        ELSE
            newschemaname := 'public';
        END IF;
        fqtn := quote_ident(newschemaname) || '.' || quote_ident(tablename);

        -- Build an histogram with the column values.
        IF TT_ColumnExists(newschemaname, tablename, columnname) THEN

            -- Precompute the min and max values so we can set the number of interval to 1 if they are equal
            query = 'SELECT min(' || columnname || '), max(' || columnname || ') FROM ' || fqtn || whereclausewithwhere;
            EXECUTE QUERY query INTO minval, maxval;
            IF maxval IS NULL AND minval IS NULL THEN
                query = 'WITH values AS (SELECT ' || columnname || ' val FROM ' || fqtn || whereclausewithwhere || '),
                              histo  AS (SELECT count(*) cnt FROM values)
                         SELECT ''NULL''::text intervals,
                                cnt::int,
                                ''SELECT * FROM ' || fqtn || ' WHERE ' || columnname || ' IS NULL' || whereclause || ';''::text query
                         FROM histo;';
                RETURN QUERY EXECUTE query;
            ELSE
                IF maxval - minval = 0 THEN
                    RAISE NOTICE 'maximum value - minimum value = 0. Will create only 1 interval instead of %...', nbinterval;
                    nbinterval = 1;
                END IF;

                -- We make sure double precision values are converted to text using the maximum number of digits before computing summaries involving this type of values
                query = 'SELECT pg_typeof(' || columnname || ')::text FROM ' || fqtn || ' LIMIT 1';
                EXECUTE query INTO columntype;
                IF left(columntype, 3) != 'int' THEN
                    SET extra_float_digits = 3;
                END IF;

                -- Compute the histogram
                query = 'WITH values AS (SELECT ' || columnname || ' val FROM ' || fqtn || whereclausewithwhere || '),
                              bins   AS (SELECT val, CASE WHEN val IS NULL THEN -1 ELSE least(floor((val - ' || minval || ')*' || nbinterval || '::numeric/(' || (CASE WHEN maxval - minval = 0 THEN maxval + 0.000000001 ELSE maxval END) - minval || ')), ' || nbinterval || ' - 1) END bin, ' || (maxval - minval) || '/' || nbinterval || '.0 binrange FROM values),
                              histo  AS (SELECT bin, count(*) cnt FROM bins GROUP BY bin)
                         SELECT CASE WHEN serie = -1 THEN ''NULL''::text ELSE ''['' || (' || minval || ' + serie * binrange)::float8::text || '' - '' || (CASE WHEN serie = ' || nbinterval || ' - 1 THEN ' || maxval || '::float8::text || '']'' ELSE (' || minval || ' + (serie + 1) * binrange)::float8::text || ''['' END) END intervals,
                                coalesce(cnt, 0)::int cnt,
                                (''SELECT * FROM ' || fqtn || ' WHERE ' || columnname || ''' || (CASE WHEN serie = -1 THEN '' IS NULL'' || ''' || whereclause || ''' ELSE ('' >= '' || (' || minval || ' + serie * binrange)::float8::text || '' AND ' || columnname || ' <'' || (CASE WHEN serie = ' || nbinterval || ' - 1 THEN ''= '' || ' || maxval || '::float8::text ELSE '' '' || (' || minval || ' + (serie + 1) * binrange)::float8::text END) || ''' || whereclause || ''' || '' ORDER BY ' || columnname || ''') END) || '';'')::text query
                         FROM generate_series(-1, ' || nbinterval || ' - 1) serie
                              LEFT OUTER JOIN histo ON (serie = histo.bin),
                              (SELECT * FROM bins LIMIT 1) foo
                         ORDER BY serie;';
                RETURN QUERY EXECUTE query;
                IF left(columntype, 3) != 'int' THEN
                    RESET extra_float_digits;
                END IF;
            END IF;
        ELSE
            RAISE NOTICE '''%'' does not exists. Returning nothing...',columnname::text;
            RETURN;
        END IF;

        RETURN;
    END;
$$ LANGUAGE plpgsql VOLATILE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_ArrayDistinct
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ArrayDistinct(anyarray, boolean, boolean);
CREATE OR REPLACE FUNCTION TT_ArrayDistinct(
  anyarray,
  purgeNulls boolean DEFAULT FALSE,
  purgeEmptys boolean DEFAULT FALSE
)
RETURNS anyarray AS $$
  WITH numbered AS (
    SELECT ROW_NUMBER() OVER() rn, x
    FROM unnest($1) x
    WHERE (purgeNulls IS FALSE OR NOT x IS NULL) AND (purgeEmptys IS FALSE OR TT_NotEmpty(x::text))
  ), distincts AS (
    SELECT x, min(rn) rn FROM numbered GROUP BY x ORDER BY rn
)
SELECT array_agg(x) FROM distincts
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_DeleteAllViews
--
-- schemaName text
--
-- Delete all view in the specified schema.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_DeleteAllViews(text);
CREATE OR REPLACE FUNCTION TT_DeleteAllViews(
  schemaName text
)
RETURNS SETOF text AS $$
  DECLARE
    res RECORD;
  BEGIN
    FOR res IN SELECT 'DROP VIEW IF EXISTS ' || TT_FullTableName(schemaName, table_name) || ' CASCADE;' query
               FROM information_schema.tables
               WHERE lower(table_schema) = lower(schemaName) AND table_type = 'VIEW'
               ORDER BY table_name LOOP
      EXECUTE res.query;
      RETURN NEXT res.query;
    END LOOP;
    RETURN;
  END;
$$ LANGUAGE plpgsql VOLATILE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_CountEstimate
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_CountEstimate(text);
CREATE OR REPLACE FUNCTION TT_CountEstimate(
  query text
)
RETURNS integer AS $$
  DECLARE
    rec record;
    rows integer;
  BEGIN
    FOR rec IN EXECUTE 'EXPLAIN ' || query LOOP
      rows := substring(rec."QUERY PLAN" FROM ' rows=([[:digit:]]+)');
      EXIT WHEN rows IS NOT NULL;
    END LOOP;
    RETURN rows;
  END;
$$ LANGUAGE plpgsql VOLATILE STRICT;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_CreateMapping
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_CreateMapping(text, int, text, int);
CREATE OR REPLACE FUNCTION TT_CreateMapping(
  fromTableName text,
  fromLayer int,
  toTableName text,
  toLayer int
)
RETURNS TABLE (num int, key text, from_att text, to_att text, contributing boolean) AS $$
  DECLARE
    queryStr text;
  BEGIN
    IF NOT TT_TableExists('translation', 'attribute_dependencies') THEN
      RAISE EXCEPTION 'ERROR TT_CreateMapping(): Could not find table ''translation.dependencies''...';
    END IF;
    queryStr = 'WITH colnames AS (
    SELECT TT_TableColumnNames(''translation'', ''attribute_dependencies'') col_name_arr
  ), colnames_num AS (
    SELECT generate_series(1, cardinality(col_name_arr)) num, unnest(col_name_arr) colname
    FROM colnames
  ), from_att AS (
    -- Vertical table of all ''from'' attribute mapping
    SELECT (jsonb_each(to_jsonb(a.*))).*
    FROM translation.attribute_dependencies a
    WHERE lower(btrim(btrim(inventory_id, '' ''), '''''''')) = lower(''' || fromTableName || ''') AND layer = ' || fromLayer || '::text
  ), to_att AS (
    -- Vertical table of all ''to'' attribute mapping
    SELECT (jsonb_each(to_jsonb(a.*))).*
    FROM translation.attribute_dependencies a
    WHERE lower(btrim(btrim(inventory_id, '' ''), '''''''')) = lower(''' || toTableName || ''') AND layer = ' || toLayer || '::text
  ), splitted AS (
    -- Splitted by comma, still vertically
    SELECT colnames_num.num, from_att.key,
           --rtrim(ltrim(trim(regexp_split_to_table(btrim(from_att.value::text, ''"''), E'','')), ''[''), '']'') from_att,
           trim(regexp_split_to_table(btrim(from_att.value::text, ''"''), E'','')) from_att,
           trim(regexp_split_to_table(btrim(to_att.value::text, ''"''), E'','')) to_att
    FROM from_att, to_att, colnames_num
    WHERE colnames_num.colname = from_att.key AND
          from_att.key = to_att.key AND
          from_att.key != ''ogc_fid'' AND
          from_att.key != ''ttable_exists''
  )
  SELECT num, key,
         rtrim(ltrim(from_att, ''[''), '']'') from_att,
         rtrim(ltrim(to_att, ''[''), '']'') to_att,
         CASE WHEN left(from_att, 1) = ''['' AND right(from_att, 1) = '']'' THEN FALSE
              ELSE TRUE
         END contributing
  FROM splitted;';
    RETURN QUERY EXECUTE queryStr;
  END;
$$ LANGUAGE plpgsql VOLATILE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_CreateMappingView
--
-- Return a view mapping attributes of fromTableName to attributes of toTableName
-- according to the translation.attribute_dependencies table.
-- Can also be used to create a view selecting the minimal set of useful attribute
-- and to get a random sample of the source table when randomNb is provided.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_CreateMappingView(text, text, int, text, int, int, text, text);
--DROP FUNCTION IF EXISTS TT_CreateMappingView(text, text, int, text, int, int, text);
--DROP FUNCTION IF EXISTS TT_CreateMappingView(text, text, int, text, int, int);
--DROP FUNCTION IF EXISTS TT_CreateMappingView(text, text, int, text, int);
CREATE OR REPLACE FUNCTION TT_CreateMappingView(
  schemaName text,
  fromTableName text,
  fromLayer int,
  toTableName text,
  toLayer int,
  randomNb int DEFAULT NULL,
  rowSubset text DEFAULT NULL,
  viewNameSuffix text DEFAULT NULL
)
RETURNS text AS $$
  DECLARE
    queryStr text;
    viewName text;
    mappingRec RECORD;
    sourceTableCols text[] = '{}';
    attributeMapStr text;
    attributeArr text[] = '{}';
    whereExpArr text[] = '{}';
    whereExpLyrAddArr text[] = '{}';
    whereExpLyrNFLArr text[] = '{}';
    whereExpStr text = '';
    nb int;
    attName text;
    filteredTableName text;
    filteredNbColName text;
    attributeList boolean = FALSE;
    validRowSubset boolean = FALSE;
    attListViewName text = '';
    rowSubsetKeywords text[] = ARRAY['lyr', 'lyr2', 'nfl', 'dst', 'eco'];
    maxLayerNb int = 0;
  BEGIN
    -- Check if table 'attribute_dependencies' exists
    IF NOT TT_TableExists('translation', 'attribute_dependencies') THEN
      RAISE NOTICE 'ERROR TT_CreateMappingView(): Could not find table ''translation.dependencies''...';
      RETURN 'ERROR: Could not find table ''translation.dependencies''...';
    END IF;

    -- Check if table fromTableName exists
    IF NOT TT_TableExists(schemaName, fromTableName) THEN
      RAISE NOTICE 'ERROR TT_CreateMappingView(): Could not find table ''translation.%''...', fromTableName;
      RETURN 'ERROR: Could not find table ''translation..' || fromTableName || '''...';
    END IF;

    -- Check if an entry for (fromTableName, fromLayer) exists in table 'attribute_dependencies'
    SELECT count(*) FROM translation.attribute_dependencies
    WHERE lower(btrim(btrim(inventory_id, ' '), '''')) = lower(fromTableName) AND layer = fromLayer::text
    INTO nb;
    IF nb = 0 THEN
      RAISE NOTICE 'ERROR TT_CreateMappingView(): No entry found for inventory_id ''%'' layer % in table ''translation.dependencies''...', fromTableName, fromLayer;
      RETURN 'ERROR: No entry could be found for inventory_id '''  || fromTableName || ''' layer ' || fromLayer || ' in table ''translation.dependencies''...';
    ELSIF nb > 1 THEN
      RAISE NOTICE 'ERROR TT_CreateMappingView(): More than one entry match inventory_id ''%'' layer % in table ''translation.dependencies''...', fromTableName, fromLayer;
      RETURN 'ERROR: More than one entry match inventory_id '''  || fromTableName || ''' layer ' || fromLayer || ' in table ''translation.dependencies''...';
    END IF;

    -- Support a variant where rowSubset is the third parameter (not toTableName)
    sourceTableCols = TT_TableColumnNames(schemaName, fromTableName);
    IF fromLayer = 1 AND toLayer = 1 AND randomNb IS NULL AND viewNameSuffix IS NULL AND
       (lower(toTableName) = ANY (rowSubsetKeywords)  OR
        strpos(toTableName, ',') != 0 OR btrim(toTableName, ' ') = ANY (sourceTableCols)) THEN
      RAISE NOTICE 'TT_CreateMappingView(): Switching viewNameSuffix, rowSubset and toTableName...';
      viewNameSuffix = rowSubset;
      rowSubset = toTableName;
      toTableName = fromTableName;
    END IF;
    rowSubset = lower(btrim(rowSubset, ' '));

    -- Check rowSubset is a valid value
    IF NOT rowSubset IS NULL THEN
      -- If rowSubset is a reserved keyword
      IF rowSubset = ANY (rowSubsetKeywords) THEN
        -- We will later name the VIEW based on rowSubset
        IF viewNameSuffix IS NULL THEN
          viewNameSuffix = rowSubset;
        ELSE
          viewNameSuffix = rowSubset || '_' || viewNameSuffix;
        END IF;
        validRowSubset = TRUE;
      -- If rowSubset is a list of attributes
      ELSIF (strpos(rowSubset, ',') != 0 OR rowSubset = ANY (sourceTableCols)) THEN
        attributeArr = string_to_array(rowSubset, ',');
        FOREACH attName IN ARRAY attributeArr LOOP
          attName = btrim(attName, ' ');
          IF NOT attName = ANY (sourceTableCols) THEN
            RAISE NOTICE 'ERROR TT_CreateMappingView(): Attribute ''%'' in ''rowSubset'' not found in table ''translation.%''...', attName, fromTableName;
            RETURN 'ERROR: Attribute ''' || attName || ''' in ''rowSubset'' not found in table ''translation.''' || fromTableName || '''...';
          END IF;
          whereExpArr = array_append(whereExpArr, '(TT_NotEmpty(' || attName || '::text) AND ' || attName || '::text != ''0'')');
          attListViewName = attListViewName || lower(left(attName, 1));
        END LOOP;
        IF viewNameSuffix IS NULL THEN
          viewNameSuffix = attListViewName;
        END IF;
        attributeList = TRUE;
        validRowSubset = TRUE;
      ELSE
        RAISE NOTICE 'ERROR TT_CreateMappingView(): Invalid rowSubset value (%)...', rowSubset;
        RETURN 'ERROR: Invalid rowSubset value (' || rowSubset || ')...';
      END IF;
    END IF;

    -- Check if an entry for (toTableName, toLayer) exists in table 'attribute_dependencies'
    SELECT count(*) FROM translation.attribute_dependencies
    WHERE lower(btrim(btrim(inventory_id, ' '), '''')) = lower(toTableName) AND layer = toLayer::text
    INTO nb;
    IF nb = 0 THEN
      RAISE NOTICE 'ERROR TT_CreateMappingView(): No entry found for inventory_id ''%'' layer % in table ''translation.dependencies''...', toTableName, toLayer;
      RETURN 'ERROR: No entry could be found for inventory_id '''  || toTableName || ''' layer ' || toLayer || ' in table ''translation.dependencies''...';
    ELSIF nb > 1 THEN
      RAISE NOTICE 'ERROR TT_CreateMappingView(): More than one entry match inventory_id ''%'' layer % in table ''translation.dependencies''...', toTableName, toLayer;
      RETURN 'ERROR: More than one entry match inventory_id '''  || toTableName || ''' layer ' || toLayer || ' in table ''translation.dependencies''...';
    END IF;

    -- Build the attribute mapping string
      WITH mapping AS (
        SELECT * FROM TT_CreateMapping(fromTableName, fromLayer, toTableName, toLayer)
      ), unique_att AS (
      -- Create only one map for each 'to' attribute (there can not be more than one)
      SELECT DISTINCT ON (to_att)
         num, key,
         -- Make sure to quote the 'from' part if it is a constant
         CASE WHEN TT_IsName(from_att) AND lower(key) != 'inventory_id' THEN from_att
              ELSE '''' || btrim(from_att, '''') || ''''
         END from_att,
         -- If the 'to' part is a contant, map the 'from' attribute to itself. They will be fixed later.
         CASE WHEN TT_IsName(to_att) THEN to_att
              WHEN TT_IsName(from_att) THEN from_att
              ELSE key
         END to_att
      FROM mapping
      WHERE NOT from_att IS NULL AND from_att != ''
      ORDER BY to_att, from_att
    ), ordered_maps AS (
      SELECT num, key,
             from_att || CASE WHEN from_att = to_att THEN ''
                              ELSE ' AS ' || to_att
                         END mapstr,
             CASE WHEN key = ANY (ARRAY['inventory_id', 'layer', 'layer_rank', 'cas_id', 'orig_stand_id', 'stand_structure', 'num_of_layers', 'map_sheet_id', 'casfri_area', 'casfri_perimeter', 'src_inv_area', 'stand_photo_year']) THEN 1
                  WHEN key = ANY (ARRAY['soil_moist_reg', 'structure_per', 'crown_closure_upper', 'crown_closure_lower', 'height_upper', 'height_lower', 'productive_for']) THEN 2
                  WHEN key = ANY (ARRAY['species_1', 'species_per_1', 'species_2', 'species_per_2', 'species_3', 'species_per_3', 'species_4', 'species_per_4', 'species_5', 'species_per_5', 'species_6', 'species_per_6', 'species_7', 'species_per_7', 'species_8', 'species_per_8', 'species_9', 'species_per_9', 'species_10', 'species_per_10']) THEN 3
                  WHEN key = ANY (ARRAY['origin_upper', 'origin_lower', 'site_class', 'site_index']) THEN 4
                  WHEN key = ANY (ARRAY['nat_non_veg', 'non_for_anth', 'non_for_veg']) THEN 5
                  WHEN key = ANY (ARRAY['dist_type_1', 'dist_year_1', 'dist_ext_upper_1', 'dist_ext_lower_1']) THEN 6
                  WHEN key = ANY (ARRAY['dist_type_2', 'dist_year_2', 'dist_ext_upper_2', 'dist_ext_lower_2']) THEN 7
                  WHEN key = ANY (ARRAY['dist_type_3', 'dist_year_3', 'dist_ext_upper_3', 'dist_ext_lower_3']) THEN 8
                  WHEN key = ANY (ARRAY['wetland_type', 'wet_veg_cover', 'wet_landform_mod', 'wet_local_mod', 'eco_site']) THEN 9
                  ELSE 10
             END groupid
      FROM unique_att ORDER BY num
    )
    SELECT string_agg(str, ', ' || chr(10))
    FROM (SELECT string_agg(mapstr, ', ') str
          FROM ordered_maps
          GROUP BY groupid
          ORDER BY groupid) foo
    INTO attributeMapStr;

    -- Determine max_layer_number and add it to the list of attributes
    maxLayerNb = CASE WHEN rowSubset IS NULL OR rowSubset != 'nfl' THEN fromLayer ELSE fromLayer + 2 END;
    attributeMapStr = attributeMapStr || ', ' || maxLayerNb || ' max_layer_number';
  
    -- Build the WHERE string
    IF validRowSubset AND NOT attributeList THEN
      FOR mappingRec IN SELECT *
                        FROM TT_CreateMapping(fromTableName, fromLayer, toTableName, toLayer)
                        WHERE TT_NotEmpty(from_att) LOOP
        IF mappingRec.contributing AND (((rowSubset = 'lyr' OR rowSubset = 'lyr2') AND (mappingRec.key = 'species_1' OR mappingRec.key = 'species_2' OR mappingRec.key = 'species_3')) OR
           (rowSubset = 'nfl' AND (mappingRec.key = 'nat_non_veg' OR mappingRec.key = 'non_for_anth' OR mappingRec.key = 'non_for_veg')) OR
           (rowSubset = 'dst' AND (mappingRec.key = 'dist_type_1' OR mappingRec.key = 'dist_year_1' OR mappingRec.key = 'dist_type_2' OR mappingRec.key = 'dist_year_2' OR mappingRec.key = 'dist_type_3' OR mappingRec.key = 'dist_year_3')) OR
           (rowSubset = 'eco' AND mappingRec.key = 'wetland_type'))
        THEN
          whereExpArr = array_append(whereExpArr, '(TT_NotEmpty(' || mappingRec.from_att || '::text) AND ' || mappingRec.from_att || '::text != ''0'')');
        END IF;
        IF rowSubset = 'lyr2' THEN
          -- Add soil_moist_reg, site_class and site_index
          IF mappingRec.contributing AND (mappingRec.key = 'soil_moist_reg' OR mappingRec.key = 'site_class' OR mappingRec.key = 'site_index') THEN
            whereExpLyrAddArr = array_append(whereExpLyrAddArr, '(TT_NotEmpty(' || mappingRec.from_att || '::text) AND ' || mappingRec.from_att || '::text != ''0'')');
          END IF;
          -- Except when any NFL attribute is set
          IF mappingRec.contributing AND (mappingRec.key = 'nat_non_veg' OR mappingRec.key = 'non_for_anth' OR mappingRec.key = 'non_for_veg' OR mappingRec.key = 'dist_type_1' OR mappingRec.key = 'dist_type_2') THEN
            whereExpLyrNFLArr = array_append(whereExpLyrNFLArr, '(TT_NotEmpty(' || mappingRec.from_att || '::text) AND ' || mappingRec.from_att || '::text != ''0'')');
          END IF;
        END IF;
      END LOOP;
    END IF;

    nb = NULL;
    -- Concatenate the WHERE attribute into a string
    IF cardinality(whereExpArr) = 0 AND validRowSubset THEN
      whereExpStr = '  WHERE FALSE = TRUE';
      nb = 0;
    ELSIF cardinality(whereExpArr) > 0 THEN
      whereExpStr = '  WHERE ' || array_to_string(TT_ArrayDistinct(whereExpArr), ' OR ' || chr(10) || '        ');
    
      -- Add extra condition for lyr including soil_moist_reg, site_class and site_index when NFL attributes are not set
      IF rowSubset = 'lyr2' THEN
        whereExpStr = whereExpStr || ' OR ' || chr(10) ||
                      '        ((' || array_to_string(TT_ArrayDistinct(whereExpLyrAddArr), ' OR ' || chr(10) || '          ') || ') AND ' || chr(10) ||
                      '         NOT (' || array_to_string(TT_ArrayDistinct(whereExpLyrNFLArr), ' OR ' || chr(10) || '              ') || '))';
      END IF;
    END IF;

    -- Contruct the name of the VIEW
    viewName = TT_FullTableName(schemaName, fromTableName ||
               CASE WHEN fromTableName = toTableName AND fromLayer = toLayer AND fromLayer != 1 THEN '_min_l' || fromLayer
                    WHEN fromTableName = toTableName AND fromLayer = toLayer THEN '_min'
                    ELSE '_l' || fromLayer || '_to_' || toTableName || '_l' || toLayer || '_map'
               END || coalesce('_' || randomNb, '') || coalesce('_' || viewNameSuffix, ''));

    -- Build the VIEW query
    queryStr = 'DROP VIEW IF EXISTS ' || viewName || ' CASCADE;' || chr(10) ||
               'CREATE OR REPLACE VIEW ' || viewName || ' AS' || chr(10);
  
    filteredTableName = TT_FullTableName(schemaName, fromTableName);
    filteredNbColName = 'ogc_fid';
    IF TT_NotEmpty(whereExpStr) THEN
      filteredTableName = 'filtered_rows_nb';
      filteredNbColName = 'rownb';
      queryStr = queryStr ||
                 'WITH filtered_rows AS (' || chr(10) ||
                 '  SELECT *' || chr(10) ||
                 '  FROM ' || TT_FullTableName(schemaName, fromTableName) || chr(10) ||
                 whereExpStr || chr(10) ||
                 '), filtered_rows_nb AS (' || chr(10) ||
                 '  SELECT ROW_NUMBER() OVER(ORDER BY ogc_fid) ' || filteredNbColName || ', filtered_rows.*' || chr(10) ||
                 '  FROM filtered_rows' || chr(10) ||
                 ')' || chr(10);
    END IF;
    queryStr = queryStr ||
               'SELECT ' || attributeMapStr || chr(10) ||
               'FROM ' || filteredTableName || ' fr';

    -- Make it random if requested
    IF NOT randomNb IS NULL THEN
      queryStr = queryStr || ', TT_RandomInt(' || randomNb || ', 1, (SELECT count(*) FROM ' || filteredTableName || ')::int, 1.0) rd' || chr(10) ||
                'WHERE rd.id = fr.' || filteredNbColName || chr(10) ||
                'LIMIT ' || randomNb || ';';
    END IF;
    RAISE NOTICE 'TT_CreateMappingView(): Creating VIEW ''%''...', viewName;
    EXECUTE queryStr;
  
    -- Display the approximate number of row returned by the view
    IF nb IS NULL THEN
      nb = TT_CountEstimate('SELECT 1 FROM ' || viewName);
    END IF;
    IF nb < 2 THEN
      RAISE NOTICE 'WARNING TT_CreateMappingView(): VIEW ''%'' should return 0 rows...', viewName;
    ELSIF nb < 1000 THEN
       RAISE NOTICE 'TT_CreateMappingView(): VIEW ''%'' should return % rows...', viewName, nb;
    ELSE
      RAISE NOTICE 'TT_CreateMappingView(): VIEW ''%'' should return at least 1000 rows or more...', viewName;
    END IF;
    RETURN queryStr;
  END;
$$ LANGUAGE plpgsql VOLATILE;
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_CreateMappingView(text, text, int, text, int, text, text);
CREATE OR REPLACE FUNCTION TT_CreateMappingView(
  schemaName text,
  fromTableName text,
  fromLayer int,
  toTableName text,
  toLayer int,
  rowSubset text,
  viewNameSuffix text DEFAULT NULL
)
RETURNS text AS $$
  SELECT TT_CreateMappingView(schemaName, fromTableName, fromLayer, toTableName, toLayer, NULL, rowSubset, viewNameSuffix);
$$ LANGUAGE sql VOLATILE;
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_CreateMappingView(text, text, text, int, text, text);
CREATE OR REPLACE FUNCTION TT_CreateMappingView(
  schemaName text,
  fromTableName text,
  toTableName text,
  randomNb int DEFAULT NULL,
  rowSubset text DEFAULT NULL,
  viewNameSuffix text DEFAULT NULL
)
RETURNS text AS $$
  SELECT TT_CreateMappingView(schemaName, fromTableName, 1, toTableName, 1, randomNb, rowSubset, viewNameSuffix);
$$ LANGUAGE sql VOLATILE;
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_CreateMappingView(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_CreateMappingView(
  schemaName text,
  fromTableName text,
  toTableName text,
  rowSubset text,
  viewNameSuffix text DEFAULT NULL
)
RETURNS text AS $$
  SELECT TT_CreateMappingView(schemaName, fromTableName, 1, toTableName, 1, NULL, rowSubset, viewNameSuffix);
$$ LANGUAGE sql VOLATILE;
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_CreateMappingView(text, text, int, text, text);
CREATE OR REPLACE FUNCTION TT_CreateMappingView(
  schemaName text,
  fromTableName text,
  randomNb int DEFAULT NULL,
  rowSubset text DEFAULT NULL,
  viewNameSuffix text DEFAULT NULL
)
RETURNS text AS $$
  SELECT TT_CreateMappingView(schemaName, fromTableName, 1, fromTableName, 1, randomNb, rowSubset, viewNameSuffix);
$$ LANGUAGE sql VOLATILE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_CreateFilterView
--
-- Create a VIEW listing only the 'selectAttrList' WHERE 'whereInAttrList' are
-- TT_NotEmpty() and 'whereOutAttrList' are NOT TT_NotEmpty(). The name
-- of the view can be suffixed with viewNameSuffix. Otherwise it will get a
-- random number.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_CreateFilterView(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_CreateFilterView(
  schemaName text,
  tableName text,
  selectAttrList text,
  whereInAttrList text DEFAULT '',
  whereOutAttrList text DEFAULT '',
  viewNameSuffix text DEFAULT NULL
)
RETURNS text AS $$
  DECLARE
    queryStr text;
    viewName text;
    fullTableName text = TT_FullTableName(schemaName, tableName);
    mappingRec RECORD;
    sourceTableCols text[] = '{}';
    keywordArr text[] = ARRAY['lyr1', 'lyr2', 'lyr3', 'nfl1', 'nfl2', 'nfl3', 'nfl4', 'nfl5', 'nfl6', 'dst1', 'dst2', 'eco'];
    keyword text;
    nb int;
    layer text;
    attName text;
    attArr text[] = '{}';
    sigAttArr text[] = '{}';
    attList text;
    sigAttList text;
    selectAttrArr text[] = '{}';
    whereInAttrArr text[] = '{}';
    whereInAttrStrArr text[] = '{}';
    whereOutAttrArr text[] = '{}';
    whereOutAttrStrArr text[] = '{}';
    whereInAttrListArr text[] = '{}';
    attCount int = 0;
    trimmedAttName text;
    indentStr text;
  BEGIN
    -- Check if table 'attribute_dependencies' exists
    IF NOT TT_TableExists('translation', 'attribute_dependencies') THEN
      RAISE NOTICE 'ERROR TT_CreateFilterView(): Could not find table ''translation.dependencies''...';
      RETURN 'ERROR: Could not find table ''translation.dependencies''...';
    END IF;

    -- Check if tableName exists
    IF NOT TT_TableExists(schemaName, tableName) THEN
      RAISE NOTICE 'ERROR TT_CreateFilterView(): Could not find table ''translation.%''...', tableName;
      RETURN 'ERROR: Could not find table ''translation..' || tableName || '''...';
    END IF;

    -- For whereInAttrList only, replace each comma inside two brackets with a special keyword that will be replaced with AND later
    whereInAttrList = regexp_replace(whereInAttrList, '(?<=\[.*\s*)(,)(?=\s*.*\])', ', CASFRI_AND,', 'g');

    -- Replace selectAttrList CASFRI attribute with their mapping attributes
    FOR mappingRec IN SELECT key, string_agg(from_att, ', ') attrs
                      FROM TT_CreateMapping(tableName, 1, tableName, 1)
                      WHERE TT_NotEmpty(from_att) AND key != 'inventory_id' AND key != 'layer'
                      GROUP BY key
    LOOP
       selectAttrList = regexp_replace(lower(selectAttrList), '\m' || mappingRec.key || '\M', mappingRec.attrs, 'g');
    END LOOP;

    -- Replace whereInAttrList and whereOutAttrList CASFRI attributes with their mapping attribute. only the
    FOR mappingRec IN SELECT key, string_agg(from_att, ', ') attrs
                      FROM TT_CreateMapping(tableName, 1, tableName, 1)
                      WHERE TT_NotEmpty(from_att) AND contributing AND key != 'inventory_id' AND key != 'layer'
                      GROUP BY key
    LOOP
       whereInAttrList = regexp_replace(lower(whereInAttrList), mappingRec.key || '\M', mappingRec.attrs, 'g');
       whereOutAttrList = regexp_replace(lower(whereOutAttrList), mappingRec.key || '\M', mappingRec.attrs, 'g');
    END LOOP;

     -- Loop through all the possible keywords building the list of attributes from attribute_dependencies and replacing them in the 3 provided lists of attributes
    FOREACH keyword IN ARRAY keywordArr LOOP
      -- Determine from which layer to grab the attributes
      layer = right(keyword, 1);
      IF NOT layer IN ('1', '2', '3', '4', '5', '6') THEN layer = '1'; END IF;
    
      -- Initialize the two attribute arrays, one for all of them and one for only contributing ones
      attArr = '{}';
      sigAttArr = '{}';
    
      -- Loop through all attribute_dependencies row mapping
      FOR mappingRec IN SELECT *
                        FROM TT_CreateMapping(tableName, layer::int, tableName, layer::int)
                        WHERE TT_NotEmpty(from_att)
      LOOP
        -- Pick attributes corresponding to keywords
        IF ((keyword = 'lyr1' OR keyword = 'lyr2' OR keyword = 'lyr3') AND (mappingRec.key = 'species_1' OR mappingRec.key = 'species_2' OR mappingRec.key = 'species_3')) OR
           ((keyword = 'nfl1' OR keyword = 'nfl2' OR keyword = 'nfl3' OR
             keyword = 'nfl4' OR keyword = 'nfl5' OR keyword = 'nfl6') AND (mappingRec.key = 'nat_non_veg' OR mappingRec.key = 'non_for_anth' OR mappingRec.key = 'non_for_veg')) OR
           ((keyword = 'dst1' OR keyword = 'dst2') AND (mappingRec.key = 'dist_type_1' OR mappingRec.key = 'dist_year_1' OR
                                                        mappingRec.key = 'dist_ext_upper_1' OR mappingRec.key = 'dist_ext_lower_1' OR
                                                        mappingRec.key = 'dist_type_2' OR mappingRec.key = 'dist_year_2' OR
                                                        mappingRec.key = 'dist_ext_upper_2' OR mappingRec.key = 'dist_ext_lower_2' OR
                                                        mappingRec.key = 'dist_type_3' OR mappingRec.key = 'dist_year_3' OR
                                                        mappingRec.key = 'dist_ext_upper_3' OR mappingRec.key = 'dist_ext_lower_3')) OR
           (keyword = 'eco' AND (mappingRec.key = 'wetland_type' OR mappingRec.key = 'wet_veg_cover' OR mappingRec.key = 'wet_landform_mod' OR mappingRec.key = 'wet_local_mod'))
        THEN
          -- Append both attributes lists
          attArr = array_append(attArr, lower(mappingRec.from_att));
          sigAttArr = array_append(sigAttArr, CASE WHEN mappingRec.contributing THEN lower(mappingRec.from_att) ELSE NULL END);
        END IF;
      END LOOP;
      -- Convert the first list to a string
      attList = array_to_string(TT_ArrayDistinct(attArr, TRUE), ', ');

      -- Warn if some keywords do not correspond to any attribute
      IF strpos(lower(selectAttrList), keyword) != 0 AND attList IS NULL THEN
        RAISE NOTICE 'WARNING TT_CreateFilterView(): No attributes for keyword ''%'' found in table ''%.%''...', keyword, schemaName, tableName;
      END IF;

      -- Replace keywords with attributes
      selectAttrList = regexp_replace(lower(selectAttrList), keyword || '\s*(,)?\s*', CASE WHEN attList != '' THEN attList || '\1' ELSE '' END, 'g');
      -- Standardise commas and spaces
      selectAttrList = regexp_replace(selectAttrList, '\s*,\s*', ', ', 'g');

      -- Convert the second list to a string
      sigAttList = array_to_string(TT_ArrayDistinct(sigAttArr, TRUE), ', ');
    
      -- Warn if some whereInAttrList keywords do not correspond to any attribute
      IF strpos(lower(whereInAttrList), keyword) != 0 AND sigAttList IS NULL THEN
        RAISE NOTICE 'WARNING TT_CreateFilterView(): No attributes for keyword ''%'' found in table ''%.%''...', keyword, schemaName, tableName;
      END IF;

      -- Replace keywords with attributes
      whereInAttrList = regexp_replace(lower(whereInAttrList), '\s*(,)?\s*(casfri_and)?\s*(,)?\s*' || keyword || '\s*(,)?\s*', CASE WHEN sigAttList != '' THEN '\1\2\3' || sigAttList || '\4' ELSE '' END, 'g');
      -- Standardise commas and spaces
      whereInAttrList = regexp_replace(whereInAttrList, '\s*,\s*', ', ', 'g');
      -- Remove remaining empty brackets
      whereInAttrList = regexp_replace(whereInAttrList, '\[\s*\],?\s*', '', 'g');

      -- Warn if some whereOutAttrList keywords do not correspond to any attribute
      IF strpos(lower(whereOutAttrList), keyword) != 0 AND sigAttList IS NULL THEN
        RAISE NOTICE 'WARNING TT_CreateFilterView(): No attributes for keyword ''%'' found in table ''%.%''...', keyword, schemaName, tableName;
      END IF;
    
      -- Replace keywords with attributes
      whereOutAttrList = regexp_replace(lower(whereOutAttrList), keyword || '\s*(,)?\s*', CASE WHEN attList != '' THEN attList || '\1' ELSE '' END, 'g');
      -- Standardise commas and spaces
      whereOutAttrList = regexp_replace(whereOutAttrList, '\s*,\s*', ', ', 'g');
    END LOOP;

    -- Parse and validate the list of provided attributes against the list of attribute in the table
    sourceTableCols = TT_TableColumnNames(schemaName, tableName);

    -- selectAttrArr
    selectAttrArr = TT_ArrayDistinct(regexp_split_to_array(selectAttrList, '\s*,\s*'), TRUE, TRUE);
    FOREACH attName IN ARRAY coalesce(selectAttrArr, '{}'::text[]) LOOP
      IF NOT attName = ANY (sourceTableCols) THEN
        RAISE NOTICE 'WARNING TT_CreateFilterView(): ''selectAttrList'' parameter''s ''%'' attribute not found in table ''%.%''...', attName, schemaName, tableName;
        --RETURN 'ERROR TT_CreateFilterView(): ''selectAttrList'' parameter''s ''' || attName || ''' attribute not found in table ''' || schemaName || '.' || tableName || '''...';
      END IF;
    END LOOP;

    -- Build the selectAttrArr string
    IF selectAttrArr IS NULL OR cardinality(selectAttrArr) = 0 THEN
      selectAttrList = '*';
    ELSE
      selectAttrList = array_to_string(selectAttrArr, ', ');
    END IF;

    -- whereInAttrArr
    whereInAttrArr = CASE WHEN whereInAttrList = '' THEN '{}'::text[]
                          ELSE regexp_split_to_array(whereInAttrList, '\s*,\s*') END;
    whereInAttrList = '';
    IF 'casfri_and' = ANY (whereInAttrArr) THEN
      indentStr = '        ';
    ELSE
      indentStr = '      ';
    END IF;
    FOREACH attName IN ARRAY coalesce(whereInAttrArr, '{}'::text[]) LOOP
      attCount = attCount + 1;
      IF left(attName, 1) = '[' AND 'casfri_and' = ANY (whereInAttrArr) THEN
        IF attCount != 1 THEN
          whereInAttrList = whereInAttrList || chr(10) || '       ' || 'OR' || chr(10) || indentStr;
        END IF;      
        whereInAttrList = whereInAttrList || '(';
        attCount = 1;
      END IF;
      trimmedAttName = rtrim(ltrim(attName, '['), ']');
      IF trimmedAttName = 'casfri_and' THEN
        whereInAttrList = whereInAttrList || ')'  || chr(10) || '       ' || 'AND'  || chr(10) || indentStr || '(';
        attCount = 0;
      ELSE
        IF NOT trimmedAttName = ANY (sourceTableCols) THEN
          RAISE NOTICE 'WARNING TT_CreateFilterView(): ''whereInAttrList'' parameter''s ''%'' attribute not found in table ''%.%''. Removed from the WHERE clause...', trimmedAttName, schemaName, tableName;
          --RETURN 'ERROR TT_CreateFilterView(): ''whereInAttrList'' parameter''s ''' || trimmedAttName || ''' attribute not found in table ''' || schemaName || '.' || tableName || '''...';
        ELSE
          IF attCount != 1 THEN
            whereInAttrList = whereInAttrList || ' OR ' || chr(10) || indentStr;
          END IF;
          whereInAttrList = whereInAttrList || '(TT_NotEmpty(' || trimmedAttName || '::text) AND ' || trimmedAttName || '::text != ''0'')';
        END IF;
      END IF;
      IF right(attName, 1) = ']' AND 'casfri_and' = ANY (whereInAttrArr) THEN
        whereInAttrList = whereInAttrList || ')' || chr(10) || '      ';
      END IF;
    END LOOP;

    -- whereOutAttrArr
    whereOutAttrArr = TT_ArrayDistinct(regexp_split_to_array(whereOutAttrList, '\s*,\s*'), TRUE, TRUE);

    -- Build the whereOutAttrArr string
    FOREACH attName IN ARRAY coalesce(whereOutAttrArr, '{}'::text[]) LOOP
      IF NOT attName = ANY (sourceTableCols) THEN
        RAISE NOTICE 'WARNING TT_CreateFilterView(): ''whereOutAttrList'' parameter''s ''%'' attribute not found in table ''%.%''. Removed from the WHERE clause...', attName, schemaName, tableName;
        --RETURN 'ERROR TT_CreateFilterView(): ''whereOutAttrList'' parameter''s ''' || attName || ''' attribute not found in table ''' || schemaName || '.' || tableName || '''...';
      ELSE
        whereOutAttrStrArr = array_append(whereOutAttrStrArr, '(TT_NotEmpty(' || attName || '::text) AND ' || attName || '::text != ''0'')');
      END IF;
    END LOOP;
    whereOutAttrList = array_to_string(whereOutAttrStrArr, ' OR ' || chr(10) || indentStr);

    -- Construct the name of the VIEW
    viewName = fullTableName || coalesce('_' || viewNamesuffix, '_' || (random()*100)::int::text);

    -- Build the VIEW query
    queryStr = 'DROP VIEW IF EXISTS ' || viewName || ' CASCADE;' || chr(10) ||
               'CREATE OR REPLACE VIEW ' || viewName || ' AS' || chr(10) ||
               'SELECT ' || selectAttrList || chr(10) ||
               'FROM ' || fullTableName;
             
    IF whereInAttrList != '' OR whereOutAttrList != '' THEN
      queryStr = queryStr || chr(10) || 'WHERE ';
      IF whereInAttrList != '' AND whereOutAttrList != '' THEN
        queryStr = queryStr || '(';
      END IF;
      IF whereInAttrList != '' THEN
        queryStr = queryStr || whereInAttrList;
      END IF;
      IF whereInAttrList != '' AND whereOutAttrList != '' THEN
        queryStr = queryStr || ')' || chr(10) || '      AND ';
      END IF;
      IF whereOutAttrList != '' THEN
        queryStr = queryStr || 'NOT' || chr(10) || '       (' || whereOutAttrList || ')';
      END IF;
    END IF;
    queryStr = queryStr  || ';';

    -- Create the VIEW
    RAISE NOTICE 'TT_CreateFilterView(): Creating VIEW ''%''...', viewName;
    EXECUTE queryStr;
  
    -- Display the approximate number of row returned by the view
    nb = TT_CountEstimate('SELECT 1 FROM ' || viewName);
    IF nb < 2 THEN
      RAISE NOTICE 'WARNING TT_CreateFilterView(): VIEW ''%'' should return 0 rows...', viewName;
    ELSIF nb < 1000 THEN
       RAISE NOTICE 'TT_CreateFilterView(): VIEW ''%'' should return % rows...', viewName, nb;
    ELSE
      RAISE NOTICE 'TT_CreateFilterView(): VIEW ''%'' should return at least 1000 rows or more...', viewName;
    END IF;
    RETURN queryStr;
  END;
$$ LANGUAGE plpgsql VOLATILE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_StackTranslationRules
--
-- List all target_attribute rules vertically for easy comparison for the provided
-- translation tables or for the 'cas', 'lyr', 'nfl', 'dst', 'eco' or 'geo' keywords.
--
-- e.g.
-- SELECT * FROM TT_StackTranslationRules('translation', 'ab06_avi01_nfl, ab16_avi01_nfl');
--
-- SELECT * FROM TT_StackTranslationRules('nfl');
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_StackTranslationRules(text, text);
CREATE OR REPLACE FUNCTION TT_StackTranslationRules(
  schemaName text,
  transTableList text DEFAULT NULL
)
RETURNS TABLE (ttable text,
               rule_id int,
               target_attribute text,
               target_attribute_type text,
               validation_rules text,
               translation_rules text
) AS $$
  DECLARE
    query text = '';
    attrPart text = '';
    wherePart text = 'WHERE ';
    attributeArr text[];
    attributeArrOld text[];
    tTableArr text[];
    tTable text;
    attr text;
    nb int = 1;
    nb2 int = 1;
  BEGIN
    -- Handle when only one keyword parameter is provided instead of a schema and a table
    IF transTableList IS NULL AND lower(schemaName) IN ('cas', 'lyr', 'nfl', 'dst', 'eco', 'geo') THEN
      transTableList = 'ab_avi01_' || lower(schemaName) || ', ' ||
                       'bc_vri01_' || lower(schemaName) || ', ' ||
                       'mb_fli01_' || lower(schemaName) || ', ' ||
                       'mb_fri01_' || lower(schemaName) || ', ' ||
                       'mb_fri02_' || lower(schemaName) || ', ' ||
                       'nb_nbi01_' || lower(schemaName) || ', ' ||
                       'nl_nli01_' || lower(schemaName) || ', ' ||
                       'ns_nsi01_' || lower(schemaName) || ', ' ||
                       'nt_fvi01_' || lower(schemaName) || ', ' ||
                       'on_fim02_' || lower(schemaName) || ', ' ||
                       'pc_panp01_' || lower(schemaName) || ', ' ||
                       'pc_wbnp01_' || lower(schemaName) || ', ' ||
                       'pe_pei01_' || lower(schemaName) || ', ' ||
                       'pe_pei02_' || lower(schemaName) || ', ' ||
                       'qc_ini03_' || lower(schemaName) || ', ' ||
                       'qc_ini04_' || lower(schemaName) || ', ' ||
                       'qc_ipf05_' || lower(schemaName) || ', ' ||
                       'sk_sfv01_' || lower(schemaName) || ', ' ||
                       'sk_utm01_' || lower(schemaName) || ', ' ||
                       'yt_yvi01_' || lower(schemaName) || ', ' ||
                       'yt_yvi02_' || lower(schemaName) || ', ' ||
                       'yt_yvi03_' || lower(schemaName);
      schemaName = 'translation';
                     
    END IF;
  
    -- Parse the list of translation tables
    tTableArr = regexp_split_to_array(transTableList, '\s*,\s*');

    nb = 1;
    query = 'SELECT ttable, rule_id, target_attribute, target_attribute_type, validation_rules, translation_rules FROM (' || chr(10);
    FOREACH tTable IN ARRAY tTableArr LOOP
      IF NOT TT_TableExists(schemaName, tTable) THEN
        RAISE EXCEPTION 'TT_StackTranslationRules() ERROR: Table ''%.%'' does not exist...', schemaName, tTable;
      END IF;
      RAISE NOTICE 'TT_StackTranslationRules(): Anlysing %...', schemaName || '.' || tTable;
      -- Build a list of all target attributes for this table
      EXECUTE 'SELECT array_agg(target_attribute)' ||
              ' FROM ' || TT_FullTableName(schemaName, tTable)
      INTO attributeArr;
      IF nb > 1 AND attributeArr != attributeArrOld THEN
        RAISE EXCEPTION 'TT_StackTranslationRules() ERROR: Table ''%.%'' does not have the same target attributes as the previous table in the list...', schemaName, tTable;
      END IF;
      attributeArrOld = attributeArr;
    
      IF nb = 1 THEN
        -- Create the attribute part of the query which will be repeated for each translation table
        nb2 = 1;
        FOREACH attr IN ARRAY attributeArr LOOP
          wherePart = wherePart || 'target_attribute = ''' || attr || '''';
          IF nb2 < cardinality(attributeArr) THEN
            wherePart = wherePart || ' OR ';
          END IF;
          nb2 = nb2 + 1;
        END LOOP;
      END IF;

      IF nb > 1 THEN
        query = query || 'UNION ALL' || chr(10);
      END IF;
      query = query || 'SELECT ' || nb || ' nb, ''' || tTable || ''' ttable,' || chr(10) ||
                       '        rule_id::int,' || chr(10) ||
                       '        target_attribute::text,' || chr(10) ||
                       '        target_attribute_type::text,' || chr(10) ||
                       '        validation_rules::text,' || chr(10) ||
                       '        translation_rules::text' || chr(10) ||
                       'FROM ' || TT_FullTableName(schemaName, tTable) || chr(10) ||
                       wherePart;
      IF nb < cardinality(tTableArr) THEN
        query = query || chr(10);
      END IF;
      nb = nb + 1;
    END LOOP;
    query = query  || chr(10) || ') foo' || chr(10) || 'ORDER BY rule_id, nb;';
    RETURN QUERY EXECUTE query;
  END
$$ LANGUAGE plpgsql VOLATILE;
-------------------------------------------------------------------------------

-------------------------------------------------------
-- Create a function that create the constraint in a non
-- blocking way and return TRUE or FALSE upon succesfull completion
-------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_AddConstraint(name, name, text, text[], text[]);
CREATE OR REPLACE FUNCTION TT_AddConstraint(
  schemaName name,
  tableName name,
  cType text,
  args text[],
  lookup_vals text[] DEFAULT NULL
)
RETURNS RECORD AS $$
  DECLARE
    acceptableCType text[] = ARRAY['PK', 'FK', 'NOTNULL', 'CHECK', 'LOOKUP', 'LOOKUPTABLE'];
    nbArgs int[] = ARRAY[1, 4, 1, 2, 2, 2];
    queryStr text;
  BEGIN
    cType = upper(cType);
    BEGIN
      IF NOT cType = ANY (acceptableCType) THEN
        RAISE EXCEPTION 'TT_AddConstraint(): ERROR invalid constraint type (%)...', cType;
      END IF;
      IF cardinality(args) != nbArgs[array_position(acceptableCType, cType)] THEN
        RAISE EXCEPTION 'TT_AddConstraint(): ERROR invalid number of arguments (%). Should be %...', cardinality(args), nbArgs[array_position(acceptableCType, cType)];
      END IF;
      queryStr = 'ALTER TABLE ' || schemaName || '.' || tableName || chr(10);
      CASE WHEN cType = 'PK' THEN
             queryStr = 'SELECT constraint_name FROM information_schema.table_constraints
                         WHERE table_schema = ''' || schemaName || '''
                         AND table_name = ''' || tableName || '''
                         AND constraint_type = ''PRIMARY KEY'';';
--RAISE NOTICE '11 queryStr = %', queryStr;
             EXECUTE queryStr INTO queryStr;
--RAISE NOTICE '22 queryStr = %', queryStr;
             IF queryStr IS NULL THEN
               queryStr = '';
             ELSE
               queryStr = 'ALTER TABLE ' || schemaName || '.' || tableName || chr(10) ||
                        'DROP CONSTRAINT IF EXISTS ' || queryStr || ' CASCADE;' || chr(10);
             END IF;
             queryStr = queryStr || 'ALTER TABLE ' || schemaName || '.' || tableName || chr(10) ||
                                    'ADD PRIMARY KEY (' || args[1] || ');';
--RAISE NOTICE '33 queryStr = %', queryStr;

           WHEN cType = 'FK' THEN
             queryStr = queryStr || 'ADD FOREIGN KEY (' || args[1] || ') ' ||
                                    'REFERENCES ' || args[2] || '.' || args[3] || ' (' || args[4] || ') MATCH FULL;';
         
           WHEN cType = 'NOTNULL' THEN
             queryStr = queryStr || 'ALTER COLUMN ' || args[1] || ' SET NOT NULL;';
         
           WHEN cType = 'CHECK' THEN
             queryStr = queryStr || 'DROP CONSTRAINT IF EXISTS ' || args[1] || ';' || chr(10) ||
                                    'ALTER TABLE ' || schemaName || '.' || tableName || chr(10) ||
                                    'ADD CONSTRAINT ' || args[1] || chr(10) ||
                                    'CHECK (' || args[2] || ');';

           WHEN cType = 'LOOKUP' THEN
             queryStr = 'DROP TABLE IF EXISTS ' || args[1] || '.' || args[2] || '_codes CASCADE;' || chr(10) || chr(10) ||

                        'CREATE TABLE ' || args[1] || '.' || args[2] || '_codes AS' || chr(10) ||
                        'SELECT * FROM (VALUES (''' || array_to_string(lookup_vals, '''), (''') || ''')) AS t(code);' || chr(10) || chr(10) ||

                        'ALTER TABLE ' || args[1] || '.' || args[2] || '_codes' || chr(10) ||
                        'ADD PRIMARY KEY (code);' || chr(10) || chr(10) ||

                        'ALTER TABLE ' || schemaName || '.' || tableName || chr(10) ||
                        'DROP CONSTRAINT IF EXISTS ' || tableName || '_' || args[2] || '_fk;' || chr(10) || chr(10) ||

                        'ALTER TABLE ' || schemaName || '.' || tableName || chr(10) ||
                        'ADD CONSTRAINT ' || tableName || '_' || args[2] || '_fk' || chr(10) ||
                        'FOREIGN KEY (' || args[2] || ')' || chr(10) ||
                        'REFERENCES ' || args[1] || '.' || args[2] || '_codes (code);';
           ELSE
             RAISE EXCEPTION 'TT_AddConstraint(): ERROR invalid constraint type (%)...', cType;
      END CASE;
      RAISE NOTICE 'TT_AddConstraint(): EXECUTING ''%''...', queryStr;
      EXECUTE queryStr;
      RETURN (TRUE, queryStr);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '%', SQLERRM;
      RETURN (FALSE, queryStr);
    END;
  END;
$$ LANGUAGE plpgsql VOLATILE;

-------------------------------------------------------
-- Drop all constraint on a table
-------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_DropAllConstraints(name, name);
CREATE OR REPLACE FUNCTION TT_DropAllConstraints(
  schemaName name,
  tableName name
)
RETURNS boolean AS $$
  DECLARE
    consList RECORD;
    queryStr text;
  BEGIN
    BEGIN
      FOR consList IN SELECT conname
                      FROM pg_catalog.pg_constraint con
                      INNER JOIN pg_catalog.pg_class rel ON rel.oid = con.conrelid
                      INNER JOIN pg_catalog.pg_namespace nsp ON nsp.oid = connamespace
                      WHERE nsp.nspname = schemaName AND rel.relname = tableName
      LOOP
        queryStr = 'ALTER TABLE ' || schemaName || '.' || tableName || ' DROP CONSTRAINT IF EXISTS ' || consList.conname ||' CASCADE;';
        RAISE NOTICE 'TT_DropAllConstraint(): Dropping contraint ''%'' (%)...', consList.conname, queryStr;
        EXECUTE queryStr;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      RETURN FALSE;
    END;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql VOLATILE;
-------------------------------------------------------------------------------
-- Overwrite the TT_DefaultProjectErrorCode() function to define default error
-- codes for these helper functions...
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_DefaultProjectErrorCode(text, text);
CREATE OR REPLACE FUNCTION TT_DefaultProjectErrorCode(
  rule text,
  targetType text
)
RETURNS text AS $$
  DECLARE
    rulelc text = lower(rule);
    targetTypelc text = lower(targetType);
  BEGIN
    IF targetTypelc = 'integer' OR targetTypelc = 'int' OR targetTypelc = 'double precision' THEN
      RETURN CASE WHEN rulelc = 'projectrule1' THEN '-9999'
                  WHEN rulelc = 'sk_utm01_species_percent_validation' THEN '-9997'
                  WHEN rulelc = 'ns_nsi01_hascountofnotnull' THEN '-8886'
                  WHEN rulelc = 'vri01_hascountofnotnull' THEN '-8886'
                  WHEN rulelc = 'fvi01_hascountofnotnull' THEN '-8886'
                  WHEN rulelc = 'fvi01_structure_per_validation' THEN '-8887'
                  WHEN rulelc = 'on_fim02_hascountofnotnull' THEN '-8886'
                  WHEN rulelc = 'pe_pei01_hascountofnotnull' THEN '-8886'
                  WHEN rulelc = 'pe_pei02_hascountofnotnull' THEN '-8886'
                  WHEN rulelc = 'qc_prg4_lengthmatchlist' THEN '-9998'
                  WHEN rulelc = 'sk_utm_hascountofnotnull' THEN '-8886'
                  WHEN rulelc = 'sfv01_hascountofnotnull' THEN '-8886'
                  WHEN rulelc = 'nl_nli01_origin_lower_validation' THEN '-8886'
				  WHEN rulelc = 'nl_nli01_origin_newfoundland_validation' THEN '-8886'
                  WHEN rulelc = 'nl_nli01_iscommercial' THEN '-8887'
                  WHEN rulelc = 'nl_nli01_isnoncommercial' THEN '-8887'
                  WHEN rulelc = 'nl_nli01_isforest' THEN '-8887'
                  WHEN rulelc = 'qc_hascountofnotnull' THEN '-8886'
                  WHEN rulelc = 'ab_photo_year_validation' THEN '-9997'
                  WHEN rulelc = 'pc02_hascountofnotnull' THEN '-8886'
                  WHEN rulelc = 'yt_yvi02_disturbance_matchlist' THEN '-9998'
                  WHEN rulelc = 'yt_yvi02_disturbance_notnull' THEN '-8888'
                  WHEN rulelc = 'yt_yvi02_disturbance_hascountoflayers' THEN '-8887'
                  WHEN rulelc = 'row_translation_rule_nt_lyr' THEN '-9997'
				  WHEN rulelc = 'mb_fri_hascountofnotnull' THEN '-8886'
				  WHEN rulelc = 'mb_mb03_disturbance_hascountofnotnull' THEN '-8888'
				  WHEN rulelc = 'nl_nli01_crown_closure_validation' THEN '-8886'
				  WHEN rulelc = 'nl_nli01_height_validation' THEN '-8886'
				  WHEN rulelc = 'nb_hascountofnotnull' THEN '-8886'
				  WHEN rulelc = 'pe_pei02_map_dist_year' THEN '-8886'
				  WHEN rulelc = 'mb_fri03_getSpeciesPer1' THEN '-8888'
				  WHEN rulelc = 'nt_fvi01_species_per_range_validation' THEN '-9999'
				  WHEN rulelc = 'yvi03_hascountofnotnull' THEN '-8886'
                  ELSE
                   TT_DefaultErrorCode(rulelc, targetTypelc) END;
    ELSIF targetTypelc = 'geometry' THEN
      RETURN CASE WHEN rulelc = 'projectrule1' THEN NULL
                  ELSE TT_DefaultErrorCode(rulelc, targetTypelc) END;
    ELSE
      RETURN CASE WHEN rulelc = 'nb_nbi01_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'vri01_nat_non_veg_validation' THEN 'INVALID_VALUE'
                  WHEN rulelc = 'vri01_non_for_anth_validation' THEN 'INVALID_VALUE'
                  WHEN rulelc = 'vri01_non_for_veg_validation' THEN 'INVALID_VALUE'
                  WHEN rulelc = 'yvi01_nat_non_veg_validation' THEN 'NOT_IN_SET'
                  WHEN rulelc = 'yvi01_nfl_soil_moisture_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'yvi03_nat_non_veg_validation' THEN 'NOT_IN_SET'
                  WHEN rulelc = 'yvi03_nfl_soil_moisture_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'avi01_stand_structure_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'fvi01_stand_structure_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'qc_prg4_lengthmatchlist' THEN 'NOT_IN_SET'
                  WHEN rulelc = 'nl_nli01_isforest' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'nl_nli01_iscommercial' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'nl_nli01_isnoncommercial' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'qc_prg3_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'qc_prg4_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'qc_prg5_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'ab_avi01_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'nl_nli01_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'bc_vri01_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'ns_nsi01_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'pe_pei01_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'pe_pei01_dist_type_length_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'nt_fvi01_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'sk_utm01_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'sk_sfv01_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'mb_fli01_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'mb_fri01_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'mb_mb03_disturbance_hascountofnotnull' THEN 'NULL_VALUE'
                  WHEN rulelc = 'pc02_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'yt_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'yt04_wetland_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'fim_species' THEN 'NOT_IN_SET'
                  WHEN rulelc = 'yvi02_stand_structure_validation' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'yt_yvi02_disturbance_matchlist' THEN 'NOT_IN_SET'
                  WHEN rulelc = 'yt_yvi02_disturbance_notnull' THEN 'NULL_VALUE'
                  WHEN rulelc = 'yt_yvi02_disturbance_hascountoflayers' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'yvi03_hasnfl' THEN 'NOT_APPLICABLE'
                  WHEN rulelc = 'row_translation_rule_nt_lyr' THEN 'INVALID_VALUE'
				  WHEN rulelc = 'hasnflinfo' THEN 'INVALID_VALUE'
				  WHEN rulelc = 'mb_fri03_species_validation' THEN 'NULL_VALUE'
                  ELSE TT_DefaultErrorCode(rulelc, targetTypelc) END;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Internal functions used by validation and translation functions...
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- TT_vri01_wetland_code(text, text, text)
--
-- Logic to return the correct 4 letter wetland code
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_bc_vri01_wetland_code(text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_bc_vri01_wetland_code(
  inventory_standard_cd text,
  l1_species_cd_1 text,
  l1_species_pct_1 text,
  l1_species_cd_2 text,
  non_productive_descriptor_cd text,
  l1_non_forest_descriptor text,
  land_cover_class_cd_1 text,
  soil_moisture_regime_1 text,
  l1_crown_closure text,
  l1_proj_height_1 text
)
RETURNS text AS $$
  DECLARE
    _l1_species_pct_1 double precision := l1_species_pct_1::double precision;
    _l1_crown_closure double precision := l1_crown_closure::double precision;
    _l1_proj_height_1 double precision := l1_proj_height_1::double precision;
  BEGIN
    RETURN CASE
             WHEN inventory_standard_cd='F' AND l1_species_cd_1 IN('SF','CW','YC') AND non_productive_descriptor_cd='S' THEN 'STNN'
             WHEN inventory_standard_cd='F' AND l1_species_cd_1 IN('SF','CW','YC') AND non_productive_descriptor_cd='NP' THEN 'STNN'
             WHEN inventory_standard_cd='F' AND l1_non_forest_descriptor='NPBR' THEN 'STNN'
             WHEN inventory_standard_cd='F' AND l1_non_forest_descriptor='S' THEN 'SONS'
             WHEN inventory_standard_cd='F' AND l1_non_forest_descriptor='MUSKEG' THEN 'STNN'
             WHEN inventory_standard_cd IN('V','I') AND land_cover_class_cd_1='W' THEN 'W---'
             WHEN inventory_standard_cd IN('V','I') AND soil_moisture_regime_1 IN('7','8') AND l1_species_cd_1='SB' AND _l1_species_pct_1=100 AND _l1_crown_closure=50 AND _l1_proj_height_1=12 THEN 'BTNN'
             WHEN inventory_standard_cd IN('V','I') AND soil_moisture_regime_1 IN('7','8') AND l1_species_cd_1 IN('SB','LT') AND _l1_species_pct_1=100 AND _l1_crown_closure>=50 AND _l1_proj_height_1>=12 THEN 'STNN'
             WHEN inventory_standard_cd IN('V','I') AND soil_moisture_regime_1 IN('7','8') AND l1_species_cd_1 IN('SB','LT') AND l1_species_cd_2 IN('SB','LT') AND _l1_crown_closure>=50 AND _l1_proj_height_1>=12 THEN 'STNN'
             WHEN inventory_standard_cd IN('V','I') AND soil_moisture_regime_1 IN('7','8') AND l1_species_cd_1 IN('EP','EA','CW','YR','PI') THEN 'STNN'
             WHEN inventory_standard_cd IN('V','I') AND soil_moisture_regime_1 IN('7','8') AND l1_species_cd_1 IN('SB','LT') AND l1_species_cd_2 IN('SB','LT') AND _l1_crown_closure<50 THEN 'FTNN'
             WHEN inventory_standard_cd IN('V','I') AND soil_moisture_regime_1 IN('7','8') AND l1_species_cd_1='LT' AND _l1_species_pct_1=100 AND _l1_proj_height_1<12 THEN 'FTNN'
             WHEN inventory_standard_cd IN('V','I') AND soil_moisture_regime_1 IN('7','8') AND land_cover_class_cd_1 IN('ST','SL') THEN 'SONS'
             WHEN inventory_standard_cd IN('V','I') AND soil_moisture_regime_1 IN('7','8') AND land_cover_class_cd_1 IN('HE','HF','HG') THEN 'MONG'
             WHEN inventory_standard_cd IN('V','I') AND soil_moisture_regime_1 IN('7','8') AND land_cover_class_cd_1 IN('BY','BM') THEN 'FONN'
             WHEN inventory_standard_cd IN('V','I') AND soil_moisture_regime_1 IN('7','8') AND land_cover_class_cd_1='BL' THEN 'BONN'
             WHEN inventory_standard_cd IN('V','I') AND soil_moisture_regime_1 IN('7','8') AND land_cover_class_cd_1='MU' THEN 'TMNN'
             ELSE NULL
           END;
  END
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_wetland_code(text, text, text)
--
-- Run logic to generate 4 letter code
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_wetland_code(text, text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_wetland_code(
  stand_id text,
  site text,
  species_comp text
)
RETURNS text AS $$
	SELECT CASE
           WHEN stand_id='920' THEN 'BONS'
           WHEN stand_id='925' THEN 'BTNN'
           WHEN stand_id='930' THEN 'MONG'
           WHEN stand_id='900' AND site='W' THEN 'STNN'
           WHEN stand_id='910' AND site='W' THEN 'STNN'
           WHEN species_comp IN('BSTL', 'BSTLBF', 'BSTLWB' ) THEN 'STNN'
           WHEN species_comp IN('TL', 'TLBF','TLWB', 'TLBS', 'TLBSBF', 'TLBSWB') THEN 'STNN'
           WHEN species_comp IN('WBTL', 'WBTLBS', 'WBBSTL') THEN 'STNN'
           ELSE NULL
         END;
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_ab_avi01_wetland_code(text, text, text)
--
-- Define the 4 letter wetland code logic for AB AVI
-- Note sp per value of 10 represents 100
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ab_avi01_wetland_code(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_ab_avi01_wetland_code(
  moisture text,
  nonfor_veg text,
  nat_nonveg text,
  sp1 text,
  sp2 text,
  crownclose text,
  sp1_percnt text
)
RETURNS text AS $$
  SELECT CASE
           WHEN UPPER(moisture)='W' AND nonfor_veg IN('SO','SC') THEN 'SONS'
           WHEN UPPER(moisture)='W' AND nonfor_veg IN('HG','HF') THEN 'MONG'
           WHEN UPPER(moisture)='W' AND nonfor_veg='BR' THEN 'FONG'
           WHEN UPPER(moisture)='W' AND nat_nonveg='NWB' THEN 'SONS'
           WHEN UPPER(moisture) IN('A','D','M') AND (sp1='LT' OR sp2='LT') AND crownclose IN('A','B') THEN 'FTNN'
           WHEN UPPER(moisture) IN('A','D','M') AND (sp1='LT' OR sp2='LT') AND crownclose='C' THEN 'STNN'
           WHEN UPPER(moisture) IN('A','D','M') AND (sp1='LT' OR sp2='LT') AND crownclose='D' THEN 'SFNN'
           WHEN UPPER(moisture) IN('A','D','M') AND (sp1='SB' AND sp1_percnt='10') AND crownclose IN('A','B') THEN 'BTNN'
           WHEN UPPER(moisture) IN('A','D','M') AND (sp1='SB' AND sp1_percnt='10') AND crownclose='C' THEN 'STNN'
           WHEN UPPER(moisture) IN('A','D','M') AND (sp1='SB' AND sp1_percnt='10') AND crownclose='D' THEN 'SFNN'
           WHEN UPPER(moisture) IN('A','D','M') AND ((sp1='SB' OR sp1='FB') AND (sp2 IS NULL OR sp2!='LT')) AND crownclose IN('A','B','C') THEN 'STNN'
           WHEN UPPER(moisture) IN('A','D','M') AND ((sp1='SB' OR sp1='FB') AND (sp2 IS NULL OR sp2!='LT')) AND crownclose='D' THEN 'SFNN'
           WHEN UPPER(moisture) IN('A','D','M') AND sp1 IN('BW','PB') AND crownclose IN('A','B','C') THEN 'STNN'
           WHEN UPPER(moisture) IN('A','D','M') AND sp1 IN('BW','PB') AND crownclose='D' THEN 'SFNN'
           ELSE NULL
         END;
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nb_nbi01_wetland_code(text, text, text)
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nb_nbi01_wetland_code(text, text, text);
CREATE OR REPLACE FUNCTION TT_nb_nbi01_wetland_code(
  wc text,
  vt text,
  im text
)
RETURNS text AS $$
  SELECT CASE
           -- Note the commented logic below came from the CASFRI04 code and cannot be validated. For example we don't know what B translates to as a wet_loca_mod value.
           --WHEN wc='BO' AND vt='EV' AND im='BP' THEN 'BO-B'
           --WHEN wc='FE' AND vt='EV' AND im='BP' THEN 'FO-B'
           --WHEN wc='BO' AND vt='EV' AND im='DI' THEN 'BO--'
           --WHEN wc='BO' AND vt='AW' AND im='BP' THEN 'BT-B'
           --WHEN wc='BO' AND vt='OV' AND im='BP' THEN 'OO-B'
           --WHEN wc='FE' AND vt='EV' AND im IN ('MI', 'DI') THEN 'FO--'
           --WHEN wc='FE' AND vt='OV' AND im='MI' THEN 'OO--'
           WHEN wc='BO' AND vt='FS' THEN 'BTNN'
           WHEN wc='BO' AND vt='SV' THEN 'BONS'
           WHEN wc='FE' AND vt IN ('FH', 'FS') THEN 'FTNN'
           WHEN wc='FE' AND vt IN ('AW', 'SV') THEN 'FONS'
           --WHEN wc='FW' AND im='BP' THEN 'OF-B'
           --WHEN wc='FE' AND vt='EV' THEN 'FO--'
           --WHEN wc IN ('FE', 'BO') AND vt='OV' THEN 'OO--'
           --WHEN wc IN ('FE', 'BO') AND vt='OW' THEN 'O---'
           --WHEN wc='BO' AND vt='EV' THEN 'BO--'
           --WHEN wc='BO' AND vt='AW' THEN 'BT--'
           WHEN wc='AB' THEN 'OONN'
           WHEN wc='FM' THEN 'MONG'
           WHEN wc='FW' THEN 'STNN'
           WHEN wc='SB' THEN 'SONS'
           WHEN wc='CM' AND vt='FV' THEN 'MCNG'
           WHEN wc='TF' AND vt IN ('FV', 'FU') THEN 'TMNN'
           --WHEN wc IN ('NP', 'WL') THEN 'W---'
           ELSE NULL
         END;
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_fim_species_code
--
-- sp_string text - source string of species and percentages
-- sp_number text - the species number being requested (i.e. SPECIES 1-10 in casfri)
--
-- This function is used by TT_fim_species_translation and TT_fim_species_percent_translation
-- to extract the requested species name an percent code.
-- The following functions take that code and extract either species name or percent info.
-- String structure is a 2-letter species code, followed by 2 spaces, then a 2 digit percentage.
-- In cases where a species is 100%, there is only 1 space so the total length of all codes is 6.
-- Multiple codes are concatenated together. Max number of species in ON is 10.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_fim_species_code(text, int);
CREATE OR REPLACE FUNCTION TT_fim_species_code(
  sp_string text,
  sp_number int
)
RETURNS text AS $$
  DECLARE
    start_char int;
    code text;
  BEGIN
    SELECT (array_agg(a))[sp_number]
    FROM (SELECT (regexp_matches(trim(sp_string), '[a-z]+\s+[0-9]+', 'gi'))[1] a ) foo
    INTO code;
    RETURN code;
  END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_wetland_code
--
-- CO_TER
-- CL_DRAIN
-- gr_ess
-- cl_dens
-- cl_haut
-- TYPE_ECO
--
-- Return 4 character wetland code based on the logic defined in the issue.
-- Species values change depending on inventory. QC03 species are different
-- than QC04éQC05 species.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_wetland_code(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_qc_wetland_code(
  CO_TER text,
  CL_DRAIN text,
  gr_ess text,
  cl_den text,
  cl_haut text,
  TYPE_ECO text,
  inventory_id text
)
RETURNS text AS $$
  DECLARE
    _bad_drainage text[] := ARRAY['50', '51', '52', '53', '54', '60', '61', '62', '63', '64'];
    _cl_den double precision;
    _cl_haut double precision;
  BEGIN
  
    -- set density and height to zero if they are null so that logic tests dont throw error. In prg3 and 4 convert density and height codes to a valuewithin the range of lower to upper
    IF cl_den IS NULL THEN
      _cl_den = 0;
    ELSE
      _cl_den = TT_mapInt(cl_den, '{''A'', ''B'', ''C'', ''D''}', '{90, 70, 50, 30}');
    END IF;
  
    IF cl_haut IS NULL THEN
      _cl_haut = 0;
    ELSE
      _cl_haut = TT_mapDouble(cl_haut, '{''1'',''2'',''3'',''4'',''5'',''6'',''7''}', '{30, 19, 14, 9, 5, 2.5, 0.5}');
    END IF;
  
    -- SONS: swamp, no trees, no permafrost, shrub 25%
    -- denude humide
    IF CO_TER = 'DH' THEN
      RETURN 'SONS';
    END IF;
  
    -- alder with bad drainage - this will include some MA18 and MA18R TYPE_ECO codes, we prioritize alder
    IF CL_DRAIN = any(_bad_drainage) AND CO_TER = 'AL' THEN
      RETURN 'SONS';
    END IF;
	
    -- set the remaining MA18 and MA18R that do not have alders
    IF TYPE_ECO = 'MA18' THEN
      RETURN 'MONS';
    END IF;
  
    IF TYPE_ECO = 'MA18R' THEN
      RETURN 'SONS';
    END IF;
  
    -- BTNN: bog, treed, no permafrost, lawns not present
    -- bad drainage, species is EE (prg 3) or EPEP (prg 4/5) with density 25-40% and height >12m
    IF CL_DRAIN = any(_bad_drainage) AND _cl_den > 25 AND _cl_den < 40 AND _cl_haut <12 THEN
      IF (inventory_id = 'QC03' AND gr_ess = 'EE') OR
      (inventory_id IN('QC04', 'QC05') AND gr_ess = 'EPEP') THEN
        RETURN 'BTNN';
      END IF;
    END IF;
  
    -- bog types
    IF TYPE_ECO IN('RE39', 'TOB9D', 'TOB9L', 'TOB9N', 'TOB9U') THEN
      RETURN 'BTNN';
    END IF;
  
    -- FTNN: fen, treed, no permafrost, lawns not present
    -- bad drainage, species are EME or MEE (prg 3) or EPML or MLEP (prg 4/5) with density 25-40%
    IF CL_DRAIN = any(_bad_drainage) AND _cl_den > 25 AND _cl_den < 40 THEN
      IF (inventory_id = 'QC03' AND gr_ess IN('EME', 'MEE')) OR
      (inventory_id IN('QC04', 'QC05') AND gr_ess IN('EPML', 'MLEP')) THEN
        RETURN 'FTNN';
      END IF;
    END IF;
  
    -- bad drainage, species is MEME (prg 3) or MLML, ML (prg 4/5) with height less than 12
    IF CL_DRAIN = any(_bad_drainage) AND _cl_haut < 12 THEN
      IF (inventory_id = 'QC03' AND gr_ess = 'MEME') OR
      (inventory_id IN('QC04', 'QC05') AND gr_ess IN('MLML', 'ML')) THEN
        RETURN 'FTNN';
      END IF;
    END IF;
  
    -- Fen type
    IF TYPE_ECO IN('RE38', 'RS38', 'TOF8L', 'TOF8N', 'TOF8U') THEN
      RETURN 'FTNN';
    END IF;
  
    IF TYPE_ECO IN('TOF8A') THEN
      RETURN 'FONS';
    END IF;

    IF TYPE_ECO IN('TO18') THEN
      RETURN 'BONS';
    END IF;
  
    -- STNN: swamp, treed, no permafrost, lawns not present
    -- bad drainage and specific swamp species or types
    IF CL_DRAIN = any(_bad_drainage) THEN
      IF TYPE_ECO IN('FE10', 'FE20', 'FE30', 'FE50', 'FE60', 'FC10', 'MJ10', 'MS10', 'MS20', 'MS40', 'MS60', 'MS70', 'RB50', 'RP10', 'RS20', 'RS20S', 'RS40', 'RS50', 'RS70', 'RT10', 'RE20', 'RE40', 'RE70') THEN
        RETURN 'STNN';
      END IF;
    
      IF _cl_den > 40 THEN
        IF _cl_haut > 12 THEN
          IF (inventory_id = 'QC03' AND gr_ess IN('EC', 'EPU', 'EME', 'RME', 'SE', 'ES', 'RE', 'MEE', 'MEC')) OR
          (inventory_id IN('QC04', 'QC05') AND gr_ess IN('EPTO', 'EPPU', 'EPML', 'RXML', 'SBEP', 'EPSE', 'RXEP', 'MLEP', 'MLTO')) THEN
            RETURN 'STNN';
          END IF;
        END IF;
      
        IF (inventory_id = 'QC03' AND gr_ess IN('EE', 'MEME')) OR
        (inventory_id IN('QC04', 'QC05') AND gr_ess IN('EPEP','MLML','ML')) THEN
          RETURN 'STNN';
        END IF;
      END IF;
    
      IF (inventory_id = 'QC03' AND gr_ess IN('FNC', 'BJ', 'FH', 'FT', 'BB', 'BB1', 'PE', 'PE1', 'FI', 'CC', 'CPU', 'CE', 'CME', 'RC', 'SC', 'CS', 'PUC', 'BBBB', 'EBB', 'BBBBE', 'BBE', 'BB1E')) OR
      (inventory_id IN('QC04', 'QC05') AND gr_ess IN('FNFN', 'BJ', 'BJBJ', 'FHFH', 'FTFT', 'BPFX', 'PEPE', 'PEFX', 'FIFI', 'TOTO', 'TOPU', 'TOEP', 'TOML', 'RXTO', 'SBTO', 'TOSE', 'PUTO', 'BPBP', 'BPEP', 'BPBPEP')) THEN
        RETURN 'STNN';
      END IF;
    END IF;
    
    -- swamp types
    IF TYPE_ECO IN('RS37', 'RS39', 'RS18', 'RE37', 'RC38', 'MJ18', 'MF18', 'FO18', 'MS18', 'MS18P', 'MS28', 'MS68', 'MJ28') THEN
      RETURN 'STNN';
    END IF;
  
    RETURN NULL;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_wetland_code_translation
--
-- Take the 4 letter wetland code and translate the requested character
--
-- e.g. TT_wetland_code_translation('BTNN', '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_wetland_code_translation(text, text);
CREATE OR REPLACE FUNCTION TT_wetland_code_translation(
  wetland_code text,
  ret_char_pos text
)
RETURNS text AS $$
  DECLARE
    _wetland_char text;
  BEGIN
    IF wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
  
    _wetland_char = substring(wetland_code from ret_char_pos::int for 1);
  
    IF _wetland_char = '-' THEN
      RETURN NULL;
    END IF;
	
    CASE WHEN ret_char_pos = '1' THEN -- WETLAND_TYPE
	         RETURN TT_MapText(_wetland_char, '{''B'', ''F'', ''S'', ''M'', ''O'', ''T'', ''E'', ''W'', ''Z''}', '{''BOG'', ''FEN'', ''SWAMP'', ''MARSH'', ''SHALLOW_WATER'', ''TIDAL_FLATS'', ''ESTUARY'', ''WETLAND'', ''NOT_WETLAND''}');
	       WHEN ret_char_pos = '2' THEN -- WET_VEG_COVER
	         RETURN TT_MapText(_wetland_char, '{''F'', ''T'', ''O'', ''C'', ''M''}', '{''FORESTED'', ''WOODED'', ''OPEN_NON_TREED_FRESHWATER'', ''OPEN_NON_TREED_COASTAL'', ''MUD''}');
	       WHEN ret_char_pos = '3' THEN -- WET_LANDFORM_MOD
	         RETURN TT_MapText(_wetland_char, '{''X'', ''P'', ''N'', ''A''}', '{''PERMAFROST_PRESENT'', ''PATTERNING_PRESENT'', ''NO_PERMAFROST_PATTERNING'', ''SALINE_ALKALINE''}');
	       WHEN ret_char_pos = '4' THEN -- WET_LOCAL_MOD
	         RETURN TT_MapText(_wetland_char, '{''C'', ''R'', ''I'', ''N'', ''S'', ''G''}', '{''INT_LAWN_SCAR'', ''INT_LAWN_ISLAND'', ''INT_LAWN'', ''NO_LAWN'', ''SHRUB_COVER'', ''GRAMINOIDS''}');
	  END CASE;  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg5_species_code_to_reordered_array
--
-- eta_ess_pc text
--
-- For QC fifth inventory, species are coded in both the sup_eta_ess_pc and inf_eta_ess_pc column.
-- These codes need to be split to get species 1, 2, 3 etc. Requested species code is then extracted based on species_number
-- and passed to lookup table.
-- Coding system for sup_eta_ess_pc and inf_eta_ess_pc is the same so this function works for both layer 1 and layer 2 values.
--
-- Species are not coded in the correct order. We need to reorder the codes so species 1 has the max percent cover. Species
-- with matching percentages should maintain the same order as the source code.
-- Function TT_qc_prg5_species_code_to_reordered_array reorders the species and percent codes and returns them in an array.
-- Species and percent functions will call TT_qc_prg5_species_code_to_reordered_array then return either the species or percent value
-- from the correct position in the array using species_number.
--
-- TT_qc_prg5_species_code_to_reordered_array returns an array of species-percent codes (e.g. BS20) ordered by percetn cover.
-- In the event of a tie the codes are returned in the same order they appeared in the original string.
-- e.g. `BS20WS60TA20` would return ARRAY['WS60', 'BS20', 'TA20']

------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg5_species_code_to_reordered_array(text);
CREATE OR REPLACE FUNCTION TT_qc_prg5_species_code_to_reordered_array(
  eta_ess_pc text
)
RETURNS text[] AS $$
  DECLARE
    sp_array text[];
    per_array text[];
  BEGIN
  
	-- replace any integers with spaces. For qc05 there are always two integers, for qc07 always one. So replace any
	-- double spaces with single spaces. Then do string to array using a single space separator.
    sp_array = string_to_array(trim(replace(translate(eta_ess_pc, '0123456789', '          '), '  ', ' ')), ' ');
  
	-- remove any characters, then do string to array using double space as separator. Both qc05 and qc07 always have
	-- two characters for species.
	per_array = string_to_array(trim(regexp_replace(eta_ess_pc, '[[:alpha:]]', ' ', 'g')), '  ');
  
    RETURN ARRAY( -- converts table to array
      SELECT code FROM(
        SELECT a || b code, b species_per, ROW_NUMBER() OVER () org_order -- concatenates values in column a and b, add index
        FROM unnest(
          sp_array,
          per_array
        ) AS t(a,b) -- converts arrays to a table
        ORDER BY species_per desc, org_order asc -- order by the percent, ties are ordered by their original order in the string
      ) x
    );
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_ns_nsi01_wetland_code
--
-- return 4 letter wetland code
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ns_nsi01_wetland_code(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_ns_nsi01_wetland_code(
  fornon text,
  species text,
  crncl text,
  height text
)
RETURNS text AS $$
  DECLARE
    _crncl double precision := crncl::double precision;
	_height double precision := height::double precision;
  BEGIN
    RETURN CASE
             WHEN fornon='70' THEN 'W---'
             WHEN fornon='71' THEN 'MONG'
             WHEN fornon='72' THEN 'BONN'
             WHEN fornon='73' THEN 'BTNN'
             WHEN fornon='74' THEN 'ECNN'
             WHEN fornon='75' THEN 'MONG'
             WHEN fornon IN('33','38','39') AND species IN('BS10','TL10','EC10','WB10','YB10','AS10') THEN 'SONS'
             WHEN (fornon='0' AND (species='TL10' OR (species LIKE '%TL%' AND species LIKE '%WB%') AND _crncl <=50 AND _height <=12)) THEN 'FTNN'
             WHEN (fornon='0' AND (species='TL10' OR (species LIKE '%TL%' AND species LIKE '%WB%') AND _crncl >50)) THEN 'STNN'
             WHEN (fornon='0' AND (species='EC10' OR (species LIKE '%EC%' AND species LIKE '%TL%')  OR (species LIKE '%EC%' AND species LIKE '%BS%')  OR (species LIKE '%EC%' AND species LIKE '%WB%'))) THEN 'STNN'
             WHEN (fornon='0' AND (species='AS10' OR (species LIKE '%AS%' AND species LIKE '%BS%')  OR (species LIKE '%AS%' AND species LIKE '%TL%'))) THEN 'STNN'
             WHEN (fornon='0' AND (species LIKE '%BS%' AND species LIKE '%LT%' )) THEN 'STNN'
             ELSE NULL
           END;
  END
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pe_pei01_wetland_code
--
-- Return 4 character wetland code
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_pe_pei01_wetland_code(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_pe_pei01_wetland_code(
  landtype text,
  per1 text,
  landtype2 text,
  per2 text,
  landtype3 text,
  per3 text
)
RETURNS text AS $$
	BEGIN
		IF landtype2 = '999'
		THEN
		 	RETURN CASE
		           WHEN landtype='BO' AND NOT per1='0' THEN 'BFX-'
		           WHEN landtype='BO' AND per1='0' THEN 'BOX-'
		           WHEN landtype='SO' THEN 'SOX-'
		           WHEN landtype='SW' AND NOT per1='0' THEN 'STX-'
		           WHEN landtype='SW' AND per1='0' THEN 'SOX-'
		           ELSE NULL END;
	    ELSE
		    RETURN CASE
		        WHEN landtype = 'BO' AND per1 >='7' THEN 'BF--'
		        WHEN landtype = 'BO' AND per1 >= '1' AND per1 < '7' THEN 'BT--'
		        WHEN landtype = 'BO' AND (landtype2 = 'DMW' OR landtype2 = 'SMW' OR landtype2 = 'OWW') THEN 'BO--'
		        WHEN landtype = 'SSW' AND (landtype2 = 'MDW' OR landtype2 = 'OWW' OR landtype2 = 'BOW') THEN 'SO-S'
		        WHEN landtype = 'SSW' AND landtype2 = 'WSW' THEN 'ST-S'
		        WHEN landtype = 'SSW' AND per1 = '10' THEN 'SO-S'
		        WHEN landtype = 'WSW' AND per1 >= '7' AND landtype2 = 'SSW' AND per2 > '2' THEN 'SF-S'
		        WHEN landtype = 'WSW' AND landtype2 = 'WSW' THEN 'SF--'
		        WHEN landtype = 'WSW' AND per1 > '1' AND per1 < '7' THEN 'ST--'
		        WHEN landtype = 'WSW' THEN 'SO--'
		        WHEN landtype = 'OWW' AND ((landtype2 = 'SSW' AND per2 >= '3') OR (landtype3 = 'SSW' AND 'per3' >= '3')) THEN 'SO-S'
		        WHEN landtype = 'OWW' AND landtype2 = 'WSW' THEN 'ST--'
		        WHEN landtype = 'OWW' AND landtype2 = 'DMW' AND landtype3 = 'SSW' AND per3 >= '3' THEN 'MO-S'
		        WHEN landtype = 'OWW' AND landtype2 = 'DMW' THEN 'MO--'
		        WHEN landtype = 'OWW' THEN 'WO--'
		        WHEN landtype = 'BKW' THEN 'EOA-'
		        WHEN landtype = 'DMW' THEN 'MO--'
		        WHEN landtype = 'MDW' THEN 'WO--'
		        WHEN landtype = 'SAW' THEN 'EOA-'
		        WHEN landtype = 'SDW' THEN 'Z---'
		        WHEN landtype = 'SFW' THEN 'W---'
		        WHEN landtype = 'SMW' THEN 'MO--'
		        ELSE NULL END;
		END IF;
	END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nt_fvi01_wetland_code
--
-- Return 4 character wetland code
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nt_fvi01_wetland_code(text, text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_nt_fvi01_wetland_code(
	landpos text,
	structur text,
	moisture text,
	typeclas text,
	mintypeclas text,
	sp1 text,
	sp2 text,
	sp1_per text,
	crownclos text,
	height text,
	wetland text
)
RETURNS text AS $$
  DECLARE
    _landpos text;
   _structur text;
   _moisture text;
   _typeclas text;
   _mintypeclas text;
   _sp1 text;
   _sp2 text;
   _wetland text;
   _height double precision;
   _crownclos double precision;
   _sp1_per double precision;
  BEGIN
    -- convert all text inputs to upper
    _landpos = UPPER(landpos);
    _structur = UPPER(structur);
    _moisture = UPPER(moisture);
    _typeclas = UPPER(typeclas);
    _mintypeclas = UPPER(mintypeclas);
    _sp1 = UPPER(sp1);
    _sp2 = UPPER(sp2);
    _wetland = UPPER(wetland);
  
    -- height, crownclos and sp1_per are never null when sp1 has a value.
    -- Cast them if sp1 is notEmpty, otherwise set them to zero, they will not be used but the logic will still run.
    IF TT_notEmpty(sp1) THEN
      _height = height::double precision;
      _crownclos = crownclos::double precision;
      IF sp1_per::int > 0 THEN
    	  _sp1_per = sp1_per::int * 10;
      ELSE
        _sp1_per = 0;
      END IF;
    ELSE
      _height = 0;
      _crownclos = 0;
      _sp1_per = 0;
    END IF;
    
    RETURN CASE
             WHEN _landpos='W' THEN 'W---'
             -- NON-FORESTED POLYGONS
             WHEN _structur='S' AND (_moisture='SD' OR _moisture='HD') AND (_typeclas='ST' OR _typeclas='SL') THEN 'SONS'
             WHEN _structur='S' AND (_moisture='SD' OR _moisture='HD') AND _typeclas IN ('HG', 'HF', 'HE') THEN 'MONG'
             WHEN _structur='S' AND (_moisture='SD' OR _moisture='HD') AND _typeclas='BM' THEN 'FONG'
             WHEN _structur='S' AND (_moisture='SD' OR _moisture='HD') AND (_typeclas='BL' OR _typeclas='BY') THEN 'BOXC'
             WHEN _structur='H' AND _moisture='SD' AND (_typeclas IN ('SL', 'HG') OR _mintypeclas IN ('SL', 'HG')) THEN 'BOXC'
             WHEN _structur='H' AND _moisture='HD' AND (_typeclas='HG' OR _mintypeclas='HG') THEN 'MONG'
             WHEN _structur='M' AND (_moisture='SD' OR _moisture='HD') AND (_typeclas='ST' OR _typeclas='SL') THEN 'FONS'
             -- FOREST LAND
             WHEN _structur IN ('M', 'C', 'H') AND _mintypeclas='SL' AND _moisture='SD' AND (((_sp1='SB' OR _sp1='PJ') AND _sp1_per=100) OR ((_sp1='SB' OR _sp1='PJ') AND (_sp2='SB' OR _sp2='PJ'))) AND _crownclos<50 AND _height<8 THEN 'BTXC'
             WHEN _structur='S' AND (_moisture='SD' OR _moisture='HD') AND ((_sp1='SB' OR _sp1='LT') AND  _sp1_per=100) AND (_crownclos>50 AND _crownclos<70) THEN 'STNN'
             WHEN (_moisture='SD' OR _moisture='HD') AND (_sp1='SB' OR _sp1='LT') AND _crownclos>70 THEN 'SFNN'
             WHEN (_moisture='SD' OR _moisture='HD') AND ((_sp1='SB' OR _sp1='LT') AND (_sp2='SB' OR _sp2='LT')) AND _height<12 THEN 'FTNN'
             WHEN (_moisture='SD' OR _moisture='HD') AND ((_sp1='SB' OR _sp1='LT') AND (_sp2='SB' OR _sp2='LT')) AND _height>=12 THEN 'STNN'
             WHEN _moisture='HD' AND ((_sp1='SB' OR _sp1='LT') AND _sp1_per=100) AND _crownclos<50 THEN 'FTNN'
             WHEN (_moisture='SD' OR _moisture='HD') AND (_sp1 IN ('SB', 'LT', 'BW', 'SW') AND _sp2 IN ('SB', 'LT', 'BW', 'SW')) AND _crownclos>50 THEN 'FTNN'
             WHEN (_moisture='SD' OR _moisture='HD') AND (_sp1='BW' OR _sp1='PO') THEN 'STNN'
             -- WETLAND CLASS
             WHEN _wetland='WE' THEN 'W---'
             WHEN _wetland='SO' THEN 'OONN'
             WHEN _wetland='MA' THEN 'MONG'
             WHEN _wetland='SW' AND TT_notEmpty(_sp1) THEN 'STNN'
             WHEN _wetland='SW' AND (_typeclas='SL' OR _typeclas='ST') THEN 'SONS'
             WHEN _wetland='FE' AND TT_notEmpty(_sp1) THEN 'FTNN'
             WHEN _wetland='FE' AND _typeclas='HG' THEN 'FONG'
             WHEN _wetland='FE' AND (_typeclas='SL' OR _typeclas='ST') THEN 'FONS'
             WHEN _wetland='BO' AND TT_notEmpty(_sp1) THEN 'BTXC'
             WHEN _wetland='BO' AND _typeclas IN ('BY', 'BL', 'BM') THEN 'BOXC'
             ELSE NULL
           END;
  END
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sk_utm01_wetland_code
--
-- Return 4-character wetland code
-- Calculate species_1_per only if needed
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_sk_utm01_wetland_code(text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_sk_utm01_wetland_code(
  drain text,
  sp10 text,
  sp11 text,
  sp12 text,
  sp20 text,
  sp21 text,
  d text,
  np text,
  soil_text text
)
RETURNS text AS $$
  BEGIN
    -- calculate species percent only if needed and run logic
    IF drain IN('PVP', 'PD') AND soil_text = 'O' AND sp10 = 'BS' THEN
      IF TT_sk_utm01_species_percent_translation('1', sp10, sp11, sp12, sp20, sp21) = 100 THEN
    	  RETURN CASE
    	           WHEN d IN('C', 'D') THEN 'STNN'
    	           WHEN d IN('A', 'B') THEN 'BTNN'
    	         END;
      END IF;
    END IF;
        -- run logic for remaining translations
    RETURN CASE
             -- Productive Forest Land
             WHEN ((drain='PVP' AND soil_text='O') OR (drain='PD' AND soil_text='O')) AND sp10 IN ('BS', 'TL', 'WB', 'MM') AND sp11 IN ('BS', 'TL', 'WB', 'MM')  THEN 'STNN'
             -- Non Productive Lands
             WHEN np='3100' THEN 'WT--'
             WHEN np='3300' THEN 'WO--'
             WHEN np='3500' THEN 'SONS'
             WHEN np='3600' OR np='5100' THEN 'MONG'
             ELSE NULL
           END;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sk_sfv01_wetland_code
--
-- Return 4-character wetland code
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_sk_sfv01_wetland_code(text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_sk_sfv01_wetland_code(
  soil_moist_reg text,
  species_1 text,
  species_2 text,
  species_per_1 text,
  crown_closure text,
  height text,
  shrub1 text,
  herb1 text,
  shrubs_crown_closure text
)
RETURNS text AS $$
  DECLARE
    _species_per_1 int;
	_crown_closure int;
	_height int;
	_shrubs_crown_closure int;
  BEGIN
  
    -- cast values
    _species_per_1 = species_per_1::int*10;
      _crown_closure = crown_closure::int;
    _height = height::int;
    _shrubs_crown_closure = shrubs_crown_closure::int;
    
    RETURN CASE
             -- Forested Land
             WHEN soil_moist_reg='MW' AND species_1='bS' AND _species_per_1=100 AND _crown_closure<=50 AND _height<12 THEN 'BTNN'
             WHEN soil_moist_reg='MW' AND TT_notEmpty(species_1) AND _crown_closure>50 THEN 'STNN'
             WHEN soil_moist_reg='MW' AND species_1='bS' AND _species_per_1=100 AND _crown_closure<=50 AND _height>=12 THEN 'STNN'
             WHEN soil_moist_reg='MW' AND TT_notEmpty(species_1) AND _crown_closure>=70 THEN 'SFNN'
             WHEN soil_moist_reg='W' AND species_1='bS' AND _species_per_1=100 AND _crown_closure<=50 AND _height<12 THEN 'BTNN'
             WHEN soil_moist_reg='W' AND species_1='bS' AND _species_per_1=100 AND _crown_closure<=50 AND _height>=12 THEN 'STNN'
             WHEN soil_moist_reg='W' AND species_1='bS' AND _species_per_1=100 AND (_crown_closure>50 AND _crown_closure<70) AND _height>=12 THEN 'STNN'
             WHEN soil_moist_reg='W' AND species_1='bS' AND _species_per_1=100 AND _crown_closure>=70 AND _height>=12 THEN 'SFNN'
             WHEN soil_moist_reg IN ('W', 'VW') AND species_1 IN('bS', 'wB', 'bP', 'mM') AND species_2 IN ('tL', 'bS', 'wB', 'bP', 'mM') AND (_crown_closure>=50 AND _crown_closure<70) AND _height>=12 THEN 'STNN'
             WHEN soil_moist_reg IN ('W', 'VW') AND species_1 IN('bS', 'wB', 'bP', 'mM') AND species_2 IN ('tL', 'bS', 'wB', 'bP', 'mM') AND _crown_closure>=70 THEN 'SFNN'
             WHEN soil_moist_reg IN ('W', 'VW') AND species_1 IN('bS', 'tL') AND species_2 IN ('bS', 'tL') AND _crown_closure<50 AND _height<12 THEN 'FTNN'
             WHEN soil_moist_reg IN ('W', 'VW') AND species_1='tL' AND _species_per_1=100 AND (_crown_closure>50 AND _crown_closure<70) AND _height>=12 THEN 'STNN'
             WHEN soil_moist_reg IN ('W', 'VW') AND species_1='tL' AND _species_per_1=100 AND _crown_closure>=70 THEN 'STNN'
             WHEN soil_moist_reg IN ('W', 'VW') AND species_1='tL' AND _species_per_1=100 AND _crown_closure<=50 AND _height>0 THEN 'FTNN'
             WHEN soil_moist_reg IN ('W', 'VW') AND species_1 IN('wB', 'mM', 'gA', 'wE') AND _species_per_1=100 AND _crown_closure<70 THEN 'STNN'
             WHEN soil_moist_reg IN ('W', 'VW') AND species_1 IN('wB', 'mM', 'gA', 'wE') AND _species_per_1=100 AND _crown_closure>=70 THEN 'SFNN'
             -- Non Forest Land
             WHEN soil_moist_reg IN ('MW', 'W', 'VW') AND herb1 IN ('HE','GR') THEN 'MONG'
             WHEN soil_moist_reg IN ('MW', 'W', 'VW') AND herb1='MO' THEN 'FONN'
             WHEN soil_moist_reg IN ('MW', 'W', 'VW') AND herb1='AV' THEN 'OONN'
             WHEN soil_moist_reg IN ('MW', 'W', 'VW') AND shrub1 IN ('TS', 'LS') AND _shrubs_crown_closure>25 THEN 'SONS'
             ELSE NULL
           END;
  END
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_mb_fli01_wetland_code(text, text, text)
--
-- Return 4-character wetland code
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_mb_fli01_wetland_code(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_mb_fli01_wetland_code(
  landmod text,
  weteco1 text,
  sp1 text,
  sp2 text,
  sp1per text,
  cc text,
  ht text
)
RETURNS text AS $$
  DECLARE
    _sp1per int;
	  _cc int;
	  _ht int;
  BEGIN
    _sp1per = sp1per::int;
	  _cc = cc::int;
	  _ht = ht::int;
	
    RETURN CASE
             -- General Wetlands: uncomment if only a general wetland class is desired
             WHEN landmod IN ('O','W') THEN 'W---'
             -- Non-treed Wetlands
             WHEN weteco1='1' THEN 'BONS'
             WHEN weteco1 IN ('2','5') THEN 'FONS'
             WHEN weteco1='3' THEN 'FONG'
             WHEN weteco1='4' THEN 'FONS'
             WHEN weteco1 IN ('6','7','8','9','10') THEN 'MONG'
             -- Treed Wetlands
             WHEN sp1='BS' AND _sp1per=100 AND _cc<50 AND _ht<12 THEN 'BTNN'
             WHEN sp1 IN ('BS','TL') AND _sp1per=100 AND _cc>=50 AND _ht>=12 THEN 'STNN'
             WHEN sp1 IN ('BS','TL') AND sp2 IN ('TL','BS') AND _cc>=50 AND _ht>=12 THEN 'STNN'
             WHEN sp1 IN ('WB','MM','EC','BA') THEN 'STNN'
             WHEN sp1 IN ('BS','TL') AND sp2 IN ('TL','BS') AND _cc<50 THEN 'FTNN'
             WHEN sp1='TL' AND _sp1per=100 AND _cc>0 AND _ht<12 THEN 'FTNN'
             ELSE NULL
           END;
  END
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_mb_fri01_wetland_code
--
-- Return 4-character wetland code
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_mb_fri01_wetland_code(text, text);
CREATE OR REPLACE FUNCTION TT_mb_fri01_wetland_code(
  productivity text,
  subtype text
)
RETURNS text AS $$
  SELECT CASE
           -- Non Productive
           WHEN productivity='701' THEN 'BTNN'
           WHEN productivity='702' THEN 'FTNN'
           WHEN productivity='703' THEN 'STNN'
           WHEN productivity IN ('721','722','723') THEN 'SONS'
           -- Productive
           WHEN subtype IN ('16','17','30','31','32','36','37','56','57','70','71','72','76','77') THEN 'STNN'
           WHEN subtype='9E' THEN 'SONS'
           ELSE NULL
         END;
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pc02_wetland_code(text, text, text)
--
-- Return 4-character wetland code
-- In pc02 every ECO translation is associated with either a lYR or NFL horizontal layer.
-- In order to correctly assign LAYER values for ECO, ROW_TRANSLATION_RULE should only run
-- the wetland translations associated with LYR when a LYR row is being translated in the attribute
-- dependencies. We use the lyr_or_nfl assigned to 'table' in the attribute_dependencies to do this.
-- Same goes for NFL, should only run for NFL rows being translated in attribute_dependencies.
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_pc02_wetland_code(text, text);
CREATE OR REPLACE FUNCTION TT_pc02_wetland_code(
  v_pcm text,
  v_str text,
  lyr_or_nfl text
)
RETURNS text AS $$
  SELECT CASE
           -- Non Productive
           WHEN lyr_or_nfl = 'NFL' AND v_pcm IN('7', '98') THEN 'SONS'
           WHEN lyr_or_nfl = 'NFL' AND v_pcm IN('1', '2', '3', '4', '99') THEN 'MONG'
           WHEN lyr_or_nfl = 'NFL' AND v_pcm IN('17') THEN 'FONG'
           WHEN lyr_or_nfl = 'NFL' AND v_pcm IN('18') THEN 'SONS'
           WHEN lyr_or_nfl = 'LYR' AND v_pcm IN('20') THEN 'STNN'
           WHEN lyr_or_nfl = 'LYR' AND v_pcm ='19' AND v_str = 'N' THEN 'FTNN'
           WHEN lyr_or_nfl = 'LYR' AND v_pcm ='19' AND v_str = 'P' THEN 'BTNN'
           ELSE NULL
         END;
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yt_wetland_code(text, text, text)
--
-- Return 4-character wetland code
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yt_wetland_code(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yt_wetland_code(
  smr text,
  cc text,
  class_ text,
  sp1 text,
  sp2 text,
  sp1_per text,
  avg_ht text
)
RETURNS text AS $$
  DECLARE
    _cc int;
    _sp1_per int;
    _avg_ht int;
    _smr text;
  BEGIN
    _cc = cc::int;
    _sp1_per = sp1_per::int;
    _avg_ht = avg_ht::int;
    _smr = upper(smr);
	RETURN CASE
           WHEN _smr='A' THEN 'MONG'
           WHEN _smr='W' AND class_='S' THEN 'SONS'
           WHEN _smr='W' AND class_='H' THEN 'MONG'
           WHEN _smr='W' AND class_='M' THEN 'SONS'
           WHEN _smr='W' AND class_='C' THEN 'FONS'
           WHEN _smr='W' AND (sp1='SB' AND _sp1_per=100) AND _cc<50 AND _avg_ht<12 THEN 'BTNN'
           WHEN _smr='W' AND (sp1='SB' AND _sp1_per=100) AND (_cc >= 50  AND  _cc < 70)  AND _avg_ht >= 12 THEN 'STNN'
           WHEN _smr='W' AND (sp1='SB' AND _sp1_per=100) AND _cc >= 70  AND _avg_ht >= 12 THEN 'SFNN'
           WHEN _smr='W' AND (sp1='SB' OR sp1='L') AND  (sp2='SB' OR sp2='L') AND _cc <= 50  AND _avg_ht < 12 THEN 'FTNN'
           WHEN _smr='W' AND (sp1='SB' OR sp1='L' OR sp1='W') AND (sp2='SB' OR sp2='L' OR sp2='W') AND _cc > 50  AND _avg_ht > 12 THEN 'STNN'
           WHEN _smr='W' AND (sp1='L' AND _sp1_per=100) AND _cc <= 50 THEN 'FTNN'
           WHEN _smr='W' AND (sp1='L' OR sp1='W') AND _sp1_per=100 AND (_cc > 50  AND _cc < 70) THEN 'STNN'
           WHEN _smr='W' AND (sp1='L' OR sp1='W') AND _sp1_per=100 AND (_cc >= 70) THEN 'SFNN'
           WHEN _smr='W' THEN 'W---'
           ELSE NULL
         END;
  END
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yt_wetland_code(text, text, text)
--
-- Return 4-character wetland code
-------------------------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yt04_wetland_string_code(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yt04_wetland_string_code(
  smr text,
  cc text,
  class_ text,
  sp1 text,
  sp2 text,
  sp1_per text,
  avg_ht text
)
RETURNS text AS $$
  DECLARE
    _cc int;
    _sp1_per int;
    _avg_ht int;
  BEGIN
    _cc = cc::int;
    _sp1_per = sp1_per::int;
    _avg_ht = avg_ht::int;
	RETURN CASE
           WHEN smr='Aquatic' THEN 'MONG'
           WHEN smr='Wet' AND class_ in ('Tall Shrub', 'Low Shrub', 'Tall Shrub, Open', 'Tall Shrub, Closed') THEN 'SONS'
           WHEN smr='Wet' AND (sp1='SB' AND _sp1_per=100) AND _cc<50 AND _avg_ht<12 THEN 'BTNN'
           WHEN smr='Wet' AND (sp1='SB' AND _sp1_per=100) AND (_cc >= 50  AND  _cc < 70)  AND _avg_ht >= 12 THEN 'STNN'
           WHEN smr='Wet' AND (sp1='SB' AND _sp1_per=100) AND _cc >= 70  AND _avg_ht >= 12 THEN 'SFNN'
           WHEN smr='Wet' AND (sp1='SB' OR sp1='L') AND  (sp2='SB' OR sp2='L') AND _cc <= 50  AND _avg_ht < 12 THEN 'FTNN'
           WHEN smr='Wet' AND (sp1='SB' OR sp1='L' OR sp1='W') AND (sp2='SB' OR sp2='L' OR sp2='W') AND _cc > 50  AND _avg_ht > 12 THEN 'STNN'
           WHEN smr='Wet' AND (sp1='L' AND _sp1_per=100) AND _cc <= 50 THEN 'FTNN'
           WHEN smr='Wet' AND (sp1='L' OR sp1='W') AND _sp1_per=100 AND (_cc > 50  AND _cc < 70) THEN 'STNN'
           WHEN smr='Wet' AND (sp1='L' OR sp1='W') AND _sp1_per=100 AND (_cc >= 70) THEN 'SFNN'
           WHEN smr='Wet' THEN 'W---'
           ELSE NULL
         END;
  END
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Begin Validation Function Definitions...
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_vri01_non_for_veg_validation
--
-- Check the correct combination of values exists based on the translation rules.
-- If not return FALSE
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_vri01_non_for_veg_validation(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_vri01_non_for_veg_validation(
  inventory_standard_cd text,
  land_cover_class_cd_1 text,
  bclcs_level_4 text,
  non_productive_descriptor_cd text
)
RETURNS boolean AS $$
  BEGIN
    -- run if statements
    IF inventory_standard_cd IN ('V', 'I') AND land_cover_class_cd_1 IS NOT NULL THEN
      IF land_cover_class_cd_1 IN ('BL', 'BM', 'BY', 'HE', 'HF', 'HG', 'SL', 'ST') THEN
        RETURN TRUE;
      END IF;
    END IF;
  
    IF inventory_standard_cd IN ('V', 'I') AND bclcs_level_4 IS NOT NULL THEN
      IF bclcs_level_4 IN ('BL', 'BM', 'BY', 'HE', 'HF', 'HG', 'SL', 'ST') THEN
        RETURN TRUE;
      END IF;
    END IF;
  
    IF inventory_standard_cd='F' AND non_productive_descriptor_cd IS NOT NULL THEN
      IF non_productive_descriptor_cd IN ('AF', 'M', 'NPBR', 'OR') THEN
        RETURN TRUE;
      END IF;
    END IF;

    IF inventory_standard_cd='F' AND bclcs_level_4 IS NOT NULL THEN
      IF bclcs_level_4 IN ('BL', 'BM', 'BY', 'HE', 'HF', 'HG', 'SL', 'ST') THEN
        RETURN TRUE;
      END IF;
    END IF;
    RETURN FALSE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_vri01_nat_non_veg_validation
--
-- Check the correct combination of values exists based on the translation rules.
-- If not return FALSE
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_vri01_nat_non_veg_validation(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_vri01_nat_non_veg_validation(
  inventory_standard_cd text,
  land_cover_class_cd_1 text,
  bclcs_level_4 text,
  non_productive_descriptor_cd text,
  non_veg_cover_type_1 text
)
RETURNS boolean AS $$
  BEGIN
    -- run if statements
    IF inventory_standard_cd IN ('V', 'I') AND non_veg_cover_type_1 IS NOT NULL THEN
      IF non_veg_cover_type_1 IN ('BE', 'BI', 'BR', 'BU', 'CB', 'DW', 'ES', 'GL', 'LA', 'LB', 'LL', 'LS', 'MN', 'MU', 'OC', 'PN', 'RE', 'RI', 'RM', 'RS', 'TA') THEN
        RETURN TRUE;
      END IF;
    END IF;

    IF inventory_standard_cd IN ('V', 'I') AND land_cover_class_cd_1 IS NOT NULL THEN
      IF land_cover_class_cd_1 IN ('BE', 'BI', 'BR', 'BU', 'CB', 'EL', 'ES', 'GL', 'LA', 'LB', 'LL', 'LS', 'MN', 'MU', 'OC', 'PN', 'RE', 'RI', 'RM', 'RO', 'RS', 'SI', 'TA') THEN
        RETURN TRUE;
      END IF;
    END IF;
  
    IF inventory_standard_cd IN ('V', 'I') AND bclcs_level_4 IS NOT NULL THEN
      IF bclcs_level_4 IN ('EL', 'RO', 'SI') THEN
        RETURN TRUE;
      END IF;
    END IF;
  
    IF inventory_standard_cd='F' AND non_productive_descriptor_cd IS NOT NULL THEN
      IF non_productive_descriptor_cd IN ('A', 'CL', 'G', 'ICE', 'L', 'MUD', 'R', 'RIV', 'S', 'SAND', 'TIDE') THEN
        RETURN TRUE;
      END IF;
    END IF;

    IF inventory_standard_cd='F' AND bclcs_level_4 IS NOT NULL THEN
      IF bclcs_level_4 IN ('EL', 'RO', 'SI') THEN
        RETURN TRUE;
      END IF;
    END IF;
    RETURN FALSE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_vri01_non_for_anth_validation
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_vri01_non_for_anth_validation(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_vri01_non_for_anth_validation(
  inventory_standard_cd text,
  land_cover_class_cd_1 text,
  non_productive_descriptor_cd text,
  non_veg_cover_type_1 text
)
RETURNS boolean AS $$
  BEGIN
    -- run if statements
    IF inventory_standard_cd IN ('V', 'I') AND non_veg_cover_type_1 IS NOT NULL THEN
      IF non_veg_cover_type_1 IN ('AP', 'GP', 'MI', 'MZ', 'OT', 'RN', 'RZ', 'TZ', 'UR') THEN
        RETURN TRUE;
      END IF;
    END IF;
      
    IF inventory_standard_cd IN ('V', 'I') AND land_cover_class_cd_1 IS NOT NULL THEN
      IF land_cover_class_cd_1 IN ('AP', 'GP', 'MI', 'MZ', 'OT', 'RN', 'RZ', 'TZ', 'UR') THEN
        RETURN TRUE;
      END IF;
    END IF;
      
    IF inventory_standard_cd='F' AND non_productive_descriptor_cd IS NOT NULL THEN
      IF non_productive_descriptor_cd IN ('C', 'GR', 'P', 'U') THEN
        RETURN TRUE;
      END IF;
    END IF;  
    RETURN FALSE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nb_nbi01_wetland_validation
--
-- Assign 4 letter wetland character code, then return true if the requested character (1-4)
-- is not null and not -.
--
-- e.g. TT_nb_nbi01_wetland_validation(wt, vt, im, '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nb_nbi01_wetland_validation(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_nb_nbi01_wetland_validation(
  wc text,
  vt text,
  im text,
  ret_char_pos text
)
RETURNS boolean AS $$
  DECLARE
		wetland_code text;
		wetland_char text;
  BEGIN
    PERFORM TT_ValidateParams('TT_nb_nbi01_wetland_validation',
                              ARRAY['ret_char_pos', ret_char_pos, 'int']);
	  wetland_code = TT_nb_nbi01_wetland_code(wc, vt, im);
    wetland_char = substring(wetland_code from ret_char_pos::int for 1);  	

    -- return true or false
    IF wetland_char IS NULL OR wetland_char = '-' THEN
      RETURN FALSE;
	  END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yvi01_nat_non_veg_validation()
--
-- type_lnd text
-- class text
-- landpos text
--
-- e.g. TT_yvi01_nat_non_veg_validation(type_lnd, class, landpos)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yvi01_nat_non_veg_validation(text,text,text);
CREATE OR REPLACE FUNCTION TT_yvi01_nat_non_veg_validation(
  type_lnd text,
  class_ text,
  landpos text
)
RETURNS boolean AS $$		
  BEGIN
    IF type_lnd IN('NW', 'NS', 'NE') THEN
      IF landpos = 'A' THEN
        RETURN TRUE;
      END IF;
    
      IF class_ IN('R','L','RS','E','S','B','RR') THEN
        RETURN TRUE;
      END IF;
    END IF;
    RETURN FALSE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yvi03_nat_non_veg_validation()
--
-- type_lnd text
-- class text
-- landpos text
-- covertype text
--
-- e.g. TT_yvi03_nat_non_veg_validation(type_lnd, class, landpos, covertype)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yvi03_nat_non_veg_validation(text,text,text, text);
CREATE OR REPLACE FUNCTION TT_yvi03_nat_non_veg_validation(
  type_lnd text,
  class_ text,
  landpos text,
  covertype text
)
RETURNS boolean AS $$
  BEGIN
    IF type_lnd IN('Non-Vegetated, Water', 'Non-Vegetated, Snow/Ice', 'Non-Vegetated, Exposed Land') THEN
      IF landpos = 'Alpine' THEN
        RETURN TRUE;
      END IF;

      IF class_ IN('River','Lake') THEN
        RETURN TRUE;
      END IF;

      IF covertype IN('River Sediments','Exposed Soil','Burned Area','Rock & Rubble') THEN
        RETURN TRUE;
      END IF;
    END IF;
    RETURN FALSE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yvi01_nfl_soil_moisture_validation
--
-- type_lnd text
-- class_ text
-- cl_mod text
-- landpos text
--
-- Only want to translate soil moisture in NFL table if the row is either non_for_veg or
-- nat_non_veg = EX (burned or exposed land).
-- e.g. TT_yvi01_nfl_soil_moisture_validation(type_land, class_, cl_mod, landpos)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yvi01_nfl_soil_moisture_validation(text,text,text,text);
CREATE OR REPLACE FUNCTION TT_yvi01_nfl_soil_moisture_validation(
  type_lnd text,
  class_ text,
  cl_mod text,
  landpos text
)
RETURNS boolean AS $$		
  BEGIN
  
    -- If row has non_for_veg attribute, return true
    IF type_lnd = 'VN' THEN
      IF class_ IN('S','H','C','M') THEN
        IF TT_yvi01_non_for_veg_translation(type_lnd, class_, cl_mod) IS NOT NULL THEN
          RETURN TRUE;
        END IF;
      END IF;
    END IF;
  
    -- If row has nat_non_veg attribute of EX, return true
    IF type_lnd IN('NW','NS','NE') THEN
      IF TT_yvi01_nat_non_veg_validation(type_lnd, class_, landpos) THEN
        IF TT_yvi01_nat_non_veg_translation(type_lnd, class_, landpos) = 'EXPOSED_LAND' THEN
          RETURN TRUE;
        END IF;
      END IF;
    END IF;
  
    RETURN FALSE;
    
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yvi03_nfl_soil_moisture_validation
--
-- type_lnd text
-- class_ text
-- cl_mod text
-- landpos text
-- covertype text
--
-- Only want to translate soil moisture in NFL table if the row is either non_for_veg or
-- nat_non_veg = EX (burned or exposed land).
-- e.g. TT_yvi03_nfl_soil_moisture_validation(type_land, class_, cl_mod, landpos, covertype)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yvi03_nfl_soil_moisture_validation(text,text,text,text);
CREATE OR REPLACE FUNCTION TT_yvi03_nfl_soil_moisture_validation(
  type_lnd text,
  class_ text,
  cl_mod text,
  landpos text,
  covertype text
)
RETURNS boolean AS $$
  BEGIN

    -- If row has non_for_veg attribute, return true
    IF type_lnd = 'Vegetated, Non-Forested' THEN
      IF cl_mod IN('Tall Shrub', 'Low Shrub', 'Tall Shrub, Open', 'Tall Shrub, Closed') THEN
        IF TT_yvi03_non_for_veg_translation(type_lnd, cl_mod) IS NOT NULL THEN
          RETURN TRUE;
        END IF;
      END IF;
    END IF;

    -- If row has nat_non_veg attribute of EX, return true
    IF type_lnd IN('Non-Vegetated, Water','Non-Vegetated, Snow/Ice','Non-Vegetated, Exposed Land') THEN
      IF TT_yvi03_nat_non_veg_validation(type_lnd, class_, landpos, covertype) THEN
        IF TT_yvi03_nat_non_veg_translation(type_lnd, class_, landpos, covertype) = 'EXPOSED_LAND' THEN
          RETURN TRUE;
        END IF;
      END IF;
    END IF;

    RETURN FALSE;

  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-- TT_avi01_stand_structure_validation
--
-- stand_structure text
-- nfl_l1_1 text
-- nfl_l1_2 text
-- nfl_l1_3 text
-- nfl_l1_4 text
--
-- Catch the cases where stand structure will be NOT_APPLICABLE because row is NFL.
-- Will be every row where overstory attributes are NFL. Except those
-- cases where stand structure is Horizontal.
-- Overstory species should always be absent when there is overstory NFL.
-- If overstory is NFL then understory should not have sp1, unless stand structure is Horizontal.
-- e.g. TT_avi01_stand_structure_validation(nfl_l1_1, nfl_l1_2, nfl_l1_2, stand_structure)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_avi01_stand_structure_validation(text,text,text, text, text);
CREATE OR REPLACE FUNCTION TT_avi01_stand_structure_validation(
  stand_structure text,
  nfl_l1_1 text,
  nfl_l1_2 text,
  nfl_l1_3 text,
  nfl_l1_4 text
)
RETURNS boolean AS $$		
  BEGIN
    -- if stand structure is Horozontal, always return true
    IF stand_structure IN ('H', 'h') THEN
      RETURN TRUE;
    END IF;
  
    -- if overstory species is NFL (and stand structure not H), return FALSE
    IF TT_notEmpty(nfl_l1_1) OR TT_notEmpty(nfl_l1_2) OR TT_notEmpty(nfl_l1_3) OR TT_notEmpty(nfl_l1_4) THEN
      RETURN FALSE;
    END IF;  
  
    -- other cases return true
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_fvi01_stand_structure_validation
--
-- stand_structure text
-- nfl text
--
-- Catch the cases where stand structure will be NOT_APPLICABLE because stand is
-- not horizontal and there is no species info.
--
-- e.g. TT_fvi01_stand_structure_validation(stand_structure, species_1_layer1, species_2_layer1, species_3_layer1, species_4_layer1, species_1_layer2, species_2_layer2, species_3_layer2, species_4_layer2)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_fvi01_stand_structure_validation(text,text,text,text,text,text,text);
CREATE OR REPLACE FUNCTION TT_fvi01_stand_structure_validation(
  stand_structure text,
  typeclas text,
  mintypeclas text,
  species_1_layer1 text,
  species_2_layer1 text,
  species_3_layer1 text,
  species_1_layer2 text,
  species_2_layer2 text,
  species_3_layer2 text
)
RETURNS boolean AS $$		
  DECLARE
    _nfl_codes text;
  BEGIN
    _nfl_codes = '{BE,BR,BU,CB,ES,LA,LL,LS,MO,MU,PO,RE,RI,RO,RS,RT,SW,AP,BP,EL,GP,TS,RD,SH,SU,PM,BL,BM,BY,HE,HF,HG,SL,ST}';

    -- if stand structure is Horozontal, always return true
    IF stand_structure IN ('H', 'h') THEN
      RETURN TRUE;
    END IF;
  
    -- if any layer 1 species info, return TRUE
    IF TT_notMatchList(typeclas, _nfl_codes) AND (TT_notEmpty(species_1_layer1) OR TT_notEmpty(species_2_layer1) OR TT_notEmpty(species_3_layer1)) THEN
      RETURN TRUE;
    END IF;
  
    -- if any layer 2 species info, return TRUE
    IF TT_notMatchList(mintypeclas, _nfl_codes) AND (TT_notEmpty(species_1_layer2) OR TT_notEmpty(species_2_layer2) OR TT_notEmpty(species_3_layer2)) THEN
      RETURN TRUE;
    END IF;
  
    -- other cases return false
    RETURN FALSE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sk_utm01_species_percent_validation
--
-- sp10 text
-- sp11 text
-- sp12 text
-- sp20 text
-- sp21 text
--
-- Checks the combination of hardwood and softwood species is valid and in one of the
-- expected codes used in the translation function.
--
-- Codes the polygon being processed based on the combination of hardwood and
-- softwood species in each column.
-- e.g. concatenates in order either H for hardwood, S for softwood or - for nothing
-- into a 5 character string such as S----
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_sk_utm01_species_percent_validation(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_sk_utm01_species_percent_validation(
  sp10 text,
  sp11 text,
  sp12 text,
  sp20 text,
  sp21 text
)
RETURNS boolean AS $$
  DECLARE
    hardwoods text[]; -- list of harwood species codes
    softwoods text[]; -- list of softwood species codes
    ft10 text; -- assigns hardwood or softwood forest type
    ft11 text;
    ft12 text;
    ft20 text;
    ft21 text;
    ft_concat text; -- concatenates the ft values.
  BEGIN
    -- assign hardwood and softwood groups
    softwoods = ARRAY['WS','BS','JP','BF','TL','LP'];
    hardwoods = ARRAY['GA','TA','BP','WB','WE','MM','BO'];
  
    -- assign forest type variables
    IF sp10 = ANY(hardwoods) THEN ft10 = 'H';
    ELSIF sp10 = ANY(softwoods) THEN ft10 = 'S';
    ELSE ft10 = '-';
    END IF;
  
    IF sp11 = ANY(hardwoods) THEN ft11 = 'H';
    ELSIF sp11 = ANY(softwoods) THEN ft11 = 'S';
    ELSE ft11 = '-';
    END IF;
  
    IF sp12 = ANY(hardwoods) THEN ft12 = 'H';
    ELSIF sp12 = ANY(softwoods) THEN ft12 = 'S';
    ELSE ft12 = '-';
    END IF;
  
    IF sp20 = ANY(hardwoods) THEN ft20 = 'H';
    ELSIF sp20 = ANY(softwoods) THEN ft20 = 'S';
    ELSE ft20 = '-';
    END IF;
  
    IF sp21 = ANY(hardwoods) THEN ft21 = 'H';
    ELSIF sp21 = ANY(softwoods) THEN ft21 = 'S';
    ELSE ft21 = '-';
    END IF;

    -- assign forest type code
    ft_concat = ft10 || ft11 || ft12 || ft20 || ft21;
  
    -- Check code is in the expected list based on source data with valid entries
    RETURN ft_concat = ANY(ARRAY['H----', 'H--S-', 'H--SS', 'HH---', 'HH-S-', 'HH-SS', 'HHH--', 'HHHS-', 'HHHSS', 'HS-S-', 'S----', 'S--H-', 'S--HH', 'SS---', 'SS-H-', 'SS-HH', 'SS-S-', 'SSS--', 'SSSH-', 'SSSHH', 'HS---', 'SH---']);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_vri01_hasCountOfNotNull
--
-- vals1 text - string list of layer 1 attributes. This is carried through to couneOfNotNull
-- vals2 text - string list of layer 2 attribtues. This is carried through to couneOfNotNull
-- inventory_standard_cd text
-- land_cover_class_cd_1 text
-- bclcs_level_4 text
-- non_productive_descriptor_cd text
-- non_veg_cover_type_1 text
-- zero_is_null
--
-- hasCountOfNotNull using custom vri countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_vri01_hasCountOfNotNull(text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_vri01_hasCountOfNotNull(
  vals1 text,
  vals2 text,
  inventory_standard_cd text,
  land_cover_class_cd_1 text,
  bclcs_level_4 text,
  non_productive_descriptor_cd text,
  non_veg_cover_type_1 text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_vri01_countOfNotNull(vals1, vals2, inventory_standard_cd, land_cover_class_cd_1, bclcs_level_4, non_productive_descriptor_cd, non_veg_cover_type_1, '5');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;
                                  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_vri01_hasCountOfNotNull
--
-- species_layer_1 text,
-- species_layer_2 text,
-- species_layer_3 text,
-- species_layer_4 text,
-- species_layer_5 text,
-- nnf_anth text,
-- count text
-- zero_is_null
--
-- hasCountOfNotNull using custom fli01 countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_mb_fli01_hasCountOfNotNull(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_mb_fli01_hasCountOfNotNull(
  species_layer_1 text,
  species_layer_2 text,
  species_layer_3 text,
  species_layer_4 text,
  species_layer_5 text,
  nnf_anth text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_mb_fli01_countOfNotNull(species_layer_1, species_layer_2, species_layer_3, species_layer_4, species_layer_5, nnf_anth, '6');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;
                                  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_ns_nsi01_hasCountOfNotNull
--
-- vals1 text - string list of layer 1 attributes. This is carried through to couneOfNotNull
-- vals2 text - string list of layer 2 attribtues. This is carried through to couneOfNotNull
-- fornon text
-- count text
-- exact
--
-- hasCOuntOfNotNull using ns custom countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ns_nsi01_hasCountOfNotNull(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_ns_nsi01_hasCountOfNotNull(
  vals1 text,
  vals2 text,
  fornon text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_ns_nsi01_countOfNotNull(vals1, vals2, fornon, '3');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_fvi01_hasCountOfNotNull
--
-- vals1 text
-- vals2 text
-- typeclas_nonveg text
-- typeclas_anth text
-- typeclas text
-- min_typeclas text
-- count text
-- exact text
--
-- hasCOuntOfNotNull using fvi custom countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_fvi01_hasCountOfNotNull(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_fvi01_hasCountOfNotNull(
  vals1 text,
  vals2 text,
  typeclas_nonveg text,
  typeclas_anth text,
  typeclas text,
  min_typeclas text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_fvi01_countOfNotNull(vals1, vals2, typeclas_nonveg, typeclas_anth, typeclas, min_typeclas, '4');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

------------------------------------------------------------
-- TT_on_fim02_hasCountOfNotNull
--
-- vals1 text
-- vals2 text
-- polytype text
-- count text
-- exact text
--
-- hasCOuntOfNotNull using fim02 custom countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_on_fim02_hasCountOfNotNull(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_on_fim02_hasCountOfNotNull(
  vals1 text,
  vals2 text,
  polytype text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_on_fim02_countOfNotNull(vals1, vals2, polytype, '3');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pe_pei01_hasCountOfNotNull
--
-- spec1 text
-- spec2 text
-- spec3 text
-- spec4 text
-- spec5 text
-- landtype text
-- count text
-- exact text
--
-- hasCountOfNotNull using pei01 custom countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_pe_pei01_hasCountOfNotNull(text, text, text, text, text, text, text,text, text);
CREATE OR REPLACE FUNCTION TT_pe_pei01_hasCountOfNotNull(
  spec1 text,
  spec2 text,
  spec3 text,
  spec4 text,
  spec5 text,
  landuse text,
  subuse text,
  class1 text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_pe_pei01_countOfNotNull(spec1, spec2, spec3, spec4, spec5, landuse, subuse, class1, '2');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pe_pei02_hasCountOfNotNull
--
-- spec1 text
-- spec2 text
-- spec3 text
-- spec4 text
-- spec5 text
-- landtype text
-- count text
-- exact text
--
-- hasCountOfNotNull using pei02 custom countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_pe_pei02_hasCountOfNotNull(text, text, text, text, text, text, text,text, text, text);
CREATE OR REPLACE FUNCTION TT_pe_pei02_hasCountOfNotNull(
  spec1 text,
  spec2 text,
  spec3 text,
  spec4 text,
  spec5 text,
  landtype text,
  class1 text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_pe_pei02_countOfNotNull(spec1, spec2, spec3, spec4, spec5, landtype, class1, '2');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- sfv01_hasCountOfNotNull
--
-- vals1 text - string list of layer 1 attributes. This is carried through to couneOfNotNull
-- vals2 text - string list of layer 2 attribtues. This is carried through to couneOfNotNull
-- vals3 text - string list of layer 3 attributes. This is carried through to couneOfNotNull
-- vals4 text - string list of layer 4 (shrub) attributes. This is carried through to couneOfNotNull
-- vals5 text - string list of layer 5 (herb) attributes. This is carried through to couneOfNotNull
-- nvsl text
-- aquatic_class text
-- luc text
-- transp_class text
-- count text
-- exact text
--
-- hasCountOfNotNull calling sfvi countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_sfv01_hasCountOfNotNull(text, text, text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_sfv01_hasCountOfNotNull(
  vals1 text,
  vals2 text,
  vals3 text,
  vals4 text,
  vals5 text,
  _type text,
  nvsl text,
  aquatic_class text,
  luc text,
  transp_class text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_sfv01_countOfNotNull(vals1, vals2, vals3, vals4, vals5, _type, nvsl, aquatic_class, luc, transp_class, '6');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sk_utm_hasCountOfNotNull
--
-- vals1 text
-- vals2 text
-- np text
-- count text
-- exact text
--
-- hasCountOfNotNull using sfvi custom countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_sk_utm_hasCountOfNotNull(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_sk_utm_hasCountOfNotNull(
  vals1 text,
  vals2 text,
  np text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_sk_utm_countOfNotNull(vals1, vals2, np, '3');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_mb_fri_hasCountOfNotNull
--
-- species text - species
-- nfl text - nfl attribute
-- count text
-- exact text
--
-- hasCountOfNotNull using mb fri custom countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_mb_fri_hasCountOfNotNull(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_mb_fri_hasCountOfNotNull(
  species text,
  nfl text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_mb_fri_countOfNotNull(species, nfl, '2');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yvi03_hasCountOfNotNull
--
-- species_1 text,
-- type_lnd text, 
-- cover_type text, 
-- cl_mod text, 
-- landpos text,
-- count text,
-- exact text
--
-- hasCountOfNotNull using yvi03 custom countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yvi03_hasCountOfNotNull(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yvi03_hasCountOfNotNull(
  species_1 text,
  type_lnd text, 
  cover_type text, 
  cl_mod text, 
  landpos text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_yvi03_countOfNotNull(species_1, type_lnd, cover_type, cl_mod, landpos, '2');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_fvi01_structure_per_validation
--
-- stand_structure text
-- layer text
--
-- Catch the case where stand structure is horizontal and layer is 2.
-- This can only happen in forested stands with horizontal structure
-- In this case we don`t know the structure percent of the second layer
-- because there is only one structure_per attribute. Catch and return
-- UNKNOWN.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_fvi01_structure_per_validation(text, text);
CREATE OR REPLACE FUNCTION TT_fvi01_structure_per_validation(
  stand_structure text,
  layer text
)
RETURNS boolean AS $$
  BEGIN
    IF stand_structure = 'H' AND layer = '2' THEN
      RETURN FALSE;
    ELSE
      RETURN TRUE;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg3_wetland_validation
--
-- CO_TER text,
-- CL_DRAIN text,
-- gr_ess text,
-- cl_dens text,
-- cl_haut text,
-- TYPE_ECO text
--
-- Get the wetland code and check it matches one of the expected values
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg3_wetland_validation(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_qc_prg3_wetland_validation(
  CO_TER text,
  CL_DRAIN text,
  gr_ess text,
  cl_den text,
  cl_haut text,
  TYPE_ECO text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_qc_wetland_code(CO_TER, CL_DRAIN, gr_ess, cl_den, cl_haut, TYPE_ECO, 'QC03');
	  _wetland_char = substring(_wetland_code from retCharPos::int for 1);
	  IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg4_wetland_validation
--
-- CO_TER text,
-- CL_DRAIN text,
-- gr_ess text,
-- cl_dens text,
-- cl_haut text,
-- TYPE_ECO text
--
-- Get the wetland code and check it matches one of the expected values
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg4_wetland_validation(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_qc_prg4_wetland_validation(
  CO_TER text,
  CL_DRAIN text,
  gr_ess text,
  cl_den text,
  cl_haut text,
  TYPE_ECO text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_qc_wetland_code(CO_TER, CL_DRAIN, gr_ess, cl_den, cl_haut, TYPE_ECO, 'QC04');
	  _wetland_char = substring(_wetland_code from retCharPos::int for 1);
	  IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
	  END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg5_wetland_validation
--
-- CO_TER text,
-- CL_DRAIN text,
-- gr_ess text,
-- cl_dens text,
-- cl_haut text,
-- TYPE_ECO text
--
-- Get the wetland code and check it matches one of the expected values
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg5_wetland_validation(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_qc_prg5_wetland_validation(
  CO_TER text,
  CL_DRAIN text,
  gr_ess text,
  cl_den text,
  cl_haut text,
  TYPE_ECO text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_qc_wetland_code(CO_TER, CL_DRAIN, gr_ess, cl_den, cl_haut, TYPE_ECO, 'QC05');
    _wetland_char = substring(_wetland_code from retCharPos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
	END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg4_not_double_species_validation
--
-- gr_ess text,
--
-- If species is doubled (e.g. FXFX) returns false. Otherwise true.
-- Must have 2 species (code length = 4) with matching values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg4_not_double_species_validation(text);
CREATE OR REPLACE FUNCTION TT_qc_prg4_not_double_species_validation(
  gr_ess text
)
RETURNS boolean AS $$
  DECLARE
    sp_1 text;
    sp_2 text;
  BEGIN
    -- Return TRUE if null or empty. Only case of double species should fail validation.
    IF NOT TT_notEmpty(gr_ess) THEN
      RETURN TRUE;
    END IF;
  
    sp_1 = trim(SPLIT_PART(species, ' ', 1))
    FROM (SELECT trim(regexp_replace(gr_ess, '(.{2})', E'\\1 ', 'g')) as species) r;

    sp_2 = trim(SPLIT_PART(species, ' ', 2))
    FROM (SELECT trim(regexp_replace(gr_ess, '(.{2})', E'\\1 ', 'g')) as species) r;
    
    IF sp_1 = sp_2 THEN
      RETURN FALSE;
    ELSE
      RETURN TRUE;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg4_lengthMatchList
--
-- gr_ess text,
-- lst text,
-- trim_ text,
-- removeSpaces text,
-- acceptNull text,
-- matches text
--
-- If species is doubled (e.g. FXFX) remove the first two characters.
-- Then calculate length and pass to matchList.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg4_lengthMatchList(text, text);
CREATE OR REPLACE FUNCTION TT_qc_prg4_lengthMatchList(
  gr_ess text,
  lst text
)
RETURNS boolean AS $$
  DECLARE
    sp_1 text;
    sp_2 text;
    _gr_ess text;
    _length text;
  BEGIN
    sp_1 = trim(SPLIT_PART(species, ' ', 1))
    FROM (SELECT trim(regexp_replace(gr_ess, '(.{2})', E'\\1 ', 'g')) as species) r;

    sp_2 = trim(SPLIT_PART(species, ' ', 2))
    FROM (SELECT trim(regexp_replace(gr_ess, '(.{2})', E'\\1 ', 'g')) as species) r;
    
    IF sp_1 = sp_2 THEN
      _gr_ess = substring(gr_ess, 3, 4);
    ELSE
      _gr_ess = gr_ess;
    END IF;
  
    RETURN TT_lengthMatchList(_gr_ess, lst);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_isCommercial
--
-- stand_id text,
-- working_group text
--
-- Is the row defined as commercial forest?
-- Commercial polygons are those with stand_id 1-899 or 1000-7000, and working_group value not equal to CS or DS
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_isCommercial(text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_isCommercial(
  stand_id text,
  working_group text
)
RETURNS boolean AS $$
  DECLARE
    _stand_id int;
  BEGIN
    -- CS and DS denote scrub, not commercial
    IF working_group IN('CS', 'DS') THEN
      RETURN FALSE;
    END IF;
  
    -- if stand id has no value, return false
    IF NOT TT_isInt(stand_id) THEN
      RETURN FALSE;
    ELSE
      _stand_id = stand_id::int;
    END IF;
  
    -- return true if working group not CS or DS, and stand_id 1-899 or 1000-7000
    IF (_stand_id >= 1 AND _stand_id <= 899) OR (_stand_id >= 1000 AND _stand_id <= 7000) THEN
      RETURN TRUE;
    END IF;
  
    RETURN FALSE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_isNonCommercial
--
-- stand_id text,
-- working_group text
--
-- Is the row defined as non-commercial forest?
-- Non-Commercial polygons are those with stand_id 900, 910 or working_group is CS or DS
-- These are all forest scrub
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_isNonCommercial(text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_isNonCommercial(
  stand_id text,
  working_group text
)
RETURNS boolean AS $$
  DECLARE
    _stand_id int;
  BEGIN
    -- CS and DS denote scrub, not commercial
    IF working_group IN('CS', 'DS') THEN
      RETURN TRUE;
    END IF;
  
    -- if stand id has no value, return false
    IF NOT TT_isInt(stand_id) THEN
      RETURN FALSE;
    ELSE
      _stand_id = stand_id::int;
    END IF;
      
    -- return true if stand_id 900 or 910 (scrub)
    IF _stand_id = 900 OR _stand_id = 910 THEN
      RETURN TRUE;
    END IF;
  
    RETURN FALSE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_isForest
--
-- stand_id text,
-- working_group text
--
-- Is row either commercial or non-commercial forest?
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_isForest(text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_isForest(
  stand_id text,
  working_group text
)
RETURNS boolean AS $$
  BEGIN
    IF TT_nl_nli01_isCommercial(stand_id, working_group) OR TT_nl_nli01_isNonCommercial(stand_id, working_group) THEN
      RETURN TRUE;
    ELSE
      RETURN FALSE;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_origin_lower_validation
--
-- age_class text,
-- src_filename text
--
-- For age class 7 in Newfoundland upper age bound is 121+ which means lower origin
-- is unknown.
-- Same for age class 9 in Labrador where age class is 161+.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_origin_lower_validation(text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_origin_lower_validation(
  age_class text,
  src_filename text
)
RETURNS boolean AS $$
  DECLARE
    map_unit_int int;
  BEGIN
    map_unit_int = substring(src_filename, 3,3)::int;
  
    IF map_unit_int > 0 AND map_unit_int <=180 THEN -- Newfoundland
       IF age_class::int = 7 THEN
         RETURN FALSE;
       END IF;
    END IF;
  
    IF map_unit_int >= 238 AND map_unit_int <= 415 THEN -- Labrador
      IF age_class::int = 9 THEN
        RETURN FALSE;
      END IF;
    END IF;

    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_origin_newfoundland_validation
--
-- density_code text,
-- src_filename text
--
-- Catch the error case where polygon is in Newfoundland and density code is 9 or 10
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_origin_newfoundland_validation(text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_origin_newfoundland_validation(
  age_code text,
  src_filename text
)
RETURNS boolean AS $$
  DECLARE
    map_unit_int int;
  BEGIN
    map_unit_int = substring(src_filename, 3,3)::int;
  
    IF map_unit_int > 0 AND map_unit_int <=180 THEN -- Newfoundland
       IF age_code IN('8','9') THEN
         RETURN FALSE;
       END IF;
    END IF;
  
    RETURN TRUE;
  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_crown_closure_validation
--
-- density_code text,
-- stand_id text
-- working_group text
--
-- Catch the error case where forest is commercial and density code is 4.
-- Should be 1-3 in commercial and 1-4 in non commercial
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_crown_closure_validation(text, text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_crown_closure_validation(
  stand_id text,
  working_group text,
  density_code text
)
RETURNS boolean AS $$
  DECLARE
    commercial boolean;
  BEGIN
    commercial = TT_nl_nli01_isCommercial(stand_id, working_group);
  
    IF commercial THEN
       IF density_code = '4' THEN
         RETURN FALSE;
       END IF;
    END IF;
  
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_height_validation
--
-- height_code text,
-- stand_id text
-- working_group text
--
-- Catch the error case where forest is non commercial and density code is 6, 7, or 8.
-- Should be 1-8 in commercial and 1-5 in non commercial
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_height_validation(text, text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_height_validation(
  height_code text,
  stand_id text,
  working_group text
)
RETURNS boolean AS $$
  DECLARE
    noncommercial boolean;
  BEGIN
    noncommercial = TT_nl_nli01_isNonCommercial(stand_id, working_group);
  
    IF noncommercial THEN
       IF height_code IN('6', '7', '8') THEN
         RETURN FALSE;
       END IF;
    END IF;
  
    RETURN TRUE;
  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_hasCountOfNotNull
--
-- cl_age text
-- co_ter text
-- count text
-- exact text
--
-- hasCountOfNotNull using qc custom countOfNotNull
-- For prg 3 and 4 we get number of LYRs from cl_age in lookup table
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_hasCountOfNotNull(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_qc_hasCountOfNotNull(
  num_of_layers text,
  co_ter text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    -- validate parameters (trigger EXCEPTION)
    PERFORM TT_ValidateParams('TT_qc_hasCountOfNotNull',
                              ARRAY['count', count, 'int',
                                    'exact', exact, 'boolean']);
  
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_qc_CountOfNotNull(num_of_layers, co_ter, '3');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_ab_avi01_wetland_validation
--
-- Check translation creates a valid 4 letter wetland code.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ab_avi01_wetland_validation(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_ab_avi01_wetland_validation(
  moisture text,
  nonfor_veg text,
  nat_nonveg text,
  sp1 text,
  sp2 text,
  crownclose text,
  sp1_percnt text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_ab_avi01_wetland_code(moisture, nonfor_veg, nat_nonveg, sp1, sp2, crownclose, sp1_percnt);
	  _wetland_char = substring(_wetland_code from retCharPos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_wetland_validation
--
-- Check for valid 4 letter code.
--
-- e.g. TT_nl_nli01_wetland_validation(landtype, per1, '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_wetland_validation(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_wetland_validation(
  stand_id text,
  site text,
  species_comp text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_nl_nli01_wetland_code(stand_id, site, species_comp);
    _wetland_char = substring(_wetland_code from retCharPos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_bc_vri01_wetland_validation
--
-- Check the requested return character is a valid wetland character
--
-- e.g. TT_bc_vri01_wetland_validation(landtype, per1, '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_bc_vri01_wetland_validation(text, text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_bc_vri01_wetland_validation(
  inventory_standard_cd text,
  l1_species_cd_1 text,
  l1_species_pct_1 text,
  l1_species_cd_2 text,
  non_productive_descriptor_cd text,
  l1_non_forest_descriptor text,
  land_cover_class_cd_1 text,
  soil_moisture_regime_1 text,
  l1_crown_closure text,
  l1_proj_height_1 text,
  ret_char_pos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_bc_vri01_wetland_code(inventory_standard_cd, l1_species_cd_1, l1_species_pct_1, l1_species_cd_2, non_productive_descriptor_cd, l1_non_forest_descriptor, land_cover_class_cd_1, soil_moisture_regime_1, l1_crown_closure, l1_proj_height_1);
    _wetland_char = substring(_wetland_code from ret_char_pos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_ns_nsi01_wetland_validation
--
-- Assign 4 letter wetland character code, then return true if the requested character (1-4)
-- is not null and not -.
--
-- e.g. TT_ns_nsi01_wetland_validation(landtype, per1, '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ns_nsi01_wetland_validation(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_ns_nsi01_wetland_validation(
  fornon text,
  species text,
  crncl text,
  height text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_ns_nsi01_wetland_code(fornon, species, crncl, height);
    _wetland_char = substring(_wetland_code from retCharPos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pe_pei01_wetland_validation
-- Assign 4 letter wetland character code, then return true if the requested character (1-4)
-- is not null and not -.
-- e.g. TT_pe_pei01_wetland_validation(landtype, per1, 999, 999, 999, '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_pe_pei01_wetland_validation(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_pe_pei01_wetland_validation(
  landtype text,
  per1 text,
  landtype2 text,
  per2 text,
  landtype3 text,
  per3 text,
  ret_char_pos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
	_wetland_code = TT_pe_pei01_wetland_code(landtype, per1, landtype2, per2, landtype3, per3);
    _wetland_char = substring(_wetland_code from ret_char_pos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nt_fvi01_wetland_validation
-- Assign 4 letter wetland character code and check value matches expected values.
--
-- e.g. TT_nt_fvi01_wetland_validation(landpos, structur, moisture, typeclas, mintypeclas, sp1, sp2, sp1_per, crownclos, height, wetland)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nt_fvi01_wetland_validation(text, text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_nt_fvi01_wetland_validation(
	landpos text,
	structur text,
	moisture text,
	typeclas text,
	mintypeclas text,
	sp1 text,
	sp2 text,
	sp1_per text,
	crownclos text,
	height text,
	wetland text,
  ret_char_pos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_nt_fvi01_wetland_code(landpos, structur, moisture, typeclas, mintypeclas, sp1, sp2, sp1_per, crownclos, height, wetland);
    _wetland_char = substring(_wetland_code from ret_char_pos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sk_utm01_wetland_validation
--
-- Assign 4 letter wetland character code and check value matches expected values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_sk_utm01_wetland_validation(text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_sk_utm01_wetland_validation(
  drain text,
  sp10 text,
  sp11 text,
  sp12 text,
  sp20 text,
  sp21 text,
  d text,
  np text,
  soil_text text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_sk_utm01_wetland_code(drain, sp10, sp11, sp12, sp20, sp21, d, np, soil_text);
    _wetland_char = substring(_wetland_code from retCharPos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sk_sfv01_wetland_validation
--
-- Assign 4 letter wetland character code and check value matches expected values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_sk_sfv01_wetland_validation(text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_sk_sfv01_wetland_validation(
  soil_moist_reg text,
  species_1 text,
  species_2 text,
  species_per_1 text,
  crown_closure text,
  height text,
  shrub1 text,
  herb1 text,
  shrubs_crown_closure text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_sk_sfv01_wetland_code(soil_moist_reg, species_1, species_2, species_per_1, crown_closure, height, shrub1, herb1, shrubs_crown_closure);
    _wetland_char = substring(_wetland_code from retCharPos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_mb_fli01_wetland_validation
--
-- Assign 4 letter wetland character code and check value matches expected values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_mb_fli01_wetland_validation(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_mb_fli01_wetland_validation(
  landmod text,
  weteco1 text,
  sp1 text,
  sp2 text,
  sp1per text,
  cc text,
  ht text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_mb_fli01_wetland_code(landmod, weteco1, sp1, sp2, sp1per, cc, ht);
    _wetland_char = substring(_wetland_code from retCharPos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_mb_fri01_wetland_validation
--
-- Assign 4 letter wetland character code and check value matches expected values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_mb_fri01_wetland_validation(text, text, text);
CREATE OR REPLACE FUNCTION TT_mb_fri01_wetland_validation(
  productivity text,
  subtype text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_mb_fri01_wetland_code(productivity, subtype);
    _wetland_char = substring(_wetland_code from retCharPos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pc02_wetland_validation
--
-- Assign 4 letter wetland character code and check value matches expected values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_pc02_wetland_validation(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_pc02_wetland_validation(
  v_pcm text,
  v_str text,
  lyr_or_nfl text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_pc02_wetland_code(v_pcm, v_str, lyr_or_nfl);
    _wetland_char = substring(_wetland_code from retCharPos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yt_wetland_validation(text, text, text)
--
-- Assign 4 letter wetland character code and check value matches expected values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yt_wetland_validation(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yt_wetland_validation(
  smr text,
  cc text,
  class_ text,
  sp1 text,
  sp2 text,
  sp1_per text,
  avg_ht text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_yt_wetland_code(smr, cc, class_, sp1, sp2, sp1_per, avg_ht);
    _wetland_char = substring(_wetland_code from retCharPos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yt_wetland_validation(text, text, text)
--
-- Assign 4 letter wetland character code and check value matches expected values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yt04_wetland_validation(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yt04_wetland_validation(
  smr text,
  cc text,
  class_ text,
  sp1 text,
  sp2 text,
  sp1_per text,
  avg_ht text,
  retCharPos text
)
RETURNS boolean AS $$
  DECLARE
    _wetland_code text;
    _wetland_char text;
  BEGIN
    _wetland_code = TT_yt04_wetland_string_code(smr, cc, class_, sp1, sp2, sp1_per, avg_ht);
    _wetland_char = substring(_wetland_code from retCharPos::int for 1);
    IF _wetland_char IS NULL OR _wetland_char = '-' THEN
      RETURN FALSE;
    END IF;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;

-------------------------------------------------------------------------------
-- TT_ab_photo_year_validation
--
-- AB inventories pre AB25 need to intersect with the photo year table to get photo year.
-- Post AB25 inventories have a photo year column so just need to check the value is valid.
--
-- All failed validations will return -9997 (INVALID_VALUE)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ab_photo_year_validation(text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_ab_photo_year_validation(
  inventoryID text,
  wkbGeometry text,
  lookupSchema text,
  lookupTable text,
  lookupCol text,
  photoYear text,
  lowerBound text,
  upperBound text,
  data_yr text
)
RETURNS boolean AS $$
  BEGIN
    -- for inventories without any data acquisition information, run the geoIsValid and geoIntersects validations
    IF TT_notNull(photoYear) IS FALSE AND data_yr = '0' THEN
      IF TT_geoIsValid(wkbGeometry, 'TRUE') IS FALSE THEN
	      RETURN FALSE;
      ELSIF TT_geoIntersects(wkbGeometry, lookupSchema, lookupTable, lookupCol) IS FALSE THEN
        RETURN FALSE;
      ELSE
        RETURN TRUE;
      END IF;
 	-- for inventories with data acquisition information, run notNull and isInt on photo year value 
    ELSIF TT_notNull(photoYear) IS FALSE AND TT_notNull(data_yr) IS FALSE THEN
      IF TT_geoIsValid(wkbGeometry, 'TRUE') IS FALSE THEN
	      RETURN FALSE;
      ELSIF TT_geoIntersects(wkbGeometry, lookupSchema, lookupTable, lookupCol) IS FALSE THEN
        RETURN FALSE;
      ELSE
        RETURN TRUE;
	  END IF;
    ELSIF TT_notNull(photoYear) IS FALSE AND data_yr != '0' THEN
	  IF TT_isInt(data_yr) IS FALSE THEN
        RETURN FALSE;
      ELSIF TT_isBetween(data_yr, lowerBound, upperBound) IS FALSE THEN
        RETURN FALSE;
      ELSE
        RETURN TRUE;
	  END IF;
	-- for inventories with photoyear information, run notNull, isInt and isBetween on photo year value
    ELSE
      IF TT_notNull(photoYear) IS FALSE THEN
        RETURN FALSE;
      ELSIF TT_isInt(photoYear) IS FALSE THEN
        RETURN FALSE;
      ELSIF TT_isBetween(photoYear, lowerBound, upperBound) IS FALSE THEN
        RETURN FALSE;
      ELSE
        RETURN TRUE;
      END IF;
    END IF;
  END;
$$ LANGUAGE plpgsql STABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pc02_hasCountOfNotNull
--
-- l1sp text, l2sp text, l3sp text,
-- l4sp text, l5sp text, l6sp text, l7sp text,
-- l8nfl text, l9nfl text, l10nfl text, l11nfl text,
-- l12nfl text, l13nfl text, l14nfl text, l15lake text,
-- lookupSchema text,
-- lookupTable text,
-- lookupCol text,
-- count text,
-- exact text
--
-- hasCountOfNotNull using pc02 custom countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_pc02_hasCountOfNotNull(text, text, text, text, text, text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_pc02_hasCountOfNotNull(
  l1sp text, l2sp text, l3sp text,
  l4sp text, l5sp text, l6sp text, l7sp text,
  l8nfl text, l9nfl text, l10nfl text, l11nfl text,
  l12nfl text, l13nfl text, l14nfl text, l15lake text,
  lookupSchema text,
  lookupTable text,
  lookupCol text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_pc02_countOfNotNull(l1sp, l2sp, l3sp, l4sp, l5sp, l6sp, l7sp, l8nfl, l9nfl, l10nfl, l11nfl, l12nfl, l13nfl, l14nfl, l15lake, lookupSchema, lookupTable, lookupCol, '15');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_bc_height
--
-- proj_height_1 - species 1 height
-- proj_height_2 - species 2 height
-- species_pct_1 - species 1 percent
-- species_pct_2 - species 2 percent
--
-- Converts any null percent values to zero.
-- If one of the height values is null, just return the other height value. If both are null return null.
-- If both percent values are zero, return the standard mean of the heights.
--
-- Calculates the weighted average height using the formula:
-- ((proj_height_1 * (species_pct_1/100)) / ((species_pct_1 + species_pct_2)/100)) + ((proj_height_2 * (species_pct_2/100)) / ((species_pct_1 + species_pct_2)/100))
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_bc_height(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_bc_height(
  proj_height_1 text,
  proj_height_2 text,
  species_pct_1 text,
  species_pct_2 text
)
RETURNS double precision AS $$
  DECLARE
    _proj_height_1 double precision := proj_height_1::double precision;
    _proj_height_2 double precision := proj_height_2::double precision;
    _species_pct_1 double precision := species_pct_1::double precision;
    _species_pct_2 double precision := species_pct_2::double precision;
  BEGIN
    -- If any percent inputs are null, set them to 0. This ensures the averaging still works and the null percent attribute will not be considered in the calculation.
    IF species_pct_1 IS NULL THEN
      _species_pct_1 = 0;
    END IF;
    IF species_pct_2 IS NULL THEN
      _species_pct_2 = 0;
    END IF;
  
    -- If one of the height values is null, just return the other height value. If both are null return null.
	  IF proj_height_1 IS NULL AND proj_height_2 IS NULL THEN
      RETURN NULL;
    END IF;
    IF proj_height_1 IS NULL THEN
      RETURN round(_proj_height_2::numeric, 1);
    END IF;
    IF proj_height_2 IS NULL THEN
      RETURN round(_proj_height_1::numeric, 1);
    END IF;
  
    -- If both percent values are zero, return the mean of the heights.
    IF _species_pct_1 = 0 AND _species_pct_2 = 0 THEN
      RETURN round(((_proj_height_1 + _proj_height_2) / 2)::numeric, 1);
    END IF;
  
    RETURN round((((_proj_height_1 * (_species_pct_1/100)) / ((_species_pct_1 + _species_pct_2)/100)) + ((_proj_height_2 * (_species_pct_2/100)) / ((_species_pct_1 + _species_pct_2)/100)))::numeric, 1);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nb_hasCountOfNotNull
--
-- layer1_sp
-- layer2_sp
-- wc
-- slu
-- water_code
-- maxRankToConsider
--
-- hasCountOfNotNull using nb custom countOfNotNull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nb_hasCountOfNotNull(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_nb_hasCountOfNotNull(
  layer1_sp text,
  layer2_sp text,
  wc text,
  slu text,
  water_code text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
    _count int;
    _exact boolean;
    _counted_nulls int;
  BEGIN
    _count = count::int;
    _exact = exact::boolean;

    -- process
    _counted_nulls = TT_nb_countOfNotNull(layer1_sp, layer2_sp, wc, slu, water_code, '3');

    IF _exact THEN
      RETURN _counted_nulls = _count;
    ELSE
      RETURN _counted_nulls >= _count;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nt_fvi01_species_per_range_validation
--
-- inventory_id
-- species_per
--
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nt_fvi01_species_per_range_validation(text, text);
CREATE OR REPLACE FUNCTION TT_nt_fvi01_species_per_range_validation(
  inventory_id text,
  species_per text
)
RETURNS BOOLEAN AS $$
  BEGIN
    IF inventory_id IN ('NT01', 'NT03') THEN
	  RETURN tt_isBetween(species_per,1::TEXT,10::TEXT);
	ELSE
	  RETURN tt_isBetween(species_per,1::TEXT,100::TEXT);
	END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- ROW_TRANSLATION_RULE Function Definitions...
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- TT_HasNFLInfo(text, text, text)
--
-- inventory_id
-- filter_attributes text - string list of nfl attributes to filter by ('non_for_veg', 'non_for_anth', 'nat_non_veg')
-- source_vals text - string list of the source values needed to run the filtering helper functions
--
-- Only called in ROW_TRANSLATION_RULE.
-- For the requested inventory_id, runs the helper functions for all requested nfl attributes. If all helper functions for at least
-- one of the provided attributes return TRUE, the function returns TRUE.
-- This filters the source data so it only includes rows being translated for a given attribute. Needed in cases like BC and SK
-- where translations are run for individual nfl attributes in turn. Without this we end up with duplicate cas_id-layer combinations
-- in CASFRI.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_HasNFLInfo(text, text, text);
CREATE OR REPLACE FUNCTION TT_HasNFLInfo(
  inventory_id text,
  filter_attributes text,
  source_vals text
)
RETURNS boolean AS $$
  DECLARE
    _fiter_attributes text[];
    _source_vals text[];
    _nat_non_veg_boolean boolean := FALSE;
    _non_for_veg_boolean boolean := FALSE;
    _non_for_anth_boolean boolean := FALSE;
    _inventory_standard_cd text; -- BC - needs to be 1st in string list
    _land_cover_class_cd_1 text; -- BC - needs to be 2nd in string list
    _bclcs_level_4 text; -- BC - needs to be 3rd in string list
    _non_productive_descriptor_cd text; -- BC - needs to be 4th in string list
    _non_veg_cover_type_1 text; -- BC - needs to be 5th in string list
    _shrub_herb text; -- SK - needs to be 1st in string list
    _nvsl_aquatic_class text; -- SK - nvsl needs to be 2nd in string list, aquatic_class needs to be 3rd
    _luc_transp_class text; -- SK - luc needs to be 4th in string list, transp_class needs to be 5th
    _yt03_nat_non_veg text; -- YT03 - needs to be 1st in string list
    _yt03_non_for_anth text; -- YT03 - needs to be 2nd in string list
    _yt03_non_for_veg text; -- YT03 - needs to be 3rd in string list
    _class1 text; -- PE02 - needs to be 1st in string list
    _landuse text; -- PE02 - needs to be 2nd in string list
    _subuse text; -- PE02 - needs to be 3rd in string list
    _pe02_non_for_veg text; -- PE02 - needs to be 3rd string list
    _nfl_code_list text;
  BEGIN
    -- parse string lists
    _fiter_attributes = TT_ParseStringList(filter_attributes, TRUE);
    _source_vals = TT_ParseStringList(source_vals, TRUE);
      
    -- run validations for the requestesd inventory and attributes
    -- If all validations for a given attribute return TRUE, then set the declared
    -- variable to true. Once run if any of the decared variables are TRUE, return
    -- TRUE from the function.
  
    -----------
    -- BC
    -----------
    -- assign source values to variables depending on the inventory id
    IF inventory_id IN('BC08','BC10', 'BC11', 'BC12','BC13','BC14','BC15','BC16') THEN
      _inventory_standard_cd = _source_vals[1];
      _land_cover_class_cd_1 = _source_vals[2];
      _bclcs_level_4 = _source_vals[3];
      _non_productive_descriptor_cd = _source_vals[4];
      _non_veg_cover_type_1 = _source_vals[5];
  
      -- run validations
      IF 'nat_non_veg' = ANY (_fiter_attributes) THEN
        IF TT_vri01_nat_non_veg_validation(_inventory_standard_cd, _land_cover_class_cd_1, _bclcs_level_4, _non_productive_descriptor_cd, _non_veg_cover_type_1)
        THEN
          _nat_non_veg_boolean = TRUE;
        END IF;
      END IF;
    
      IF 'non_for_anth' = ANY (_fiter_attributes) THEN
        IF TT_vri01_non_for_anth_validation(_inventory_standard_cd, _land_cover_class_cd_1, _non_productive_descriptor_cd, _non_veg_cover_type_1)
        THEN
          _non_for_anth_boolean = TRUE;
        END IF;
      END IF;
    
      IF 'non_for_veg' = ANY (_fiter_attributes) THEN
        IF TT_vri01_non_for_veg_validation(_inventory_standard_cd, _land_cover_class_cd_1, _bclcs_level_4, _non_productive_descriptor_cd)
        THEN
          _non_for_veg_boolean = TRUE;
        END IF;
      END IF;
    END IF;
  
    -----------
    -- SK
    -----------
    -- assign source values to variables depending on the inventory id
    IF inventory_id IN('SK02','SK03','SK04','SK05','SK06') THEN
      _shrub_herb = _source_vals[1];
      _nvsl_aquatic_class = CONCAT(trim(_source_vals[2]), trim(_source_vals[3])); -- concatenate nvsl and aquatic class for use in matchList
      _luc_transp_class = CONCAT(trim(_source_vals[4]), trim(_source_vals[5]), trim(_source_vals[3])); -- concatenate luc, transp_class and aquatic class for use in matchList
    END IF;

    -- run validations
    IF inventory_id IN('SK02', 'SK03', 'SK04', 'SK05', 'SK06') THEN
      IF 'nat_non_veg' = ANY (_fiter_attributes) THEN
        IF TT_matchList(_nvsl_aquatic_class,'{''UK'', ''CB'', ''RK'', ''SA'', ''MS'', ''GR'', ''SB'', ''WA'', ''LA'', ''RI'', ''FL'', ''SF'', ''FP'', ''ST'', ''WASF'', ''WALA'', ''UKLA'', ''WARI'', ''WAFL'', ''WAFP'', ''WAST'',''L'', ''R''}')
        THEN
          _nat_non_veg_boolean = TRUE;
        END IF;
      END IF;
    
      IF 'non_for_anth' = ANY (_fiter_attributes) THEN
        IF TT_matchList(_luc_transp_class,'{''ALA'', ''POP'', ''REC'', ''PEX'', ''GPI'', ''BPI'', ''MIS'', ''ASA'', ''NSA'', ''OIS'', ''OUS'', ''AFS'', ''CEM'', ''WEH'', ''TOW'', ''RWC'', ''RRC'', ''TLC'', ''PLC'', ''MPC'',''PL'',''RD'',''TL'',''vegu'', ''bugp'', ''towu'', ''cmty'', ''dmgu'', ''gsof'', ''rwgu'', ''muou'', ''mg'', ''peatc'', ''lmby'', ''sdgu'', ''bupo'', ''ftow'', ''FP'', ''WADI''}')
        THEN
          _non_for_anth_boolean = TRUE;
        END IF;
      END IF;
    
      IF 'non_for_veg' = ANY (_fiter_attributes) THEN
        IF TT_matchList(_shrub_herb,'{''Ts'',''Al'',''Bh'',''Ma'',''Sa'',''Pc'',''Cr'',''Wi'',''Ls'',''Ro'',''Bi'',''Bu'',''Dw'',''Ra'',''Cu'',''Sn'',''Bb'',''Ci'',''Bl'',''La'',''Le'',''Be'',''Lc'',''Lb'',''He'',''Fe'',''Gr'',''Mo'',''Li'',''Av'',''Se''}')
        THEN
          _non_for_veg_boolean = TRUE;
        END IF;
      END IF;
    END IF;
  
	---------
	-- YT03
	---------
	-- assign source values to variables depending on the inventory id
    IF inventory_id IN('YT03') THEN
      _yt03_nat_non_veg = _source_vals[1];
      _yt03_non_for_anth = _source_vals[2];
      _yt03_non_for_veg = _source_vals[3];
    END IF;
	
	-- run validations
	IF 'nat_non_veg' = ANY (_fiter_attributes) THEN
      IF TT_notEmpty(_yt03_nat_non_veg) THEN
        _nat_non_veg_boolean = TRUE;
      END IF;
    END IF;
	
	IF 'non_for_anth' = ANY (_fiter_attributes) THEN
      IF TT_notEmpty(_yt03_non_for_anth) THEN
        _non_for_anth_boolean = TRUE;
      END IF;
    END IF;
	
	IF 'non_for_veg' = ANY (_fiter_attributes) THEN
      IF TT_notEmpty(_yt03_non_for_veg) THEN
        _non_for_veg_boolean = TRUE;
      END IF;
    END IF;

   	---------
   	-- PE02
   	---------
   	-- assign source values to variables depending on the inventory id
       IF inventory_id IN('PE02', 'PE03','PE04') THEN
         _class1 = _source_vals[1];
         _landuse = _source_vals[2];
         _subuse = _source_vals[3];
         _pe02_non_for_veg = _source_vals[4];
       END IF;

   	-- run validations
    IF 'all_nfl' = ANY (_fiter_attributes) THEN
    	_nfl_code_list := '{''BAR'',''BSB'',''SDW'',''WWW'',''WAT'',''SO'',''SD'',''WW'',''FL'',''AGR'',''COM'',''RES'',''IND'',''NON'',''REC'',''TRN'',''URB'',''INT'',''CL'',''WF'',''PL'',''RN'',''RD'',''RR'',''AG'',''EP'',''UR'',''BOW'',''BO''}';
       IF (TT_matchList(_class1, _nfl_code_list) OR TT_matchList(_subuse, _nfl_code_list) OR TT_matchList(_landuse, _nfl_code_list)) THEN
         _non_for_veg_boolean = TRUE;
       END IF;
     END IF;
	
	-------------------------------------------------------------
    -- return TRUE if any of the nfl attribute validations passed
    IF _nat_non_veg_boolean OR _non_for_veg_boolean OR _non_for_anth_boolean THEN
      RETURN TRUE;
    ELSE
      RETURN FALSE;
    END IF;
  
  END;
$$ LANGUAGE plpgsql;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_row_translation_rule_nt_lyr
-------------------------------------------------------------------------------
-- typeclas_nonveg
-- typeclas_anth
-- typeclas
-- species_1
-- species_2
-- species_3
-- species_4
--
-- If typeclas is in not an nfl type, and species 1, 2, 3 or 4 is not empty, then the
-- row is a LYR row.
-- Same for layer 2 but using mintypeclas, min sp1, 2, 3, 4.
-- Note typeclas can be empty string or NULL and still have species info.
-- We just want to avoid adding rows where typeclas is an NFL value and species
-- are present.
CREATE OR REPLACE FUNCTION TT_row_translation_rule_nt_lyr(
  typeclas_nonveg text,
  typeclas_anth text,
  typeclas text,
  sp1 text,
  sp2 text,
  sp3 text,
  sp4 text
)
RETURNS boolean AS $$
  DECLARE
    nfl_string_list text[];
  BEGIN
    -- set up nfl_string_list
    nfl_string_list = ARRAY['BE','BR','BU','CB','ES','LA','LL','LS','MO','MU','PO','RE','RI','RO','RS','RT','SW','AP','BP','EL','GP','TS','RD','SH','SU','PM','BL','BM','BY','HE','HF','HG','SL','ST'];
	
	-- catch any NFL rows and return FALSE
    IF typeclas = ANY(nfl_string_list) OR typeclas_nonveg = ANY(nfl_string_list) OR typeclas_anth = ANY(nfl_string_list) THEN
      RETURN FALSE;
    END IF;
	
	-- Check for any species
	IF (TT_notEmpty(sp1) OR TT_notEmpty(sp2) OR TT_notEmpty(sp3) OR TT_notEmpty(sp4)) THEN
      RETURN TRUE;
    ELSE
      RETURN FALSE;
    END IF;
  END;
$$ LANGUAGE plpgsql;


-------------------------------------------------------------------------------
-- TT_yvi03_hasNFL
-------------------------------------------------------------------------------
-- landtype
-- covertype
-- cover_class
--
-- If landtype is an NFL type, check the covertype contains an NFL type as well, if so return true
-- if landtype is vegetated, check if it's cover is one of Shrub types or rock, if so return true
-- else FALSE
CREATE OR REPLACE FUNCTION TT_yvi03_hasNFL(
  landtype text,
  covertype text,
  cover_class text,
  landpos text
)
RETURNS boolean AS $$
  DECLARE
  	urban text[];
    shrub text[];
    nonveg_land text[];
    water text[];
    non_veg text[];
  BEGIN
  	urban = ARRAY['Road Surface', 'Gravel Pit', 'Tailings'];
    shrub = ARRAY['Tall Shrub', 'Low Shrub', 'Tall Shrub, Open', 'Tall Shrub, Closed', 'Rock'];
    nonveg_land = ARRAY['Non-Vegetated, Water', 'Non-Vegetated, Snow/Ice', 'Non-Vegetated, Exposed Land'];
    water = ARRAY['River', 'Lake'];
    non_veg = ARRAY['River Sediments', 'Exposed Soil', 'Burned Area', 'Rock & Rubble'];
    IF landtype = 'Non-Vegetated, Urban/Industrial' AND covertype = ANY(urban) THEN
      RETURN TRUE;
    ELSIF landtype = 'Vegetated, Non-Forested' AND cover_class = ANY(shrub) THEN
      RETURN TRUE;
    ELSIF landpos = 'Alpine' AND landtype = ANY(nonveg_land)  THEN
      RETURN TRUE;
    ELSIF landtype = ANY(nonveg_land) AND covertype = ANY(water) THEN
      RETURN TRUE;
    ELSIF landtype = ANY(nonveg_land) AND covertype = ANY(non_veg) THEN
      RETURN TRUE;
    ELSE
      --- nfl feature not found
      RETURN FALSE;
    END IF;
  END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Begin Translation Function Definitions...
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_vri01_origin_translation
--
-- get projected year as first 4 characters of proj_date
-- return projected year minus projected age
-- Validation should ensure projected year substring is an integer using TT_vri01_origin_validation,
-- and that projected age is not zero using TT_IsNotEqualToInt()
--
-- e.g. TT_vri01_origin_translation(proj_date, proj_age)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_vri01_origin_translation(text, text);
CREATE OR REPLACE FUNCTION TT_vri01_origin_translation(
  proj_date text,
  proj_age text
)
RETURNS integer AS $$
  BEGIN
    RETURN substring(proj_date from 1 for 4)::int - proj_age::int;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_vri01_site_index_translation
--
-- If site_index not null, return it.
-- Otherwise return site_index_est.
-- If both are null, TT_vri01_site_index_validation should return error.
--
-- e.g. TT_vri01_site_index_translation(site_index, site_index_est)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_vri01_site_index_translation(text, text);
CREATE OR REPLACE FUNCTION TT_vri01_site_index_translation(
  site_index text,
  site_index_est text
)
RETURNS double precision AS $$
  BEGIN
    IF TT_NotEmpty(site_index) THEN
      RETURN site_index::double precision;
    ELSIF NOT TT_NotEmpty(site_index) AND TT_NotEmpty(site_index_est) THEN
      RETURN site_index_est::double precision;
	  END IF;
		RETURN NULL;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_vri01_non_for_veg_translation(text, text, text, text)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_vri01_non_for_veg_translation(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_vri01_non_for_veg_translation(
  inventory_standard_cd text,
  land_cover_class_cd_1 text,
  bclcs_level_4 text,
  non_productive_descriptor_cd text
)
RETURNS text AS $$
  DECLARE
    result text = NULL;
	  src_cover_types text[] = '{BL, BM, BY, HE, HF, HG, SL, ST}';
	  tgt_cover_types text[] = '{BRYOID, BRYOID, BRYOID, HERBS, FORBS, GRAMINOIDS, LOW_SHRUB, TALL_SHRUB}';
    src_non_prod_desc text[] = '{AF, M, NPBR, OR}';
  BEGIN
    -- run if statements
    IF inventory_standard_cd IN ('V', 'I') AND land_cover_class_cd_1 IS NOT NULL THEN
      IF land_cover_class_cd_1 = ANY(src_cover_types) THEN
        result = TT_MapText(land_cover_class_cd_1, src_cover_types::text, tgt_cover_types::text);
      END IF;
    END IF;
  
    IF inventory_standard_cd IN ('V', 'I') AND bclcs_level_4 IS NOT NULL AND result IS NULL THEN
      IF bclcs_level_4  = ANY(src_cover_types) THEN
        result = TT_MapText(bclcs_level_4, src_cover_types::text, tgt_cover_types::text);
      END IF;
    END IF;
  
    IF inventory_standard_cd='F' AND non_productive_descriptor_cd IS NOT NULL THEN
      IF non_productive_descriptor_cd = ANY(src_non_prod_desc) THEN
        result = TT_MapText(non_productive_descriptor_cd, src_non_prod_desc::Text, '{''ALPINE_FOREST'', ''GRAMINOIDS'', ''LOW_SHRUB'', ''GRAMINOIDS''}');
      END IF;
    END IF;

    IF inventory_standard_cd='F' AND bclcs_level_4 IS NOT NULL AND result IS NULL THEN
      IF bclcs_level_4  = ANY(src_cover_types) THEN
        result = TT_MapText(bclcs_level_4, src_cover_types::text, tgt_cover_types::text);
      END IF;
    END IF;
    RETURN result;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_vri01_nat_non_veg_translation
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_vri01_nat_non_veg_translation(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_vri01_nat_non_veg_translation(
  inventory_standard_cd text,
  land_cover_class_cd_1 text,
  bclcs_level_4 text,
  non_productive_descriptor_cd text,
  non_veg_cover_type_1 text
)
RETURNS text AS $$
  DECLARE
    result text = NULL;
    src_cover_types text[] = '{BE, BI, BR, BU, CB, ES, GL, LA, LB, LL, LS, MN, MU, OC, PN, RE, RI, RM, RS, TA}';
    tgt_cover_types text[] = '{BEACH, ROCK_RUBBLE, ROCK_RUBBLE, EXPOSED_LAND, EXPOSED_LAND, EXPOSED_LAND, SNOW_ICE, LAKE, ROCK_RUBBLE, EXPOSED_LAND, WATER_SEDIMENT, EXPOSED_LAND, WATER_SEDIMENT, OCEAN, SNOW_ICE, LAKE, RIVER, EXPOSED_LAND, WATER_SEDIMENT, ROCK_RUBBLE}';
    src_non_productive_descriptor_cd text[] = '{A, CL, G, ICE, L, MUD, R, RIV, S, SAND, TIDE}';
    src_bclcs_level_4 text[] = '{EL, RO, SI}';
  BEGIN
    -- run if statements
    IF inventory_standard_cd IN ('V', 'I') AND non_veg_cover_type_1 IS NOT NULL THEN
      IF non_veg_cover_type_1 = ANY(src_cover_types || ARRAY['DW']) THEN
        result = TT_MapText(non_veg_cover_type_1, (src_cover_types || ARRAY['DW'])::text, (tgt_cover_types || ARRAY['EXPOSED_LAND'])::text);
      END IF;
    END IF;

    IF inventory_standard_cd IN ('V', 'I') AND land_cover_class_cd_1 IS NOT NULL AND result IS NULL THEN
      IF land_cover_class_cd_1 = ANY(src_cover_types || ARRAY['EL', 'RO', 'SI']) THEN
        result = TT_MapText(land_cover_class_cd_1, (src_cover_types || ARRAY['EL', 'RO', 'SI'])::text, (tgt_cover_types || ARRAY['EXPOSED_LAND', 'ROCK_RUBBLE', 'SNOW_ICE'])::text);
      END IF;
    END IF;

    IF inventory_standard_cd IN ('V', 'I') AND bclcs_level_4 IS NOT NULL AND result IS NULL THEN
      IF bclcs_level_4 = ANY(src_bclcs_level_4) THEN
        result = TT_MapText(bclcs_level_4, src_bclcs_level_4::text, '{''EXPOSED_LAND'', ''ROCK_RUBBLE'', ''SNOW_ICE''}');
      END IF;
    END IF;
  
    IF inventory_standard_cd='F' AND non_productive_descriptor_cd IS NOT NULL THEN
      IF non_productive_descriptor_cd = ANY(src_non_productive_descriptor_cd) THEN
        result = TT_MapText(non_productive_descriptor_cd, src_non_productive_descriptor_cd::text, '{''ALPINE'', ''EXPOSED_LAND'', ''WATER_SEDIMENT'', ''SNOW_ICE'', ''LAKE'', ''EXPOSED_LAND'', ''ROCK_RUBBLE'', ''RIVER'', ''SLIDE'', ''SAND'', ''TIDAL_FLATS''}');
      END IF;
    END IF;

    IF inventory_standard_cd='F' AND bclcs_level_4 IS NOT NULL AND result IS NULL THEN
      IF bclcs_level_4 = ANY(src_bclcs_level_4) THEN
        result = TT_MapText(bclcs_level_4, src_bclcs_level_4::text, '{''EXPOSED_LAND'', ''ROCK_RUBBLE'', ''SNOW_ICE''}');
      END IF;
    END IF;
    RETURN result;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_vri01_non_for_anth_translation
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_vri01_non_for_anth_translation(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_vri01_non_for_anth_translation(
  inventory_standard_cd text,
  land_cover_class_cd_1 text,
  non_productive_descriptor_cd text,
  non_veg_cover_type_1 text
)
RETURNS text AS $$
  DECLARE
    result text = NULL;
    src_cover_types text[] = '{AP, GP, MI, MZ, OT, RN, RZ, TZ, UR}';
    tgt_cover_types text[] = '{FACILITY_INFRASTRUCTURE, INDUSTRIAL, INDUSTRIAL, INDUSTRIAL, OTHER, FACILITY_INFRASTRUCTURE, FACILITY_INFRASTRUCTURE, INDUSTRIAL, FACILITY_INFRASTRUCTURE}';
    src_non_prod_desc text[] = '{C, GR, P, U}';
  BEGIN
    -- run if statements
    IF inventory_standard_cd IN ('V', 'I') AND non_veg_cover_type_1 IS NOT NULL THEN
      IF non_veg_cover_type_1 = ANY(src_cover_types) THEN
        result = TT_MapText(non_veg_cover_type_1, src_cover_types::text, tgt_cover_types::text);
      END IF;
    END IF;
      
    IF inventory_standard_cd IN ('V', 'I') AND land_cover_class_cd_1 IS NOT NULL AND result IS NULL THEN
      IF land_cover_class_cd_1 = ANY(src_cover_types) THEN
        result = TT_MapText(land_cover_class_cd_1, src_cover_types::text, tgt_cover_types::text);
      END IF;
    END IF;
      
    IF inventory_standard_cd = 'F' AND non_productive_descriptor_cd IS NOT NULL THEN
      IF non_productive_descriptor_cd = ANY(src_non_prod_desc) THEN
        result = TT_MapText(non_productive_descriptor_cd, src_non_prod_desc::text, '{''CULTIVATED'', ''INDUSTRIAL'', ''CULTIVATED'', ''FACILITY_INFRASTRUCTURE''}');
      END IF;
    END IF;
  
    RETURN result;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_avi01_non_for_veg_translation
--
-- nfl_code text
-- nfl_height text
--
-- Use mapText to translate nfl values. If value is open shrub or closed shrub,
-- assign to tall shrub if height is >2m, and low shrub if <2m.
--
-- e.g. TT_avi01_non_for_veg_translation(nfl_code, nfl_height)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_avi01_non_for_veg_translation(text, text);
CREATE OR REPLACE FUNCTION TT_avi01_non_for_veg_translation(
  nfl_code text,
  nfl_height text
)
RETURNS text AS $$
  DECLARE
    _nfl_height double precision;
    _nfl_code text;
  BEGIN
    PERFORM TT_ValidateParams('TT_avi01_non_for_veg_translation',
                              ARRAY['nfl_code', nfl_code, 'text',
                                    'nfl_height', nfl_height, 'numeric']);
    _nfl_height = nfl_height::double precision;
    _nfl_code = UPPER(nfl_code);
	
    IF _nfl_code IN('HF','HG','SC','SO','BR') THEN
      IF _nfl_code IN('SC','SO') THEN
        IF _nfl_height < 2 THEN
          RETURN 'LOW_SHRUB';
        ELSE
          RETURN 'TALL_SHRUB';
        END IF;
      ELSE
        RETURN TT_mapText(_nfl_code, '{''HF'',''HG'',''BR''}', '{''FORBS'',''GRAMINOIDS'',''BRYOID''}');
      END IF;
    END IF;

    RETURN NULL;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nbi01_stand_structure_translation
--
-- If src_filename = 'Forest' and l2vs=0, then stand_structure=“SINGLE_LAYERED”
-- If src_filename = 'Forest' and (l1vs>0 and l2vs>0) then stand_structure=“MULTI_LAYERED”
-- If src_filename = 'Forest' and (l1vs>1 and l2vs>1) then stand_structure=“COMPLEX”
--
-- For NB01 src_filename should match 'Forest'.
-- For NB02 src_filename should match 'geonb_forest-foret'.
--
-- e.g. TT_nbi01_stand_structure_translation(src_filename, l1vs, l2vs)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nbi01_stand_structure_translation(text, text, text);
CREATE OR REPLACE FUNCTION TT_nbi01_stand_structure_translation(
  src_filename text,
  l1vs text,
  l2vs text
)
RETURNS text AS $$
  DECLARE
    _l1vs int;
    _l2vs int;
  BEGIN
    PERFORM TT_ValidateParams('TT_nbi01_stand_structure_translation',
                              ARRAY['src_filename', src_filename, 'text',
                                    'l1vs', l1vs, 'int',
                                    'l2vs', l2vs, 'int']);
    _l1vs = l1vs::int;
    _l2vs = l2vs::int;
		
    IF src_filename IN ('Forest', 'geonb_forest-foret') THEN
      IF _l2vs = 0 THEN
      RETURN 'SINGLE_LAYERED';
      ELSIF _l1vs > 1 AND _l2vs > 1 THEN
        RETURN 'COMPLEX';
      ELSIF _l1vs > 0 AND _l2vs > 0 THEN
        RETURN 'MULTI_LAYERED';
      END IF;
    END IF;				
    RETURN NULL;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nb_nbi01_wetland_translation
--
-- Assign 4 letter wetland character code, then return the requested character (1-4)
--
-- e.g. TT_nb_nbi01_wetland_translation(wt, vt, im, '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nb_nbi01_wetland_translation(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_nb_nbi01_wetland_translation(
  wc text,
  vt text,
  im text,
  ret_char_pos text
)
RETURNS text AS $$
  DECLARE
	wetland_code text;
    result text;
  BEGIN
    PERFORM TT_ValidateParams('TT_nb_nbi01_wetland_translation',
                              ARRAY['ret_char_pos', ret_char_pos, 'int']);
    wetland_code = TT_nb_nbi01_wetland_code(wc, vt, im);

    RETURN TT_wetland_code_translation(wetland_code, ret_char_pos);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nbi01_nb01_productive_for_translation(text, text, text, text, text)
--
-- If no valid crown closure value, or no valid height value. Assign PP.
-- Or if forest stand type is 0, and l1 or l2 trt is neither CC or empty string. Assign PP.
-- Otherwise assign PF (productive forest).
--
-- e.g. TT_nbi01_nb01_productive_for_translation(l1cc, l1ht, l1trt, l2trt, fst)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nbi01_nb01_productive_for_translation(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_nbi01_nb01_productive_for_translation(
  l1cc text,
  l1ht text,
  l1trt text,
  l2trt text,
  fst text
)
RETURNS text AS $$
  BEGIN
    IF NOT TT_NotNull(l1cc) THEN
      RETURN 'POTENTIALLY_PRODUCTIVE';
    ELSIF NOT TT_MatchList(l1cc, '{''1'', ''2'', ''3'', ''4'', ''5''}') THEN
      RETURN 'POTENTIALLY_PRODUCTIVE';
    ELSEIF NOT TT_NotNull(l1ht) THEN
      RETURN 'POTENTIALLY_PRODUCTIVE';
    ELSIF NOT TT_IsGreaterThan(l1ht, '0.1') THEN
      RETURN 'POTENTIALLY_PRODUCTIVE';
    ELSIF NOT TT_IsLessThan(l1ht, '100') THEN
      RETURN 'POTENTIALLY_PRODUCTIVE';
    ELSIF fst = '0'::text AND l1trt != 'CC' AND btrim(l1trt, ' ') != '' THEN
      RETURN 'POTENTIALLY_PRODUCTIVE';
    ELSIF fst = '0'::text AND l2trt != 'CC' AND btrim(l2trt, ' ') != '' THEN
      RETURN 'POTENTIALLY_PRODUCTIVE';
    END IF;
    RETURN 'PRODUCTIVE_FOREST';
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nbi01_nb02_productive_for_translation
--
--  2 options for PRODUCTIVE_FOR, replicating NB02 using trt, l1cc, l1ht, l1s1.
--  Or using fst.
--  Here I`m using the simpler fst method until issue #181
--
-- If no valid crown closure value, or no valid height value. Assign PP.
-- Or if forest stand type is 0, and l1 or l2 trt is neither CC or empty string. Assign PP.
-- Otherwise assign PF (productive forest).
--
-- e.g. TT_nbi01_nb02_productive_for_translation(fst)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nbi01_nb02_productive_for_translation(text);
CREATE OR REPLACE FUNCTION TT_nbi01_nb02_productive_for_translation(
  fst text
)
RETURNS text AS $$
  DECLARE
    _fst int;
  BEGIN
    _fst = fst::int;
	
    IF _fst IN (1, 2) THEN
      RETURN 'PRODUCTIVE_FOREST';
    ELSIF _fst = 3 THEN
      RETURN 'POTENTIALLY_PRODUCTIVE';
    END IF;
    RETURN NULL;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_vri01_dist_yr_translation
--
--  val
-- cutoff_val
--
-- BC disturbance codes are always a single character for the type, concatenated
-- to two digits for the year (e.g. B00). Digits needs to extracted and converted to 4-digit
-- integer for disturbance year.
--
-- Takes the disturbance code, substrings to get the last two values,
-- then concats with either 19 or 20 depending on cutoff.
-- If val <= cutoff_val, concat with 20, else concat with 19.
-- e.g. with cutoff_val of 17 B17 would become 2017, B18 would become
-- 1918.
--
-- e.g. TT_vri01_dist_yr_translation(val, cutoff_val)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_vri01_dist_yr_translation(text, text);
CREATE OR REPLACE FUNCTION TT_vri01_dist_yr_translation(
  val text,
  cutoff_val text
)
RETURNS int AS $$
  DECLARE
    _val_text text;
    _val_int int;
    _cutoff_val int;
  BEGIN
    PERFORM TT_ValidateParams('TT_vri01_dist_yr_translation',
                                ARRAY['cutoff_val', cutoff_val, 'int']);
    _cutoff_val = cutoff_val::int;
    _val_text = TT_SubstringText(val, '2'::text, '2'::text); -- get last two characters from string. This is the year. First character is the dist type.
    _val_int = _val_text::int;
  
    IF _val_int <= _cutoff_val THEN
      RETURN TT_Concat('{''20'', ' || _val_text || '}'::text, ''::text)::int;
    ELSE
      RETURN TT_Concat('{''19'', ' || _val_text || '}'::text, ''::text)::int;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_fim_species
--
-- sp_string text - source string of species and percentages
-- sp_number text - the species number being requested (i.e. SPECIES 1-10 in casfri)
--
-- This functions calls TT_fim_species_code() to extract the requested species-percent code,
-- then extracts the species code as the first two characters.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_fim_species(text, text);
CREATE OR REPLACE FUNCTION TT_fim_species(
  sp_string text,
  sp_number text
)
RETURNS text AS $$
  DECLARE
    code text;
    species text;
    _sp_number int;
  BEGIN
    PERFORM TT_ValidateParams('TT_fim_species',
                              ARRAY['sp_number', sp_number, 'int']);
    _sp_number = sp_number::int;
    code = TT_fim_species_code(sp_string, _sp_number); -- get the requested species code and percent
  
    IF TT_Length(code) > 1 THEN --
      species = (regexp_split_to_array (code, '\s+'))[1];
    ELSE
      RETURN FALSE;
    END IF;
    RETURN species;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_fim_species_count_validate
--
-- sp_string text - source string of species and percentages
--
-- This functions count the number of species present in sp_string.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_fim_species_count_validate(text, text);
CREATE OR REPLACE FUNCTION TT_fim_species_count_validate(
  sp_string text,
  sp_number text
)
RETURNS boolean AS $$
  DECLARE
    _sp_number int;
  BEGIN
    PERFORM TT_ValidateParams('TT_fim_species',
                              ARRAY['sp_number', sp_number, 'int']);
    _sp_number = sp_number::int;
    RETURN NOT TT_fim_species_code(sp_string, _sp_number) IS NULL;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
/*
SELECT TT_fim_species_count_validate('ab 10bb 3c 10 0', '1');
SELECT TT_fim_species_count_validate('ab 10bb 3c 10 0', '2');
SELECT TT_fim_species_count_validate('ab 10bb 3c 10 0', '3');
SELECT TT_fim_species_count_validate('ab 10bb 3c 10 0', '4');
*/
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_fim_species_percent_translation
--
-- sp_string text - source string of species and percentages
-- sp_number text - the species number being requested (i.e. SPECIES 1-10 in casfri)
--
-- This functions calls TT_fim_species_code() to extract the requested species-percent code,
-- then extracts the percentage.
-- Uses alpha numeric codes to lookup if the percent values need to be multiplied by 10.
-- Uses alpha numeric codes to return 100 when code has a zero value and a single species (ON01).
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_fim_species_percent_translation(text, text);
CREATE OR REPLACE FUNCTION TT_fim_species_percent_translation(
  sp_string text,
  sp_number text
)
RETURNS int AS $$
  DECLARE
    _code text;
    _sp_number int;
    _short_percent int;
  BEGIN
    PERFORM TT_ValidateParams('TT_fim_species_translation',
                              ARRAY['sp_number', sp_number, 'int']);
    _sp_number = sp_number::int;
    _code = TT_fim_species_code(sp_string, _sp_number);
    _short_percent = (regexp_split_to_array(_code, '\s+'))[2]::int;
    RETURN CASE WHEN (sp_string ~ '^[a-zA-Z]+\s*0{1,2}$') AND _short_percent = 0 THEN 100 -- cases 'x 0', 'xx 0' and 'x 00'
                WHEN _short_percent > 100 THEN _short_percent / 10 -- case when _short_percent > 100
                WHEN (sp_string ~ '[02-9][0-9]') THEN _short_percent -- case when two digit value other than 10 are found
                WHEN _short_percent = 10 THEN 10 -- case 10
                ELSE _short_percent * 10
           END;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
/*
SELECT TT_fim_species_percent_translation('a 40b 10 0', '1') -- 40
SELECT TT_fim_species_percent_translation('a 40b 10 0', '2') -- 10
SELECT TT_fim_species_percent_translation('a 40b 10 0', '3') -- NULL

SELECT TT_fim_species_percent_translation('a 4b 10 0', '1') -- 4
SELECT TT_fim_species_percent_translation('a 4b 10 0', '2') -- 10
SELECT TT_fim_species_percent_translation('a 4b 10 0', '3') -- NULL

SELECT TT_fim_species_percent_translation('a 4b 1 0', '1') -- 4
SELECT TT_fim_species_percent_translation('a 4b 1 0', '2') -- 10
SELECT TT_fim_species_percent_translation('a 4b 1 0', '3') -- NULL

SELECT TT_fim_species_percent_translation('SB 5B 2O 10', '1') -- 4
SELECT TT_fim_species_percent_translation('SB 5B 2O 10', '2') -- 20
SELECT TT_fim_species_percent_translation('SB 5B 2O 10', '3') -- 10

SELECT TT_fim_species_percent_translation('SB 500B 2O 10', '1') -- 50
SELECT TT_fim_species_percent_translation('SB 500B 9O 10', '2') -- 9
SELECT TT_fim_species_percent_translation('SB 500B 2O 10', '3') -- 10
*/
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yvi01_nat_non_veg_translation
--
-- type_lnd text
-- class_ text
-- landpos text
--
-- Assigns nat non veg casfri attributes based on source attribute from various columns.
-- landpos of A becomes AP
-- classes of 'R','L','RS','E','S','B','RR' become 'RIVER,'LAKE,'WATER_SEDIMENT','EXPOSED_LAND','SAND','EXPOSED_LAND','ROCK_RUBBLE'
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yvi01_nat_non_veg_translation(text, text, text);
CREATE OR REPLACE FUNCTION TT_yvi01_nat_non_veg_translation(
  type_lnd text,
  class_ text,
  landpos text
)
RETURNS text AS $$
  BEGIN
    IF type_lnd IN('NW', 'NS', 'NE') THEN
      IF landpos = 'A' THEN
        RETURN 'ALPINE';
      END IF;
    
      IF class_ IN('R','L','RS','E','S','B','RR') THEN
        RETURN TT_mapText(class_, '{''R'',''L'',''RS'',''E'',''S'',''B'',''RR''}', '{''RIVER'',''LAKE'',''WATER_SEDIMENT'',''EXPOSED_LAND'',''SAND'',''EXPOSED_LAND'',''ROCK_RUBBLE''}');
      END IF;
    END IF;
    
    RETURN NULL;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yvi03_nat_non_veg_translation
--
-- type_lnd text
-- class_ text
-- landpos text
-- covertype text
--
-- Assigns nat non veg casfri attributes based on source attribute from various columns.
-- landpos of Alipine becomes ALPINE
-- classes of 'River','Lake','River Sediments','Exposed Soil','Burned Area','Rock & Rubble' become 'RIVER,'LAKE,'WATER_SEDIMENT','EXPOSED_LAND','EXPOSED_LAND','ROCK_RUBBLE'
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yvi03_nat_non_veg_translation(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yvi03_nat_non_veg_translation(
  type_lnd text,
  class_ text,
  landpos text,
  covertype text
)
RETURNS text AS $$
  BEGIN
    IF type_lnd IN('Non-Vegetated, Water', 'Non-Vegetated, Snow/Ice', 'Non-Vegetated, Exposed Land') THEN
      IF landpos = 'Alpine' THEN
        RETURN 'ALPINE';
      END IF;

      IF class_ IN('River','Lake') THEN
        RETURN TT_mapText(class_, '{''River'',''Lake''}','{''RIVER'',''LAKE''}');
      END IF;

      IF covertype IN('River Sediments','Exposed Soil','Burned Area','Rock & Rubble') THEN
        RETURN TT_mapText(class_, '{''RS'',''E'',''B'',''RR''}', '{''WATER_SEDIMENT'',''EXPOSED_LAND'',''EXPOSED_LAND'',''ROCK_RUBBLE''}');
      END IF;
    END IF;

    RETURN NULL;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;

-------------------------------------------------------------------------------
-- TT_yvi01_non_for_veg_translation
--
-- cl_mod text
-- class_ text
--
-- Assigns non for veg casfri attributes based on source attribute from various columns.
-- assumes type_lnd is VN and class is in 'S','H','C','M'
-- then translates cl_mod 'TS','TSo','TSc','LS' to 'TALL_SHRUB','TALL_SHRUB','TALL_SHRUB','LOW_SHRUB'
-- and class 'C','H','M' to 'BRYOID','HERBS','HERBS'
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yvi01_non_for_veg_translation(text, text, text);
CREATE OR REPLACE FUNCTION TT_yvi01_non_for_veg_translation(
  type_lnd text,
  class_ text,
  cl_mod text
)
RETURNS text AS $$
	SELECT CASE
	       WHEN type_lnd = 'VN' AND class_ = 'S' AND cl_mod = 'TS' THEN 'TALL_SHRUB'
           WHEN type_lnd = 'VN' AND class_ = 'S' AND cl_mod = 'TSo' THEN 'TALL_SHRUB'
           WHEN type_lnd = 'VN' AND class_ = 'S' AND cl_mod = 'TSc' THEN 'TALL_SHRUB'
           WHEN type_lnd = 'VN' AND class_ = 'S' AND cl_mod = 'LS' THEN 'LOW_SHRUB'
           WHEN type_lnd = 'VN' AND class_ = 'S' AND cl_mod = '' THEN 'TALL_SHRUB' -- assign generic shrub to TALL_SHRUB
           WHEN type_lnd = 'VN' AND class_ = 'S' AND cl_mod IS NULL THEN 'TALL_SHRUB' -- assign generic shrub to TALL_SHRUB
           WHEN type_lnd = 'VN' AND class_ = 'C' THEN 'BRYOID'
           WHEN type_lnd = 'VN' AND class_ = 'H' THEN 'HERBS'
           WHEN type_lnd = 'VN' AND class_ = 'M' THEN 'HERBS'
           ELSE NULL
         END;
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yvi03_non_for_veg_translation
--
-- cl_mod text
-- cl_mod text
--
-- Assigns non for veg casfri attributes based on source attribute from various columns.
-- assumes type_lnd is VN
-- then translates cl_mod 'Tall Shrub', 'Low Shrub', 'Tall Shrub, Open', 'Tall Shrub, Closed' to 'TALL_SHRUB','TALL_SHRUB','TALL_SHRUB','LOW_SHRUB'
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yvi03_non_for_veg_translation(text, text);
CREATE OR REPLACE FUNCTION TT_yvi03_non_for_veg_translation(
  type_lnd text,
  cl_mod text
)
RETURNS text AS $$
	SELECT CASE
           WHEN type_lnd = 'Vegetated, Non-Forested' AND cl_mod = 'Tall Shrub' THEN 'TALL_SHRUB'
           WHEN type_lnd = 'Vegetated, Non-Forested' AND cl_mod = 'Tall Shrub, Open' THEN 'TALL_SHRUB'
           WHEN type_lnd = 'Vegetated, Non-Forested' AND cl_mod = 'Tall Shrub, Closed' THEN 'TALL_SHRUB'
           WHEN type_lnd = 'Vegetated, Non-Forested' AND cl_mod = 'Low Shrub' THEN 'LOW_SHRUB'
           WHEN type_lnd = 'Vegetated, Non-Forested' AND cl_mod = '' THEN 'TALL_SHRUB' -- assign generic shrub to TALL_SHRUB
		   WHEN type_lnd = 'Vegetated, Non-Forested' AND cl_mod IS NULL THEN 'TALL_SHRUB' -- assign generic shrub to TALL_SHRUB
           ELSE NULL
         END;
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_generic_stand_structure_translation
--
-- stand_structure text
-- layer1_sp1 text
-- layer1_sp2 text
-- layer1_sp3 text
-- layer2_sp1 text
-- layer2_sp2 text
-- layer2_sp3 text
-- layer3_sp1 text
-- layer3_sp2 text
-- layer3_sp3 text
--
-- Generic function the passes H or C from source to casfri, otherwise counts not null
-- forest layers and returns S or M.
--
-- All other cases should be caught in validation.
--
-- Inventory specific signatures are made from this generic version using the correct
-- number of species and layers.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_generic_stand_structure_translation(text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_generic_stand_structure_translation(
  stand_structure text,
  layer1_sp1 text,
  layer1_sp2 text,
  layer1_sp3 text,
  layer2_sp1 text,
  layer2_sp2 text,
  layer2_sp3 text,
  layer3_sp1 text,
  layer3_sp2 text,
  layer3_sp3 text,
  layer4_sp1 text,
  layer4_sp2 text,
  layer4_sp3 text,
  layer5_sp1 text,
  layer5_sp2 text,
  layer5_sp3 text
)
RETURNS text AS $$
  DECLARE
    _count1 int := 0;
    _count2 int := 0;
    _count3 int := 0;
    _count4 int := 0;
    _count5 int := 0;
    _count int;
  BEGIN
    -- are there any layer 1 species? (tried forming a TT_countOfNotNull call here but couldn't get it to run correctly)
    IF TT_notEmpty(layer1_sp1) OR TT_notEmpty(layer1_sp2) OR TT_notEmpty(layer1_sp3) THEN
      _count1 = 1;
    END IF;
  
    -- are there any layer 2 species?
    IF TT_notEmpty(layer2_sp1) OR TT_notEmpty(layer2_sp2) OR TT_notEmpty(layer2_sp3) THEN
      _count2 = 1;
    END IF;
  
    -- are there any layer 3 species?
    IF TT_notEmpty(layer3_sp1) OR TT_notEmpty(layer3_sp2) OR TT_notEmpty(layer3_sp3) THEN
      _count3 = 1;
    END IF;
  
    -- are there any layer 4 species?
    IF TT_notEmpty(layer4_sp1) OR TT_notEmpty(layer4_sp2) OR TT_notEmpty(layer4_sp3) THEN
      _count4 = 1;
    END IF;
  
    -- are there any layer 5 species?
    IF TT_notEmpty(layer5_sp1) OR TT_notEmpty(layer5_sp2) OR TT_notEmpty(layer5_sp3) THEN
      _count5 = 1;
    END IF;

    _count = _count1 + _count2 + _count3 + _count4 + _count5;

    -- if stand structure is H or C, return H or C. Note CX was added so this function can be re-used in ON02.
    IF stand_structure IN ('H', 'h', 'C', 'c', 'C0', 'C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7', 'C8', 'C9', 'CX', 'Complex') THEN
      RETURN TT_mapText(stand_structure, '{''H'', ''h'', ''C'', ''c'', ''C0'', ''C1'', ''C2'', ''C3'', ''C4'', ''C5'', ''C6'', ''C7'', ''C8'', ''C9'', ''CX'', ''Complex''}', '{''HORIZONTAL'', ''HORIZONTAL'', ''COMPLEX'', ''COMPLEX'', ''COMPLEX'', ''COMPLEX'', ''COMPLEX'', ''COMPLEX'', ''COMPLEX'', ''COMPLEX'', ''COMPLEX'', ''COMPLEX'', ''COMPLEX'', ''COMPLEX'', ''COMPLEX'', ''COMPLEX''}');
  
    -- if stand structure is not HORIZONTAL or COMPLEX, it must be SINGLE_LAYERED or MULTI_LAYERED.
    -- if only one species layer, return S (this should always be sp1)
    ELSIF _count = 1 THEN
      RETURN 'SINGLE_LAYERED';
    ELSIF _count IN(2, 3, 4, 5) THEN
      RETURN 'MULTI_LAYERED';
    ELSE
      RETURN NULL;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- avi signature - 2 layers, 3 species
-- DROP FUNCTION IF EXISTS TT_avi01_stand_structure_translation(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_avi01_stand_structure_translation(
  stand_structure text,
  layer1_sp1 text,
  layer1_sp2 text,
  layer1_sp3 text,
  layer2_sp1 text,
  layer2_sp2 text,
  layer2_sp3 text
)
RETURNS text AS $$
  SELECT TT_generic_stand_structure_translation(stand_structure, layer1_sp1, layer1_sp2, layer1_sp3, layer2_sp1, layer2_sp2, layer2_sp3, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text);
$$ LANGUAGE sql IMMUTABLE;

-- fvi signature - 2 layers, 3 species
-- species should only be counted if typeclas is not NFL type
-- DROP FUNCTION IF EXISTS TT_fvi01_stand_structure_translation(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_fvi01_stand_structure_translation(
  stand_structure text,
  typeclas text,
  mintypeclas text,
  layer1_sp1 text,
  layer1_sp2 text,
  layer1_sp3 text,
  layer2_sp1 text,
  layer2_sp2 text,
  layer2_sp3 text
)
RETURNS text AS $$
  DECLARE
    _nfl_codes text[];
    _layer1_sp1 text;
    _layer1_sp2 text;
    _layer1_sp3 text;
    _layer2_sp1 text;
    _layer2_sp2 text;
    _layer2_sp3 text;
  BEGIN
    _nfl_codes = ARRAY['BE','BR','BU','CB','ES','LA','LL','LS','MO','MU','PO','RE','RI','RO','RS','RT','SW','AP','BP','EL','GP','TS','RD','SH','SU','PM','BL','BM','BY','HE','HF','HG','SL','ST'];
  
    -- if layer 1 is NFL set species to ''
    IF typeclas = ANY(_nfl_codes) THEN
      _layer1_sp1 = '';
      _layer1_sp2 = '';
      _layer1_sp3 = '';
    ELSE
      _layer1_sp1 = layer1_sp1;
      _layer1_sp2 = layer1_sp2;
      _layer1_sp3 = layer1_sp3;
    END IF;

    -- if layer 2 is NFL set species to ''
    IF mintypeclas = ANY(_nfl_codes) THEN
      _layer2_sp1 = '';
      _layer2_sp2 = '';
      _layer2_sp3 = '';
    ELSE
      _layer2_sp1 = layer2_sp1;
      _layer2_sp2 = layer2_sp2;
      _layer2_sp3 = layer2_sp3;
    END IF;

    RETURN TT_generic_stand_structure_translation(stand_structure, _layer1_sp1, _layer1_sp2, _layer1_sp3, _layer2_sp1, _layer2_sp2, _layer2_sp3, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ON02 signature - 2 layers, 1 species
CREATE OR REPLACE FUNCTION TT_fim02_stand_structure_translation(
  stand_structure text,
  layer1_sp1 text,
  layer2_sp1 text
)
RETURNS text AS $$
  SELECT TT_generic_stand_structure_translation(stand_structure, layer1_sp1, NULL::text, NULL::text, layer2_sp1, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text);
$$ LANGUAGE sql IMMUTABLE;

-- SK SFVI signature - 3 layers, 1 species
CREATE OR REPLACE FUNCTION TT_sfv01_stand_structure_translation(
  stand_structure text,
  layer1_sp1 text,
  layer2_sp1 text,
  layer3_sp1 text
)
RETURNS text AS $$
  SELECT TT_generic_stand_structure_translation(stand_structure, layer1_sp1, NULL::text, NULL::text, layer2_sp1, NULL::text, NULL::text, layer3_sp1, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text);
$$ LANGUAGE sql IMMUTABLE;

-- MB FLI signature - 5 layers, 3 species
CREATE OR REPLACE FUNCTION TT_mb_fli01_stand_structure_translation(
  stand_structure text,
  layer1_sp1 text,
  layer1_sp2 text,
  layer1_sp3 text,
  layer2_sp1 text,
  layer2_sp2 text,
  layer2_sp3 text,
  layer3_sp1 text,
  layer3_sp2 text,
  layer3_sp3 text,
  layer4_sp1 text,
  layer4_sp2 text,
  layer4_sp3 text,
  layer5_sp1 text,
  layer5_sp2 text,
  layer5_sp3 text
)
RETURNS text AS $$
  SELECT TT_generic_stand_structure_translation(stand_structure, layer1_sp1, layer1_sp2, layer1_sp3, layer2_sp1, layer2_sp2, layer2_sp3, layer3_sp1, layer3_sp2, layer3_sp3, layer4_sp1, layer4_sp2, layer4_sp3, layer5_sp1, layer5_sp2, layer5_sp3);
$$ LANGUAGE sql IMMUTABLE;

-- YT YVI02 signature - 2 layers, 4 species
CREATE OR REPLACE FUNCTION TT_yt_yvi02_stand_structure_translation(
  stand_structure text,
  layer1_sp1 text,
  layer1_sp2 text,
  layer1_sp3 text,
  layer2_sp1 text,
  layer2_sp2 text,
  layer2_sp3 text
)
RETURNS text AS $$
  SELECT TT_generic_stand_structure_translation(stand_structure, layer1_sp1, layer1_sp2, layer1_sp3, layer2_sp1, layer2_sp2, layer2_sp3, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text);
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_fvi01_countOfNotNull
--
-- vals1 text
-- vals2 text
-- typeclas_nonveg text
-- typeclas_anth text
-- typeclas text
-- min_typeclas text
-- max_rank_to_consider text
--
-- Use match list to determine if typeclas and min_typeclas are NFL values.
-- If they are assign them a string so they are counted as layers. If not assign
-- NULL.
-- Same for LYR, check typeclas and min_typeclass are not nfl types. If they are
-- we don't want to count the species as LYR layers because we'll be double counting
-- the NFL veg.
--
-- Pass vals1, vals2 and the string/NULLs to countOfNotNull().
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_fvi01_countOfNotNull(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_fvi01_countOfNotNull(
  vals1 text,
  vals2 text,
  typeclas_nonveg text,
  typeclas_anth text,
  typeclas text,
  mintypeclas text,
  max_rank_to_consider text
)
RETURNS int AS $$
  DECLARE
    lyr_string_list text[];
    nfl_string_list text[];
    _lyr1 text;
    _lyr2 text;
    _is_nfl1 text;
    _is_nfl2 text;
  BEGIN
    -- set up nfl_string_list
    nfl_string_list = ARRAY['BE','BR','BU','CB','ES','LA','LL','LS','MO','MU','PO','RE','RI','RO','RS','RT','SW','AP','BP','EL','GP','TS','RD','SH','SU','PM','BL','BM','BY','HE','HF','HG','SL','ST'];
	
    -- if NFL 1 present, give _is_nfl1 a string.
    IF typeclas_nonveg = ANY(nfl_string_list) OR typeclas_anth = ANY(nfl_string_list) OR typeclas = ANY(nfl_string_list) THEN
      _is_nfl1 = 'a_value';
	  _lyr1 = NULL::text;
    ELSE
      _is_nfl1 = NULL::text;
	  _lyr1 = vals1;
    END IF;
  
    -- if NFL 2 present, give _is_nfl2 a string.
    IF mintypeclas = ANY(nfl_string_list) THEN
      _is_nfl2 = 'a_value';
	  _lyr2 = NULL::text;
    ELSE
    	IF mintypeclas = '999' AND _is_nfl1 = 'a_value'
    	THEN
			_lyr2 = NULL::text;
    	ELSE 
    		_lyr2 = vals2;
    	END IF;
    	_is_nfl2 = NULL::text;
    END IF;

    -- call countOfNotNull
    RETURN TT_countOfNotNull(_lyr1, _lyr2, _is_nfl1, _is_nfl2, max_rank_to_consider, 'FALSE');
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_vri01_countOfNotNull
--
-- vals1 text - string list of layer 1 attributes. This is carried through to couneOfNotNull
-- vals2 text - string list of layer 2 attribtues. This is carried through to couneOfNotNull
-- inventory_standard_cd text
-- land_cover_class_cd_1 text
-- bclcs_level_4 text
-- non_productive_descriptor_cd text
-- non_veg_cover_type_1 text
--
-- Use the custom helper function:
-- to determine if the row contains 1 - 3 NFL records. If it does assign a string
-- for each NFL layer so they can be counted as a non-null layer.
--
-- Pass vals1, vals2 and the string/NULLs to countOfNotNull().
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_vri01_countOfNotNull(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_vri01_countOfNotNull(
  vals1 text,
  vals2 text,
  inventory_standard_cd text,
  land_cover_class_cd_1 text,
  bclcs_level_4 text,
  non_productive_descriptor_cd text,
  non_veg_cover_type_1 text,
  max_rank_to_consider text
)
RETURNS int AS $$
  DECLARE
    is_nfl1 text;
    is_nfl2 text;
    is_nfl3 text;
  BEGIN
    -- if nat_non_veg is present, add a string.
    IF TT_vri01_nat_non_veg_validation(inventory_standard_cd, land_cover_class_cd_1, bclcs_level_4, non_productive_descriptor_cd, non_veg_cover_type_1) THEN
      is_nfl1 = 'a_value';
    ELSE
      is_nfl1 = NULL::text;
    END IF;

    -- if non_for_anth is present, add a string.
    IF TT_vri01_non_for_anth_validation(inventory_standard_cd, land_cover_class_cd_1, non_productive_descriptor_cd, non_veg_cover_type_1) THEN
      is_nfl2 = 'a_value';
    ELSE
      is_nfl2 = NULL::text;
    END IF;

    -- if non_for_veg is present, add a string.
    IF TT_vri01_non_for_veg_validation(inventory_standard_cd, land_cover_class_cd_1, bclcs_level_4, non_productive_descriptor_cd) THEN
      is_nfl3 = 'a_value';
    ELSE
      is_nfl3 = NULL::text;
    END IF;

  
    -- call countOfNotNull
    -- WE HAVE UPDATED BC08 TO INCLUDE ALL LAYER TABLES. IF WE TRANSLATE ANY OF THE OLD RANK1 LAYER1 DATASETS FROM BC WE WILL NEED TO UNCOMMENT THE FOLLOWING LINES
    -- if BC08 there is only 1 forest layer so remove the second forest layer from the count
    --IF inventory_id = 'BC08' THEN
      --RETURN TT_countOfNotNull(vals1, is_nfl1, is_nfl2, is_nfl3, max_rank_to_consider, 'FALSE');
    --ELSE
    RETURN TT_countOfNotNull(vals1, vals2, is_nfl3, is_nfl1, is_nfl2, max_rank_to_consider, 'FALSE');
    --END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sk_utm01_species_percent_translation
--
-- sp_number text - the species number being requested (i.e. SPECIES 1-10 in casfri)
-- sp10 text
-- sp11 text
-- sp12 text
-- sp20 text
-- sp21 text
--
-- returns the species percent based on the requested sp_number and many logical statements
-- to determine the percent based on what species are present. Logical statements were developed
-- with John Cosco and are recorded in an appendix doc.
--
-- Codes the polygon being processed based on the combination of hardwood and
-- softwood species in each column.
-- e.g. concatenates in order either H for hardwood, S for softwood or - for nothing
-- into a 5 character string such as S----
--
-- The code is then used to make a percentage vector and the species requested is returned
-- as an index from the vector.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_sk_utm01_species_percent_translation(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_sk_utm01_species_percent_translation(
  sp_number text,
  sp10 text,
  sp11 text,
  sp12 text,
  sp20 text,
  sp21 text
)
RETURNS int AS $$
  DECLARE
    _sp_number int := sp_number::int;
    hardwoods text[]; -- list of harwood species codes
    softwoods text[]; -- list of softwood species codes
    ft10 text; -- assigns hardwood or softwood forest type
    ft11 text;
    ft12 text;
    ft20 text;
    ft21 text;
    ft_concat text; -- concatenates the ft values.
    percent_vector int[]; -- percentages for the 5 species in a vector
  BEGIN
    -- assign hardwood and softwood groups
    softwoods = ARRAY['WS','BS','JP','BF','TL','LP'];
    hardwoods = ARRAY['GA','TA','BP','WB','WE','MM','BO'];
  
    -- assign forest type variables
    IF sp10 = ANY(hardwoods) THEN
      ft10 = 'H';
    ELSIF sp10 = ANY(softwoods) THEN
      ft10 = 'S';
    ELSE
      ft10 = '-';
    END IF;
  
    IF sp11 = ANY(hardwoods) THEN
      ft11 = 'H';
    ELSIF sp11 = ANY(softwoods) THEN
      ft11 = 'S';
    ELSE
      ft11 = '-';
    END IF;
  
    IF sp12 = ANY(hardwoods) THEN
      ft12 = 'H';
    ELSIF sp12 = ANY(softwoods) THEN
      ft12 = 'S';
    ELSE
      ft12 = '-';
    END IF;
  
    IF sp20 = ANY(hardwoods) THEN
      ft20 = 'H';
    ELSIF sp20 = ANY(softwoods) THEN
      ft20 = 'S';
    ELSE
      ft20 = '-';
    END IF;
  
    IF sp21 = ANY(hardwoods) THEN
      ft21 = 'H';
    ELSIF sp21 = ANY(softwoods) THEN
      ft21 = 'S';
    ELSE
      ft21 = '-';
    END IF;

    -- assign forest type code
    ft_concat = ft10 || ft11 || ft12 || ft20 || ft21;
  
    -- Assign logical tests to make percent vector for each forest type code in the source data
    IF ft_concat IN('S----', 'H----') THEN
      percent_vector = ARRAY[100, 0, 0, 0, 0];
    ELSIF ft_concat IN('HH---') THEN
      percent_vector = ARRAY[70, 30, 0, 0, 0];
    ELSIF ft_concat IN('SS---') AND CONCAT(sp10, sp11) NOT IN('JPBS', 'BSJP') THEN
      percent_vector = ARRAY[70, 30, 0, 0, 0];
    ELSIF ft_concat IN('SS---') AND CONCAT(sp10, sp11) IN('JPBS', 'BSJP') THEN
      percent_vector = ARRAY[60, 40, 0, 0, 0];
    ELSIF ft_concat IN('S--S-') THEN
      percent_vector = ARRAY[80, 20, 0, 0, 0];
    ELSIF ft_concat IN('HHH--', 'SSS--') THEN
      percent_vector = ARRAY[40, 30, 30, 0, 0];
    ELSIF ft_concat IN('SS-S-') THEN
      percent_vector = ARRAY[50, 30, 0, 20, 0];
    ELSIF ft_concat IN('S--H-', 'H--S-') THEN
      percent_vector = ARRAY[65, 0, 0, 35, 0];
    ELSIF ft_concat IN('HS-S-') THEN
      percent_vector = ARRAY[60, 30, 0, 10, 0];
    ELSIF ft_concat IN('HS-S-') THEN
      percent_vector = ARRAY[60, 30, 0, 10, 0];
    ELSIF ft_concat IN('HH-S-', 'SS-H-') THEN
      percent_vector = ARRAY[50, 25, 0, 25, 0];
    ELSIF ft_concat IN('H--SS', 'S--HH') THEN
      percent_vector = ARRAY[70, 0, 0, 20, 10];
    ELSIF ft_concat IN('HH-SS', 'SS-HH') THEN
      percent_vector = ARRAY[30, 30, 0, 20, 20];
    ELSIF ft_concat IN('SSSH-', 'HHHS-') THEN
      percent_vector = ARRAY[25, 25, 25, 25, 0];
    ELSIF ft_concat IN('SSSHH', 'HHHSS') THEN
      percent_vector = ARRAY[25, 25, 20, 15, 15];
    ELSIF ft_concat IN('SH---', 'HS---') THEN
      percent_vector = ARRAY[60, 40, 0, 0, 0]; -- this rule needed for layer 2 (u1, u2)
    ELSE
      RETURN NULL; -- if code does not match any of the above, it should have been caught by the validation function. Return NULL.
    END IF;
  
    -- return the requested index, after removing all zero values
    RETURN (array_remove(percent_vector, 0))[_sp_number];
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sk_utm01_species
--
-- sp_number text - the species number being requested (i.e. SPECIES 1-10 in casfri)
-- sp10 text
-- sp11 text
-- sp12 text
-- sp20 text
-- sp21 text
--
-- Determines the species code for the requested species, ignoring any preceding slots with
-- no data. For example, if only sp10 and sp20 are present, sp20 becomes SPECIES_2 in CASFRI.
--
-- Once the correct species code is identified, it is run through the lookup table and returned.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_sk_utm01_species(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_sk_utm01_species(
  sp_number text,
  sp10 text,
  sp11 text,
  sp12 text,
  sp20 text,
  sp21 text
)
RETURNS text AS $$
  DECLARE
    _sp_number int := sp_number::int;
    sp_array text[]; -- array to hold species values
    sp_to_lookup text; -- the species code to be translated
  BEGIN
    -- make species array
    sp_array = ARRAY[sp10, sp11, sp12, sp20, sp21];

    -- remove NULLs
    sp_array = array_remove(sp_array, NULL);
  
    -- remove empty strings
    sp_array = array_remove(sp_array, '');
    sp_array = array_remove(sp_array, ' ');

    -- return the requested index, after removing all zero values
    sp_to_lookup = sp_array[_sp_number];
    RETURN sp_to_lookup;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sfv01_countOfNotNull
--
-- vals1 text - string list of layer 1 attributes. This is carried through to couneOfNotNull
-- vals2 text - string list of layer 2 attribtues. This is carried through to couneOfNotNull
-- vals3 text - string list of layer 3 attributes. This is carried through to couneOfNotNull
-- vals4 text - string list of layer 4 (shrub) attributes. This is carried through to couneOfNotNull
-- vals5 text - string list of layer 5 (herb) attributes. This is carried through to couneOfNotNull
-- nvsl text
-- aquatic_class text
-- luc text
-- transp_class text
--
-- Use the custom helper function:
-- to determine if the row contains an NFL record. If it does assign a string
-- so it can be counted as a non-null layer.
--
-- Pass vals1-vals5 and the string/NULLs to countOfNotNull().
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_sfv01_countOfNotNull(text, text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_sfv01_countOfNotNull(
  vals1 text,
  vals2 text,
  vals3 text,
  vals4 text,
  vals5 text,
  _type text,
  nvsl text,
  aquatic_class text,
  luc text,
  transp_class text,
  max_rank_to_consider text
)
RETURNS int AS $$
	DECLARE
     is_nfl text;
	BEGIN
		-- if any of the nfl functions return true, we know there is an NFL record.
		-- set is_nfl to be a valid string.
		IF CONCAT(trim(nvsl), trim(aquatic_class)) IN ('UK', 'CB', 'RK', 'SA', 'MS', 'GR', 'SB', 'WA', 'LA', 'RI', 'FL', 'SF', 'FP', 'ST', 'WASF', 'WALA', 'UKLA', 'WARI', 'WAFL', 'WAFP', 'WAST','L','R')
		   OR CONCAT(trim(luc), trim(transp_class), trim(aquatic_class)) IN ('ALA', 'POP', 'REC', 'PEX', 'GPI', 'BPI', 'MIS', 'ASA', 'NSA', 'OIS', 'OUS', 'AFS', 'CEM', 'WEH', 'TOW', 'RWC', 'RRC', 'TLC', 'PLC', 'MPC','PL','RD','TL','vegu', 'bugp', 'towu', 'cmty', 'dmgu', 'gsof', 'rwgu', 'muou', 'mg', 'peatc', 'lmby', 'sdgu', 'bupo', 'ftow', 'FP', 'WADI') THEN
		  is_nfl = 'a_value';
		ELSE
		  is_nfl = NULL::text;
		END IF;

		-- If type is non-productive code, force vals1 to be present by assigning it a string
		IF _type IN('BSH', 'TMS') THEN
		  vals1 = 'a_string';
		END IF;

		-- call countOfNotNull
		RETURN TT_countOfNotNull(vals1, vals2, vals3, vals4, vals5, is_nfl, max_rank_to_consider, 'FALSE');
	END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_mb_fli01_countOfNotNull
--
-- species_layer_1 text,
-- species_layer_2 text,
-- species_layer_3 text,
-- species_layer_4 text,
-- species_layer_5 text,
-- nnf_anth text,
-- max_rank_to_consider text
--
-- Determine if the row contains an NFL record. If it does assign a string
-- so it can be counted as a non-null layer.
--
-- Pass species and the string/NULLs to countOfNotNull().
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_mb_fli01_countOfNotNull(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_mb_fli01_countOfNotNull(
  species_layer_1 text,
  species_layer_2 text,
  species_layer_3 text,
  species_layer_4 text,
  species_layer_5 text,
  nnf_anth text,
  max_rank_to_consider text
)
RETURNS int AS $$
  DECLARE
    is_nfl text;
  BEGIN
    -- set is_nfl to be a valid string.
    IF nnf_anth IN('NMB','NMC','NMR','NMS','NMG','NWL','NWR','NWW','NMM','NMO','NWE','NWA','NSL','NMF', 'CP', 'CA', 'CPR', 'ASB', 'AFL', 'ADD', 'CIP','CIW','CIU','ASC','ASR','ASP','ASN','AIH','AIR', 'AAR', 'AIG','AII','AIW','AIA','AIF','AIU', 'SO','SO1','SO2','SO3','SO4','SO5','SO6','SO7','SO8','SO9','AL','SC','SC1','SC2','SC3','SC4','SC5','SC6','SC7','SC8','SC9','CC','HG','CS','HF','AS','HU','VI','BR','RA','CL','DL','AU') THEN
      is_nfl = 'a_value';
    ELSE
      is_nfl = NULL::text;
    END IF;
  
    -- call countOfNotNull
    RETURN TT_countOfNotNull(species_layer_1, species_layer_2, species_layer_3, species_layer_4, species_layer_5, is_nfl, max_rank_to_consider, 'FALSE');
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_ns_nsi01_countOfNotNull
--
-- vals1 text - string list of layer 1 attributes. This is carried through to couneOfNotNull
-- vals2 text - string list of layer 2 attribtues. This is carried through to couneOfNotNull
-- fornon text
-- max_rank_to_consider text
--
-- Determine if the row contains an NFL record. If it does assign a string
-- so it can be counted as a non-null layer.
-- If fornon is a non-productive type, make sure vals1 returns true. This indicates
-- a LYR layer that needs to be counted ecen if no species code exists.
--
-- Pass vals1-vals2 and the string/NULLs to countOfNotNull().
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ns_nsi01_countOfNotNull(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_ns_nsi01_countOfNotNull(
  vals1 text,
  vals2 text,
  fornon text,
  max_rank_to_consider text
)
RETURNS int AS $$
  DECLARE
    is_nfl text;
  BEGIN
    -- if any of the nfl functions return true, we know there is an NFL record.
    -- set is_nfl to be a valid string.
    IF fornon IN('71','76','77','78','84','85','94', '5','86','87','91','92','93','95','96','97','98','99', '70','72','74','75','83','88','89') THEN
      is_nfl = 'a_value';
    ELSE
      is_nfl = NULL::text;
    END IF;
  
    IF fornon IN('33', '38', '39', '73') THEN
      vals1 = 'a_string';
    END IF;
	
    -- call countOfNotNull
    RETURN TT_countOfNotNull(vals1, vals2, is_nfl, max_rank_to_consider, 'FALSE');
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pe_pei01_countOfNotNull
--
-- spec1 text
-- spec2 text
-- spec3 text
-- spec4 text
-- spec5 text
-- landtype text
-- class1 text
-- max_rank_to_consider text
--
-- Determine if spec1/2/3/4/5 contain a valid species code. Note that the
-- value needs to be checked against the valid codes because spec1 in pe01
-- contains non-species codes. If a valid species code is present, assign
-- a string to indicate a layer in countOfNotNull.
-- Determine if the row contains an NFL record. If it does assign a string
-- so it can be counted as a non-null layer.
--
-- Pass species and nfl variables to countOfNotNull().
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_pe_pei01_countOfNotNull(text, text, text, text, text, text,text, text);
CREATE OR REPLACE FUNCTION TT_pe_pei01_countOfNotNull(
  spec1 text,
  spec2 text,
  spec3 text,
  spec4 text,
  spec5 text,
  landuse text,
  subuse text,
  class1 text,
  max_rank_to_consider text
)
RETURNS int AS $$
  DECLARE
    species_codes text[] := '{AL,AP,AS,BA,BE,BF,BI,BN,BS,CE,CP,DF,EB,EL,EL,EM,GB,HE,HP,HS,IH,JL,JP,LA,LI,LP,LX,MA,NS,PC,PO,PP,RM,RO,RP,RS,SF,SI,SM,SP,TH,WA,WB,WI,WP,WS,YB,YP}'; --codes copied from PEI CORPORATE LAND USE INVENTORY 2000
    nfl_codes text[] := '{BAR,BSB,SDW,WWW,WAT,SO,SD,WW,FL,AGR,COM,RES,IND,NON,REC,TRN,URB,INT,CL,WF,PL,RN,RD,RR,AG,EP,UR,BOW,BO}';
    is_lyr text;
    is_nfl text;
  BEGIN
    -- if any of the species have a valid species code, set is_lyr to be a valid string.
    IF spec1 = ANY(species_codes) OR spec2 = ANY(species_codes) OR spec3 = ANY(species_codes) OR spec4 = ANY(species_codes) OR spec5 = ANY(species_codes) THEN
      is_lyr = 'a_value';
    ELSE
      is_lyr = NULL::text;
    END IF;


    -- if landtype matches any of the nfl values, we know there is an NFL record., set is_nfl to be a valid string.
    IF landuse = ANY(nfl_codes) OR subuse = ANY(nfl_codes) OR class1 = ANY(nfl_codes)  THEN
      is_nfl = 'a_value';
    ELSE
      is_nfl = NULL::text;
    END IF;

    -- call countOfNotNull
    RETURN TT_countOfNotNull(is_lyr, is_nfl, max_rank_to_consider, 'FALSE');
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pe_pei01_map_dist_year
--
-- dist_type text
--
-- The PEI02 disturbance codes include a plantation code with year established
-- eg. PN-92, PN-02
-- This value needs to be parsed into a full year and returned as int to populate
-- the dist_year columns
--
-- pass dist_type values where dist_type includes PN
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION TT_pe_pei01_map_dist_year(
  dist_type text
)
RETURNS text AS $$
  DECLARE
    partial_year text;
  BEGIN
    -- eg. PN-92, year is 1992
    partial_year = TT_SubstringText(dist_type, '4'::text, '2'::text);

    IF partial_year is NULL THEN
      RETURN NULL;
    END IF;

    -- if between 50 - 99, year is in 1900's
    IF TT_IsBetween(partial_year, '30'::text, '99'::text, TRUE::text, TRUE::text ) THEN
      RETURN TT_Concat('{''19'', ' || partial_year || '}'::text, ''::text);
    ELSE -- 2000's
      RETURN TT_Concat('{''20'', ' || partial_year || '}'::text, ''::text);
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pe_pei01_dist_type_length_validation
--
-- dist_type text
-- landtype text
-- substring_start text
--
-- Intended to validate dist_type_2 length for PEI. 
-- If the inventory records two disturbance types in one field, then the substring start will be equal to 3. 
-- If this is the case, and the length isnt 4, then the disturbance type isn't applicable and will return false.
-- Returns true otherwise
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION TT_pe_pei01_dist_type_length_validation(
  dist_type TEXT,
  landtype TEXT,
  substring_start TEXT
)
RETURNS BOOLEAN AS $$
	BEGIN
		RETURN length(tt_coalesceText(ARRAY[dist_type,landtype]::TEXT)) = 4 OR substring_start = 1::TEXT;
	 END;
$$ LANGUAGE plpgsql STABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_on_fim02_countOfNotNull
--
-- vals1 text - string list of layer 1 attributes. This is carried through to couneOfNotNull
-- vals2 text - string list of layer 2 attribtues. This is carried through to couneOfNotNull
-- polytype text
-- max_rank_to_consider text
--
-- Determine if the row contains an NFL record. If it does assign a string
-- so it can be counted as a non-null layer.
-- If polytype contains a non-productive LYR record, count vals1 as present.
--
-- Pass vals1-vals2 and the string/NULLs to countOfNotNull().
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_on_fim02_countOfNotNull(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_on_fim02_countOfNotNull(
  vals1 text,
  vals2 text,
  polytype text,
  max_rank_to_consider text
)
RETURNS int AS $$
  DECLARE
    is_nfl text;
  BEGIN
    -- if any of the nfl functions return true, we know there is an NFL record.
    -- set is_nfl to be a valid string.
    IF polytype IN ('ISL','WAT','RCK','DAL','UCL','GRS','OMS', 'RRW') THEN
      is_nfl = 'a_value';
    ELSE
      is_nfl = NULL::text;
    END IF;
	
    IF polytype IN ('BSH', 'TMS') THEN
      vals1 = 'a_value';
    END IF;
  
    -- call countOfNotNull
    RETURN TT_countOfNotNull(vals1, vals2, is_nfl, max_rank_to_consider, 'FALSE');
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sk_utm_countOfNotNull(text, text, text, text)
--
-- vals1 text - string list of layer 1 attributes. This is carried through to couneOfNotNull
-- vals2 text - string list of layer 2 attribtues. This is carried through to couneOfNotNull
-- np text
-- max_rank_to_consider text
--
-- Determine if the row contains an NFL record. If it does assign a string
-- so it can be counted as a non-null layer.
--
-- Pass vals1-vals2 and the string/NULLs to countOfNotNull().
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_sk_utm_countOfNotNull(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_sk_utm_countOfNotNull(
  vals1 text,
  vals2 text,
  np text,
  max_rank_to_consider text
)
RETURNS int AS $$
  DECLARE
    is_nfl text;
  BEGIN
    -- if any of the nfl functions return true, we know there is an NFL record.
    -- set is_nfl to be a valid string.
    IF np IN ('3300','3500','3600','3900','3700','9000','4000','3800','5100','3400','5210','5220','5200') THEN
      is_nfl = 'a_value';
    ELSE
      is_nfl = NULL::text;
    END IF;

    -- if np is a non-productive type, set vals to string.
    IF np IN ('3100','3200') THEN
      vals1 = 'a_value';
    END IF;

    -- call countOfNotNull
    RETURN TT_countOfNotNull(vals1, vals2, is_nfl, max_rank_to_consider, 'FALSE');
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_mb_fri_countOfNotNull
--
-- species text - string list of species attributes. This is carried through to couneOfNotNull
-- nfl text - nfl code
-- max_rank_to_consider text
--
-- Determine if the row contains an NFL record. If it does assign a string
-- so it can be counted as a non-null layer.
--
-- Pass species and the string/NULLs to countOfNotNull().
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_mb_fri_countOfNotNull(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_mb_fri_countOfNotNull(
  species text,
  nfl text,
  max_rank_to_consider text
)
RETURNS int AS $$
  DECLARE
    is_nfl text;
  BEGIN
    -- if any of the nfl functions return true, we know there is an NFL record.
    -- set is_nfl to be a valid string.
    IF TT_matchList(nfl,'{''802'',''803'',''804'',''838'',''839'',''848'',''900'',''901'',''991'',''992'',''993'',''994'',''995'',''810'',''811'',''812'',''813'',''815'',''816'',''840'',''841'',''842'',''843'',''844'',''845'',''846'',''847'',''849'',''851'', ''801'',''821'',''822'',''823'',''824'',''830'',''831'',''832'',''835''}') THEN
      is_nfl = 'a_value';
    ELSE
      is_nfl = NULL::text;
    END IF;
	
	  -- if val is a non-productive type, we know there is a LYR record. It's the same attribute as nfl
    -- set species to be a valid string.
    IF TT_matchList(nfl,'{''701'', ''702'', ''703'', ''704'', ''711'', ''712'', ''713'', ''721'', ''722'', ''723'', ''724'', ''725'', ''731'', ''732'', ''733'', ''734''}')
    OR tt_hasCountOfNotNull(species, '1', 'FALSE') THEN
      species = 'a_value';
    END IF;
  
    -- call countOfNotNull
    RETURN TT_countOfNotNull(species, is_nfl, max_rank_to_consider, 'FALSE');
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yvi03_countofnotnull
--
-- Identify any NFL layers. Identify any non-productve LYR layers and set species_1 to a string.
-- Pass strings and species to countofnotnull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yvi03_countofnotnull(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yvi03_countofnotnull(
  species_1 text,
  type_lnd text, 
  cover_type text, 
  cl_mod text, 
  landpos text,
  maxRankToConsider text
)
RETURNS int AS $$
  DECLARE
	_nfl text;
  BEGIN
    IF tt_notEmpty(species_1) THEN
      species_1 = 'a string';
    END IF;
  
    IF tt_yvi03_hasNFL(type_lnd, cover_type, cl_mod, landpos) THEN
      _nfl = 'a_string';
    ELSE
      _nfl = NULL;
    END IF;
    		
    RETURN TT_countOfNotNull(species_1, _nfl, maxRankToConsider, 'FALSE');
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_fvi01_structure_per
--
-- stand_structure text
-- structure_per - text
--
-- If stand structure is C, M, S return 100.
-- If stand structure is H, return structure_val *10.

------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_fvi01_structure_per(text, text);
CREATE OR REPLACE FUNCTION TT_fvi01_structure_per(
  stand_structure text,
  structure_per text
)
RETURNS int AS $$
  DECLARE
    _structure_per int := structure_per::int;
  BEGIN
    IF stand_structure IN('C', 'M', 'S', 'V') THEN
      RETURN 100;
    END IF;
  
    IF stand_structure = 'H' THEN
      IF _structure_per = 0 THEN
        RETURN 100;
      ELSE
        RETURN _structure_per * 10;
      END IF;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg3_wetland_translation
--
-- CO_TER text,
-- CL_DRAIN text,
-- gr_ess text,
-- cl_dens text,
-- cl_haut text,
-- TYPE_ECO text
--
-- Get the 4 character wetland code and translate
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg3_wetland_translation(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_qc_prg3_wetland_translation(
  CO_TER text,
  CL_DRAIN text,
  gr_ess text,
  cl_dens text,
  cl_haut text,
  TYPE_ECO text,
  ret_char text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_qc_wetland_code(CO_TER, CL_DRAIN, gr_ess, cl_dens, cl_haut, TYPE_ECO, 'QC03');
  
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
  
    RETURN TT_wetland_code_translation(_wetland_code, ret_char);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg4_wetland_translation
--
-- CO_TER text,
-- CL_DRAIN text,
-- gr_ess text,
-- cl_dens text,
-- cl_haut text,
-- TYPE_ECO text
--
-- Get the 4 character wetland code and translate
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg4_wetland_translation(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_qc_prg4_wetland_translation(
  CO_TER text,
  CL_DRAIN text,
  gr_ess text,
  cl_dens text,
  cl_haut text,
  TYPE_ECO text,
  ret_char text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_qc_wetland_code(CO_TER, CL_DRAIN, gr_ess, cl_dens, cl_haut, TYPE_ECO, 'QC04');
  
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
  
    RETURN TT_wetland_code_translation(_wetland_code, ret_char);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg5_wetland_translation
--
-- CO_TER text,
-- CL_DRAIN text,
-- gr_ess text,
-- cl_dens text,
-- cl_haut text,
-- TYPE_ECO text
--
-- Get the 4 character wetland code and translate
-- Note this is identical to TT_qc_prg4_wetland_translation
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg5_wetland_translation(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_qc_prg5_wetland_translation(
  CO_TER text,
  CL_DRAIN text,
  gr_ess text,
  cl_dens text,
  cl_haut text,
  TYPE_ECO text,
  ret_char text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_qc_wetland_code(CO_TER, CL_DRAIN, gr_ess, cl_dens, cl_haut, TYPE_ECO, 'QC05');
  
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
  
    RETURN TT_wetland_code_translation(_wetland_code, ret_char);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg4_species
--
-- gr_ess text,
-- species_number text
--
-- For QC fourth inventory, species are coded in gr_ess column, gr_ess code needs to be split
-- to get species 1, 2, 3 etc. Requested species code is then extracted based on species_number.
--
-- If species is a doubled code (e.g. FXFX, PUPU etc.) then only species 1 should be returned.
-- These codes should be interpreted as species 1 with 100%.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg4_species(text, text);
CREATE OR REPLACE FUNCTION TT_qc_prg4_species(
  gr_ess text,
  species_number text
)
RETURNS text AS $$
  DECLARE
    sp_val text;
    _gr_ess text;
  BEGIN
    -- If gr_ess starts with a double species code, it should only be one species. Remove the first two characters.
    IF NOT TT_qc_prg4_not_double_species_validation(gr_ess) THEN
      _gr_ess = substring(gr_ess, 3, 4);
    ELSE
      _gr_ess = gr_ess;
    END IF;
  
    -- Translate the gr_ess code according to position
    sp_val = trim(SPLIT_PART(species, ' ', species_number::int))
      FROM (SELECT trim(regexp_replace(_gr_ess, '(.{2})', E'\\1 ', 'g')) as species) r;
    
    -- Pass the value to the lookup table
    IF sp_val IS NULL OR sp_val = '' THEN
      RETURN NULL;
    ELSE
      RETURN sp_val;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg5_species
--
-- eta_ess_pc text,
-- species_number text
--
-- First checks if the code is a species group code (e.g. FXFN) which have no percent values.
-- If it is, return the requested species code.
-- If not, it is a normal code with species percent values (e.g. BF1BS9).
-- Runs TT_qc_prg5_species_code_to_reordered_array then returns the species code from the requested position.
--
-- e.g. TT_qc_prg5_species('BS20WS60TA20', 1) would return 'WS'.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg5_species(text, text);
CREATE OR REPLACE FUNCTION TT_qc_prg5_species(
  eta_ess_pc text,
  species_number text
)
RETURNS text AS $$
  DECLARE
    code_array text[];
    sp_code text;
  BEGIN
    -- Check if code contains any integers. If no, its a species group type code. Get the requested species code.
    IF translate(eta_ess_pc, '0123456789', '') = eta_ess_pc THEN
      sp_code = substring(eta_ess_pc, (species_number::int * 2) - 1, 2);
    ELSE
	  -- If the code contains numbers, parse them out in order using code_to_reordered_array, then grab the requested code and drop the percent value.
      code_array = TT_qc_prg5_species_code_to_reordered_array(eta_ess_pc);
      sp_code = translate(code_array[species_number::int], '0123456789', '');
    END IF;
	
    IF sp_code IS NULL OR sp_code = '' THEN
      RETURN NULL;
    ELSE
      RETURN sp_code;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg5_species_per_translation
--
-- eta_ess_pc text,
-- species_number text
--
-- First checks if the code is a species group code (e.g. FXFN) which have no percent values.
  -- If it is, return the following percentages based on length of code and requested species:
  -- if 3 species groups (length is 6), return percent's as 35%, 35%, 30%
  -- if 2 species groups (length is 4), return percent's as 65%, 35%
  -- if 1 species group (length is 2), return percent as 100%
-- If not, it is a normal code with species percent values (e.g. BF1BS9).
-- Runs TT_qc_prg5_species_code_to_reordered_array then gets the percent value from the requested position.
  -- If it's 0 return 100, if <10 multiply by 10 (these are both specific to QC07).
  -- Otherwise just return the value (for QC05).
--
-- e.g. TT_qc_prg5_species_per_translation('BS20WS60TA20', 1) would return 60.

------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg5_species_per_translation(text, text);
CREATE OR REPLACE FUNCTION TT_qc_prg5_species_per_translation(
  eta_ess_pc text,
  species_number text
)
RETURNS int AS $$
  DECLARE
    code_array text[];
    per int;
  BEGIN
    -- check if code contains any integers. If no, its a species group type code.
    IF translate(eta_ess_pc, '0123456789', '') = eta_ess_pc THEN
      RETURN CASE
               WHEN LENGTH(eta_ess_pc) = 2 AND species_number = '1' THEN 100
               WHEN LENGTH(eta_ess_pc) = 4 AND species_number = '1' THEN 65
               WHEN LENGTH(eta_ess_pc) = 4 AND species_number = '2' THEN 35
               WHEN LENGTH(eta_ess_pc) = 6 AND species_number = '1' THEN 35
               WHEN LENGTH(eta_ess_pc) = 6 AND species_number = '2' THEN 35
               WHEN LENGTH(eta_ess_pc) = 6 AND species_number = '3' THEN 30
               ELSE NULL
             END;
    ELSE
      code_array = TT_qc_prg5_species_code_to_reordered_array(eta_ess_pc);
      per = regexp_replace(code_array[species_number::int], '[[:alpha:]]', '', 'g')::int;
    
      -- for qc07, percent values need to be multiplied by 10. Any zero values in QC07 represent
      -- 100%. Catch those first.
      RETURN CASE WHEN per = 0 THEN 100 -- qc07
                  WHEN per < 10 THEN per*10 -- qc07
    			        ELSE per
             END; -- qc05
    END IF;		
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg4_species_per_translation
--
-- gr_ess text,
-- species_number text
--
-- For QC fourth inventory, species are coded in gr_ess column. If only one species (code length = 2)
-- then percent is 100%. If species is doubled (e.g. FXFX) then species 1 is 100%, species 2 is null.
-- If 2 species (code length =4) and not doubled then species 1 is 65% and 2 is 35%. If three species
-- (code length is 6) then species 1 is 37%, 2 is 33% and 3 is 30%.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg4_species_per_translation(text, text);
CREATE OR REPLACE FUNCTION TT_qc_prg4_species_per_translation(
  gr_ess text,
  species_number text
)
RETURNS int AS $$
  DECLARE
    _species_number int := species_number::int;
    _gr_ess text;
  BEGIN
  
    -- if gr_ess starts with a double species code, it should only be one species. Remove the first two characters.
    IF NOT TT_qc_prg4_not_double_species_validation(gr_ess) THEN
      _gr_ess = substring(gr_ess, 3, 4);
    ELSE
      _gr_ess = gr_ess;
    END IF;
  
    -- translate the gr_ess code according to length of gr_ess and position
    IF LENGTH(_gr_ess) = 2 THEN
      IF _species_number = 1 THEN
        RETURN 100;
      ELSE
        RETURN NULL;
      END IF;
  
    ELSIF LENGTH(_gr_ess) = 4 THEN    
      IF _species_number = 1 THEN
        RETURN 65;
      ELSIF _species_number = 2 THEN
        RETURN 35;
      ELSE
        RETURN NULL;
      END IF;
  
    ELSIF LENGTH(_gr_ess) = 6 THEN
      IF _species_number = 1 THEN
        RETURN 37;
      ELSIF _species_number = 2 THEN
        RETURN 33;
      ELSIF _species_number = 3 THEN
        RETURN 30;
      ELSE
        RETURN NULL;
      END IF;
    ELSE
      RETURN NULL;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_crown_closure_upper_translation
--
-- stand_id text,
-- working_group text,
-- density_code
--
-- If commercial forest run mapInt(density_code, {1,2,3}, {50,75,100})
-- If non-commercial forest run: mapInt(density_code, {1,2,3,4}, {25,50,75,100})
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_crown_closure_upper_translation(text, text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_crown_closure_upper_translation(
  stand_id text,
  working_group text,
  density_code text
)
RETURNS int AS $$
  BEGIN
    IF TT_nl_nli01_isCommercial(stand_id, working_group) THEN
      RETURN TT_mapInt(density_code, '{''1'',''2'',''3''}', '{''50'',''75'',''100''}');
    ELSIF TT_nl_nli01_isNonCommercial(stand_id, working_group) THEN
      RETURN TT_mapInt(density_code, '{''1'',''2'',''3'',''4''}', '{''25'',''50'',''75'',''100''}');
    ELSE
      RETURN NULL;
    END IF;  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_crown_closure_lower_translation
--
-- stand_id text,
-- working_group text,
-- density_code
--
-- If commercial forest run: mapInt(density_code, {1,2,3}, {26,51,76})
-- If non-commercial forest run: mapInt(density_code, {1,2,3,4}, {10,26,51,76})
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_crown_closure_lower_translation(text, text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_crown_closure_lower_translation(
  stand_id text,
  working_group text,
  density_code text
)
RETURNS int AS $$
  BEGIN
    IF TT_nl_nli01_isCommercial(stand_id, working_group) THEN
      RETURN TT_mapInt(density_code, '{''1'',''2'',''3''}', '{''26'',''51'',''76''}');
    ELSIF TT_nl_nli01_isNonCommercial(stand_id, working_group) THEN
      RETURN TT_mapInt(density_code, '{''1'',''2'',''3'',''4''}', '{''10'',''26'',''51'',''76''}');
    ELSE
      RETURN NULL;
    END IF;  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_height_upper_translation
--
-- stand_id text,
-- working_group text,
-- height_class
--
-- If commercial forest run TT_mapInt(height_class, {1,2,3,4,5,6,7,8}, {3.5,6.5,9.5,12.5,15.5,18.5,21.5,100})
-- If non-commercial forest run: TT_mapInt(height_class, {1,2,3,4,5}, {3.5,6.5,9.5,12.5,15.5})
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_height_upper_translation(text, text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_height_upper_translation(
  stand_id text,
  working_group text,
  height_class text
)
RETURNS double precision AS $$
  BEGIN
    IF TT_nl_nli01_isCommercial(stand_id, working_group) THEN
      RETURN TT_mapDouble(height_class, '{''1'',''2'',''3'',''4'',''5'',''6'',''7'',''8''}', '{''3.5'',''6.5'',''9.5'',''12.5'',''15.5'',''18.5'',''21.5'',''100''}');
    ELSIF TT_nl_nli01_isNonCommercial(stand_id, working_group) THEN
      RETURN TT_mapDouble(height_class, '{''1'',''2'',''3'',''4'',''5''}', '{''3.5'',''6.5'',''9.5'',''12.5'',''15.5''}');
    ELSE
      RETURN NULL;
    END IF;  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_height_lower_translation
--
-- stand_id text,
-- working_group text,
-- height_class
--
-- If commercial forest run: TT_mapInt(height_class, {1,2,3,4,5,6,7,8}, {0,3.6,6.6,9.6,12.6,15.6,18.6,21.6})
-- If non-commercial forest run: TT_mapInt(height_class, {1,2,3,4,5}, {0,3.6,6.6,9.6,12.6})
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_height_lower_translation(text, text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_height_lower_translation(
  stand_id text,
  working_group text,
  height_class text
)
RETURNS double precision AS $$
  BEGIN
    IF TT_nl_nli01_isCommercial(stand_id, working_group) THEN
      RETURN TT_mapDouble(height_class, '{''1'',''2'',''3'',''4'',''5'',''6'',''7'',''8''}', '{''0'',''3.6'',''6.6'',''9.6'',''12.6'',''15.6'',''18.6'',''21.6''}');
    ELSIF TT_nl_nli01_isNonCommercial(stand_id, working_group) THEN
      RETURN TT_mapDouble(height_class, '{''1'',''2'',''3'',''4'',''5''}', '{''0'',''3.6'',''6.6'',''9.6'',''12.6''}');
    ELSE
      RETURN NULL;
    END IF;  
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_productivity_translation
--
-- stand_id text,
-- working_group text
--
-- If commercial return PRODUCTIVE_FOREST, if non-commercial return NON_PRODUCTIVE_FOREST
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_productivity_translation(text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_productivity_translation(
  stand_id text,
  working_group text
)
RETURNS text AS $$
  BEGIN
    IF TT_nl_nli01_isCommercial(stand_id, working_group) THEN
      RETURN 'PRODUCTIVE_FOREST';
    ELSIF TT_nl_nli01_isNonCommercial(stand_id, working_group) THEN
      RETURN 'NON_PRODUCTIVE_FOREST';
    ELSE
      RETURN NULL;
    END IF;    
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_productivity_type_translation
--
-- stand_id text,
-- working_group text
--
-- If commercial, return HARVESTABLE, if non-commercial return SCRUB_SHRUB, if treed bog return TREED_MUSKEG.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_productivity_type_translation(text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_productivity_type_translation(
  stand_id text,
  working_group text
)
RETURNS text AS $$
  BEGIN
    IF stand_id = '930' THEN
      RETURN 'TREED_MUSKEG';
    ELSIF TT_nl_nli01_isCommercial(stand_id, working_group) THEN
      RETURN 'HARVESTABLE';
    ELSIF TT_nl_nli01_isNonCommercial(stand_id, working_group) THEN
      RETURN 'SCRUB_SHRUB';
    ELSE
      RETURN NULL;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_origin_upper_translation(text, text)
--
-- age_class text,
-- src_filename text
-- the_geom text
--
-- NL map units have values 1 - 180, Labrador map units are 238 - 415
-- Origin translation is different for Newfoundland and Labrador
-- Figure out which area the row is from and use the correct translation
-- to get the upper bound of age range. Then subtract this from the photo
-- year to get origin upper.
-- photo year is calculated by intersecting with the photo year map.

------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_origin_upper_translation(text, text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_origin_upper_translation(
  age_class text,
  src_filename text,
  the_geom text
)
RETURNS int AS $$
  DECLARE
    map_unit_int int;
    photo_year int;
    age int;
  BEGIN
    map_unit_int = substring(src_filename, 3,3)::int;
    photo_year = TT_geoIntersectionInt(the_geom, 'rawfri', 'nl_photoyear', 'wkb_geometry', 'photoyear', 'GREATEST_AREA');
  
    IF map_unit_int > 0 AND map_unit_int <=180 THEN
      age = TT_mapText(age_class, '{''1'',''2'',''3'',''4'',''5'',''6'',''7''}', '{''0'',''21'',''41'',''61'',''81'',''101'',''121''}')::int; -- Newfoundland
    ELSIF map_unit_int >= 238 AND map_unit_int <= 415 THEN
      age = TT_mapText(age_class, '{''1'',''2'',''3'',''4'',''5'',''6'',''7'',''8'',''9''}', '{''0'',''21'',''41'',''61'',''81'',''101'',''121'',''141'',''161''}')::int; -- Labrador
    ELSE
      RETURN NULL;
    END IF;
  
    RETURN photo_year - age;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_origin_lower_translation
--
-- age_class text,
-- src_filename text
-- the_geom text
--
-- NL map units have values 1 - 180, Labrador map units are 238 - 415
-- Origin translation is different for Newfoundland and Labrador
-- Figure out which area the row is from and use the correct translation
-- to get the upper bound of age range. Then subtract this from the photo
-- year to get origin upper.
-- photo year is calculated by intersecting with the photo year map.

------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_origin_lower_translation(text, text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_origin_lower_translation(
  age_class text,
  src_filename text,
  the_geom text
)
RETURNS int AS $$
  DECLARE
    map_unit_int int;
    photo_year int;
    age int;
  BEGIN
    map_unit_int = substring(src_filename, 3,3)::int;
    photo_year = TT_geoIntersectionInt(the_geom, 'rawfri', 'nl_photoyear', 'wkb_geometry', 'photoyear', 'GREATEST_AREA');
  
    -- don't return the last values of 7 and 9 because the upper age is not defined, therefore lower origin is unknown_value. Catch these with validation.
    IF map_unit_int > 0 AND map_unit_int <=180 THEN
      age = TT_mapText(age_class, '{''1'',''2'',''3'',''4'',''5'',''6''}', '{''20'',''40'',''60'',''80'',''100'',''120''}')::int; -- Newfoundland
    ELSIF map_unit_int >= 238 AND map_unit_int <= 415 THEN
      age = TT_mapText(age_class, '{''1'',''2'',''3'',''4'',''5'',''6'',''7'',''8''}', '{''20'',''40'',''60'',''80'',''100'',''120'',''140'',''160''}')::int; -- Labrador
    ELSE
      RETURN NULL;
    END IF;
  
    RETURN photo_year - age;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_origin_translation
--
-- cl_age text
-- an_pro_ori text
--
-- Get the age value from the lookup table based on the cl_age code.
-- Subtract the age from the an_pro_ori year to get origin.
-- Same value for origin upper and lower.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_origin_translation(text, text);
CREATE OR REPLACE FUNCTION TT_qc_origin_translation(
  age text,
  an_pro_ori text
)
RETURNS int AS $$
  SELECT an_pro_ori::int - age::int;
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_countOfNotNull
--
-- lyr_layers text - lyr layer from qc_standstructure_lookup table
-- nfl text - nfl code
-- max_rank_to_consider text
--
-- Lookup the number of LYR layers using the translation.qc_standstructure_lookup table
-- Assign variables so these layers can be counter.
--
-- Determine if the row contains an NFL record. If it does assign a string
-- so it can be counted as a non-null layer.
--
-- Pass LYR and NFL variables to countOfNotNull().
-- Used for prg3 and 4.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_countOfNotNull(text, text, text);
CREATE OR REPLACE FUNCTION TT_qc_countOfNotNull(
  lyr_layers text,
  nfl text,
  max_rank_to_consider text
)
RETURNS int AS $$
  DECLARE
    is_lyr1 text;
    is_lyr2 text;
    is_nfl text;
  BEGIN
    -- assign lyr 1 and 2
    CASE
      WHEN lyr_layers = '1' THEN
        is_lyr1 = 'a_value';
        is_lyr2 = NULL::text;
      WHEN lyr_layers = '2' THEN
        is_lyr1 = 'a_value';
        is_lyr2 = 'a_value';
      ELSE
        is_lyr1 = NULL::text;
        is_lyr2 = NULL::text;
    END CASE;

    -- if any of the nfl functions return true, we know there is an NFL record.
    -- set is_nfl to be a valid string.
    IF TT_matchList(nfl,'{''BAT'',''DS'',''EAU'',''ILE'',''INO'',''A'',''AEP'',''AER'',''AF'',''ANT'',''BAS'',''CFO'',''CU'',''DEF'',''DEP'',''GR'',''HAB'',''LTE'',''MI'',''NF'',''RO'',''US'',''VIL'',''AL'',''DH'',''NX'',''BHE'',''BLE'',''CAM'',''CAR'',''CEX'',''CHE'',''CIM'',''CNE'',''CS'',''CV'',''DEM'',''GOL'',''PIC'',''PPN'',''QUA'',''SC'',''TOE'',''VRG'',''IMP'',''OBS'',''PAI''}') THEN
      is_nfl = 'a_value';
    ELSE
      is_nfl = NULL::text;
    END IF;
  
    -- call countOfNotNull
    RETURN TT_countOfNotNull(is_lyr1, is_lyr2, is_nfl, max_rank_to_consider, 'FALSE');
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_lyr_layer_translation
--
-- heights stringlist - list of heights to order layers by
-- layer1/2/3/4/5spp stringlist - list of layer 1/2/3/4/5 species to test for notNull
-- getIndex - the index of the initial height stringlist to be returned from the reordered list
--
-- If getIndex is 1, return the position of the first height value (corresponding to layer1spp)
-- after reordering the heights and removing and heights corresponding to FALSE layer*spp tests.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_lyr_layer_translation(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_lyr_layer_translation(
  heights text,
  layer1spp text,
  layer2spp text,
  layer3spp text,
  layer4spp text,
  layer5spp text,
  getIndex text,
  layerCount text
)
RETURNS int AS $$
  DECLARE
    _heights double precision[];
    _getIndex int;
    testArray int[];
    heightArray double precision[];
    testArrayOrdered int[];
    _layerCount int := layerCount::int;
  BEGIN
	  -- Validate source values (return NULL)
    IF TT_NotNull(heights) AND NOT TT_IsStringList(heights) OR
       TT_NotNull(layer1spp) AND NOT TT_IsStringList(layer1spp) OR
       TT_NotNull(layer2spp) AND NOT TT_IsStringList(layer2spp) OR
       TT_NotNull(layer3spp) AND NOT TT_IsStringList(layer3spp) OR
       TT_NotNull(layer4spp) AND NOT TT_IsStringList(layer4spp) OR
       TT_NotNull(layer5spp) AND NOT TT_IsStringList(layer5spp) THEN
      RETURN NULL;
    END IF;
	
    -- cast all variables
    _heights = TT_ParseStringList(heights, TRUE);
    _getIndex = getIndex::int;
  
    -- set any null heights to zero, if species are present the layer will reported as the lowest
    _heights = array_replace(_heights, null::double precision, 0::double precision);
  
    -- check length of heights matches length of testArray
    IF NOT array_length(_heights, 1) = _layerCount THEN
      RETURN NULL;
    END IF;
  
    -- test for layer presence using species stringlists
    -- if layer is present, add its index to testArray, and add the corresponding height to heightArray
    IF TT_notEmpty(layer1spp, 'TRUE') THEN
      testArray = array_append(testArray, 1);
      heightArray = array_append(heightArray, _heights[1]);
    END IF;
  
    IF TT_notEmpty(layer2spp, 'TRUE') THEN
      testArray = array_append(testArray, 2);
      heightArray = array_append(heightArray, _heights[2]);
    END IF;

    IF TT_notEmpty(layer3spp, 'TRUE') THEN
      testArray = array_append(testArray, 3);
      heightArray = array_append(heightArray, _heights[3]);
    END IF;

    IF TT_notEmpty(layer4spp, 'TRUE') THEN
      testArray = array_append(testArray, 4);
      heightArray = array_append(heightArray, _heights[4]);
    END IF;

    IF TT_notEmpty(layer5spp, 'TRUE') THEN
      testArray = array_append(testArray, 5);
      heightArray = array_append(heightArray, _heights[5]);
    END IF;
  
    -- reorder the testArray by the height array. In the case of ties, maintain the original layer order.
    testArrayOrdered = ARRAY( -- converts table to array
      SELECT layer FROM(
        SELECT a height, b layer
        FROM unnest(
          heightArray,
          testArray
        ) AS t(a,b) -- converts arrays to a table
        ORDER BY height desc, layer asc -- order by height, ties are ordered by their original order in the string
      ) x
    );
	
	-- return the position in the reordered array of the getIndex value (aka the layer being translated)
	RETURN array_position(testArrayOrdered, _getIndex);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION TT_lyr_layer_translation(
  heights text,
  layer1spp text,
  layer2spp text,
  layer3spp text,
  layer4spp text,
  layer5spp text,
  getIndex text
)
RETURNS int AS $$
  SELECT TT_lyr_layer_translation(heights, layer1spp, layer2spp, layer3spp, layer4spp, layer5spp, getIndex, '5');
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION TT_lyr_layer_translation(
  heights text,
  layer1spp text,
  layer2spp text,
  layer3spp text,
  layer4spp text,
  getIndex text
)
RETURNS int AS $$
  SELECT TT_lyr_layer_translation(heights, layer1spp, layer2spp, layer3spp, layer4spp, NULL::text, getIndex, '4');
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION TT_lyr_layer_translation(
  heights text,
  layer1spp text,
  layer2spp text,
  layer3spp text,
  getIndex text
)
RETURNS int AS $$
  SELECT TT_lyr_layer_translation(heights, layer1spp, layer2spp, layer3spp, NULL::text, NULL::text, getIndex, '3');
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION TT_lyr_layer_translation(
  heights text,
  layer1spp text,
  layer2spp text,
  getIndex text
)
RETURNS int AS $$
  SELECT TT_lyr_layer_translation(heights, layer1spp, layer2spp, NULL::text, NULL::text, NULL::text, getIndex, '2');
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nb_lyr_layer_translation
--
-- heights
-- l1_species
-- l2_species
-- getIndex
-- productivity
--
-- If productivity is a non-productive type (FW), then set l1_species to a string.
-- Then run lyr_layer_translation as normal.
-- This creates a layer for l1_species when FW is present. Since species never occur
-- when productivity is FW, any FW values should always be layer 1.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nb_lyr_layer_translation(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_nb_lyr_layer_translation(
  heights text,
  l1_species text,
  l2_species text,
  productivity text,
  getIndex text
)
RETURNS int AS $$
  BEGIN
    IF upper(productivity) = 'FW' THEN
      l1_species = 'a_string';
    END IF;
  
    RETURN TT_lyr_layer_translation(heights, l1_species, l2_species, getIndex);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_ns_lyr_layer_translation
--
-- heights
-- l1_species
-- l2_species
-- getIndex
-- productivity
--
-- If productivity is a non-productive type (FW), then set l1_species to a string.
-- Then run lyr_layer_translation as normal.
-- This creates a layer for l1_species when FW is present. Since species never occur
-- when productivity is FW, any FW values should always be layer 1.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ns_lyr_layer_translation(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_ns_lyr_layer_translation(
  heights text,
  l1_species text,
  l2_species text,
  productivity text,
  getIndex text
)
RETURNS int AS $$
  BEGIN  
    IF productivity IN('33','38','39','73') THEN
      l1_species = 'a_string';
    END IF;
  
    RETURN TT_lyr_layer_translation(heights, l1_species, l2_species, getIndex);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_on_lyr_layer_translation
--
-- heights
-- l1_species
-- l2_species
-- getIndex
-- productivity
--
-- If productivity is a non-productive type (BSH, TMS), then set l1_species to a string.
-- Then run lyr_layer_translation as normal.
-- This creates a layer for l1_species when BSH or TMS is present. Since species never occur
-- when productivity is BSH or TMS, any BSH or TMS values should always be layer 1.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_on_lyr_layer_translation(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_on_lyr_layer_translation(
  heights text,
  l1_species text,
  l2_species text,
  productivity text,
  getIndex text
)
RETURNS int AS $$
  BEGIN
    IF productivity IN ('BSH', 'TMS') THEN
      l1_species = 'a_string';
    END IF;
  
    RETURN TT_lyr_layer_translation(heights, l1_species, l2_species, getIndex);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sk_sfvi_lyr_layer_translation
--
-- heights
-- l1_species
-- l2_species
-- getIndex
-- productivity
--
-- If productivity is a non-productive type (BSH, TMS), then set l1_species to a string.
-- Then run lyr_layer_translation as normal.
-- This creates a layer for l1_species when BSH or TMS is present.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_sk_sfvi_lyr_layer_translation(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_sk_sfvi_lyr_layer_translation(
  heights text,
  l1_species text,
  l2_species text,
  l3_species text,
  productivity text,
  getIndex text
)
RETURNS int AS $$
  BEGIN
    IF productivity IN ('BSH', 'TMS') THEN
      l1_species = 'a_string';
    END IF;
	
    RETURN TT_lyr_layer_translation(heights, l1_species, l2_species, l3_species, getIndex);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nt_lyr_layer_translation
--
-- typeclas_nonveg
-- typeclas_anth
-- typeclas
-- mintypeclas
-- heights
-- l1_species
-- l2_species
-- getIndex
--
-- Test if layer 1 and 2 contain species (i.e. not NFL and have species values)
-- If yes, order by height.
-- If no, whichever layer has species gets reported as layer 1.
-- This prevents the situation where LYR layers are ordered incorectly because some
-- non-forest rows have species and height info (e.g. shrub rows that are reported as NFL layers)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nt_lyr_layer_translation(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_nt_lyr_layer_translation(
  typeclas_nonveg text,
  typeclas_anth text, 
  typeclas text,
  mintypeclas text,
  heights text,
  l1_species text,
  l2_species text,
  getIndex text
)
RETURNS int AS $$
  DECLARE
    nfl_string_list text[];
	lyr1 boolean;
	lyr2 boolean;
  BEGIN
  
    nfl_string_list = ARRAY['BE','BR','BU','CB','ES','LA','LL','LS','MO','MU','PO','RE','RI','RO','RS','RT','SW','AP','BP','EL','GP','TS','RD','SH','SU','PM','BL','BM','BY','HE','HF','HG','SL','ST'];
	
	-- layer 1 present if species have values and typeclas is either null, or a non-nfl value
	IF TT_notEmpty(l1_species, 'TRUE') THEN
	  IF NOT COALESCE(typeclas,'NULL') = ANY(nfl_string_list) AND NOT COALESCE(typeclas_nonveg,'NULL') = ANY(nfl_string_list) AND NOT COALESCE(typeclas_anth,'NULL') = ANY(nfl_string_list) THEN
        lyr1 = TRUE; -- species present, typeclas NULL or not NFL
	  ELSE
	    lyr1 = FALSE; -- species present, typeclas is NFL
	  END IF;
	ELSE
	  lyr1 = FALSE; -- species not present
	END IF;
	
	-- repeat for species 2
	IF TT_notEmpty(l2_species, 'TRUE') THEN
	  IF NOT COALESCE(mintypeclas,'NULL') = ANY(nfl_string_list) AND NOT COALESCE(typeclas_nonveg,'NULL') = ANY(nfl_string_list) AND NOT COALESCE(typeclas_anth,'NULL') = ANY(nfl_string_list) THEN
        lyr2 = TRUE; -- species present, mintypeclas NULL or not NFL
	  ELSE
	    lyr2 = FALSE; -- species present, mintypeclas is NFL
	  END IF;
	ELSE
	  lyr2 = FALSE; -- species not present
	END IF;
    -- if 2 lyr layers order by height
    IF lyr1 AND lyr2 THEN
      RETURN TT_lyr_layer_translation(heights, l1_species, l2_species, getIndex);
    END IF;
    
	-- otherwise the layer present has to be layer 1 
    IF lyr1 THEN
      RETURN 1;
    END IF;
	
	IF lyr2 THEN
      RETURN 1;
    END IF;
	
	RETURN NULL;
    
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_bc_lyr_layer_translation
--
-- l1_proj_height_1
-- l1_proj_height_2
-- l1_species_pct_1
-- l1_species_pct_2
-- l2_proj_height_1
-- l2_proj_height_2
-- l2_species_pct_1
-- l2_species_pct_2
-- layer1/2/3/4/5spp stringlist - list of layer 1/2/3/4/5 species to test for notNull
-- getIndex - the index of the initial height stringlist to be returned from the reordered list
--
-- Calculates weighted average height using bc_height function, passes heights as string list to lyr_layer_translation()
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_bc_lyr_layer_translation(text, text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_bc_lyr_layer_translation(
  l1_proj_height_1 text,
  l1_proj_height_2 text,
  l1_species_pct_1 text,
  l1_species_pct_2 text,
  l2_proj_height_1 text,
  l2_proj_height_2 text,
  l2_species_pct_1 text,
  l2_species_pct_2 text,
  layer1spp text,
  layer2spp text,
  getIndex text
)
RETURNS int AS $$
  DECLARE
    height1 double precision;
	height2 double precision;
    heights text;
  BEGIN
    height1 = TT_bc_height(l1_proj_height_1, l1_proj_height_2, l1_species_pct_1, l1_species_pct_2);
    height2 = TT_bc_height(l2_proj_height_1, l2_proj_height_2, l2_species_pct_1, l2_species_pct_2);
    heights = TT_repackStringList(ARRAY[height1::text, height2::text]);
	
    RETURN TT_lyr_layer_translation(heights, layer1spp, layer2spp, getIndex);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_ab_avi01_wetland_translation
--
-- Assign 4 letter wetland character code, then return the requested character (1-4)
--
-- e.g. TT_ab_avi01_wetland_translation(landtype, per1, '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ab_avi01_wetland_translation(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_ab_avi01_wetland_translation(
  moisture text,
  nonfor_veg text,
  nat_nonveg text,
  sp1 text,
  sp2 text,
  crownclose text,
  sp1_percnt text,
  ret_char text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_ab_avi01_wetland_code(moisture, nonfor_veg, nat_nonveg, sp1, sp2, crownclose, sp1_percnt);
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(_wetland_code, ret_char);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nl_nli01_wetland_translation
--
-- Assign 4 letter wetland character code, then return the requested character (1-4)
--
-- e.g. TT_nl_nli01_wetland_translation(landtype, per1, '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nl_nli01_wetland_translation(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_nl_nli01_wetland_translation(
  stand_id text,
  site text,
  species_comp text,
  ret_char text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_nl_nli01_wetland_code(stand_id, site, species_comp);
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(_wetland_code, ret_char);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_bc_vri01_wetland_translation
--
-- Assign 4 letter wetland character code, then return the requested character (1-4)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_bc_vri01_wetland_translation(text, text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_bc_vri01_wetland_translation(
  inventory_standard_cd text,
  l1_species_cd_1 text,
  l1_species_pct_1 text,
  l1_species_cd_2 text,
  non_productive_descriptor_cd text,
  l1_non_forest_descriptor text,
  land_cover_class_cd_1 text,
  soil_moisture_regime_1 text,
  l1_crown_closure text,
  l1_proj_height_1 text,
  ret_char_pos text
)
RETURNS text AS $$
  DECLARE
	wetland_code text;
  BEGIN
    wetland_code = TT_bc_vri01_wetland_code(inventory_standard_cd, l1_species_cd_1, l1_species_pct_1, l1_species_cd_2, non_productive_descriptor_cd, l1_non_forest_descriptor, land_cover_class_cd_1, soil_moisture_regime_1, l1_crown_closure, l1_proj_height_1);
    IF wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(wetland_code, ret_char_pos);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_ns_nsi01_wetland_translation
--
-- Assign 4 letter wetland character code, then return the requested character (1-4)
--
-- e.g. TT_nsi01_wetland_translation(landtype, per1, '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ns_nsi01_wetland_translation(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_ns_nsi01_wetland_translation(
  fornon text,
  species text,
  crncl text,
  height text,
  ret_char text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_ns_nsi01_wetland_code(fornon, species, crncl, height);
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(_wetland_code, ret_char);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pe_pei01_wetland_translation
--
-- Assign 4 letter wetland character code, then return the requested character (1-4)
-- e.g. TT_pe_pei01_wetland_translation(landtype, per1, 999, 999, 999, 999, '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_pe_pei01_wetland_translation(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_pe_pei01_wetland_translation(
  landtype text,
  per1 text,
  landtype2 text,
  per2 text,
  landtype3 text,
  per3 text,
  ret_char_pos text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
	_wetland_code = TT_pe_pei01_wetland_code(landtype, per1, landtype2, per2, landtype3, per3);
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(_wetland_code, ret_char_pos);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nt_fvi01_wetland_translation
--
-- Assign 4 letter wetland character code, then return the requested character (1-4)
--
-- e.g. TT_nt_fvi01_wetland_translation(landpos, structur, moisture, typeclas, mintypeclas, sp1, sp2, sp1_per, crownclos, height, wetland, '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nt_fvi01_wetland_translation(text, text, text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_nt_fvi01_wetland_translation(
	landpos text,
	structur text,
	moisture text,
	typeclas text,
	mintypeclas text,
	sp1 text,
	sp2 text,
	sp1_per text,
	crownclos text,
	height text,
	wetland text,
    ret_char text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_nt_fvi01_wetland_code(landpos, structur, moisture, typeclas, mintypeclas, sp1, sp2, sp1_per, crownclos, height, wetland);
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(_wetland_code, ret_char);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pc01_species_per_translation
--
-- Return the requested percent value based on the following rules:
-- If 1 species, species_per = 100%
-- If 2 species and species are pine (PB) and black spruce (PM), species_per 1st=60% and 2nd=40%
-- If 2 species with any other combinations, species_per 1st=70% and 2nd=30%
-- If 3 species, any combination, species_per 1st=50%, 2nd=30% and 3rd=20%
--
-- e.g. TT_pc01_species_per_translation(val, '1')
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_pc01_species_per_translation(text, text);
CREATE OR REPLACE FUNCTION TT_pc01_species_per_translation(
	val text,
	speciesNumber text
)
RETURNS int AS $$
  DECLARE
	  _length int;
  BEGIN
  
	  IF val IS NULL THEN
	    RETURN NULL;
	  END IF;
	
	  _length = LENGTH(val);
	
    RETURN CASE
             WHEN _length = 2 AND speciesNumber = '1' THEN 100
             WHEN _length = 4 AND val IN('PBPM', 'PMPB') AND speciesNumber = '1' THEN 60
             WHEN _length = 4 AND val IN('PBPM', 'PMPB') AND speciesNumber = '2' THEN 40
             WHEN _length = 4 AND speciesNumber = '1' THEN 70
             WHEN _length = 4 AND speciesNumber = '2' THEN 30
             WHEN _length = 6 AND speciesNumber = '1' THEN 50
             WHEN _length = 6 AND speciesNumber = '2' THEN 30
             WHEN _length = 6 AND speciesNumber = '3' THEN 20
             ELSE NULL
           END;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sk_utm01_wetland_translation
--
-- Assign 4 letter wetland character code, then return the requested character (1-4)
--
-- e.g. TT_sk_utm01_wetland_translation(drain, sp10, sp11, sp12, sp20, sp21, d, np, soil_text, retCharPos)
------------------------------------------------------------
CREATE OR REPLACE FUNCTION TT_sk_utm01_wetland_translation(
  drain text,
  sp10 text,
  sp11 text,
  sp12 text,
  sp20 text,
  sp21 text,
  d text,
  np text,
  soil_text text,
  retCharPos text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_sk_utm01_wetland_code(drain, sp10, sp11, sp12, sp20, sp21, d, np, soil_text);
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(_wetland_code, retCharPos);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_ab_photo_year_translation
--
-- AB inventories pre AB25 need to intersect with the photo year table to get photo year.
-- Post AB25 inventories have a photo year column so just return it.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_ab_photo_year_translation(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_ab_photo_year_translation(
  inventoryID text,
  wkbGeometry text,
  lookupSchema text,
  lookupTable text,
  lookupCol text,
  returnCol text,
  photoYear text,
  data_yr text
)
RETURNS int AS $$
  BEGIN
    -- for inventories without photoyear information, run geoIntersection
    IF TT_notNull(photoYear) IS FALSE AND data_yr = '0' THEN
      RETURN TT_geoIntersectionInt(wkbGeometry, lookupSchema, lookupTable, lookupCol, returnCol, 'GREATEST_AREA');
    -- for inventories with data acquisition information, run copyInt()
    ELSIF TT_notNull(photoYear) IS FALSE AND data_yr != '0' THEN
	  RETURN TT_copyInt(data_yr);
   -- for inventories with photoyear information, run copyInt
    ELSE
      RETURN TT_copyInt(photoYear);
    END IF;
  END;
$$ LANGUAGE plpgsql STABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_sk_sfv01_wetland_translation
--
-- Assign 4 letter wetland character code, then return the requested character (1-4)
--
-- e.g. TT_sk_sfv01_wetland_translation(text, text, text, text, text, text, text, text, text, text)
------------------------------------------------------------
CREATE OR REPLACE FUNCTION TT_sk_sfv01_wetland_translation(
  soil_moist_reg text,
  species_1 text,
  species_2 text,
  species_per_1 text,
  crown_closure text,
  height text,
  shrub1 text,
  herb1 text,
  shrubs_crown_closure text,
  retCharPos text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_sk_sfv01_wetland_code(soil_moist_reg, species_1, species_2, species_per_1, crown_closure, height, shrub1, herb1, shrubs_crown_closure);
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(_wetland_code, retCharPos);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_mb_fli01_wetland_validation
--
-- Assign 4 letter wetland character code and check value matches expected values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_mb_fli01_wetland_translation(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_mb_fli01_wetland_translation(
  landmod text,
  weteco1 text,
  sp1 text,
  sp2 text,
  sp1per text,
  cc text,
  ht text,
  retCharPos text
  )
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_mb_fli01_wetland_code(landmod, weteco1, sp1, sp2, sp1per, cc, ht);
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(_wetland_code, retCharPos);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_mb_fri01_wetland_translation
--
-- Assign 4 letter wetland character code and check value matches expected values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_mb_fri01_wetland_translation(text, text, text);
CREATE OR REPLACE FUNCTION TT_mb_fri01_wetland_translation(
  productivity text,
  subtype text,
  retCharPos text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_mb_fri01_wetland_code(productivity, subtype);
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(_wetland_code, retCharPos);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pc02_wetland_translation
--
-- Assign 4 letter wetland character code and check value matches expected values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_pc02_wetland_translation(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_pc02_wetland_translation(
  v_pcm text,
  v_str text,
  lyr_or_nfl text,
  retCharPos text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_pc02_wetland_code(v_pcm, v_str, lyr_or_nfl);
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(_wetland_code, retCharPos);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_pc02_countOfNotNull
--
-- l1sp text, l2sp text, l3sp text,
-- l4sp text, l5sp text, l6sp text, l7sp text,
-- l8nfl text, l9nfl text, l10nfl text, l11nfl text,
-- l12nfl text, l13nfl text, l14nfl text, l15lake text,
-- lookupSchema text,
-- lookupTable text,
-- lookupCol text,
-- maxRankToConsider text
--
-- Use match list to determine if LYR or NFL values are present.
-- If they are assign them a string so they are counted as layers. If not assign
-- NULL.
--
-- Pass to countOfNotNull().
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_pc02_countOfNotNull(text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_pc02_countOfNotNull(
  l1sp text, l2sp text, l3sp text,
  l4sp text, l5sp text, l6sp text, l7sp text,
  l8nfl text, l9nfl text, l10nfl text, l11nfl text,
  l12nfl text, l13nfl text, l14nfl text, l15lake text,
  lookupSchema text,
  lookupTable text,
  lookupCol text,
  maxRankToConsider text
)
RETURNS int AS $$
  DECLARE
    nfl_string_list text;
    lake_string_list text;
    _lyr1 text;
    _lyr2 text;
    _lyr3 text;
    _lyr4 text;
    _lyr5 text;
    _lyr6 text;
    _lyr7 text;
    _nfl8 text;
    _nfl9 text;
    _nfl10 text;
    _nfl11 text;
    _nfl12 text;
    _nfl13 text;
    _nfl14 text;
    _lake15 text;
  BEGIN
    -- set up string lists
    nfl_string_list = '{''1'', ''2'', ''3'', ''4'', ''5'', ''6'', ''7'', ''13'', ''17'', ''18'', ''98'', ''99''}';
    lake_string_list = '{''Z'', ''U''}';
	
    -- check for all 7 LYR layers
    IF TT_matchTable(l1sp, lookupSchema, lookupTable, lookupCol, 'TRUE'::text) THEN
      _lyr1 = 'lyr1_value';
    END IF;
    IF TT_matchTable(l2sp, lookupSchema, lookupTable, lookupCol, 'TRUE'::text) THEN
      _lyr2 = 'lyr2_value';
    END IF;
    IF TT_matchTable(l3sp, lookupSchema, lookupTable, lookupCol, 'TRUE'::text) THEN
      _lyr3 = 'lyr3_value';
    END IF;
    IF TT_matchTable(l4sp, lookupSchema, lookupTable, lookupCol, 'TRUE'::text) THEN
      _lyr4 = 'lyr4_value';
    END IF;
    IF TT_matchTable(l5sp, lookupSchema, lookupTable, lookupCol, 'TRUE'::text) THEN
      _lyr5 = 'lyr5_value';
    END IF;
    IF TT_matchTable(l6sp, lookupSchema, lookupTable, lookupCol, 'TRUE'::text) THEN
      _lyr6 = 'lyr6_value';
    END IF;
    IF TT_matchTable(l7sp, lookupSchema, lookupTable, lookupCol, 'TRUE'::text) THEN
      _lyr7 = 'lyr7_value';
    END IF;
  
    -- check for all 7 nfl layers
    IF TT_matchList(l8nfl, nfl_string_list) THEN
      _nfl8 = 'lyr8_value';
    END IF;
    IF TT_matchList(l9nfl, nfl_string_list) THEN
      _nfl9 = 'lyr9_value';
    END IF;
    IF TT_matchList(l10nfl, nfl_string_list) THEN
      _nfl10 = 'lyr10_value';
    END IF;
    IF TT_matchList(l11nfl, nfl_string_list) THEN
      _nfl11 = 'lyr11_value';
    END IF;
    IF TT_matchList(l12nfl, nfl_string_list) THEN
      _nfl12 = 'lyr12_value';
    END IF;
    IF TT_matchList(l13nfl, nfl_string_list) THEN
      _nfl13 = 'lyr13_value';
    END IF;
    IF TT_matchList(l14nfl, nfl_string_list) THEN
      _nfl14 = 'lyr14_value';
    END IF;
    
      -- check for lake
    IF TT_matchList(l15lake, lake_string_list) THEN
      _lake15 = 'lyr15_value';
    END IF;
	
    -- call countOfNotNull
    RETURN TT_countOfNotNull(_lyr1, _lyr2, _lyr3, _lyr4, _lyr5, _lyr6, _lyr7, _nfl8, _nfl9, _nfl10, _nfl11, _nfl12, _nfl13, _nfl14, _lake15, maxRankToConsider, 'FALSE');
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yt_wetland_translation
--
-- Assign 4 letter wetland character code and check value matches expected values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yt_wetland_translation(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yt_wetland_translation(
  smr text,
  cc text,
  class_ text,
  sp1 text,
  sp2 text,
  sp1_per text,
  avg_ht text,
  retCharPos text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_yt_wetland_code(smr, cc, class_, sp1, sp2, sp1_per, avg_ht);
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(_wetland_code, retCharPos);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yt04_wetland_translation
--
-- Assign 4 letter wetland character code and check value matches expected values.
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_yt04_wetland_translation(text, text, text, text,text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yt04_wetland_translation(
  smr text,
  cc text,
  class_ text,
  sp1 text,
  sp2 text,
  sp1_per text,
  avg_ht text,
  retCharPos text
)
RETURNS text AS $$
  DECLARE
    _wetland_code text;
  BEGIN
    _wetland_code = TT_yt04_wetland_string_code(smr, cc, class_, sp1, sp2, sp1_per, avg_ht);
    IF _wetland_code IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TT_wetland_code_translation(_wetland_code, retCharPos);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nb_countofnotnull
--
-- Identify any NFL layers. Identify any non-productve LYR layers and set layer1_sp to a string.
-- Pass strings and species to countofnotnull
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nb_countofnotnull(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_nb_countofnotnull(
  layer1_sp text,
  layer2_sp text,
  wc text,
  slu text,
  water_code text,
  maxRankToConsider text
)
RETURNS int AS $$
  DECLARE
	_nfl text;
  BEGIN
    IF wc = 'FW' THEN
      layer1_sp = 'a string';
    END IF;
  
    IF CONCAT(slu, water_code) IN('BL','RF','RO', 'LK', 'RV', 'ON', 'PN', 'SL', 'WA', '4', '6', '7', '8', '9', '100', '416', 'AI','AR','BA','CB','CG','CH','CL','CO','CS','CT','EA','FD','FP','GC','GP','IP','IZ','LE','LF','MI','PA','PB','PP','PR','QU','RD','RR','RU','RY','SG','SK','TM','TR','UR','WR','AQ','415', 'BR','BW','DM','GR','P1','P2','WF', 'BO') THEN
      _nfl = 'a_string';
    ELSE
      _nfl = NULL;
    END IF;
    		
    RETURN TT_countOfNotNull(layer1_sp, layer2_sp, _nfl, maxRankToConsider, 'FALSE');
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_nb_stand_structure_translation
--
-- Return either 'SINGLE_LAYERED' or 'MULTI_LAYERED' depending on count of lyr_all layers
-- If wc = 'FW' then the layer exists
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_nb_stand_structure_translation(text, text, text)
CREATE OR REPLACE FUNCTION TT_nb_stand_structure_translation(
  layer1_sp text,
  layer2_sp text,
  wc text
)
RETURNS text AS $$
  DECLARE
	_nfl text;
  BEGIN
    IF wc = 'FW' THEN
      layer1_sp = 'a string';
    END IF;
		
    RETURN tt_ifElseCountOfNotNullText(layer1_sp, layer2_sp, 2::TEXT, 1::TEXT, 'SINGLE_LAYERED', 'MULTI_LAYERED');
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_qc_prg3_src_inv_area_translation
--
-- If inventory_id is QC01, use divideDouble(src_inv_area, 10000)
-- Else(QC02, QC03, and possibly future datasets using this standrad), use copyDouble(src_inv_area)
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_qc_prg3_src_inv_area_translation(text, text);
CREATE OR REPLACE FUNCTION TT_qc_prg3_src_inv_area_translation(
  inventory_id text,
  src_inv_area text
)
RETURNS double precision AS $$
  BEGIN
    IF inventory_id = 'QC01' THEN
	  RETURN TT_divideDouble(src_inv_area, '10000');
	ELSE
	  RETURN src_inv_area::double precision;
	END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yt_yvi02_disturbance_copyText
--
-- returnList stringList - list of values to return (e.g. disturbance codes)
-- yearList stringList - list of disturbance years
-- layerList text - list of layer assignments ('Entire polygon disturbed', 'Layer 1 disturbance', 'Layer 2 disturbance')
-- layerNumber - 1 or 2
-- indexToReturn - the index to test
-- lst - list to test against
--
-- If layer is 1, remove any disturbances labelled 'Layer 2 disturbance'
-- If layer is 2, remove any disturbances labelled 'Layer 1 disturbance'
-- Order by year, return requested index from returnList
------------------------------------------------------------
-- DROP FUNCTION IF EXISTS TT_yt_yvi02_disturbance_copyText(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yt_yvi02_disturbance_copyText(
  returnList text,
  yearList text,
  layerList text,
  layerNumber text,
  indexToReturn text
)
RETURNS text AS $$
  DECLARE
    _returnList text[];
	_yearList int[];
	_layerList text[];
    _layerArray text[];
  BEGIN
	-- Parse inputs
	_returnList = TT_ParseStringList(returnList, 'TRUE');
	_yearList = TT_ParseStringList(yearList, 'TRUE');
	_layerList = TT_ParseStringList(layerList, 'TRUE');
	
	-- set up layers to filter by
	IF layerNumber = '1' THEN
	  _layerArray = ARRAY['Entire polygon disturbed', 'Layer 1 disturbance']::text[];
	ELSIF layerNumber = '2' THEN
	  _layerArray = ARRAY['Entire polygon disturbed', 'Layer 2 disturbance']::text[];
	ELSE
	  RETURN NULL;
	END IF;
	
	-- run the getIndexMatc hlist code but add in the filter for layer values
    RETURN (ARRAY( -- converts table to array
      SELECT returnVal FROM(
        SELECT a returnVal, b yearVal, c layerVal, a IS NULL::int not_null_order, ROW_NUMBER() OVER () org_order
        FROM unnest(
          _returnList,
          _yearList,
		  _layerList
        ) AS t(a,b,c) -- converts arrays to a table
		WHERE c = ANY(_layerArray) -- filter by the layer assignments
        ORDER BY yearVal, not_null_order, org_order asc -- order by the values, ties are ordered by not null values first, then ordered by their original order in the string
      ) x
    ))[indexToReturn::int];
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yt_yvi02_disturbance_copyInt
--
-- Cast TT_yt_yvi02_disturbance_copyText to int
------------------------------------------------------------
-- DROP FUNCTION IF EXISTS TT_yt_yvi02_disturbance_copyInt(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yt_yvi02_disturbance_copyInt(
  returnList text,
  yearList text,
  layerList text,
  layerNumber text,
  indexToReturn text
)
RETURNS int AS $$
  SELECT TT_yt_yvi02_disturbance_copyText(returnList, yearList, layerList, layerNumber, indexToReturn)::int
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yt_yvi02_disturbance_mapText
--
-- Pass TT_yt_yvi02_disturbance_copyText result to mapText
------------------------------------------------------------
-- DROP FUNCTION IF EXISTS TT_yt_yvi02_disturbance_mapText(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yt_yvi02_disturbance_mapText(
  returnList text,
  yearList text,
  layerList text,
  layerNumber text,
  indexToReturn text,
  srcList text,
  mapList text
)
RETURNS text AS $$
  SELECT TT_mapText(TT_yt_yvi02_disturbance_copyText(returnList, yearList, layerList, layerNumber, indexToReturn), srcList, mapList)
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yt_yvi02_disturbance_matchList
--
-- Pass TT_yt_yvi02_disturbance_copyText result to matchList
------------------------------------------------------------
-- DROP FUNCTION IF EXISTS TT_yt_yvi02_disturbance_matchList(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yt_yvi02_disturbance_matchList(
  returnList text,
  yearList text,
  layerList text,
  layerNumber text,
  indexToReturn text,
  srcList text
)
RETURNS boolean AS $$
  SELECT TT_matchList(TT_yt_yvi02_disturbance_copyText(returnList, yearList, layerList, layerNumber, indexToReturn), srcList)
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yt_yvi02_disturbance_notNull
--
-- Pass TT_yt_yvi02_disturbance_copyText result to notNull
------------------------------------------------------------
-- DROP FUNCTION IF EXISTS TT_yt_yvi02_disturbance_notNull(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yt_yvi02_disturbance_notNull(
  returnList text,
  yearList text,
  layerList text,
  layerNumber text,
  indexToReturn text
)
RETURNS boolean AS $$
  SELECT TT_notNull(TT_yt_yvi02_disturbance_copyText(returnList, yearList, layerList, layerNumber, indexToReturn))
$$ LANGUAGE sql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_yt_yvi02_disturbance_hasCountOfLayers
--
-- returnList stringList - list of values to return (e.g. disturbance codes)
-- yearList stringList - list of disturbance years
-- layerList text - list of layer assignments ('Entire polygon disturbed', 'Layer 1 disturbance', 'Layer 2 disturbance')
-- layerNumber - 1 or 2
-- testVal
-- exact
--
-- If layer is 1, remove any disturbances labelled 'Layer 2 disturbance'
-- If layer is 2, remove any disturbances labelled 'Layer 1 disturbance'
-- count the number of layers, is it equal to, or greater than or equal to the count argument?
------------------------------------------------------------
-- DROP FUNCTION IF EXISTS TT_yt_yvi02_disturbance_hasCountOfLayers(text, text, text, text);
CREATE OR REPLACE FUNCTION TT_yt_yvi02_disturbance_hasCountOfLayers(
  layerList text,
  layerNumber text,
  count text,
  exact text
)
RETURNS boolean AS $$
  DECLARE
	_layerList text[];
	_counted_rows int;
	_exact boolean;
  BEGIN
    -- Parse inputs
    _layerList = TT_ParseStringList(layerList, 'TRUE');
  
    _exact = exact::boolean;
  
    -- for layer 1, remove layer 2. For layer 2 remove layer 1
    IF layerNumber = '1' THEN
      _layerList = array_remove(_layerList, 'Layer 2 disturbance');
    ELSIF layerNumber = '2' THEN
      _layerList = array_remove(_layerList, 'Layer 1 disturbance');
    ELSE
      RETURN FALSE;
    END IF;
  
      -- count rows
    _counted_rows = count(*) FROM unnest(_layerList) WHERE unnest IS NOT NULL;
  
    IF _exact THEN
      RETURN _counted_rows = count::int;
    ELSE
      RETURN _counted_rows >= count::int;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;


-------------------------------------------------------------------------------
-- TT_mb_mb03_disturbance_notNull
--
-- dst_type1 to dst_type5 - contain year values for fire_yr, blowdown_yr, cut_yr, regen_yr, and ftg_sp_yr
-- dist_num - number of the CASFRI disturbanc feature, 1 - 3
-- Check any of the disturbance fields are not null for a certain count
--    first dist_type requires 1 value to not be null, 2nd requires 2, 3rd requires 3
------------------------------------------------------------
-- DROP FUNCTION IF EXISTS TT_mb_mb03_disturbance_notNull(text, text, text, text, text,text);
CREATE OR REPLACE FUNCTION TT_mb_mb03_disturbance_hasCountOfNotNull(
  dst_type1 text,
  dst_type2 text,
  dst_type3 text,
  dst_type4 text,
  dst_type5 text,
  dist_num text
)
RETURNS boolean AS $$
  BEGIN
    RETURN TT_hasCountOfNotNullOrZero(dst_type1, dst_type2, dst_type3, dst_type4, dst_type5, dist_num, TRUE::text);
  END;
$$ LANGUAGE plpgsql IMMUTABLE;



-------------------------------------------------------------------------------
-- TT_mb_mb03_map_disturbance
--
-- There are five columns for mb03 disturbances, each may contain a year of that disturbance
--
-- dst_type list will contain year values for fire_yr, blowdown_yr, cut_yr, regen_yr, and ftg_sp_yr
-- dst_pos - which dist var is being mapped, valid values 1-3
-- isType - what to return the disturbance type or year
-- uses coalesece text to find first non-zero & non-null value and slices array based on dst_pos variable in order
--    to extract dist_type 1 - 3,
------------------------------------------------------------
-- DROP FUNCTION IF EXISTS TT_mb_mb03_map_disturbance_(text, text, text, text, text);
CREATE OR REPLACE FUNCTION TT_mb_mb03_map_disturbance(
  dst_type_list text,
  dst_pos text,
  isType text
)
RETURNS text AS $$
  DECLARE
    _isType boolean := isType::boolean;
    _dst_list text[];
    _coalesced_val1 text;
    _index1 int;
    _dst_list2 text[];
    _coalesced_val2 text;
    _index2 int;
    _dst_list3 text[];
    _coalesced_val3 text;
    _index3 int;
  BEGIN
    _dst_list = TT_ParseStringList(dst_type_list, 'TRUE');
    -- coalesce text on dst_type_list, if vals are 0 only ftg_sp_yr will have a value
    _coalesced_val1 = TT_CoalesceText(dst_type_list::text, TRUE::text);
    _index1 = array_position(_dst_list, _coalesced_val1);
    IF dst_pos::int = 1 THEN
      IF isType THEN
        IF _index1 = 1 THEN
          return 'BURN';
        ELSEIF _index1 = 2 THEN
          return 'WINDFALL';
        ELSEIF _index1 = 3 THEN
          return 'CUT';
        ELSEIF _index1 = 4 THEN
          RETURN 'SILVICULTURE_TREATMENT';
        ELSEIF _index1 = 5 THEN
          RETURN 'SILVICULTURE_TREATMENT';
        ELSE
          RETURN NULL;
        END IF;
      ELSE
        -- return year
        return _coalesced_val1;
      END IF;
    END IF;

    --    find the next non-zero/null value
    _dst_list2 = _dst_list[_index1+1:];
    _coalesced_val2 = TT_CoalesceText(_dst_list2::text, TRUE::text);
    _index2 = array_position(_dst_list2, _coalesced_val2);
    -- no more non-zero/non-null values, return
    IF _coalesced_val2 is NULL OR _index2 IS NULL THEN
      RETURN NULL;
    END IF;

    IF dst_pos::int = 2 THEN
      IF isType THEN
        IF _index1 + _index2 = 2 THEN
          return 'WINDFALL';
        ELSEIF _index1 + _index2 = 3 THEN
          return 'CUT';
        ELSEIF _index1 + _index2 = 4 THEN
          RETURN 'SILVICULTURE_TREATMENT';
        ELSEIF _index1 + _index2 = 5 THEN
          RETURN 'SILVICULTURE_TREATMENT';
        END IF;
      -- return year
      ELSE
        return _coalesced_val2;
      END IF;
    END IF;

    --    find the next non-zero/null value
    _dst_list3 = _dst_list[_index1 + _index2 + 1:];
    _coalesced_val3 = TT_CoalesceText(_dst_list3::text, TRUE::text);
    _index3 = array_position(_dst_list3, _coalesced_val3);
    IF _coalesced_val3 IS NULL OR _index3 IS NULL THEN
      RETURN NULL;
    END IF;

    IF dst_pos::int = 3 THEN
      IF isType THEN
        IF _index1 + _index2 + _index3 = 3 THEN
          RETURN 'CUT';
        ELSIF _index1 + _index2 + _index3 = 4 THEN
          RETURN 'SILVICULTURE_TREATMENT';
        ELSIF _index1 + _index2 + _index3 = 5 THEN
          RETURN 'SILVICULTURE_TREATMENT';
        END IF;
      -- return year
      ELSE
        return _coalesced_val3;
      END IF;
    END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_mb_fri03_getSpeciesPer1
--
-- Given a string composition of species in a polygon, get the percentage of species_1
-- If the string only contains one species, must be 100%
-- If there are two or more species, parse the integer in the 3rd position
-- 
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_mb_fri03_getSpeciesPer1(text);
CREATE OR REPLACE FUNCTION TT_mb_fri03_getSpeciesPer1(
  species TEXT
)
RETURNS INTEGER AS $$
  BEGIN
     IF (length(species) = 2 AND species ~ '^[A-Za-z]+$') OR 
     	(length(species) = 4 AND substring(species, 1, 2) ~ '^[A-Za-z]+$' AND substring(species, 3, 2) = '10')
	THEN 
		RETURN 100;
	ELSIF length(species) > 2 AND substring(species, 1, 2) ~ '^[A-Za-z]+$' AND substring(species, 3, 1) ~ '^[0-9]+$'
	THEN
		RETURN substring(species, 3, 1)::INT*10;    
	END IF;
	RETURN NULL;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- TT_mb_fri03_species_validation
--
-- Given a string composition of species in a polygon and the specific species index to look for, return true if the string contains correct information for that entry
-- If the string only contains one species, must be 100%
-- Returns true if both a two letter species code and a percentage exists in the string at the correct index
-- 
------------------------------------------------------------
--DROP FUNCTION IF EXISTS TT_mb_fri03_species_validation(text, integer);
CREATE OR REPLACE FUNCTION TT_mb_fri03_species_validation(
  species TEXT,
  species_count TEXT
)
RETURNS boolean AS $$
  BEGIN
	  
    IF (species_count::integer = 1 AND length(species) = 2 AND species ~ '^[A-Za-z]+$')                                                                -- JP
    OR (species_count::integer = 1 AND length(species) = 4 AND substring(species, 1, 2) ~ '^[A-Za-z]+$' AND substring(species, 3, 2) = '10')           -- JP10
    OR (species_count::integer = 1 AND length(species) >= 6 AND substring(species, 1, 2) ~ '^[A-Za-z]+$' AND substring(species, 3, 1) ~ '^[0-9]+$')    -- JP8TR2
    OR (species_count::integer = 2 AND length(species) >= 6 AND substring(species, 4, 2) ~ '^[A-Za-z]+$' AND substring(species, 6, 1) ~ '^[0-9]+$')    -- JP8TR2
    OR (species_count::integer = 3 AND length(species) >= 9 AND substring(species, 7, 2) ~ '^[A-Za-z]+$' AND substring(species, 9, 1) ~ '^[0-9]+$')    -- JP7TR2TL1
    OR (species_count::integer = 4 AND length(species) >= 12 AND substring(species, 10, 2) ~ '^[A-Za-z]+$' AND substring(species, 12, 1) ~ '^[0-9]+$') -- JP6TR2TL1PL1
    OR (species_count::integer = 5 AND length(species) >= 15 AND substring(species, 13, 2) ~ '^[A-Za-z]+$' AND substring(species, 15, 1) ~ '^[0-9]+$') -- JP5TR2TL1PL1TS1
    OR (species_count::integer = 6 AND length(species) >= 18 AND substring(species, 16, 2) ~ '^[A-Za-z]+$' AND substring(species, 18, 1) ~ '^[0-9]+$') -- JP4TR2TL1PL1TS1WS1
	THEN 
		RETURN TRUE;
	ELSE
		RETURN FALSE;
	END IF;
  END;
$$ LANGUAGE plpgsql IMMUTABLE;
-------------------------------------------------------------------------------
