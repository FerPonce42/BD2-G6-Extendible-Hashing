#include <stdio.h>
#include <stdlib.h>
#include "../include/inserccion.h"
#include "../include/busqueda.h"
#include "../include/split.h"

void insertar_llave(struct Directorio* dir, int llave) {

    // Guardianes de seguridad, por si el directorio viene mal formado
    if (!dir || !dir->ARR_BUCKETS) return;

    // 1) Primero nos fijamos si la clave YA existe (con el puntero de la busqueda de nicol)
    if (buscar_llave(dir, llave) != NULL) {
        printf("[AVISO] La clave %d ya existe en el directorio, no se inserta de nuevo\n", llave);
        return;
    }

    // 2) Misma mascara/hash que se usa en busqueda.c para ubicar el bucket
    int indice = llave & ((1 << dir->PROF_GLOBAL) - 1);

    struct Bucket* bucket_actual = dir->ARR_BUCKETS[indice]; // puntero al bucket que le toca

    if (!bucket_actual) return; // guardian por si el bucket no existe

    // 3) Si hay espacio en el bucket, se inserta directo al final del arreglo
    if (bucket_actual->ELEM < bucket_actual->TAM) {

        bucket_actual->ARR_CLAVES[bucket_actual->ELEM] = llave; // se guarda la clave
        bucket_actual->ELEM++; // se actualiza el contador de elementos

        printf("[OK] Clave %d insertada en bucket[%d] (ELEM=%d/%d)\n",
            llave, indice, bucket_actual->ELEM, bucket_actual->TAM);

    }
    else {
        // 4) El bucket esta lleno -> hace falta el split (trabajo de Iair en split.c)
        printf("[INFO] Bucket[%d] esta lleno, se necesita split para insertar la clave %d\n",
            indice, llave);

        dividir_bucket(dir, indice);

        // Una vez dividido el bucket, se reintenta la insercion (recursivo)
        insertar_llave(dir, llave);
    }
}