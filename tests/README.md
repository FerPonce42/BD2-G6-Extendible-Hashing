# tests/ — Actividad 4.4 (corrección de errores)

Pruebas de correctitud de la estructura. No miden tiempos (eso es el benchmark).

| Archivo | Qué prueba |
|---|---|
| `01_datasets.sql` | D1 y D2 en 100k, 500k y 1M: insertadas, perdidas, reinsertadas y falsos positivos |
| `02_casos_limite.sql` | 0, negativos, extremos de `int`, `NULL`, repetidas, sesión vacía |
| `03_tope_profundidad.sql` | Claves que comparten 24 bits bajos (llega a `PROF_MAXIMA`) y luego carga normal |
| `revision_interna.c` | Revisa por dentro el directorio y los buckets después de 1M inserciones |
| `correr_tests.sh` | Corre todo y guarda las salidas en `tests/resultados/<etiqueta>/` |

## Cómo correrlo

Con el contenedor levantado (README principal, pasos 1 a 4) y los CSV de los **3 tamaños**:

```
py scripts/generar_datos.py
docker cp data/. bd2_g6_hashing:/app/data
docker cp tests/. bd2_g6_hashing:/app/tests
docker exec -w /app bd2_g6_hashing sh tests/correr_tests.sh despues
docker cp bd2_g6_hashing:/app/tests/resultados/. tests/resultados/
```

En Mac/Linux usar `python3` en vez de `py`.

## Resultado esperado (código corregido)

- `01_datasets.txt`: en las 6 filas, `insertadas = filas` y `perdidas = reinsertadas = falsos_positivos = 0`.
- `02_casos_limite.txt`: en cada caso, `obtenido` igual a `esperado`.
- `03_tope_profundidad.txt`: paso 1 = 50, paso 2 = `ERROR`, paso 3 = 100000, paso 4 = 0.
- `04_revision_interna.txt`: `Errores de estructura: 0` y `[OK]` en D1 y D2.

`resultados/antes/` tiene la salida con el código de `main` sin corregir (en el paso 2 da `f`, en el 3 da 645 y en el 4 da 99355).
