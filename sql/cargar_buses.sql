-- cargar_buses.sql
-- Grupo 6 - BD2 - Extendible Hashing
-- Crea la tabla buses y carga uno de los CSV que genera scripts/generar_datos.py
--
-- OJO: la tabla NO tiene PRIMARY KEY a proposito, porque PostgreSQL crearia
-- solo un indice B-tree y necesitamos probar tambien el caso "sin indice".
--
-- Uso (desde la carpeta del proyecto):
--   psql -U postgres -d postgres -f sql/cargar_buses.sql
-- Para cargar otro archivo, cambiar el nombre en la linea del \copy.

DROP TABLE IF EXISTS buses;

CREATE TABLE buses (
    id_bus    INTEGER,
    placa     VARCHAR(7),
    ruta      VARCHAR(5),
    capacidad INTEGER
);

\copy buses FROM 'data/D2_aleatorio_100000.csv' WITH (FORMAT csv, HEADER true);

-- verificacion rapida
SELECT COUNT(*) AS total_filas FROM buses;
SELECT * FROM buses LIMIT 5;
