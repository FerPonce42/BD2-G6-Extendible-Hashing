-- plan_replicacion.sql
-- Grupo 6 - BD2 - Actividad 8.3 (Fabricio Stelman)
--
-- Plan de replicacion como TABLAS: que se replica, desde que nodo y hacia cual,
-- y las comprobaciones y el costo esperado calculados con consultas.
-- Parte de la fragmentacion y la asignacion de 8.1 y 8.2 (Iair Suico):
--   A = Norte, B = Centro (nodo central), C = Sur; latencias A-B 20, A-C 40, B-C 25 ms.
-- Es SQL estandar: no necesita los datos de viajes ni los nodos levantados.
-- Se puede correr en cualquier base de PostgreSQL:
--   psql -U postgres -d <base> -f replicacion/plan_replicacion.sql

DROP VIEW  IF EXISTS v_costo_esperado;
DROP VIEW  IF EXISTS v_almacenamiento;
DROP VIEW  IF EXISTS v_espera_escritura_sincrona;
DROP VIEW  IF EXISTS v_distancia;
DROP VIEW  IF EXISTS v_tolerancia;
DROP VIEW  IF EXISTS v_copias;
DROP TABLE IF EXISTS replicas;
DROP TABLE IF EXISTS objetos;
DROP TABLE IF EXISTS zonas;
DROP TABLE IF EXISTS latencias;
DROP TABLE IF EXISTS nodos;

-- ------------------------------------------------------------ nodos y latencias (rubrica 6.3)
CREATE TABLE nodos (
    nodo CHAR(1) PRIMARY KEY
);
INSERT INTO nodos VALUES ('A'), ('B'), ('C');

-- Se guarda en los dos sentidos, y 0 ms de un nodo a si mismo.
CREATE TABLE latencias (
    nodo_a CHAR(1) NOT NULL REFERENCES nodos (nodo),
    nodo_b CHAR(1) NOT NULL REFERENCES nodos (nodo),
    ms     INTEGER NOT NULL CHECK (ms >= 0),
    PRIMARY KEY (nodo_a, nodo_b)
);
INSERT INTO latencias (nodo_a, nodo_b, ms) VALUES
    ('A','A', 0), ('B','B', 0), ('C','C', 0),
    ('A','B',20), ('B','A',20),
    ('A','C',40), ('C','A',40),
    ('B','C',25), ('C','B',25);

-- ------------------------------------------------------------ zonas (8.1 y 8.2)
-- nodo: donde esta el fragmento principal de la zona. peso_trafico: 30/40/30.
CREATE TABLE zonas (
    zona          VARCHAR(6)   PRIMARY KEY CHECK (zona IN ('Norte', 'Centro', 'Sur')),
    nodo          CHAR(1)      NOT NULL REFERENCES nodos (nodo),
    peso_trafico  NUMERIC(3,2) NOT NULL CHECK (peso_trafico > 0 AND peso_trafico <= 1)
);
INSERT INTO zonas (zona, nodo, peso_trafico) VALUES
    ('Norte',  'A', 0.30),
    ('Centro', 'B', 0.40),
    ('Sur',    'C', 0.30);

-- ------------------------------------------------------------ objetos a replicar
-- Los 6 fragmentos de buses y viajes, mas conductores y rutas (que no se fragmentan).
-- filas: valores de diseno (1 200 000 viajes y 100 000 buses repartidos 30/40/30).
CREATE TABLE objetos (
    objeto          VARCHAR(20) PRIMARY KEY,
    relacion        VARCHAR(12) NOT NULL,
    zona            VARCHAR(6)  REFERENCES zonas (zona),   -- NULL en conductores y rutas
    nodo_primario   CHAR(1)     NOT NULL REFERENCES nodos (nodo),
    filas           INTEGER     NOT NULL
);
INSERT INTO objetos (objeto, relacion, zona, nodo_primario, filas) VALUES
    ('viajes_norte',  'viajes', 'Norte',  'A',  360000),
    ('viajes_centro', 'viajes', 'Centro', 'B',  480000),
    ('viajes_sur',    'viajes', 'Sur',    'C',  360000),
    ('buses_norte',   'buses',  'Norte',  'A',   30000),
    ('buses_centro',  'buses',  'Centro', 'B',   40000),
    ('buses_sur',     'buses',  'Sur',    'C',   30000),
    ('conductores',   'conductores', NULL, 'B',   5000),
    ('rutas',         'rutas',       NULL, 'B',     10);

