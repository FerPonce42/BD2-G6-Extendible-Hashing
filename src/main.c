#include <stdio.h>
#include "../include/directorio.h"


int main(){

    int profundidad = 2;
    int tam_bucket = 4;


    printf("===== PRUEBA DE CONSTRUCCION =====\n\n");

    printf("Configuracion inicial:\n");
    printf("Profundidad global: %d\n", profundidad);
    printf("Tamano de bucket: %d\n", tam_bucket);
    printf("Cantidad esperada de buckets: %d\n\n", 1 << profundidad);



    struct Directorio* d = CrearDirectorio(profundidad, tam_bucket);


    if(d == NULL){

        printf("[ERROR] No se pudo crear el directorio\n");
        return 1;
    }


    printf("[OK] Directorio creado correctamente\n");


    if(d->PROF_GLOBAL == profundidad){

        printf("[OK] Profundidad global correcta: %d\n",
               d->PROF_GLOBAL);

    }
    else{

        printf("[ERROR] Profundidad global incorrecta\n");

    }



    printf("\nVerificacion de buckets creados:\n");


    for(int i = 0; i < (1 << profundidad); i++){


        if(d->ARR_BUCKETS[i] == NULL){

            printf("[ERROR] Bucket %d no fue creado\n", i);
            continue;

        }


        printf("\nBucket %d\n", i);

        printf("TAM = %d\n",
               d->ARR_BUCKETS[i]->TAM);

        printf("ELEM = %d\n",
               d->ARR_BUCKETS[i]->ELEM);

        printf("PROF_LOCAL = %d\n",
               d->ARR_BUCKETS[i]->PROF_LOCAL);



        if(d->ARR_BUCKETS[i]->TAM == tam_bucket &&
           d->ARR_BUCKETS[i]->ELEM == 0){


            printf("[OK] Bucket inicializado correctamente\n");

        }
        else{

            printf("[ERROR] Bucket mal inicializado\n");

        }

    }



    printf("\n\n===== PRUEBA DE BUSQUEDA =====\n\n");


    /*
        Actualmente no existe una funcion de insercion.
        Se cargan claves manualmente solamente para
        validar la funcion buscar_llave().
    */


    d->ARR_BUCKETS[0]->ARR_CLAVES[0] = 4;
    d->ARR_BUCKETS[0]->ELEM = 1;


    d->ARR_BUCKETS[1]->ARR_CLAVES[0] = 5;
    d->ARR_BUCKETS[1]->ELEM = 1;


    d->ARR_BUCKETS[2]->ARR_CLAVES[0] = 6;
    d->ARR_BUCKETS[2]->ELEM = 1;


    d->ARR_BUCKETS[3]->ARR_CLAVES[0] = 7;
    d->ARR_BUCKETS[3]->ELEM = 1;



    printf("Buscando claves existentes:\n");


    if(buscar_llave(d,4))
        printf("[OK] Clave 4 encontrada\n");
    else
        printf("[ERROR] Clave 4 no encontrada\n");


    if(buscar_llave(d,5))
        printf("[OK] Clave 5 encontrada\n");
    else
        printf("[ERROR] Clave 5 no encontrada\n");


    if(buscar_llave(d,6))
        printf("[OK] Clave 6 encontrada\n");
    else
        printf("[ERROR] Clave 6 no encontrada\n");


    if(buscar_llave(d,7))
        printf("[OK] Clave 7 encontrada\n");
    else
        printf("[ERROR] Clave 7 no encontrada\n");



    printf("\nBuscando clave inexistente:\n");


    if(buscar_llave(d,100) == 0)
        printf("[OK] Clave 100 no existe en el directorio\n");
    else
        printf("[ERROR] Clave 100 fue encontrada\n");



    printf("\n===== PRUEBAS FINALIZADAS =====\n");


    return 0;
}