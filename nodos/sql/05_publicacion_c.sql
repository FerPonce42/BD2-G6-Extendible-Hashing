-- 05_publicacion_c.sql
-- Grupo 6 - BD2 - Actividad 9.1 (Maricielo Luna)
-- PASO 1 de replicacion_nodos.sql (Fabricio, 8.3) en el nodo C: C publica Sur.
CREATE PUBLICATION pub_sur FOR TABLE buses_sur, viajes_sur;
