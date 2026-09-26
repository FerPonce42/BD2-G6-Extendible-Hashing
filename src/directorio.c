#include <stdio.h>
#include <stdlib.h>
#include "../include/directorio.h"
#include "../include/bucket.h"

/*
struct Directorio{

    int PROF_GLOBAL;

    struct Bucket** ARR_BUCKETS;

};
*/

/*
1 << d mueve el 1 a la izquierda d veces, rellenando con ceros.
Con eso sacamos 2^d sin necesidad de pow().
*/


struct Directorio* CrearDirectorio(int d, int tam_bucket){

    struct Directorio* directorio = malloc(sizeof(struct Directorio));

    directorio->PROF_GLOBAL = d;

    directorio->ARR_BUCKETS = malloc((1<<d) * sizeof(struct Bucket*));

    int i = 0;

    while( i < (1<<d)){

        directorio->ARR_BUCKETS[i] = CrearBucket(tam_bucket, d);

        i++;
    }

    return directorio;
}


void liberar_directorio(struct Directorio* dir) {

    if (dir == NULL) return;

    if (dir->ARR_BUCKETS != NULL) {

        int tam = 1 << dir->PROF_GLOBAL;

        for (int i = 0; i < tam; i++) {

            struct Bucket* actual = dir->ARR_BUCKETS[i];

            if (actual != NULL) {

                free(actual->ARR_CLAVES);
                free(actual);

                // varias casillas pueden apuntar al mismo bucket (por los splits)
                // asi que anulamos todas las que apunten a este mismo, para no liberarlo dos veces
                for (int j = i; j < tam; j++) {
                    if (dir->ARR_BUCKETS[j] == actual) {
                        dir->ARR_BUCKETS[j] = NULL;
                    }
                }
            }
        }

        free(dir->ARR_BUCKETS);
    }

    free(dir);
}