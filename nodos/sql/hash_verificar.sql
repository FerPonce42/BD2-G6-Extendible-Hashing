-- hash_verificar.sql
-- Grupo 6 - BD2 - Actividad 10.1 (Maricielo Luna)
-- Muestra que tiene cada nodo de la estrategia hash.
--   docker exec nodo_a psql -U postgres -d distribuido -v nodo=A -f /nodos/hash_verificar.sql
--   (igual con nodo_b -v nodo=B y nodo_c -v nodo=C)

SELECT :'nodo' = 'A' AS es_a, :'nodo' = 'B' AS es_b, :'nodo' = 'C' AS es_c \gset
\if :es_a
    \set k 0
\endif
\if :es_b
    \set k 1
\endif
\if :es_c
    \set k 2
\endif

\echo '>>> Filas por tabla en el nodo' :nodo
SELECT 'rutas' AS tabla, count(*) AS filas FROM rutas
UNION ALL SELECT 'conductores', count(*) FROM conductores
UNION ALL SELECT 'buses_h' || :k, count(*) FROM buses_h:k
UNION ALL SELECT 'viajes_h' || :k, count(*) FROM viajes_h:k;

\echo '>>> Viajes por zona en este nodo (con hash, cada nodo tiene viajes de las 3 zonas)'
SELECT r.zona, count(*) AS viajes
FROM viajes_h:k v JOIN rutas r USING (id_ruta)
GROUP BY r.zona ORDER BY r.zona;

\echo '>>> Viajes cuyo bus esta en este mismo nodo (con zona es el 100 %)'
SELECT count(*) FILTER (WHERE id_bus % 3 = :k) AS con_bus_local,
       count(*) AS total,
       round(100.0 * count(*) FILTER (WHERE id_bus % 3 = :k) / nullif(count(*), 0), 1) AS porcentaje
FROM viajes_h:k;

\echo '>>> Suscripciones de este nodo (A y C reciben conductores de B)'
-- una suscripcion puede tener mas de un proceso (en PG 18, uno extra para cargas grandes),
-- por eso se agrupa por nombre
SELECT subname AS suscripcion, bool_or(pid IS NOT NULL) AS recibiendo
FROM pg_stat_subscription WHERE relid IS NULL GROUP BY subname ORDER BY 1;

\echo '>>> Extension pg_hashing instalada'
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_hashing';
