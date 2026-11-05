-- 05_publicacion_a.sql
-- Grupo 6 - BD2 - Actividad 9.1 (Maricielo Luna)
-- PASO 1 de replicacion_nodos.sql (Fabricio, 8.3) en el nodo A: A publica Norte.
CREATE PUBLICATION pub_norte FOR TABLE buses_norte, viajes_norte;
