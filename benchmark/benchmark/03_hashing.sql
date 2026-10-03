-- 03_hashing.sql
-- Grupo 6 - BD2 - Benchmark
-- Busqueda con NUESTRA estructura (Extendible Hashing) via pg_buscar().
-- Mismas claves que 01 y 02.
--
-- OJO: la estructura vive en memoria de la sesion. Por eso este script
-- INSERTA las claves y BUSCA en la MISMA sesion de psql. No lo partas.
--
-- COMPARACION JUSTA: sin_indice y btree ejecutan UNA CONSULTA SQL por clave
-- (planificador + ejecutor). pg_buscar es una funcion en C. Para separar
-- ese costo, aqui se miden TRES cosas:
--   hashing_directo  : hit := pg_buscar(k)            (llamada directa, sin consulta SQL)
--   hashing_via_sql  : SELECT pg_buscar(k) INTO hit   (una consulta SQL por clave, igual que 01 y 02)
--   baseline_sql     : SELECT (k IS NOT NULL) INTO hit (consulta SQL que no busca nada: costo fijo de una consulta)
-- La comparacion justa con sin_indice y btree es hashing_via_sql.
-- Requiere haber corrido 00_preparar_claves.sql.
-- Parametro opcional: -v reps=5

\set ON_ERROR_STOP on
\if :{?reps} \else \set reps 5 \endif

-- Solo valen como oficiales las corridas en PostgreSQL 18 (el del Docker del grupo).
SELECT (current_setting('server_version_num')::int >= 180000) AS es_pg18 \gset
\if :es_pg18
\else
  \if :{?permitir_otra_version}
    \echo 'AVISO: el servidor NO es PostgreSQL 18; estos resultados no son oficiales.'
  \else
    \echo 'ERROR: el servidor no es PostgreSQL 18. Corre esto en el contenedor del grupo (docker exec ...).'
    \quit
  \endif
\endif

\echo '=== BENCHMARK 3: EXTENDIBLE HASHING (pg_buscar) ==='
SELECT version();
SELECT count(*) AS filas_buses FROM buses;
SELECT count(*) AS claves_a_buscar,
       count(*) FILTER (WHERE existe)     AS existen,
       count(*) FILTER (WHERE NOT existe) AS ausentes
FROM claves_benchmark;
\echo 'repeticiones:' :reps

CREATE EXTENSION IF NOT EXISTS pg_hashing;

\echo
\echo '--- Construccion: pg_insertar de todas las claves de buses ---'
CREATE TEMP TABLE construccion (insertadas bigint, total bigint, ms numeric);
DO $$
DECLARE t0 timestamptz := clock_timestamp(); ins bigint; tot bigint;
BEGIN
    SELECT count(*) FILTER (WHERE pg_insertar(id_bus)), count(*) INTO ins, tot FROM buses;
    INSERT INTO construccion
    VALUES (ins, tot, round(extract(epoch FROM (clock_timestamp() - t0)) * 1000, 3));
END $$;
SELECT insertadas, total, ms AS construccion_ms, (insertadas = total) AS todas_insertadas FROM construccion;

CREATE TEMP TABLE medidas (metodo text, rep int, n_consultas int, total_ms numeric, aciertos int, esperados int);

