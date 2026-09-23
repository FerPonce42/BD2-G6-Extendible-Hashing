// Fernando: Definire aqui el struct del bucket = una estructura.... donde estan atributos extras del ARREGLO de claves.
#ifndef BUCKET_H
#define BUCKET_H
#include <stdio.h>
#include <stdlib.h>


struct Bucket{

    int TAM;
    int ELEM;
    int PROF_LOCAL;

    int* ARR_CLAVES;

};

struct Bucket* CrearBucket(int tam);

/*
Fer: Información: 

TAM = tamaño del bucket (imagenlo como un nodo raro, el TAM corresponde en si al TAM del ARREGLO)
ELEM = elementos actuales en el bucket (que viven en el arreglo de claves)
PROF_LOCAL = una especie de contador que crece cuando ELEM == TAM(lleno) o con un "SPLIT" (esa logica mas adelante)

ARR_CLAVES = puntero que creara memoria dinamica para crear el arreglo donde se guardaran las claves


*/


#endif