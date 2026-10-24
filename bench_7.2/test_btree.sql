DROP INDEX IF EXISTS idx_btree_test;

\timing on

-- Crear índice B-tree tradicional
CREATE INDEX idx_btree_test ON buses USING btree (id_bus);

BEGIN;
-- Inserciones W3 acordadas (20,000 claves en tabla buses)
INSERT INTO buses (id_bus, placa, ruta, capacidad)
SELECT x + (SELECT COALESCE(MAX(id_bus), 0) FROM buses), 'W3-TEST', 'RUTA1', 40
FROM generate_series(1, 20000) AS x;
ROLLBACK;

\timing off