#ifndef SPLIT_H
#define SPLIT_H

#include "directorio.h"
#include "bucket.h"


// Iair Suico: Dividir bucket cuando ocurre overflow
void dividir_bucket(struct Directorio* dir, int indice_bucket);

#endif 