-- 02_casos_limite.sql
-- Grupo 6 - BD2 - Actividad 4.4 (Iair Suico)
-- Casos raros en una sesion NUEVA. Cada fila muestra lo obtenido y lo esperado.
-- Uso: docker exec -w /app bd2_g6_hashing psql -U postgres -d hashing_db -X -f tests/02_casos_limite.sql

CREATE EXTENSION IF NOT EXISTS pg_hashing;
\c hashing_db

SELECT 'buscar en sesion vacia (10)'        AS caso, pg_buscar(10)::text      AS obtenido, 'false' AS esperado;

SELECT 'cero: insertar'                     AS caso, pg_insertar(0)::text     AS obtenido, 'true' AS esperado;
SELECT 'cero: buscar'                       AS caso, pg_buscar(0)::text       AS obtenido, 'true' AS esperado;
SELECT 'cero: insertar otra vez'            AS caso, pg_insertar(0)::text     AS obtenido, 'false' AS esperado;

SELECT 'negativo: insertar -1'              AS caso, pg_insertar(-1)::text    AS obtenido, 'true' AS esperado;
SELECT 'negativo: insertar -4'              AS caso, pg_insertar(-4)::text    AS obtenido, 'true' AS esperado;
SELECT 'negativo: buscar -1'                AS caso, pg_buscar(-1)::text      AS obtenido, 'true' AS esperado;
SELECT 'negativo: buscar -4'                AS caso, pg_buscar(-4)::text      AS obtenido, 'true' AS esperado;
SELECT 'negativo: buscar -2 (no existe)'    AS caso, pg_buscar(-2)::text      AS obtenido, 'false' AS esperado;
SELECT 'positivo: buscar 4 (no existe)'     AS caso, pg_buscar(4)::text       AS obtenido, 'false' AS esperado;

SELECT 'extremo: insertar 2147483647'       AS caso, pg_insertar(2147483647)::text  AS obtenido, 'true' AS esperado;
SELECT 'extremo: insertar -2147483648'      AS caso, pg_insertar(-2147483648)::text AS obtenido, 'true' AS esperado;
SELECT 'extremo: buscar 2147483647'         AS caso, pg_buscar(2147483647)::text    AS obtenido, 'true' AS esperado;
SELECT 'extremo: buscar -2147483648'        AS caso, pg_buscar(-2147483648)::text   AS obtenido, 'true' AS esperado;

SELECT 'NULL: pg_insertar(NULL) es NULL'    AS caso, (pg_insertar(NULL) IS NULL)::text AS obtenido, 'true' AS esperado;

SELECT 'repetidas en una consulta (7,7,7,8)' AS caso,
       count(*) FILTER (WHERE pg_insertar(v))::text AS obtenido, '2' AS esperado
FROM (VALUES (7), (7), (7), (8)) AS t(v);

-- -1 y -4 ya estaban, por eso se esperan 99998 nuevas
SELECT 'negativos -1..-100000: insertadas'  AS caso,
       count(*) FILTER (WHERE pg_insertar(-g))::text AS obtenido, '99998' AS esperado
FROM generate_series(1, 100000) AS g;
SELECT 'negativos -1..-100000: perdidas'    AS caso,
       count(*) FILTER (WHERE NOT pg_buscar(-g))::text AS obtenido, '0' AS esperado
FROM generate_series(1, 100000) AS g;
