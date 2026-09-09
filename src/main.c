#include <stdio.h>
#include "../include/directorio.h"

int main(){

    struct Directorio* d = CrearDirectorio(2, 4); // d and tam de bbuckets

    printf("Directorio creado, profundidad global: %d\n", d->PROF_GLOBAL);
    
}