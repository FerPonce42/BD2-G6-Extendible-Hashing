#include <stdio.h>
#include <stdbool.h>
#include "../include/directorio.h"
#include "../include/bucket.h"
#include "../include/busqueda.h"
#include "../include/inserccion.h"

int main() {

    int profundidad = 2;
    int tam_bucket = 4;

    printf("===== PRUEBA DE CRECIMIENTO Y ROBUSTEZ =====\n\n");

    struct Directorio* d = CrearDirectorio(profundidad, tam_bucket);

    if (d == NULL) {
        printf("[ERROR] No se pudo crear el directorio\n");
        return 1;
    }

    printf("[OK] Directorio creado (PROF_GLOBAL=%d, %d casillas)\n\n",
        d->PROF_GLOBAL, 1 << d->PROF_GLOBAL);

    // ---- Prueba 1: insertar suficientes claves para forzar varios splits ----
    printf("--- Insertando 20 claves seguidas (4,8,12,...) para forzar splits ---\n");

    int claves[20];
    int cantidad = 20;

    for (int i = 0; i < cantidad; i++) {
        claves[i] = (i + 1) * 4; // 4, 8, 12, 16, ... todas caen en el mismo indice al inicio
    }

    for (int i = 0; i < cantidad; i++) {
        insertar_llave(d, claves[i]);
        printf("    -> PROF_GLOBAL ahora es %d (%d casillas)\n",
            d->PROF_GLOBAL, 1 << d->PROF_GLOBAL);
    }

    // ---- Prueba 2: insertar una clave repetida ----
    printf("\n--- Insertando clave repetida (%d otra vez) ---\n", claves[0]);
    // insertar_llave devuelve false si la clave ya existia
    if (!insertar_llave(d, claves[0]))
        printf("[OK] La clave %d ya existia, no se duplico\n", claves[0]);
    else
        printf("[ERROR] Se inserto una clave repetida\n");
    
    // ---- Prueba 3: verificar que NINGUNA clave se perdio despues de los splits ----
    printf("\n--- Verificando que las 20 claves sigan encontrandose ---\n");

    int perdidas = 0;
    bool encontrado;

    for (int i = 0; i < cantidad; i++) {
        buscar_llave(d, claves[i], &encontrado);
        if (!encontrado) {
            printf("[ERROR] Se perdio la clave %d\n", claves[i]);
            perdidas++;
        }
    }

    if (perdidas == 0)
        printf("[OK] Las %d claves siguen intactas despues de los splits\n", cantidad);
    else
        printf("[ERROR] Se perdieron %d claves\n", perdidas);

    // ---- Prueba 4: clave que nunca se inserto ----
    printf("\n--- Buscando clave que nunca se inserto (999999) ---\n");
    buscar_llave(d, 999999, &encontrado);
    if (!encontrado)
        printf("[OK] No existe, como se esperaba\n");
    else
        printf("[ERROR] Encontro algo que no deberia existir\n");

    printf("\n--- Estado final ---\n");
    printf("PROF_GLOBAL final: %d (%d casillas en el directorio)\n",
        d->PROF_GLOBAL, 1 << d->PROF_GLOBAL);


    liberar_directorio(d);


    return 0;
}