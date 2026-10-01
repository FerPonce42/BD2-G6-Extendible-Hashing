-- 01_datasets.sql
-- Grupo 6 - BD2 - Actividad 4.4 (Iair Suico)
-- Para cada dataset (D1 y D2, 100k / 500k / 1M), en una sesion NUEVA (\c):
--   insertadas       = claves que pg_insertar acepto        (esperado: = filas)
--   perdidas         = claves insertadas que pg_buscar no encuentra (esperado: 0)
--   reinsertadas     = claves aceptadas al cargar todo otra vez     (esperado: 0, ya existian)
--   falsos_positivos = claves que NO estan en el dataset pero pg_buscar dice que si (esperado: 0)
--                      se revisa el rango -100000 .. max(id)+100000
-- Cada metrica es una sentencia aparte para que se ejecuten en orden.
-- Uso: docker exec -w /app bd2_g6_hashing psql -U postgres -d hashing_db -X -f tests/01_datasets.sql

CREATE EXTENSION IF NOT EXISTS pg_hashing;
DROP TABLE IF EXISTS resultados_4_4;
CREATE TABLE resultados_4_4 (
    orden            serial,
    dataset          text,
    filas            bigint,
    insertadas       bigint,
    perdidas         bigint,
    reinsertadas     bigint,
    falsos_positivos bigint
);

