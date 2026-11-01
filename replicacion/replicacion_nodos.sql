-- replicacion_nodos.sql
-- Grupo 6 - BD2 - Actividad 8.3 (Fabricio Stelman)
--
-- Comandos de replicacion logica de PostgreSQL para el plan de plan_replicacion.sql.
-- Es la receta para la 9.1 (levantar los nodos): NO se corre en una sola base.
-- Cada bloque dice en que nodo se ejecuta.
--
-- Antes de empezar, cada nodo (A, B y C) tiene que:
--   1) arrancar con wal_level = logical
--        (en docker-compose.yml: command: ["postgres", "-c", "wal_level=logical"])
--   2) tener la extension:   CREATE EXTENSION IF NOT EXISTS pg_hashing;
--   3) tener creadas como TABLAS (no vistas, las vistas no se pueden publicar) los fragmentos
--      que guarda segun plan_replicacion.sql, con el mismo nombre y las mismas columnas en
--      todos los nodos (definidas en esquema_global.sql):
--        A: buses_norte,  viajes_norte,  buses_centro, viajes_centro, conductores, rutas
--        B: buses_centro, viajes_centro, buses_norte,  viajes_norte,
--           buses_sur,    viajes_sur,    conductores,  rutas
--        C: buses_sur,    viajes_sur,    conductores,  rutas
--   4) cargar rutas (10 filas, las mismas en los 3 nodos).
--
-- Los datos se cargan SOLO en el nodo principal de cada fragmento. Las tablas de replica
-- se dejan vacias: la suscripcion las llena sola con copy_data = true.
-- Las tablas de replica no se escriben a mano (solo las escribe la suscripcion).
--
-- Conexiones: nodo_a, nodo_b y nodo_c son los nombres de host que defina la 9.1.
-- Usuario y clave: los de docker-compose.yml, solo para el laboratorio. En un entorno real
-- se usa un rol con permiso REPLICATION.

-- Orden: PASO 1 en los tres nodos (publicaciones), y despues PASO 2 en los tres (suscripciones),
-- porque una suscripcion necesita que la publicacion ya exista.

-- =========================================================== PASO 1: PUBLICACIONES
-- En el nodo A (Norte principal):
CREATE PUBLICATION pub_norte FOR TABLE buses_norte, viajes_norte;

-- En el nodo B (Centro principal y copia principal de conductores):
CREATE PUBLICATION pub_centro      FOR TABLE buses_centro, viajes_centro;
CREATE PUBLICATION pub_conductores FOR TABLE conductores;

-- En el nodo C (Sur principal):
CREATE PUBLICATION pub_sur FOR TABLE buses_sur, viajes_sur;

-- =========================================================== PASO 2: SUSCRIPCIONES
-- En el nodo A: replica de Centro y de conductores, desde B.
CREATE SUBSCRIPTION sub_a_centro
    CONNECTION 'host=nodo_b port=5432 dbname=hashing_db user=postgres password=password123'
    PUBLICATION pub_centro
    WITH (copy_data = true);
CREATE SUBSCRIPTION sub_a_conductores
    CONNECTION 'host=nodo_b port=5432 dbname=hashing_db user=postgres password=password123'
    PUBLICATION pub_conductores
    WITH (copy_data = true);

-- En el nodo B: replica de Norte (desde A) y de Sur (desde C).
CREATE SUBSCRIPTION sub_b_norte
    CONNECTION 'host=nodo_a port=5432 dbname=hashing_db user=postgres password=password123'
    PUBLICATION pub_norte
    WITH (copy_data = true);
CREATE SUBSCRIPTION sub_b_sur
    CONNECTION 'host=nodo_c port=5432 dbname=hashing_db user=postgres password=password123'
    PUBLICATION pub_sur
    WITH (copy_data = true);

-- En el nodo C: replica de conductores, desde B.
CREATE SUBSCRIPTION sub_c_conductores
    CONNECTION 'host=nodo_b port=5432 dbname=hashing_db user=postgres password=password123'
    PUBLICATION pub_conductores
    WITH (copy_data = true);

-- =========================================================== COMPROBAR (en cualquier nodo)
-- Estado de las suscripciones y retraso (lag) de cada publicacion, en el nodo que publica:
--   SELECT subname, received_lsn, latest_end_time FROM pg_stat_subscription;
--   SELECT application_name, state, replay_lag FROM pg_stat_replication;
-- Las filas de una replica deben ser iguales a las del principal:
--   en A:  SELECT count(*) FROM viajes_norte;     en B:  SELECT count(*) FROM viajes_norte;

-- =========================================================== CAIDA DE UN NODO (promocion)
-- Si cae A, B pasa a ser el principal de Norte. En B:
--   ALTER SUBSCRIPTION sub_b_norte DISABLE;
--   ALTER SUBSCRIPTION sub_b_norte SET (slot_name = NONE);
--   DROP SUBSCRIPTION sub_b_norte;
-- Desde ese momento B recibe las escrituras de Norte. Si A vuelve, hay que reconstruirlo
-- como replica de B (no se mezcla solo). Lo mismo con Sur (nodo C, replica en B) y con
-- Centro (nodo B, replica en A: ahi se usa sub_a_centro).
-- Con replica asincrona se pueden perder las ultimas transacciones que no llegaron.
-- Despues de promover, la estructura de Extendible Hashing se reconstruye en cada sesion
-- (ver seccion 5 del informe):
--   SELECT count(*) FILTER (WHERE pg_insertar(id_viaje)) FROM viajes_norte;
