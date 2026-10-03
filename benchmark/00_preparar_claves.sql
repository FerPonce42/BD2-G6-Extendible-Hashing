-- 00_preparar_claves.sql
-- Grupo 6 - BD2 - Benchmark
-- Crea la lista de claves a buscar. LOS TRES METODOS USAN ESTA MISMA TABLA.
-- Por defecto: 20000 claves = 10000 que EXISTEN en buses + 10000 AUSENTES (rubrica).
-- Usa setseed para que sea reproducible (misma CSV => mismas claves).
--
-- Parametro opcional: -v n_consultas=20000   (total; mitad existen, mitad no)

\set ON_ERROR_STOP on
\if :{?n_consultas} \else \set n_consultas 20000 \endif

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

SELECT version();
SELECT count(*) AS filas_buses FROM buses \gset

SELECT setseed(0.42);

DROP TABLE IF EXISTS claves_benchmark;
CREATE TABLE claves_benchmark (ord int PRIMARY KEY, k int NOT NULL, existe boolean NOT NULL);

INSERT INTO claves_benchmark
WITH presentes AS (
    SELECT id_bus AS k, row_number() OVER () AS r
    FROM (SELECT id_bus FROM buses ORDER BY random() LIMIT :n_consultas / 2) s
),
candidatos AS (
    SELECT DISTINCT (floor(random() * 10 * :filas_buses) + 1)::int AS k
    FROM generate_series(1, :n_consultas * 3)
),
ausentes AS (
    SELECT c.k, row_number() OVER () AS r
    FROM candidatos c
    WHERE NOT EXISTS (SELECT 1 FROM buses b WHERE b.id_bus = c.k)
    LIMIT :n_consultas / 2
)
SELECT r * 2,     k, true  FROM presentes
UNION ALL
SELECT r * 2 + 1, k, false FROM ausentes;

SELECT count(*) AS claves_total,
       count(*) FILTER (WHERE existe)     AS existen,
       count(*) FILTER (WHERE NOT existe) AS ausentes
FROM claves_benchmark;
