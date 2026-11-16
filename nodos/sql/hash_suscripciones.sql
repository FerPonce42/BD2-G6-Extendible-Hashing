-- hash_suscripciones.sql
-- Grupo 6 - BD2 - Actividad 10.1 (Maricielo Luna)
-- Estrategia hash: A y C se suscriben a conductores, que viene de B
-- (igual que sub_a_conductores y sub_c_conductores de la estrategia por zona).
-- B no se suscribe a nada.
--
-- Uso, cuando los 3 nodos hash ya estan levantados:
--   docker exec nodo_a psql -U postgres -d distribuido -v nodo=A -f /nodos/hash_suscripciones.sql
--   docker exec nodo_c psql -U postgres -d distribuido -v nodo=C -f /nodos/hash_suscripciones.sql

\set ON_ERROR_STOP on
SELECT :'nodo' = 'A' AS es_a, :'nodo' = 'C' AS es_c \gset

\if :es_a
    CREATE SUBSCRIPTION sub_a_conductores
        CONNECTION 'host=nodo_b port=5432 dbname=distribuido user=postgres password=password123'
        PUBLICATION pub_conductores
        WITH (copy_data = true);
\endif

\if :es_c
    CREATE SUBSCRIPTION sub_c_conductores
        CONNECTION 'host=nodo_b port=5432 dbname=distribuido user=postgres password=password123'
        PUBLICATION pub_conductores
        WITH (copy_data = true);
\endif

SELECT subname AS suscripcion, subenabled AS activa FROM pg_subscription ORDER BY 1;
