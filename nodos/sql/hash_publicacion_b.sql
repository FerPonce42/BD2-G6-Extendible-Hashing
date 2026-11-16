-- hash_publicacion_b.sql
-- Grupo 6 - BD2 - Actividad 10.1 (Maricielo Luna)
-- Estrategia hash: B publica conductores, igual que en la estrategia por zona.
-- Los fragmentos h0, h1 y h2 no se publican: no tienen replica.
CREATE PUBLICATION pub_conductores FOR TABLE conductores;
