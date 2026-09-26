#include <stdio.h>
#include <stdlib.h>
#include "../include/inserccion.h"
#include "../include/busqueda.h"
#include "../include/split.h"

void insertar_llave(struct Directorio* dir, int llave) {

    if (dir == NULL || dir->ARR_BUCKETS == NULL) return;

    bool encontrado;
    struct Bucket* bucket_actual = buscar_llave(dir, llave, &encontrado);

    if (bucket_actual == NULL) return;

    if (encontrado) {
        printf("[AVISO] La clave %d ya existe, no se inserta de nuevo\n", llave);
        return;
    }

    if (bucket_actual->ELEM < bucket_actual->TAM) {

        bucket_actual->ARR_CLAVES[bucket_actual->ELEM] = llave;
        bucket_actual->ELEM++;

        printf("[OK] Clave %d insertada (ELEM=%d/%d)\n",
            llave, bucket_actual->ELEM, bucket_actual->TAM);

    } else {

        printf("[INFO] Bucket lleno, se necesita split para insertar la clave %d\n", llave);

        int indice = llave & ((1 << dir->PROF_GLOBAL) - 1);
        dividir_bucket(dir, indice);

        insertar_llave(dir, llave); // reintenta luego del split
    }
}