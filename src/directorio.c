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


// ==========================================
// TAREA 2.2: Función de búsqueda (Nicol)
// ==========================================

// Retorna 1 si encuentra la llave, 0 si no existe
int buscar_llave(struct Directorio* dir, int llave) {
    // 1. Usar la propia llave como hash 
    int hash = llave;

    // 2. Crear la máscara con la PROF_GLOBAL y obtener el índice
    int mascara = (1 << dir->PROF_GLOBAL) - 1;
    int indice = hash & mascara;

    // 3. Obtener el puntero al bucket correcto usando ARR_BUCKETS
    struct Bucket* bucket_actual = dir->ARR_BUCKETS[indice];

    // 4. Buscar secuencialmente iterando hasta ELEM (elementos actuales)
    for (int i = 0; i < bucket_actual->ELEM; i++) {
        // Verificar si la llave en la posición i de ARR_CLAVES coincide
        if (bucket_actual->ARR_CLAVES[i] == llave) {
            return 1; // ¡Encontrado!
        }
    }
    
    return 0; // No encontrado en el bucket
}

