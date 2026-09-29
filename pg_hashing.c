#include "postgres.h"
#include "fmgr.h"

#include "directorio.h"
#include "inserccion.h"
#include "busqueda.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(pg_insertar);
PG_FUNCTION_INFO_V1(pg_buscar);

#define PROF_INICIAL 2
#define TAM_BUCKET   50

/* El directorio vive aquí: se crea en la primera llamada y se reutiliza */
static struct Directorio *dir_global = NULL;

static struct Directorio *obtener_directorio(void)
{
    if (dir_global == NULL)
        dir_global = CrearDirectorio(PROF_INICIAL, TAM_BUCKET);
    return dir_global;
}

Datum pg_insertar(PG_FUNCTION_ARGS)
{
    int32 llave = PG_GETARG_INT32(0);
    bool ok = insertar_llave(obtener_directorio(), llave);

    PG_RETURN_BOOL(ok);
}

Datum pg_buscar(PG_FUNCTION_ARGS)
{
    int32 llave = PG_GETARG_INT32(0);
    bool encontrado = false;

    buscar_llave(obtener_directorio(), llave, &encontrado);

    PG_RETURN_BOOL(encontrado);
}