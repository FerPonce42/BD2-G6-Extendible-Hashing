-- hash_h2.sql
-- Grupo 6 - BD2 - Actividad 10.1 (Maricielo Luna)
-- Estrategia hash (alternativa 2 de 8.1/8.2): fragmento 2, va en el nodo C.
-- Aqui caen los buses con id_bus mod 3 = 2 y los viajes con id_viaje mod 3 = 2.
-- Mismas columnas que la estrategia por zona (esquema_global.sql de Iair).
--
-- Diferencias con la estrategia por zona:
--   - El CHECK es por id mod 3, no por ruta: aqui entran buses y viajes de cualquier ruta.
--   - viajes_h2 NO tiene clave foranea a su bus: el bus casi siempre esta en otro nodo
--     (es la perdida de localidad de la seccion 3.3 de 8.1/8.2). La regla
--     "la ruta del viaje es la ruta de su bus" la garantiza el generador, no la base.

CREATE TABLE buses_h2 (
    id_bus     INTEGER     PRIMARY KEY CHECK (id_bus % 3 = 2),
    placa      VARCHAR(7)  NOT NULL,
    id_ruta    SMALLINT    NOT NULL REFERENCES rutas (id_ruta),
    capacidad  SMALLINT    NOT NULL CHECK (capacidad IN (20, 30, 40, 50))
);

CREATE TABLE viajes_h2 (
    id_viaje      INTEGER       PRIMARY KEY CHECK (id_viaje % 3 = 2),
    id_bus        INTEGER       NOT NULL,
    id_conductor  INTEGER       NOT NULL REFERENCES conductores (id_conductor),
    id_ruta       SMALLINT      NOT NULL REFERENCES rutas (id_ruta),
    salida        TIMESTAMP     NOT NULL,
    pasajeros     SMALLINT      NOT NULL CHECK (pasajeros >= 0),
    tarifa        NUMERIC(6,2)  NOT NULL CHECK (tarifa >= 0)
);

-- El mismo B-tree que en la estrategia por zona (L2: una ruta en un rango de fechas),
-- para que la comparacion de la 10.1 sea pareja
CREATE INDEX idx_viajes_h2_ruta_salida ON viajes_h2 (id_ruta, salida);
