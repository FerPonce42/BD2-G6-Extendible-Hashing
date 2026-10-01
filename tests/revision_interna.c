// revision_interna.c
// Grupo 6 - BD2 - Actividad 4.4 (Iair Suico)
//
// Revisa POR DENTRO la estructura despues de insertar un CSV completo.
// No pasa por PostgreSQL: usa directamente el nucleo en C (src/).
//
// Reglas que se comprueban en cada casillero i del directorio:
//   1) ELEM <= TAM                     (ningun bucket se desborda)
//   2) PROF_LOCAL <= PROF_GLOBAL
//   3) todos los casilleros que tienen los mismos PROF_LOCAL bits bajos que i
//      apuntan al mismo bucket
//   4) cada clave del bucket tiene esos mismos PROF_LOCAL bits bajos
//      (o sea, esta en el bucket que le corresponde)
// Ademas se cuenta cuantas claves hay en total (cada bucket se cuenta una sola vez).
//
// Compilar y correr (dentro del contenedor, desde /app):
//   gcc -O2 -Iinclude -o /tmp/revision_interna tests/revision_interna.c src/bucket.c src/busqueda.c src/directorio.c src/inserccion.c src/split.c
//   /tmp/revision_interna data/D2_aleatorio_1000000.csv

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include "directorio.h"
#include "inserccion.h"

int main(int argc, char** argv) {

    if (argc < 2) {
        printf("Uso: %s archivo.csv\n", argv[0]);
        return 1;
    }

    FILE* f = fopen(argv[1], "r");
    if (f == NULL) {
        printf("[ERROR] No se pudo abrir %s\n", argv[1]);
        return 1;
    }

    // mismos parametros que pg_hashing.c
    struct Directorio* dir = CrearDirectorio(2, 50);

    char linea[256];
    int llave;
    long leidas = 0, insertadas = 0;

    if (fgets(linea, sizeof(linea), f) == NULL) { // salta la cabecera
        printf("[ERROR] Archivo vacio\n");
        return 1;
    }
    while (fgets(linea, sizeof(linea), f)) {
        if (sscanf(linea, "%d", &llave) == 1) {
            leidas++;
            if (insertar_llave(dir, llave)) insertadas++;
        }
    }
    fclose(f);

    int G = dir->PROF_GLOBAL;
    int casillas = 1 << G;
    long errores = 0, total_claves = 0, buckets = 0;

    for (int i = 0; i < casillas; i++) {

        struct Bucket* b = dir->ARR_BUCKETS[i];
        int L = b->PROF_LOCAL;
        int mascara = (1 << L) - 1;
        int base = i & mascara;

        if (b->ELEM > b->TAM) errores++;   // regla 1
        if (L > G) errores++;              // regla 2

        for (int j = base; j < casillas; j += (1 << L)) {   // regla 3
            if (dir->ARR_BUCKETS[j] != b) errores++;
        }

        for (int k = 0; k < b->ELEM; k++) {                 // regla 4
            if ((b->ARR_CLAVES[k] & mascara) != base) errores++;
        }

        if (i == base) {            // el primer casillero del grupo cuenta el bucket
            buckets++;
            total_claves += b->ELEM;
        }
    }

    printf("Archivo:              %s\n", argv[1]);
    printf("Filas leidas:         %ld\n", leidas);
    printf("Insertadas:           %ld\n", insertadas);
    printf("Claves en buckets:    %ld\n", total_claves);
    printf("PROF_GLOBAL final:    %d (%d casillas)\n", G, casillas);
    printf("Buckets distintos:    %ld\n", buckets);
    printf("Errores de estructura: %ld\n", errores);
    printf(errores == 0 && total_claves == insertadas ? "[OK] Estructura correcta\n"
                                                      : "[ERROR] Estructura inconsistente\n");

    liberar_directorio(dir);
    return 0;
}
