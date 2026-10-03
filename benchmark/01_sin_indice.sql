-- 01_sin_indice.sql
-- Grupo 6 - BD2 - Benchmark
-- Busqueda SIN indice: PostgreSQL revisa la tabla fila por fila (Seq Scan).
-- Una consulta SQL por clave. Requiere haber corrido 00_preparar_claves.sql.
-- Ojo: con 20000 claves tarda varios minutos (cada busqueda recorre la tabla).
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

\echo '=== BENCHMARK 1: SIN INDICE ==='
SELECT version();
SELECT count(*) AS filas_buses FROM buses;
SELECT count(*) AS claves_a_buscar,
       count(*) FILTER (WHERE existe)     AS existen,
       count(*) FILTER (WHERE NOT existe) AS ausentes
FROM claves_benchmark;
\echo 'repeticiones:' :reps

SET max_parallel_workers_per_gather = 0;   -- fila por fila de verdad
DROP INDEX IF EXISTS idx_buses_btree;
ANALYZE buses;

\echo
\echo '--- Plan de ejecucion (debe decir Seq Scan) ---'
EXPLAIN (COSTS OFF) SELECT EXISTS (SELECT 1 FROM buses WHERE id_bus = 1);

CREATE TEMP TABLE medidas (metodo text, rep int, n_consultas int, total_ms numeric, aciertos int, esperados int);

CREATE FUNCTION pg_temp.medir(p_metodo text, p_rep int, p_n int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    ks int[]; esperados int; aciertos int := 0; hit boolean; t0 timestamptz; t1 timestamptz;
BEGIN
    -- las claves se cargan ANTES de cronometrar
    SELECT array_agg(k ORDER BY ord), count(*) FILTER (WHERE existe)
      INTO ks, esperados
      FROM (SELECT * FROM claves_benchmark ORDER BY ord LIMIT p_n) s;
    t0 := clock_timestamp();
    FOR i IN 1 .. array_length(ks, 1) LOOP
        SELECT EXISTS (SELECT 1 FROM buses WHERE id_bus = ks[i]) INTO hit;
        IF hit THEN aciertos := aciertos + 1; END IF;
    END LOOP;
    t1 := clock_timestamp();
    INSERT INTO medidas VALUES (p_metodo, p_rep, array_length(ks, 1),
        round(extract(epoch FROM (t1 - t0)) * 1000, 3), aciertos, esperados);
END $$;

\o /dev/null
SELECT pg_temp.medir('sin_indice', 0, 200);      -- calentamiento corto (se descarta)
DELETE FROM medidas;
SELECT pg_temp.medir('sin_indice', rep, (SELECT count(*) FROM claves_benchmark)::int) FROM generate_series(1, :reps) rep;
\o

\echo
\echo '--- Resultado por repeticion ---'
SELECT metodo, rep AS repeticion, n_consultas, total_ms, aciertos, esperados FROM medidas ORDER BY metodo, rep;

\echo
\echo '--- Resumen ---'
SELECT metodo,
       max(n_consultas) AS n_consultas,
       count(*) AS repeticiones,
       min(total_ms) AS min_ms,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY total_ms)::numeric, 3) AS mediana_ms,
       max(total_ms) AS max_ms,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY total_ms) / max(n_consultas))::numeric, 5) AS mediana_ms_por_consulta,
       bool_and(aciertos = esperados) AS resultados_correctos
FROM medidas
GROUP BY metodo
ORDER BY mediana_ms DESC;