CREATE FUNCTION pg_temp.medir_directo(p_metodo text, p_rep int, p_n int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    ks int[]; esperados int; aciertos int := 0; hit boolean; t0 timestamptz; t1 timestamptz;
BEGIN
    -- las claves se cargan ANTES de cronometrar
    SELECT array_agg(k ORDER BY ord), count(*) FILTER (WHERE existe)
      INTO ks, esperados
      FROM (SELECT * FROM claves_benchmark ORDER BY ord LIMIT p_n) s;
    t0 := clock_timestamp();
    FOR i IN 1 .. array_length(ks, 1) LOOP
        hit := pg_buscar(ks[i]);
        IF hit THEN aciertos := aciertos + 1; END IF;
    END LOOP;
    t1 := clock_timestamp();
    INSERT INTO medidas VALUES (p_metodo, p_rep, array_length(ks, 1),
        round(extract(epoch FROM (t1 - t0)) * 1000, 3), aciertos, esperados);
END $$;

CREATE FUNCTION pg_temp.medir_sql(p_metodo text, p_rep int, p_n int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    ks int[]; esperados int; aciertos int := 0; hit boolean; t0 timestamptz; t1 timestamptz;
BEGIN
    -- las claves se cargan ANTES de cronometrar
    SELECT array_agg(k ORDER BY ord), count(*) FILTER (WHERE existe)
      INTO ks, esperados
      FROM (SELECT * FROM claves_benchmark ORDER BY ord LIMIT p_n) s;
    t0 := clock_timestamp();
    FOR i IN 1 .. array_length(ks, 1) LOOP
        SELECT pg_buscar(ks[i]) INTO hit;
        IF hit THEN aciertos := aciertos + 1; END IF;
    END LOOP;
    t1 := clock_timestamp();
    INSERT INTO medidas VALUES (p_metodo, p_rep, array_length(ks, 1),
        round(extract(epoch FROM (t1 - t0)) * 1000, 3), aciertos, esperados);
END $$;

CREATE FUNCTION pg_temp.medir_base(p_metodo text, p_rep int, p_n int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    ks int[]; esperados int; aciertos int := 0; hit boolean; t0 timestamptz; t1 timestamptz;
BEGIN
    -- las claves se cargan ANTES de cronometrar
    SELECT array_agg(k ORDER BY ord), count(*) FILTER (WHERE existe)
      INTO ks, esperados
      FROM (SELECT * FROM claves_benchmark ORDER BY ord LIMIT p_n) s;
    t0 := clock_timestamp();
    FOR i IN 1 .. array_length(ks, 1) LOOP
        SELECT (ks[i] IS NOT NULL) INTO hit;
        IF hit THEN aciertos := aciertos + 1; END IF;
    END LOOP;
    t1 := clock_timestamp();
    INSERT INTO medidas VALUES (p_metodo, p_rep, array_length(ks, 1),
        round(extract(epoch FROM (t1 - t0)) * 1000, 3), aciertos, esperados);
END $$;

\o /dev/null
SELECT pg_temp.medir_directo('hashing_directo', 0, 200);      -- calentamiento corto (se descarta)
DELETE FROM medidas;
SELECT pg_temp.medir_directo('hashing_directo', rep, (SELECT count(*) FROM claves_benchmark)::int) FROM generate_series(1, :reps) rep;
\o

\o /dev/null
SELECT pg_temp.medir_sql('hashing_via_sql', 0, 200);      -- calentamiento corto (se descarta)

SELECT pg_temp.medir_sql('hashing_via_sql', rep, (SELECT count(*) FROM claves_benchmark)::int) FROM generate_series(1, :reps) rep;
\o

\o /dev/null
SELECT pg_temp.medir_base('baseline_sql', 0, 200);      -- calentamiento corto (se descarta)

SELECT pg_temp.medir_base('baseline_sql', rep, (SELECT count(*) FROM claves_benchmark)::int) FROM generate_series(1, :reps) rep;
\o

\echo
\echo '--- Resultado por repeticion ---'
SELECT metodo, rep AS repeticion, n_consultas, total_ms, aciertos, esperados FROM medidas WHERE rep > 0 ORDER BY metodo, rep;

\echo
\echo '--- Resumen ---'
SELECT metodo,
       max(n_consultas) AS n_consultas,
       count(*) AS repeticiones,
       min(total_ms) AS min_ms,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY total_ms)::numeric, 3) AS mediana_ms,
       max(total_ms) AS max_ms,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY total_ms) / max(n_consultas))::numeric, 5) AS mediana_ms_por_consulta,
       CASE WHEN metodo = 'baseline_sql' THEN NULL ELSE bool_and(aciertos = esperados) END AS resultados_correctos  -- baseline no busca nada
FROM medidas WHERE rep > 0
GROUP BY metodo
ORDER BY mediana_ms DESC;
