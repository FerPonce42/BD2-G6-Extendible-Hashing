#include <stdio.h>
#include <stdlib.h>
#include "../include/busqueda.h"

struct Bucket* buscar_llave(struct Directorio* dir, int llave, bool* encontrado) {

    *encontrado = false;

    if (dir == NULL || dir->ARR_BUCKETS == NULL) return NULL;

    int indice = llave & ((1 << dir->PROF_GLOBAL) - 1); // funcion hash: ubica la casilla del directorio

    struct Bucket* bucket_actual = dir->ARR_BUCKETS[indice];

    if (bucket_actual == NULL) return NULL;

    for (int i = 0; i < bucket_actual->ELEM; i++) {
        if (bucket_actual->ARR_CLAVES[i] == llave) {
            *encontrado = true;
            return bucket_actual;
        }
    }

    return bucket_actual; // no existe, pero es el bucket donde debe insertarse
}