-- ------------------------------------------------------------ plan de replicacion (8.3)
-- Copia principal + replicas. Todas las replicas de fragmentos son asincronas.
-- 'carga_fija': rutas casi no cambia (10 filas), se carga igual en los 3 nodos y no usa
-- replicacion logica.
CREATE TABLE replicas (
    objeto         VARCHAR(20) NOT NULL REFERENCES objetos (objeto),
    nodo_replica   CHAR(1)     NOT NULL REFERENCES nodos (nodo),
    modo           VARCHAR(12) NOT NULL CHECK (modo IN ('asincrona', 'sincrona', 'carga_fija')),
    PRIMARY KEY (objeto, nodo_replica)
);
INSERT INTO replicas (objeto, nodo_replica, modo) VALUES
    ('viajes_norte',  'B', 'asincrona'),   -- Norte (A) -> B: 20 ms
    ('buses_norte',   'B', 'asincrona'),
    ('viajes_centro', 'A', 'asincrona'),   -- Centro (B) -> A: 20 ms
    ('buses_centro',  'A', 'asincrona'),
    ('viajes_sur',    'B', 'asincrona'),   -- Sur (C) -> B: 25 ms
    ('buses_sur',     'B', 'asincrona'),
    ('conductores',   'A', 'asincrona'),   -- chica y casi solo de lectura: a los otros dos nodos
    ('conductores',   'C', 'asincrona'),
    ('rutas',         'A', 'carga_fija'),
    ('rutas',         'C', 'carga_fija');

-- ------------------------------------------------------------ copias (principal + replicas)
CREATE VIEW v_copias AS
SELECT o.objeto, o.relacion, o.zona, o.nodo_primario AS nodo, 'principal' AS rol, o.filas
FROM objetos o
UNION ALL
SELECT o.objeto, o.relacion, o.zona, r.nodo_replica, 'replica', o.filas
FROM replicas r JOIN objetos o ON o.objeto = r.objeto;

-- ------------------------------------------------------------ comprobaciones
-- 1) Ninguna replica esta en el mismo nodo que su copia principal (debe dar 0 filas).
--    SELECT * FROM replicas r JOIN objetos o ON o.objeto = r.objeto
--     WHERE r.nodo_replica = o.nodo_primario;

-- 2) Tolerancia a la caida de UN nodo: para cada nodo caido, cuantas copias vivas le quedan
--    a cada objeto. Debe dar 0 filas con copias_vivas = 0.
CREATE VIEW v_tolerancia AS
SELECT n.nodo AS nodo_caido,
       o.objeto,
       (SELECT count(*) FROM v_copias c
         WHERE c.objeto = o.objeto AND c.nodo <> n.nodo) AS copias_vivas
FROM nodos n CROSS JOIN objetos o;

-- ------------------------------------------------------------ costo de red esperado
-- Mismo modelo que la seccion 4.4 de 8.1/8.2: solo latencia de red, mezcla de 4.3
-- (L3 10 %, L4 5 %, escrituras 30 %), cliente conectado al nodo de su zona.
-- Con replicas, una lectura de otra zona va a la copia mas cercana.

