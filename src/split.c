#include <stdio.h>
#include <stdlib.h>
#include "../include/split.h"

// Duplica el directorio: de 2^d casilleros pasa a 2^(d+1).
// El casillero [i + 2^d] apunta al mismo bucket que [i].
static int duplicar_directorio(struct Directorio* dir) {

    int tam_viejo = 1 << dir->PROF_GLOBAL;
    int tam_nuevo = tam_viejo << 1;

    struct Bucket** nuevo = realloc(dir->ARR_BUCKETS, tam_nuevo * sizeof(struct Bucket*));
    if (nuevo == NULL) return 0;

    for (int i = 0; i < tam_viejo; i++) {
        nuevo[i + tam_viejo] = nuevo[i];
    }

    dir->ARR_BUCKETS = nuevo;
    dir->PROF_GLOBAL++;

    return 1;
}

int dividir_bucket(struct Directorio* dir, int indice_bucket) {

    if (dir == NULL || dir->ARR_BUCKETS == NULL) return 0;
    if (indice_bucket < 0 || indice_bucket >= (1 << dir->PROF_GLOBAL)) return 0;

    struct Bucket* viejo = dir->ARR_BUCKETS[indice_bucket];
    if (viejo == NULL) return 0;

    if (viejo->PROF_LOCAL == dir->PROF_GLOBAL) {
        if (!duplicar_directorio(dir)) return 0;
    }

    int p = viejo->PROF_LOCAL;

    struct Bucket* nuevo = CrearBucket(viejo->TAM, p + 1);
    if (nuevo == NULL) return 0;

    viejo->PROF_LOCAL = p + 1;

    int tam_dir = 1 << dir->PROF_GLOBAL;

    for (int i = 0; i < tam_dir; i++) {
        if (dir->ARR_BUCKETS[i] == viejo && ((i >> p) & 1)) {
            dir->ARR_BUCKETS[i] = nuevo;
        }
    }

    int j = 0;

    for (int i = 0; i < viejo->ELEM; i++) {

        int llave = viejo->ARR_CLAVES[i];

        if (((unsigned int)llave >> p) & 1) {
            nuevo->ARR_CLAVES[nuevo->ELEM] = llave;
            nuevo->ELEM++;
        } else {
            viejo->ARR_CLAVES[j] = llave;
            j++;
        }
    }

    viejo->ELEM = j;

    return 1;
}