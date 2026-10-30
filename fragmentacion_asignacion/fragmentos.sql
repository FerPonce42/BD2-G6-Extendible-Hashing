-- fragmentos.sql
-- Grupo 6 - BD2 - Actividades 8.1 y 8.2 (Iair Suico)
--
-- Define los fragmentos de la alternativa elegida (horizontal por zona) como
-- consultas sobre el esquema global, y comprueba que la fragmentacion es correcta.
-- Se corre sobre UNA base con esquema_global.sql ya cargado y con datos.
-- No crea los nodos: eso es la actividad 9.1. Sirve para validar el diseno y
-- como referencia de que filas va a cada nodo.
--
--   Fragmento        Definicion                                  Nodo (8.2)
--   rutas_norte      zona = 'Norte'                              A
--   rutas_centro     zona = 'Centro'                             B
--   rutas_sur        zona = 'Sur'                                C
--   buses_<zona>     buses  semijoin  rutas_<zona>  (derivada)   mismo nodo que su zona
--   viajes_<zona>    viajes semijoin  rutas_<zona>  (derivada)   mismo nodo que su zona
--   conductores      sin fragmentar                              B (copia principal; replicas = 8.3)
--
-- Uso: psql -U postgres -d <base> -f fragmentacion_asignacion/fragmentos.sql

-- ------------------------------------------------------------ fragmentos
-- Fragmentacion horizontal PRIMARIA de rutas (por el atributo zona)
CREATE OR REPLACE VIEW rutas_norte  AS SELECT * FROM rutas WHERE zona = 'Norte';
CREATE OR REPLACE VIEW rutas_centro AS SELECT * FROM rutas WHERE zona = 'Centro';
CREATE OR REPLACE VIEW rutas_sur    AS SELECT * FROM rutas WHERE zona = 'Sur';

-- Fragmentacion horizontal DERIVADA de buses (semijoin con el fragmento de rutas)
CREATE OR REPLACE VIEW buses_norte  AS SELECT b.* FROM buses b WHERE b.id_ruta IN (SELECT id_ruta FROM rutas_norte);
CREATE OR REPLACE VIEW buses_centro AS SELECT b.* FROM buses b WHERE b.id_ruta IN (SELECT id_ruta FROM rutas_centro);
CREATE OR REPLACE VIEW buses_sur    AS SELECT b.* FROM buses b WHERE b.id_ruta IN (SELECT id_ruta FROM rutas_sur);

-- Fragmentacion horizontal DERIVADA de viajes (semijoin con el fragmento de rutas)
CREATE OR REPLACE VIEW viajes_norte  AS SELECT v.* FROM viajes v WHERE v.id_ruta IN (SELECT id_ruta FROM rutas_norte);
CREATE OR REPLACE VIEW viajes_centro AS SELECT v.* FROM viajes v WHERE v.id_ruta IN (SELECT id_ruta FROM rutas_centro);
CREATE OR REPLACE VIEW viajes_sur    AS SELECT v.* FROM viajes v WHERE v.id_ruta IN (SELECT id_ruta FROM rutas_sur);

-- ------------------------------------------------------------ correctitud
-- 1) Completitud: cada fila de la relacion global esta en algun fragmento.
-- 2) Disyuncion:  ninguna fila esta en dos fragmentos.
-- 3) Reconstruccion: la union de los fragmentos es igual a la relacion global.
-- Las tres se cumplen si la suma de los fragmentos es igual al total
-- y la union sin repetidos tambien.

\echo '>>> Tamano de cada fragmento'
SELECT 'rutas' AS relacion,
       (SELECT count(*) FROM rutas_norte)  AS norte_A,
       (SELECT count(*) FROM rutas_centro) AS centro_B,
       (SELECT count(*) FROM rutas_sur)    AS sur_C,
       (SELECT count(*) FROM rutas)        AS total
UNION ALL
SELECT 'buses',
       (SELECT count(*) FROM buses_norte), (SELECT count(*) FROM buses_centro),
       (SELECT count(*) FROM buses_sur),   (SELECT count(*) FROM buses)
UNION ALL
SELECT 'viajes',
       (SELECT count(*) FROM viajes_norte), (SELECT count(*) FROM viajes_centro),
       (SELECT count(*) FROM viajes_sur),   (SELECT count(*) FROM viajes);

\echo '>>> Completitud y disyuncion (las dos columnas deben ser iguales al total)'
SELECT 'buses' AS relacion,
       (SELECT count(*) FROM (SELECT * FROM buses_norte UNION ALL SELECT * FROM buses_centro UNION ALL SELECT * FROM buses_sur) u) AS suma_fragmentos,
       (SELECT count(*) FROM (SELECT * FROM buses_norte UNION     SELECT * FROM buses_centro UNION     SELECT * FROM buses_sur) u) AS union_sin_repetidos,
       (SELECT count(*) FROM buses) AS total
UNION ALL
SELECT 'viajes',
       (SELECT count(*) FROM (SELECT * FROM viajes_norte UNION ALL SELECT * FROM viajes_centro UNION ALL SELECT * FROM viajes_sur) u),
       (SELECT count(*) FROM (SELECT * FROM viajes_norte UNION     SELECT * FROM viajes_centro UNION     SELECT * FROM viajes_sur) u),
       (SELECT count(*) FROM viajes);

\echo '>>> Co-localizacion: viajes cuyo bus esta en OTRA zona (debe ser 0)'
SELECT count(*) AS viajes_con_bus_de_otra_zona
FROM viajes v JOIN buses b ON b.id_bus = v.id_bus
WHERE b.id_ruta <> v.id_ruta;
