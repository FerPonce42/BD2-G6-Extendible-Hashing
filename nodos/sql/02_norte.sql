-- 02_norte.sql
-- Grupo 6 - BD2 - Actividad 9.1 (Maricielo Luna)
-- Fragmentos de la zona Norte como TABLAS (las vistas no se pueden replicar).
-- Va en los nodos A (principal) y B (replica).
-- El CHECK de id_ruta hace que en esta tabla solo entren filas de la zona Norte
-- (rutas 1, 2, 3), asi el fragmento no se puede mezclar con otra zona.
-- La clave foranea doble (id_bus, id_ruta) obliga a que cada viaje tenga la misma ruta
-- que su bus (regla 2 de 8.1/8.2). Si el generador rompe esa regla, la carga falla.

CREATE TABLE buses_norte (
    id_bus     INTEGER     PRIMARY KEY,
    placa      VARCHAR(7)  NOT NULL,
    id_ruta    SMALLINT    NOT NULL REFERENCES rutas (id_ruta) CHECK (id_ruta IN (1, 2, 3)),
    capacidad  SMALLINT    NOT NULL CHECK (capacidad IN (20, 30, 40, 50)),
    UNIQUE (id_bus, id_ruta)   -- para que viajes pueda pedir el par (bus, ruta)
);

CREATE TABLE viajes_norte (
    id_viaje      INTEGER       PRIMARY KEY,
    id_bus        INTEGER       NOT NULL,
    id_conductor  INTEGER       NOT NULL REFERENCES conductores (id_conductor),
    id_ruta       SMALLINT      NOT NULL REFERENCES rutas (id_ruta) CHECK (id_ruta IN (1, 2, 3)),
    salida        TIMESTAMP     NOT NULL,
    pasajeros     SMALLINT      NOT NULL CHECK (pasajeros >= 0),
    tarifa        NUMERIC(6,2)  NOT NULL CHECK (tarifa >= 0),
    -- regla de 8.1/8.2: la ruta del viaje es la ruta de su bus, y el bus es de esta zona
    FOREIGN KEY (id_bus, id_ruta) REFERENCES buses_norte (id_bus, id_ruta)
);

-- B-tree para los viajes de una ruta en un rango de fechas (L2, seccion 5 de 8.1/8.2)
CREATE INDEX idx_viajes_norte_ruta_salida ON viajes_norte (id_ruta, salida);
