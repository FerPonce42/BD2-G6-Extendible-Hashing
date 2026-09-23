// Iair Suico: SPLIT de un bucket cuando ocurre overflow (ELEM == TAM).
#include <stdio.h>
#include <stdlib.h>
#include "../include/split.h"

/*
Idea general (misma "funcion hash" que usa busqueda.c):

    indice = llave & ((1 << PROF_GLOBAL) - 1)   -> se usan los bits BAJOS de la llave

Si el bucket B tiene PROF_LOCAL = p, todas sus llaves comparten los p bits bajos.
Al partirlo se mira el siguiente bit (el bit p):

    bit p = 0  -> la llave se queda en B
    bit p = 1  -> la llave se va al bucket nuevo

Dos casos:

  1) PROF_LOCAL == PROF_GLOBAL
     Solo un casillero del directorio apunta a B, no hay "de donde repartir".
     => primero se DUPLICA el directorio (PROF_GLOBAL++), y luego se parte.

  2) PROF_LOCAL < PROF_GLOBAL
     Varios casilleros apuntan a B.
     => no se toca el tamaño del directorio, solo se reparten los punteros.

Nota: esta funcion NO inserta la llave nueva. Solo parte el bucket.
La insercion debe volver a calcular el indice y reintentar
(si el bucket sigue lleno, se vuelve a llamar a dividir_bucket).
*/


// Duplica el directorio: de 2^d casilleros pasa a 2^(d+1).
// El casillero [i + 2^d] apunta al mismo bucket que [i]
// (tienen los mismos d bits bajos, solo difieren en el bit d).
static int duplicar_directorio(struct Directorio* dir) {

    int tam_viejo = 1 << dir->PROF_GLOBAL;   // 2^d
    int tam_nuevo = tam_viejo << 1;          // 2^(d+1)

    struct Bucket** nuevo = realloc(dir->ARR_BUCKETS, tam_nuevo * sizeof(struct Bucket*));
    if (!nuevo) return 0; // Guardián: no hubo memoria, no se cambia nada

    for (int i = 0; i < tam_viejo; i++) {
        nuevo[i + tam_viejo] = nuevo[i];
    }

    dir->ARR_BUCKETS = nuevo;
    dir->PROF_GLOBAL++;

    return 1;
}


void dividir_bucket(struct Directorio* dir, int indice_bucket) {

    // Guardianes de seguridad
    if (!dir || !dir->ARR_BUCKETS) return;
    if (indice_bucket < 0 || indice_bucket >= (1 << dir->PROF_GLOBAL)) return;

    struct Bucket* viejo = dir->ARR_BUCKETS[indice_bucket];
    if (!viejo) return;

    // CASO 1: el bucket ya usa todos los bits del directorio -> duplicar
    if (viejo->PROF_LOCAL == dir->PROF_GLOBAL) {
        if (!duplicar_directorio(dir)) return;
    }

    int p = viejo->PROF_LOCAL;   // bit que decide a donde va cada llave

    struct Bucket* nuevo = CrearBucket(viejo->TAM);
    if (!nuevo) return;

    viejo->PROF_LOCAL = p + 1;
    nuevo->PROF_LOCAL = p + 1;


    // 1) Redirigir punteros del directorio:
    //    de los casilleros que apuntaban a "viejo", los que tienen el bit p en 1
    //    ahora apuntan a "nuevo".
    int tam_dir = 1 << dir->PROF_GLOBAL;

    for (int i = 0; i < tam_dir; i++) {
        if (dir->ARR_BUCKETS[i] == viejo && ((i >> p) & 1)) {
            dir->ARR_BUCKETS[i] = nuevo;
        }
    }


    // 2) Redistribuir llaves:
    //    bit p = 1 -> se mueve al bucket nuevo
    //    bit p = 0 -> se queda (se compacta el arreglo del viejo con "j")
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
}
