DROP INDEX IF EXISTS idx_btree_test;
CREATE INDEX idx_btree_test ON buses USING btree (id_bus);

\timing on
BEGIN;
-- Inserciones W3 dinámicas
INSERT INTO buses (id_bus, placa, ruta, capacidad)
SELECT x + (SELECT COALESCE(MAX(id_bus), 0) FROM buses), 'W3-TEST', 'RUTA1', 40
FROM generate_series(1, :n_inserts) AS x;
ROLLBACK;
\timing off