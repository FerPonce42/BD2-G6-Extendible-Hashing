#ifndef BUSQUEDA_H
#define BUSQUEDA_H

#include "directorio.h"
#include "bucket.h"


// Retorna el puntero al Bucket si encuentra la llave, o NULL si no existe
struct Bucket* buscar_llave(struct Directorio* dir, int llave);

#endif 