// Fernando: Definire aqui el struct del directorio = arreglo de punteros.... donde iran punteros a los buckets
#ifndef DIRECTORIO_H
#define DIRECTORIO_H
#include <stdio.h>
#include <stdlib.h>
#include "../include/bucket.h"



struct Directorio{

    int PROF_GLOBAL;

    struct Bucket** ARR_BUCKETS;

};

struct Directorio* CrearDirectorio(int d, int tam_bucket);

#endif