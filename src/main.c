#include <stdio.h>
#include "../include/directorio.h"
#include "../include/bucket.h"
#include "../include/busqueda.h"
#include "../include/inserccion.h"

int main() {

    int profundidad = 2;
    int tam_bucket = 4;

    printf("===== PRUEBA DE CONSTRUCCION Y BUSQUEDA =====\n\n");

    struct Directorio* d = CrearDirectorio(profundidad, tam_bucket);

    if (d == NULL) {
        printf("[ERROR] No se pudo crear el directorio\n");
        return 1;
    }

    printf("[OK] Directorio creado correctamente\n");


    printf("\nInsertando claves...\n");
    insertar_llave(d, 4);
    insertar_llave(d, 5);
    insertar_llave(d, 6);
    insertar_llave(d, 7);


    printf("\nBuscando claves existentes:\n");

    if (buscar_llave(d, 4) != NULL)
        printf("[OK] Clave 4 encontrada\n");
    else
        printf("[ERROR] Clave 4 no encontrada\n");

    if (buscar_llave(d, 5) != NULL)
        printf("[OK] Clave 5 encontrada\n");
    else
        printf("[ERROR] Clave 5 no encontrada\n");

    printf("\nBuscando clave inexistente:\n");

    if (buscar_llave(d, 100) == NULL)
        printf("[OK] Clave 100 no existe en el directorio\n");
    else
        printf("[ERROR] Clave 100 fue encontrada\n");

    return 0;
}