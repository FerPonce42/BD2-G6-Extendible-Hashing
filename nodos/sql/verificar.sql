-- verificar.sql
-- Grupo 6 - BD2 - Actividad 9.1 (Maricielo Luna)
-- Muestra que tiene cada nodo y si sus suscripciones estan funcionando.
--   docker exec nodo_a psql -U postgres -d distribuido -v nodo=A -f /nodos/verificar.sql
--   (igual con nodo_b -v nodo=B y nodo_c -v nodo=C)

SELECT :'nodo' = 'A' AS es_a, :'nodo' = 'B' AS es_b, :'nodo' = 'C' AS es_c \gset

\echo '>>> Filas por tabla en el nodo' :nodo
\if :es_a
SELECT 'rutas' AS tabla, 'todas' AS rol, count(*) AS filas FROM rutas
UNION ALL SELECT 'conductores',   'replica (de B)', count(*) FROM conductores
UNION ALL SELECT 'buses_norte',   'principal',      count(*) FROM buses_norte
UNION ALL SELECT 'viajes_norte',  'principal',      count(*) FROM viajes_norte
UNION ALL SELECT 'buses_centro',  'replica (de B)', count(*) FROM buses_centro
UNION ALL SELECT 'viajes_centro', 'replica (de B)', count(*) FROM viajes_centro;
\endif
\if :es_b
SELECT 'rutas' AS tabla, 'todas' AS rol, count(*) AS filas FROM rutas
UNION ALL SELECT 'conductores',   'principal',      count(*) FROM conductores
UNION ALL SELECT 'buses_centro',  'principal',      count(*) FROM buses_centro
UNION ALL SELECT 'viajes_centro', 'principal',      count(*) FROM viajes_centro
UNION ALL SELECT 'buses_norte',   'replica (de A)', count(*) FROM buses_norte
UNION ALL SELECT 'viajes_norte',  'replica (de A)', count(*) FROM viajes_norte
UNION ALL SELECT 'buses_sur',     'replica (de C)', count(*) FROM buses_sur
UNION ALL SELECT 'viajes_sur',    'replica (de C)', count(*) FROM viajes_sur;
\endif
\if :es_c
SELECT 'rutas' AS tabla, 'todas' AS rol, count(*) AS filas FROM rutas
UNION ALL SELECT 'conductores',   'replica (de B)', count(*) FROM conductores
UNION ALL SELECT 'buses_sur',     'principal',      count(*) FROM buses_sur
UNION ALL SELECT 'viajes_sur',    'principal',      count(*) FROM viajes_sur;
\endif

\echo '>>> Viajes cuyo bus tiene otra ruta (regla de 8.1/8.2, debe ser 0)'
\if :es_a
SELECT count(*) AS viajes_fuera_de_lugar FROM viajes_norte v JOIN buses_norte b USING (id_bus) WHERE b.id_ruta <> v.id_ruta;
\endif
\if :es_b
SELECT count(*) AS viajes_fuera_de_lugar FROM viajes_centro v JOIN buses_centro b USING (id_bus) WHERE b.id_ruta <> v.id_ruta;
\endif
\if :es_c
SELECT count(*) AS viajes_fuera_de_lugar FROM viajes_sur v JOIN buses_sur b USING (id_bus) WHERE b.id_ruta <> v.id_ruta;
\endif

\echo '>>> Suscripciones de este nodo (A: Centro y conductores, B: Norte y Sur, C: conductores)'
SELECT subname AS suscripcion, (pid IS NOT NULL) AS recibiendo, latest_end_time AS ultimo_dato
FROM pg_stat_subscription WHERE relid IS NULL ORDER BY 1;

\echo '>>> Publicaciones de este nodo y quien las esta leyendo'
SELECT application_name AS suscriptor, state AS estado, replay_lag AS retraso
FROM pg_stat_replication ORDER BY 1;

\echo '>>> Extension pg_hashing instalada'
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_hashing';
