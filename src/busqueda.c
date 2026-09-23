#include <stdio.h>
#include <stdlib.h>
#include "../include/busqueda.h"

//--------------------------------------------------
// FUNCION DE BUSQUEDA DE CLAVE!
//--------------------------------------------------

struct Bucket* buscar_llave(struct Directorio* dir, int llave) {
    
    // Guardianes de seguridad por si el directorio o el arreglo vienen nulos
    if (!dir || !dir->ARR_BUCKETS) return NULL;

    int hash = llave;

    // 1 << N(veces que se mueve a la izquierda el 1) [ Lo que les expliqué en pizarra. La info esta tambien en el director.c en "2^d"]
     // mini funcion hash para "enmascarar a nuestra CLAVE y ubicarla en el [i] del directorio "
    
    int indice = hash & ((1 << dir->PROF_GLOBAL) - 1); // FAMOSA funcion HASH
    
    // Fer:   Recuerden que en C++ -> % , pero en C -> &
    // basicamente: llave modulo mascara

    struct Bucket* bucket_actual = dir->ARR_BUCKETS[indice]; // puntero hacia el bucket que corresponde

    if (!bucket_actual) return NULL; // Guardián por si el bucket no existe

    for (int i = 0; i < bucket_actual->ELEM; i++) { // busqueda lineal simple para saber si la clave existe o no en el bucket.
        
        if (bucket_actual->ARR_CLAVES[i] == llave) {
            return bucket_actual; // SI existe esa llave,ten la direccion donde está 
        }
    }
    
    return NULL; // No existe esa llave en el bucket (inserta!)
}

