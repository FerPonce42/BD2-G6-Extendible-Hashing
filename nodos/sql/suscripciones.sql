-- suscripciones.sql
-- Grupo 6 - BD2 - Actividad 9.1 (Maricielo Luna)
-- PASO 2 de replicacion_nodos.sql (Fabricio, 8.3): cada nodo se suscribe a lo que replica.
-- Se corre una vez en cada nodo, cuando los 3 ya estan levantados
-- (las publicaciones del PASO 1 se crean solas al iniciar cada nodo).
-- Cambio respecto a la receta de Fabricio: dbname=distribuido en vez de hashing_db.
--
-- Uso (la variable nodo dice en que nodo se esta corriendo):
--   docker exec nodo_a psql -U postgres -d distribuido -v nodo=A -f /nodos/suscripciones.sql
--   docker exec nodo_b psql -U postgres -d distribuido -v nodo=B -f /nodos/suscripciones.sql
--   docker exec nodo_c psql -U postgres -d distribuido -v nodo=C -f /nodos/suscripciones.sql

\set ON_ERROR_STOP on
SELECT :'nodo' = 'A' AS es_a, :'nodo' = 'B' AS es_b, :'nodo' = 'C' AS es_c \gset

\if :es_a
    -- A guarda la replica de Centro y de conductores, que vienen de B
    CREATE SUBSCRIPTION sub_a_centro
        CONNECTION 'host=nodo_b port=5432 dbname=distribuido user=postgres password=password123'
        PUBLICATION pub_centro
        WITH (copy_data = true);
    CREATE SUBSCRIPTION sub_a_conductores
        CONNECTION 'host=nodo_b port=5432 dbname=distribuido user=postgres password=password123'
        PUBLICATION pub_conductores
        WITH (copy_data = true);
\endif

\if :es_b
    -- B guarda la replica de Norte (viene de A) y de Sur (viene de C)
    CREATE SUBSCRIPTION sub_b_norte
        CONNECTION 'host=nodo_a port=5432 dbname=distribuido user=postgres password=password123'
        PUBLICATION pub_norte
        WITH (copy_data = true);
    CREATE SUBSCRIPTION sub_b_sur
        CONNECTION 'host=nodo_c port=5432 dbname=distribuido user=postgres password=password123'
        PUBLICATION pub_sur
        WITH (copy_data = true);
\endif

\if :es_c
    -- C guarda la replica de conductores, que viene de B
    CREATE SUBSCRIPTION sub_c_conductores
        CONNECTION 'host=nodo_b port=5432 dbname=distribuido user=postgres password=password123'
        PUBLICATION pub_conductores
        WITH (copy_data = true);
\endif

SELECT subname AS suscripcion, subenabled AS activa FROM pg_subscription ORDER BY 1;
