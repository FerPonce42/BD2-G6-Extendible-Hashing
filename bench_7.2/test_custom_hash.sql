CREATE EXTENSION IF NOT EXISTS pg_hashing;

-- 1. Cargar las filas del dataset en la estructura de memoria (Sin medir tiempo)
SELECT count(pg_insertar(id_bus)) FROM buses;

-- 2. Medir el tiempo de las inserciones nuevas (W3)
\timing on
SELECT count(pg_insertar((x + (SELECT COALESCE(MAX(id_bus), 0) FROM buses))::integer))
FROM generate_series(1, :n_inserts) AS x;
\timing off