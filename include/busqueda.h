#ifndef BUSQUEDA_H
#define BUSQUEDA_H

#include <stdbool.h>
#include "directorio.h"
#include "bucket.h"

// Retorna el bucket donde va o esta la llave, o NULL si el directorio esta mal formado.
// "encontrado" indica si la llave ya estaba en ese bucket.
struct Bucket* buscar_llave(struct Directorio* dir, int llave, bool* encontrado);

#endif