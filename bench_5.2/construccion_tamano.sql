-- construccion_tamano.sql
-- Grupo 6 - BD2 - Actividad 5.2: comparacion preliminar con B-tree (Iair Suico)
--
-- Complementa benchmark/02_btree.sql y benchmark/03_hashing.sql (Fabricio), que miden la
-- construccion UNA vez. Aqui:
--   * construccion B-tree (CREATE INDEX) : 1 calentamiento + 5 repeticiones
--   * construccion hash (pg_insertar de todas las filas): 1 calentamiento + 5 repeticiones,
--     cada una en una sesion NUEVA (\c), porque la estructura vive por sesion
--   * tamano del indice B-tree y de la tabla (pg_relation_size)
-- Usa la tabla buses tal como este cargada.
--
-- Uso: psql -U postgres -d hashing_db -X -f bench_5.2/construccion_tamano.sql

\set ON_ERROR_STOP on

SELECT (current_setting('server_version_num')::int >= 180000) AS es_pg18 \gset
\if :es_pg18
\else
  \if :{?permitir_otra_version}
    \echo 'AVISO: el servidor NO es PostgreSQL 18; estos resultados no son oficiales.'
  \else
    \echo 'ERROR: el servidor no es PostgreSQL 18. Corre esto en el contenedor del grupo.'
    \quit
  \endif
\endif

\echo '=== 5.2: CONSTRUCCION Y TAMANO ==='
SELECT version();
SELECT count(*) AS filas_buses FROM buses;

CREATE EXTENSION IF NOT EXISTS pg_hashing;
DROP TABLE IF EXISTS medidas_construccion;
CREATE TABLE medidas_construccion (metodo text, rep int, filas bigint, ms numeric);

-- ---------------------------------------------------------------- B-tree
SET max_parallel_maintenance_workers = 0;   -- CREATE INDEX con un solo proceso, igual que pg_insertar
DO $$
DECLARE t0 timestamptz; ms numeric; i int;
BEGIN
    FOR i IN 0..5 LOOP                       -- 0 = calentamiento (se descarta)
        EXECUTE 'DROP INDEX IF EXISTS idx_buses_btree';
        t0 := clock_timestamp();
        EXECUTE 'CREATE INDEX idx_buses_btree ON buses USING btree (id_bus)';
        ms := round(extract(epoch FROM clock_timestamp() - t0)::numeric * 1000, 3);
        IF i > 0 THEN
            INSERT INTO medidas_construccion VALUES ('btree', i, (SELECT count(*) FROM buses), ms);
        END IF;
    END LOOP;
END $$;

\echo
\echo '--- Tamano ---'
SELECT pg_size_pretty(pg_relation_size('idx_buses_btree')) AS indice_btree,
       pg_relation_size('idx_buses_btree')                 AS indice_btree_bytes,
       pg_size_pretty(pg_relation_size('buses'))           AS tabla_buses,
       round(pg_relation_size('idx_buses_btree')::numeric / (SELECT count(*) FROM buses), 2) AS bytes_por_clave_btree;

-- ---------------------------------------------------------------- Extendible Hashing
-- Cada repeticion en sesion nueva: la estructura empieza vacia.
\c hashing_db
SELECT set_config('bench.rep', '0', false) \g /dev/null
DO $$
DECLARE t0 timestamptz; n bigint; ms numeric;
BEGIN
    t0 := clock_timestamp();
    SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) INTO n FROM buses;
    ms := round(extract(epoch FROM clock_timestamp() - t0)::numeric * 1000, 3);
    IF current_setting('bench.rep')::int > 0 THEN
        INSERT INTO medidas_construccion VALUES ('hashing', current_setting('bench.rep')::int, n, ms);
    END IF;
END $$;
\c hashing_db
SELECT set_config('bench.rep', '1', false) \g /dev/null
DO $$
DECLARE t0 timestamptz; n bigint; ms numeric;
BEGIN
    t0 := clock_timestamp();
    SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) INTO n FROM buses;
    ms := round(extract(epoch FROM clock_timestamp() - t0)::numeric * 1000, 3);
    IF current_setting('bench.rep')::int > 0 THEN
        INSERT INTO medidas_construccion VALUES ('hashing', current_setting('bench.rep')::int, n, ms);
    END IF;
END $$;
\c hashing_db
SELECT set_config('bench.rep', '2', false) \g /dev/null
DO $$
DECLARE t0 timestamptz; n bigint; ms numeric;
BEGIN
    t0 := clock_timestamp();
    SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) INTO n FROM buses;
    ms := round(extract(epoch FROM clock_timestamp() - t0)::numeric * 1000, 3);
    IF current_setting('bench.rep')::int > 0 THEN
        INSERT INTO medidas_construccion VALUES ('hashing', current_setting('bench.rep')::int, n, ms);
    END IF;
END $$;
\c hashing_db
SELECT set_config('bench.rep', '3', false) \g /dev/null
DO $$
DECLARE t0 timestamptz; n bigint; ms numeric;
BEGIN
    t0 := clock_timestamp();
    SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) INTO n FROM buses;
    ms := round(extract(epoch FROM clock_timestamp() - t0)::numeric * 1000, 3);
    IF current_setting('bench.rep')::int > 0 THEN
        INSERT INTO medidas_construccion VALUES ('hashing', current_setting('bench.rep')::int, n, ms);
    END IF;
END $$;
\c hashing_db
SELECT set_config('bench.rep', '4', false) \g /dev/null
DO $$
DECLARE t0 timestamptz; n bigint; ms numeric;
BEGIN
    t0 := clock_timestamp();
    SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) INTO n FROM buses;
    ms := round(extract(epoch FROM clock_timestamp() - t0)::numeric * 1000, 3);
    IF current_setting('bench.rep')::int > 0 THEN
        INSERT INTO medidas_construccion VALUES ('hashing', current_setting('bench.rep')::int, n, ms);
    END IF;
END $$;
\c hashing_db
SELECT set_config('bench.rep', '5', false) \g /dev/null
DO $$
DECLARE t0 timestamptz; n bigint; ms numeric;
BEGIN
    t0 := clock_timestamp();
    SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) INTO n FROM buses;
    ms := round(extract(epoch FROM clock_timestamp() - t0)::numeric * 1000, 3);
    IF current_setting('bench.rep')::int > 0 THEN
        INSERT INTO medidas_construccion VALUES ('hashing', current_setting('bench.rep')::int, n, ms);
    END IF;
END $$;

\echo
\echo '--- Construccion por repeticion ---'
SELECT metodo, rep AS repeticion, filas, ms FROM medidas_construccion ORDER BY metodo, rep;

\echo
\echo '--- Resumen construccion ---'
SELECT metodo,
       count(*) AS repeticiones,
       max(filas) AS filas,
       min(ms) AS min_ms,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY ms)::numeric, 3) AS mediana_ms,
       max(ms) AS max_ms,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY ms) * 1000 / max(filas))::numeric, 3) AS mediana_us_por_fila
FROM medidas_construccion
GROUP BY metodo
ORDER BY metodo;
