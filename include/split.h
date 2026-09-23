#ifndef SPLIT_H
#define SPLIT_H

#include "directorio.h"
#include "bucket.h"


// Iair Suico: Dividir bucket cuando ocurre overflow
/*
dividir_bucket(dir, indice_bucket):
  - Parte el bucket al que apunta dir->ARR_BUCKETS[indice_bucket].
  - Si PROF_LOCAL == PROF_GLOBAL, primero duplica el directorio (PROF_GLOBAL++).
  - Crea un bucket nuevo, sube PROF_LOCAL de ambos en 1 y reparte
    punteros y llaves segun el bit PROF_LOCAL (el anterior) de cada una.
  - NO inserta la llave nueva: la insercion debe recalcular el indice
    y reintentar (llamando otra vez a dividir_bucket si sigue lleno).
*/
void dividir_bucket(struct Directorio* dir, int indice_bucket);

#endif