-- Distancia de cada zona cliente a la copia mas cercana de los viajes de cada zona dato.
CREATE VIEW v_distancia AS
SELECT zc.zona AS zona_cliente,
       zd.zona AS zona_dato,
       (SELECT MIN(l.ms)
          FROM v_copias c
          JOIN latencias l ON l.nodo_a = zc.nodo AND l.nodo_b = c.nodo
         WHERE c.relacion = 'viajes' AND c.zona = zd.zona) AS ms
FROM zonas zc CROSS JOIN zonas zd;

-- Espera de una escritura de viajes por zona SI la replica fuera sincrona:
-- hay que esperar a la replica mas lejana. Con replicas asincronas no se espera.
CREATE VIEW v_espera_escritura_sincrona AS
SELECT z.zona, z.peso_trafico,
       COALESCE(MAX(l.ms), 0) AS espera_ms
FROM zonas z
LEFT JOIN replicas r ON r.objeto = 'viajes_' || lower(z.zona)
LEFT JOIN latencias l ON l.nodo_a = z.nodo AND l.nodo_b = r.nodo_replica
GROUP BY z.zona, z.peso_trafico;

-- Datos que guarda cada nodo.
CREATE VIEW v_almacenamiento AS
SELECT nodo,
       SUM(filas) FILTER (WHERE relacion = 'viajes') AS filas_viajes,
       ROUND(100.0 * SUM(filas) FILTER (WHERE relacion = 'viajes')
             / (SELECT SUM(filas) FROM objetos WHERE relacion = 'viajes'), 1) AS pct_de_viajes
FROM v_copias
GROUP BY nodo;

-- Latencia de red esperada por operacion (ms).
CREATE VIEW v_costo_esperado AS
WITH
l3 AS (  -- leer de otra zona: promedio de las dos zonas ajenas, ponderado por trafico
    SELECT SUM(z.peso_trafico * x.ms_prom) AS ms
    FROM zonas z
    JOIN (SELECT zona_cliente, AVG(ms * 1.0) AS ms_prom
            FROM v_distancia WHERE zona_cliente <> zona_dato
           GROUP BY zona_cliente) x ON x.zona_cliente = z.zona
),
l4 AS (  -- reporte global: se pregunta en paralelo, manda la copia mas lejana
    SELECT SUM(z.peso_trafico * x.ms_max) AS ms
    FROM zonas z
    JOIN (SELECT zona_cliente, MAX(ms) AS ms_max
            FROM v_distancia GROUP BY zona_cliente) x ON x.zona_cliente = z.zona
),
esc AS (
    SELECT SUM(peso_trafico * espera_ms) AS ms FROM v_espera_escritura_sincrona
)
SELECT ROUND(CAST(l3.ms AS NUMERIC), 2)                                  AS l3_ms,
       ROUND(CAST(l4.ms AS NUMERIC), 2)                                  AS l4_ms,
       ROUND(CAST(esc.ms AS NUMERIC), 2)                                 AS escritura_sincrona_ms,
       ROUND(CAST(0.10 * l3.ms + 0.05 * l4.ms AS NUMERIC), 2)            AS por_operacion_asincrona_ms,
       ROUND(CAST(0.10 * l3.ms + 0.05 * l4.ms + 0.30 * esc.ms AS NUMERIC), 2) AS por_operacion_sincrona_ms
FROM l3, l4, esc;

-- ------------------------------------------------------------ consultas para correr
-- Plan completo:
--   SELECT objeto, nodo_primario, nodo_replica, modo FROM objetos JOIN replicas USING (objeto) ORDER BY 1, 3;
-- Caida de un nodo (debe dar 0 filas):
--   SELECT * FROM v_tolerancia WHERE copias_vivas = 0;
-- Datos por nodo (A 70 %, B 100 %, C 30 % de los viajes):
--   SELECT * FROM v_almacenamiento ORDER BY nodo;
-- Costo esperado (L3 10.5, L4 13.5, escritura sincrona 21.5, asincrona 1.73, sincrona 8.18):
--   SELECT * FROM v_costo_esperado;
