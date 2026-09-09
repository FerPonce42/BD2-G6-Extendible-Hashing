// Fernando: Y... aqui metere las funciones.
#include <stdio.h>
#include <stdlib.h>
#include "../include/bucket.h"

/*

struct Bucket{

    int TAM;
    int ELEM;
    int PROF_LOCAL;

    int* ARR_CLAVES;

};

*/


struct Bucket* CrearBucket(int tam){
 
    struct Bucket* bucket = malloc(sizeof(struct Bucket)); // p hace un new Bucket; mirenlo como un new Nodo;


    // inicializacion de atributos.
    bucket->TAM = tam;
    bucket->ELEM = 0;
    bucket->PROF_LOCAL = 1;

    bucket->ARR_CLAVES = malloc( bucket->TAM * sizeof(int)); // Aqui realmente se crea el arreglo para las claves.


    return bucket; // esto lo guardará nuestro director.
}