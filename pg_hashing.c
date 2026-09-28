#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"

/* Incluir los headers de tu carpeta include */
#include "include/directorio.h"
#include "include/inserccion.h"
#include "include/busqueda.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(pg_insertar);
PG_FUNCTION_INFO_V1(pg_buscar);

Datum pg_insertar(PG_FUNCTION_ARGS) {
    int32 llave = PG_GETARG_INT32(0);
    /* 
     * Llamar a la lógica de Fabricio. 
     * Asegúrate de inicializar/obtener 'directorio' según tu lógica.
     */
    /* bool exito = insertar_llave(directorio, llave); */
    
    PG_RETURN_BOOL(true);
}

Datum pg_buscar(PG_FUNCTION_ARGS) {
    int32 llave = PG_GETARG_INT32(0);
    /* 
     * Llamar a tu propia lógica de búsqueda.
     */
    /* 
     * bool encontrado = false;
     * buscar_llave(directorio, llave, &encontrado); 
     */
    
    PG_RETURN_BOOL(true);
}