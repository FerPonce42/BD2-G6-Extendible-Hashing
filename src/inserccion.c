#include <stdio.h>
#include <stdlib.h>
#include "../include/inserccion.h"
#include "../include/busqueda.h"
#include "../include/split.h"

// seguridad para que el directorio no crezca sin control
#define PROF_MAXIMA 24

bool insertar_llave(struct Directorio* dir, int llave) {

    if (dir == NULL || dir->ARR_BUCKETS == NULL) return false;

    bool encontrado;
    struct Bucket* bucket_actual = buscar_llave(dir, llave, &encontrado);

    if (bucket_actual == NULL) return false;

    if (encontrado) return false; // la clave ya existe, no se duplica

    if (bucket_actual->ELEM < bucket_actual->TAM) {
        bucket_actual->ARR_CLAVES[bucket_actual->ELEM] = llave;
        bucket_actual->ELEM++;
        return true;
    }

    // bucket lleno: split y reintento.
    // El limite solo importa si el split tendria que DUPLICAR el directorio
    // (PROF_LOCAL == PROF_GLOBAL). Si PROF_LOCAL < PROF_GLOBAL se puede partir igual.
    if (bucket_actual->PROF_LOCAL >= dir->PROF_GLOBAL && dir->PROF_GLOBAL >= PROF_MAXIMA) return false;

    int indice = llave & ((1 << dir->PROF_GLOBAL) - 1);
    if (!dividir_bucket(dir, indice)) return false; // sin memoria: no reintentar para siempre

    return insertar_llave(dir, llave);
}