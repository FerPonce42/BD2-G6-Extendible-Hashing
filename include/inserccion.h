#ifndef INSERCION_H
#define INSERCION_H

#include <stdbool.h>
#include "directorio.h"

// true = la clave se insertó; false = ya existía o hubo un problema
bool insertar_llave(struct Directorio* dir, int llave);

#endif