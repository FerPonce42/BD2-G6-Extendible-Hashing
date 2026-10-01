#ifndef SPLIT_H
#define SPLIT_H

#include "directorio.h"
#include "bucket.h"

// Devuelve 1 si partio el bucket, 0 si no pudo (datos invalidos o sin memoria).
int dividir_bucket(struct Directorio* dir, int indice_bucket);

#endif