-- datos_prueba.sql
-- Grupo 6 - BD2 - Actividad 9.1 (Maricielo Luna)
-- Datos chicos SOLO para comprobar que los nodos y la replicacion funcionan.
-- Son el 1 % del tamano de diseno (1 000 buses y 12 000 viajes, repartidos 30/40/30).
-- Los datos reales (1 200 000 viajes) salen del generador de Iair.
--
-- Igual que en la receta de Fabricio, cada fila se inserta SOLO en su nodo principal;
-- a las replicas les llega por la suscripcion.
-- Se respetan las dos reglas de 8.1/8.2: un bus tiene una sola ruta y la ruta del
-- viaje es la ruta de su bus (el viaje se arma con un JOIN a su bus).
--
-- Orden: primero B (tiene los conductores), esperar unos segundos a que lleguen
-- a A y C, y despues A y C (sus viajes usan los conductores).
-- Si se corre A o C antes de que lleguen los conductores, el script avisa y no
-- inserta nada (la replica es asincrona: ver seccion 7 de 8.3). Basta con esperar
-- y volver a correrlo. Cada nodo carga todo en una sola transaccion.
--   docker exec nodo_b psql -U postgres -d distribuido -v nodo=B -f /nodos/datos_prueba.sql
--   docker exec nodo_a psql -U postgres -d distribuido -v nodo=A -f /nodos/datos_prueba.sql
--   docker exec nodo_c psql -U postgres -d distribuido -v nodo=C -f /nodos/datos_prueba.sql

\set ON_ERROR_STOP on
SELECT :'nodo' = 'A' AS es_a, :'nodo' = 'B' AS es_b, :'nodo' = 'C' AS es_c \gset

\if :es_b
    BEGIN;
    -- 50 conductores (principal en B)
    INSERT INTO conductores (id_conductor, nombre, licencia, fecha_ingreso)
    SELECT g, 'Conductor ' || g, 'L' || lpad(g::text, 6, '0'), DATE '2020-01-01' + g
    FROM generate_series(1, 50) AS g;

    -- Centro: buses 301..700 en las rutas 4 a 7, viajes 3601..8400
    INSERT INTO buses_centro (id_bus, placa, id_ruta, capacidad)
    SELECT g, 'CEN-' || lpad((g % 1000)::text, 3, '0'), 4 + g % 4, (ARRAY[20, 30, 40, 50])[1 + g % 4]
    FROM generate_series(301, 700) AS g;

    INSERT INTO viajes_centro (id_viaje, id_bus, id_conductor, id_ruta, salida, pasajeros, tarifa)
    SELECT g, b.id_bus, 1 + g % 50, b.id_ruta, TIMESTAMP '2026-01-01' + g * INTERVAL '7 minutes', g % 51, 1.50
    FROM generate_series(3601, 8400) AS g
    JOIN buses_centro b ON b.id_bus = 301 + g % 400;
    COMMIT;
\endif

-- A y C necesitan que ya hayan llegado los 50 conductores desde B
\if :es_b
\else
    SELECT count(*) = 50 AS llegaron_conductores FROM conductores \gset
    \if :llegaron_conductores
    \else
        \echo 'Todavia no llegan los conductores desde B. Espera unos segundos y vuelve a correr este script.'
        \quit
    \endif
\endif

\if :es_a
    BEGIN;
    -- Norte: buses 1..300 en las rutas 1 a 3, viajes 1..3600
    INSERT INTO buses_norte (id_bus, placa, id_ruta, capacidad)
    SELECT g, 'NOR-' || lpad(g::text, 3, '0'), 1 + g % 3, (ARRAY[20, 30, 40, 50])[1 + g % 4]
    FROM generate_series(1, 300) AS g;

    INSERT INTO viajes_norte (id_viaje, id_bus, id_conductor, id_ruta, salida, pasajeros, tarifa)
    SELECT g, b.id_bus, 1 + g % 50, b.id_ruta, TIMESTAMP '2026-01-01' + g * INTERVAL '7 minutes', g % 51, 1.50
    FROM generate_series(1, 3600) AS g
    JOIN buses_norte b ON b.id_bus = 1 + g % 300;
    COMMIT;
\endif

\if :es_c
    BEGIN;
    -- Sur: buses 701..1000 en las rutas 8 a 10, viajes 8401..12000
    INSERT INTO buses_sur (id_bus, placa, id_ruta, capacidad)
    SELECT g, 'SUR-' || lpad((g % 1000)::text, 3, '0'), 8 + g % 3, (ARRAY[20, 30, 40, 50])[1 + g % 4]
    FROM generate_series(701, 1000) AS g;

    INSERT INTO viajes_sur (id_viaje, id_bus, id_conductor, id_ruta, salida, pasajeros, tarifa)
    SELECT g, b.id_bus, 1 + g % 50, b.id_ruta, TIMESTAMP '2026-01-01' + g * INTERVAL '7 minutes', g % 51, 1.50
    FROM generate_series(8401, 12000) AS g
    JOIN buses_sur b ON b.id_bus = 701 + g % 300;
    COMMIT;
\endif
