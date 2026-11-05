-- 01_comun.sql
-- Grupo 6 - BD2 - Actividad 9.1 (Maricielo Luna)
-- Lo que tienen los 3 nodos: la extension, rutas (completa) y conductores.
-- Las columnas son las de fragmentacion_asignacion/esquema_global.sql (Iair).
--   rutas:       las 10 filas se cargan igual en los 3 nodos (no se replica, 8.3)
--   conductores: principal en B, replica en A y C (llega por la suscripcion)

CREATE EXTENSION IF NOT EXISTS pg_hashing;

CREATE TABLE rutas (
    id_ruta  SMALLINT    PRIMARY KEY,
    codigo   VARCHAR(5)  NOT NULL UNIQUE,
    zona     VARCHAR(6)  NOT NULL CHECK (zona IN ('Norte', 'Centro', 'Sur'))
);

INSERT INTO rutas (id_ruta, codigo, zona) VALUES
    (1, '1A',  'Norte'),
    (2, '2B',  'Norte'),
    (3, '3C',  'Norte'),
    (4, '5A',  'Centro'),
    (5, '7B',  'Centro'),
    (6, '10',  'Centro'),
    (7, '12C', 'Centro'),
    (8, '15',  'Sur'),
    (9, '20A', 'Sur'),
    (10,'C1',  'Sur');

CREATE TABLE conductores (
    id_conductor   INTEGER      PRIMARY KEY,
    nombre         VARCHAR(60)  NOT NULL,
    licencia       VARCHAR(10)  NOT NULL UNIQUE,
    fecha_ingreso  DATE         NOT NULL
);
