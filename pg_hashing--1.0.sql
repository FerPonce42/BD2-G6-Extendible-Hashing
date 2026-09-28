CREATE FUNCTION pg_insertar(integer) RETURNS boolean
AS 'MODULE_PATHNAME', 'pg_insertar'
LANGUAGE C STRICT;

CREATE FUNCTION pg_buscar(integer) RETURNS boolean
AS 'MODULE_PATHNAME', 'pg_buscar'
LANGUAGE C STRICT;