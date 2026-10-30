-- esquema_global.sql
-- Grupo 6 - BD2 - Actividad 8.1 (Iair Suico)
--
-- Esquema GLOBAL de la parte distribuida: 4 relaciones vinculadas.
-- Es la vista "como si todo estuviera en un solo nodo". La forma en que se
-- reparte entre los nodos A, B y C esta en fragmentos.sql y en el informe.
--
--   rutas (10)  <──  buses (100 000)  <──  viajes (1 200 000)  ──>  conductores (5 000)
--     └──────────────────────────────────────────┘
--
-- Relacion principal: viajes (mas de 1 000 000 de registros, como pide la rubrica 6.3.1).
-- Las 10 rutas y sus codigos son los mismos que usa scripts/generar_datos.py,
-- asi la tabla buses de la etapa I encaja en este esquema.

DROP TABLE IF EXISTS viajes;
DROP TABLE IF EXISTS buses;
DROP TABLE IF EXISTS conductores;
DROP TABLE IF EXISTS rutas;

-- Cada ruta pertenece a UNA zona. La zona es el criterio de fragmentacion.
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

-- Conductores: tabla chica que usan todas las zonas (no se fragmenta).
CREATE TABLE conductores (
    id_conductor   INTEGER      PRIMARY KEY,
    nombre         VARCHAR(60)  NOT NULL,
    licencia       VARCHAR(10)  NOT NULL UNIQUE,
    fecha_ingreso  DATE         NOT NULL
);

-- Buses: misma idea que la tabla buses de la etapa I, pero la ruta pasa a ser
-- una clave foranea. Un bus trabaja siempre en una sola ruta.
CREATE TABLE buses (
    id_bus     INTEGER     PRIMARY KEY,
    placa      VARCHAR(7)  NOT NULL,
    id_ruta    SMALLINT    NOT NULL REFERENCES rutas (id_ruta),
    capacidad  SMALLINT    NOT NULL CHECK (capacidad IN (20, 30, 40, 50))
);

-- Viajes: relacion principal. Cada fila es un viaje de un bus en su ruta.
-- id_ruta se guarda en el viaje (y debe ser la ruta del bus) para que el
-- fragmento de un viaje se pueda saber sin consultar otra tabla.
CREATE TABLE viajes (
    id_viaje      INTEGER       PRIMARY KEY,
    id_bus        INTEGER       NOT NULL REFERENCES buses (id_bus),
    id_conductor  INTEGER       NOT NULL REFERENCES conductores (id_conductor),
    id_ruta       SMALLINT      NOT NULL REFERENCES rutas (id_ruta),
    salida        TIMESTAMP     NOT NULL,
    pasajeros     SMALLINT      NOT NULL CHECK (pasajeros >= 0),
    tarifa        NUMERIC(6,2)  NOT NULL CHECK (tarifa >= 0)
);