-- ---------------------------------------------------------------- D1_secuencial_100000
\c hashing_db
\echo '>>> D1_secuencial_100000'
\set ds 'D1_secuencial_100000'
DROP TABLE IF EXISTS prueba;
CREATE TABLE prueba (id_bus INTEGER, placa VARCHAR(7), ruta VARCHAR(5), capacidad INTEGER);
\copy prueba FROM 'data/D1_secuencial_100000.csv' WITH (FORMAT csv, HEADER true)
INSERT INTO resultados_4_4 (dataset, filas) SELECT :'ds', count(*) FROM prueba;
UPDATE resultados_4_4 SET insertadas   = (SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET perdidas     = (SELECT count(*) FILTER (WHERE NOT pg_buscar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET reinsertadas = (SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET falsos_positivos = (
    SELECT count(*)
    FROM generate_series(-100000, (SELECT max(id_bus) FROM prueba) + 100000) AS g
    WHERE pg_buscar(g)
      AND NOT EXISTS (SELECT 1 FROM prueba p WHERE p.id_bus = g)
) WHERE dataset = :'ds';

-- ---------------------------------------------------------------- D2_aleatorio_100000
\c hashing_db
\echo '>>> D2_aleatorio_100000'
\set ds 'D2_aleatorio_100000'
DROP TABLE IF EXISTS prueba;
CREATE TABLE prueba (id_bus INTEGER, placa VARCHAR(7), ruta VARCHAR(5), capacidad INTEGER);
\copy prueba FROM 'data/D2_aleatorio_100000.csv' WITH (FORMAT csv, HEADER true)
INSERT INTO resultados_4_4 (dataset, filas) SELECT :'ds', count(*) FROM prueba;
UPDATE resultados_4_4 SET insertadas   = (SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET perdidas     = (SELECT count(*) FILTER (WHERE NOT pg_buscar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET reinsertadas = (SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET falsos_positivos = (
    SELECT count(*)
    FROM generate_series(-100000, (SELECT max(id_bus) FROM prueba) + 100000) AS g
    WHERE pg_buscar(g)
      AND NOT EXISTS (SELECT 1 FROM prueba p WHERE p.id_bus = g)
) WHERE dataset = :'ds';

-- ---------------------------------------------------------------- D1_secuencial_500000
\c hashing_db
\echo '>>> D1_secuencial_500000'
\set ds 'D1_secuencial_500000'
DROP TABLE IF EXISTS prueba;
CREATE TABLE prueba (id_bus INTEGER, placa VARCHAR(7), ruta VARCHAR(5), capacidad INTEGER);
\copy prueba FROM 'data/D1_secuencial_500000.csv' WITH (FORMAT csv, HEADER true)
INSERT INTO resultados_4_4 (dataset, filas) SELECT :'ds', count(*) FROM prueba;
UPDATE resultados_4_4 SET insertadas   = (SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET perdidas     = (SELECT count(*) FILTER (WHERE NOT pg_buscar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET reinsertadas = (SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET falsos_positivos = (
    SELECT count(*)
    FROM generate_series(-100000, (SELECT max(id_bus) FROM prueba) + 100000) AS g
    WHERE pg_buscar(g)
      AND NOT EXISTS (SELECT 1 FROM prueba p WHERE p.id_bus = g)
) WHERE dataset = :'ds';

-- ---------------------------------------------------------------- D2_aleatorio_500000
\c hashing_db
\echo '>>> D2_aleatorio_500000'
\set ds 'D2_aleatorio_500000'
DROP TABLE IF EXISTS prueba;
CREATE TABLE prueba (id_bus INTEGER, placa VARCHAR(7), ruta VARCHAR(5), capacidad INTEGER);
\copy prueba FROM 'data/D2_aleatorio_500000.csv' WITH (FORMAT csv, HEADER true)
INSERT INTO resultados_4_4 (dataset, filas) SELECT :'ds', count(*) FROM prueba;
UPDATE resultados_4_4 SET insertadas   = (SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET perdidas     = (SELECT count(*) FILTER (WHERE NOT pg_buscar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET reinsertadas = (SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET falsos_positivos = (
    SELECT count(*)
    FROM generate_series(-100000, (SELECT max(id_bus) FROM prueba) + 100000) AS g
    WHERE pg_buscar(g)
      AND NOT EXISTS (SELECT 1 FROM prueba p WHERE p.id_bus = g)
) WHERE dataset = :'ds';

-- ---------------------------------------------------------------- D1_secuencial_1000000
\c hashing_db
\echo '>>> D1_secuencial_1000000'
\set ds 'D1_secuencial_1000000'
DROP TABLE IF EXISTS prueba;
CREATE TABLE prueba (id_bus INTEGER, placa VARCHAR(7), ruta VARCHAR(5), capacidad INTEGER);
\copy prueba FROM 'data/D1_secuencial_1000000.csv' WITH (FORMAT csv, HEADER true)
INSERT INTO resultados_4_4 (dataset, filas) SELECT :'ds', count(*) FROM prueba;
UPDATE resultados_4_4 SET insertadas   = (SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET perdidas     = (SELECT count(*) FILTER (WHERE NOT pg_buscar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET reinsertadas = (SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET falsos_positivos = (
    SELECT count(*)
    FROM generate_series(-100000, (SELECT max(id_bus) FROM prueba) + 100000) AS g
    WHERE pg_buscar(g)
      AND NOT EXISTS (SELECT 1 FROM prueba p WHERE p.id_bus = g)
) WHERE dataset = :'ds';

-- ---------------------------------------------------------------- D2_aleatorio_1000000
\c hashing_db
\echo '>>> D2_aleatorio_1000000'
\set ds 'D2_aleatorio_1000000'
DROP TABLE IF EXISTS prueba;
CREATE TABLE prueba (id_bus INTEGER, placa VARCHAR(7), ruta VARCHAR(5), capacidad INTEGER);
\copy prueba FROM 'data/D2_aleatorio_1000000.csv' WITH (FORMAT csv, HEADER true)
INSERT INTO resultados_4_4 (dataset, filas) SELECT :'ds', count(*) FROM prueba;
UPDATE resultados_4_4 SET insertadas   = (SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET perdidas     = (SELECT count(*) FILTER (WHERE NOT pg_buscar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET reinsertadas = (SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM prueba) WHERE dataset = :'ds';
UPDATE resultados_4_4 SET falsos_positivos = (
    SELECT count(*)
    FROM generate_series(-100000, (SELECT max(id_bus) FROM prueba) + 100000) AS g
    WHERE pg_buscar(g)
      AND NOT EXISTS (SELECT 1 FROM prueba p WHERE p.id_bus = g)
) WHERE dataset = :'ds';

-- ---------------------------------------------------------------- resumen
\echo '>>> RESUMEN'
SELECT dataset, filas, insertadas, perdidas, reinsertadas, falsos_positivos
FROM resultados_4_4 ORDER BY orden;

DROP TABLE prueba;
