-- 03_tope_profundidad.sql
-- Grupo 6 - BD2 - Actividad 4.4 (Iair Suico)
-- Caso extremo: claves que comparten sus 24 bits bajos (multiplos de 2^24 = 16777216).
-- Con buckets de 50, la clave 51 obliga a duplicar el directorio hasta PROF_MAXIMA = 24
-- y aun asi no cabe. Despues se carga D2 100000 con el directorio ya en el tope.
--
-- Esperado ANTES (main sin corregir):  paso 2 = f (sin aviso), paso 3 = 645, paso 4 = 99355
-- Esperado DESPUES (con correcciones): paso 2 = ERROR,         paso 3 = 100000, paso 4 = 0
--
-- Uso: docker exec -w /app bd2_g6_hashing psql -U postgres -d hashing_db -X -f tests/03_tope_profundidad.sql

CREATE EXTENSION IF NOT EXISTS pg_hashing;
DROP TABLE IF EXISTS prueba_tope;
CREATE TABLE prueba_tope (id_bus INTEGER, placa VARCHAR(7), ruta VARCHAR(5), capacidad INTEGER);
\copy prueba_tope FROM 'data/D2_aleatorio_100000.csv' WITH (FORMAT csv, HEADER true)

\c hashing_db

\echo '>>> Paso 1: insertar 50 multiplos de 2^24 (0..49) -> llenan un bucket. Esperado: 50'
SELECT count(*) FILTER (WHERE pg_insertar(g * 16777216)) AS insertadas
FROM generate_series(0, 49) AS g;

\echo '>>> Paso 2: insertar la clave 51 (50 * 2^24 = 838860800)'
SELECT pg_insertar(50 * 16777216) AS insertada;

\echo '>>> Paso 3: cargar D2 100000 con el directorio en el tope'
SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) AS insertadas FROM prueba_tope;

\echo '>>> Paso 4: claves de D2 que no se encuentran'
SELECT count(*) FILTER (WHERE NOT pg_buscar(id_bus)) AS no_encontradas FROM prueba_tope;

DROP TABLE prueba_tope;
