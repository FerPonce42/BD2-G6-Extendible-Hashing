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
Aqui no existe el 2^algo.

aqui el truco es el siguiente operador: 

1 << d
---- 
1 << 1
seria
10
----
1<<2
100
----
1<<3
1000
---- Bascaimente mueve el 1 (tablas de verdad) a la izquierda dependiendo del numero que sea d, completando los lugares con cero.
*/


struct Directorio* CrearDirectorio(int d, int tam_bucket){

    struct Directorio* directorio = malloc(sizeof(struct Directorio));

    directorio->PROF_GLOBAL = d;

    directorio->ARR_BUCKETS = malloc((1<<d) * sizeof(struct Bucket*));
    /*
    ARR_BUCKETS guarda ...espacio.. para los buckets...
pero como no los quiere almacenar.
solo quiere APUNTAR. entonces los reduce a un puntero === (struct Bucket*)
    */


    // Llenar el arreglo de punteros con las direcciones de los buckets.

    int i = 0;

    while( i < (1<<d)){

        directorio->ARR_BUCKETS[i] = CrearBucket(tam_bucket);

        i++;
    }



    return directorio;
}


