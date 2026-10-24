CREATE EXTENSION IF NOT EXISTS pg_hashing;

\timing on

-- Evaluar la estructura propia llamando a la función C pg_insertar()
-- Inyecta 20,000 claves calculadas a partir del máximo id_bus actual
SELECT count(pg_insertar((x + (SELECT COALESCE(MAX(id_bus), 0) FROM buses))::integer))
FROM generate_series(1, 20000) AS x;

\timing off