-- inserciones_sin_indice.sql
-- Grupo 6 - BD2 - Actividad 7.1: inserciones (W3) sin indice (Fernando Ponce)
-- Variable: n_inserts (cantidad de claves nuevas)
-- Mismo metodo que bench_7.2: claves max+1 .. max+n_inserts, BEGIN, INSERT, ROLLBACK.
-- El maximo se calcula antes de medir: sin indice costaria un recorrido de la tabla
-- y se sumaria al tiempo de la insercion.

\set ON_ERROR_STOP on

SELECT COALESCE(MAX(id_bus), 0) AS maxid FROM buses \gset

\timing on
BEGIN;
INSERT INTO buses (id_bus, placa, ruta, capacidad)
SELECT x + :maxid, 'W3-TEST', 'RUTA1', 40
FROM generate_series(1, :n_inserts) AS x;
ROLLBACK;
\timing off
