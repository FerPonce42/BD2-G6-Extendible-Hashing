-- 05_publicacion_b.sql
-- Grupo 6 - BD2 - Actividad 9.1 (Maricielo Luna)
-- PASO 1 de replicacion_nodos.sql (Fabricio, 8.3) en el nodo B: B publica Centro y conductores.
CREATE PUBLICATION pub_centro      FOR TABLE buses_centro, viajes_centro;
CREATE PUBLICATION pub_conductores FOR TABLE conductores;
