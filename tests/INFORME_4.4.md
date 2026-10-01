# 4.4 Corrección de errores

**Responsable:** Iair Suico
**Rama:** `iair-correcciones` (sobre `main` en `a09605e`)
**Fecha de ejecución:** 30/09/2026 (ANTES 22:45, DESPUÉS 22:53, hora de Lima)

## 1. Objetivo

Comprobar que la estructura de Extendible Hashing no pierde claves después de los splits y que se comporta bien en casos límite. Se corrigieron los errores encontrados **antes** del benchmark: cualquier cambio en el código obliga a reconstruir la extensión y repetir las mediciones.

Estas pruebas son de **correctitud**, no de rendimiento. No miden tiempos.

## 2. Entorno de ejecución

Todo se ejecutó en el Docker del grupo, levantado con el `Dockerfile` y el `docker-compose.yml` del repositorio. Los datos de entorno salen de `tests/resultados/*/00_entorno.txt`.

| Elemento | Valor |
|---|---|
| DBMS | PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2), 64-bit |
| Contenedor | `bd2_g6_hashing`, imagen construida con `docker compose up --build` |
| Host | Windows 11 + Docker Desktop (kernel `6.18.40.1-microsoft-standard-WSL2`) |
| CPU / memoria visibles en el contenedor | Intel Core i5-13420H (13.ª gen.), 12 núcleos, 7759 MB |
| Configuración | `shared_buffers` = 16384 × 8 kB (128 MB), `work_mem` = 4096 kB, `max_parallel_workers_per_gather` = 2 (valores por defecto) |
| Parámetros de la estructura | `PROF_INICIAL` = 2, `TAM_BUCKET` = 50, `PROF_MAXIMA` = 24 |
| Datos | `scripts/generar_datos.py`, semilla 42: D1 (secuencial) y D2 (aleatorio) en 100 000, 500 000 y 1 000 000 |

## 3. Plan de pruebas

Los scripts están en `tests/` y se corren todos con `tests/correr_tests.sh`.

| Script | Qué verifica |
|---|---|
| `01_datasets.sql` | Para cada uno de los 6 datasets, en una sesión nueva: claves insertadas, perdidas, reinsertadas y falsos positivos |
| `02_casos_limite.sql` | 0, negativos, extremos de `int`, `NULL`, repetidas en una misma consulta y búsqueda en sesión vacía (18 casos) |
| `03_tope_profundidad.sql` | Caso extremo: claves que comparten sus 24 bits bajos (múltiplos de $2^{24}$), seguidas de una carga normal |
| `revision_interna.c` | Revisa por dentro el directorio y los buckets después de 1 000 000 de inserciones |

Las métricas de `01_datasets.sql` se definen así:

- **perdidas**: claves que se insertaron pero que `pg_buscar` no encuentra. Lo esperado es 0.
- **reinsertadas**: claves que `pg_insertar` acepta al cargar el dataset por segunda vez. Lo esperado es 0, porque ya existían.
- **falsos positivos**: claves del rango $[-100\,000,\ \max(id) + 100\,000]$ que no están en el dataset, pero que `pg_buscar` da como encontradas. Lo esperado es 0.

La revisión interna comprueba cuatro reglas en cada casillero $i$ del directorio, donde $d_L$ es la profundidad local de su bucket:

1. Ningún bucket tiene más claves que su capacidad: $ELEM \le TAM$.
2. La profundidad local nunca supera a la global: $d_L \le d_G$.
3. Todos los casilleros que comparten los mismos $d_L$ bits bajos que $i$ apuntan al mismo bucket.
4. Cada clave del bucket tiene esos mismos $d_L$ bits bajos.

## 4. Procedimiento

1. Se generaron los datos de los 3 tamaños, se copiaron al contenedor y se cargó la tabla `buses` (pasos 2 a 4 del README).
2. **ANTES:** con el código de `main` sin cambios, se corrió `sh tests/correr_tests.sh antes`.
3. Se creó la rama `iair-correcciones` y se aplicó cada corrección en un commit separado (sección 6).
4. Se reconstruyó el entorno desde cero con `docker compose down -v` y `docker compose up --build`, y se repitió el paso 1.
5. **DESPUÉS:** con el código corregido, se corrió `sh tests/correr_tests.sh despues`.

Los comandos exactos están en `tests/README.md`.

## 5. Resultados

### 5.1 Datasets (`01_datasets.txt`)

El resultado fue **idéntico en ANTES y en DESPUÉS**.

| Dataset | Filas | Insertadas | Perdidas | Reinsertadas | Falsos positivos |
|---|---|---|---|---|---|
| D1_secuencial_100000 | 100 000 | 100 000 | 0 | 0 | 0 |
| D2_aleatorio_100000 | 100 000 | 100 000 | 0 | 0 | 0 |
| D1_secuencial_500000 | 500 000 | 500 000 | 0 | 0 | 0 |
| D2_aleatorio_500000 | 500 000 | 500 000 | 0 | 0 | 0 |
| D1_secuencial_1000000 | 1 000 000 | 1 000 000 | 0 | 0 | 0 |
| D2_aleatorio_1000000 | 1 000 000 | 1 000 000 | 0 | 0 | 0 |

Con estos datos, ni la inserción ni el split ni la búsqueda pierden claves o dan falsos positivos. El error encontrado no aparece con D1 ni con D2: solo aparece en el caso extremo de la sección 5.3.

### 5.2 Casos límite (`02_casos_limite.txt`)

En ANTES y en DESPUÉS, los 18 casos dieron el resultado esperado:

- La clave 0, los negativos ($-1$, $-4$) y los extremos de `int` ($2\,147\,483\,647$ y $-2\,147\,483\,648$) se insertan y se encuentran.
- Las claves que no existen ($-2$ y $4$) no se encuentran.
- Al insertar 0 por segunda vez, devuelve `false`.
- `pg_insertar(NULL)` devuelve `NULL`, porque la función es `STRICT`.
- En la consulta con 7, 7, 7 y 8 se insertaron 2 claves.
- Al insertar $-1$ a $-100\,000$ entraron 99 998 claves (−1 y −4 ya estaban) y no se perdió ninguna.
- Una búsqueda en una sesión vacía devuelve `false`.

### 5.3 Tope de profundidad (`03_tope_profundidad.txt`)

| Paso | Operación | ANTES (`main`) | DESPUÉS (`iair-correcciones`) |
|---|---|---|---|
| 1 | Insertar 50 múltiplos de $2^{24}$ (llenan un bucket) | 50 | 50 |
| 2 | Insertar la clave 51 ($50 \cdot 2^{24} = 838\,860\,800$) | `f` (sin aviso) | `ERROR: no se pudo insertar la clave 838860800` |
| 3 | Cargar D2 100 000 con el directorio en el tope | **645** | **100 000** |
| 4 | Claves de D2 no encontradas | **99 355** | **0** |

### 5.4 Revisión interna (`04_revision_interna.txt`)

El resultado fue idéntico en ANTES y en DESPUÉS.

| Dataset | Insertadas | Claves en buckets | $d_G$ final | Casillas | Buckets distintos | Errores |
|---|---|---|---|---|---|---|
| D1_secuencial_1000000 | 1 000 000 | 1 000 000 | 15 | 32 768 | 32 768 | 0 |
| D2_aleatorio_1000000 | 1 000 000 | 1 000 000 | 16 | 65 536 | 31 547 | 0 |

Con D1 cada casillero tiene su propio bucket, porque las claves secuenciales se reparten parejo entre los bits bajos. Con D2 hay menos buckets distintos que casillas (31 547 de 65 536): varios casilleros comparten bucket porque esos buckets tienen una profundidad local menor que la global.

## 6. Errores encontrados y correcciones

### Error 1: el límite de profundidad bloqueaba inserciones válidas (commit `33e3bdd`)

`insertar_llave` rechazaba cualquier clave que llegara a un bucket lleno cuando `PROF_GLOBAL >= PROF_MAXIMA`. Pero solo hace falta duplicar el directorio si el bucket ya usa todos los bits (`PROF_LOCAL == PROF_GLOBAL`). Si `PROF_LOCAL < PROF_GLOBAL`, el bucket se puede partir sin cambiar el tamaño del directorio.

La sección 5.3 muestra el efecto: después de que 50 claves llevaron el directorio al tope, de 100 000 claves normales solo entraron 645.

```c
// src/inserccion.c — antes
if (dir->PROF_GLOBAL >= PROF_MAXIMA) return false;

// después
if (bucket_actual->PROF_LOCAL >= dir->PROF_GLOBAL && dir->PROF_GLOBAL >= PROF_MAXIMA) return false;
```

### Error 2: si faltaba memoria, la inserción nunca terminaba (commit `cddbd5d`)

`dividir_bucket` devolvía `void`. Si `realloc` o `malloc` fallaban, salía sin cambiar nada y `insertar_llave` se volvía a llamar a sí misma sobre el mismo bucket lleno, sin fin, hasta que se caía el proceso de PostgreSQL.

Se corrigió así:

- `dividir_bucket` ahora devuelve `int`: 1 si partió el bucket y 0 si no pudo (en `src/split.c` y `include/split.h`).
- `insertar_llave` deja de intentarlo si recibe 0.
- `CrearBucket` revisa ambos `malloc` y, si alguno falla, libera lo reservado y devuelve `NULL` (en `src/bucket.c`).

Este error no se reprodujo, porque forzar que `malloc` falle dentro del contenedor no es práctico. La corrección se hizo a partir de la revisión del código. Las pruebas de las secciones 5.1 a 5.4 confirman que el cambio no altera el funcionamiento normal.

### Error 3: una inserción fallida parecía una clave repetida (commit `dc45544`)

`pg_insertar` devolvía `false` tanto si la clave ya existía como si no se había podido insertar. Así, el fallo del error 1 pasaba desapercibido, y un benchmark que contara las inserciones daría resultados equivocados sin aviso.

En `pg_hashing.c`, cuando la inserción devuelve `false` ahora se busca la clave. Si tampoco existe, se lanza `ERROR` con el mensaje «no se pudo insertar la clave». La sección 5.3, paso 2, lo muestra: antes la clave 51 devolvía `f` sin aviso y ahora PostgreSQL muestra el error.

## 7. Evidencia

Todo está en la rama `iair-correcciones`:

```
tests/
  01_datasets.sql  02_casos_limite.sql  03_tope_profundidad.sql
  revision_interna.c  correr_tests.sh  README.md
  resultados/
    antes/    00_entorno.txt  01_datasets.txt  02_casos_limite.txt  03_tope_profundidad.txt  04_revision_interna.txt
    despues/  00_entorno.txt  01_datasets.txt  02_casos_limite.txt  03_tope_profundidad.txt  04_revision_interna.txt
```

| Commit | Contenido |
|---|---|
| `33e3bdd` | Error 1: `src/inserccion.c` |
| `cddbd5d` | Error 2: `src/split.c`, `include/split.h`, `src/inserccion.c`, `src/bucket.c` |
| `dc45544` | Error 3: `pg_hashing.c` |
| `40cb37a` | Carpeta `tests/` y resultados de ANTES y DESPUÉS |

Para reproducir: hacer checkout de la rama, levantar con `docker compose up --build`, cargar los datos y correr `docker exec -w /app bd2_g6_hashing sh tests/correr_tests.sh despues`. Tienen que salir los mismos números de la sección 5.

## 8. Observaciones sobre el README

1. **El paso 2 genera solo los datos de 100 000** (`generar_datos.py 100000`). Para los 3 tamaños obligatorios hay que correr `py scripts/generar_datos.py` sin argumentos.
2. **`sql/cargar_buses.sql` siempre carga `D2_aleatorio_100000.csv`.** Para cargar D1 u otro tamaño hay que editar la línea del `\copy`, porque `\copy` no acepta variables de psql.
3. **`docker cp` y el `COPY` del `Dockerfile` pueden chocar.** El `Dockerfile` copia todo el proyecto con `COPY . /app/` y no hay `.dockerignore`. Si `data/` ya existía al construir la imagen, `docker cp data bd2_g6_hashing:/app/data` copia a `/app/data/data/`. En estas pruebas se usó `docker cp data/. bd2_g6_hashing:/app/data`, que copia el contenido y evita el problema. Se recomienda cambiar el README y agregar un `.dockerignore` con `data/`.
4. **`py` solo existe en Windows.** En Linux y macOS el comando es `python3`.

## 9. Limitaciones

- Son pruebas de correctitud y no miden tiempos. Los resultados son deterministas (semilla fija, mismos datos), así que una ejecución por etapa basta para comprobar que todo es correcto. Las 5 repeticiones que pide la rúbrica corresponden al benchmark (actividad 5.1).
- El error 2 se corrigió sin poder reproducirlo (ver sección 6).
- En el caso extremo, el directorio llega a $2^{24}$ punteros (unos 128 MB) dentro del proceso de la sesión. Es un límite de diseño (`PROF_MAXIMA`) y no un error, pero conviene considerarlo si se aumenta `PROF_MAXIMA`.
- La estructura vive en memoria solo mientras dura la sesión, por lo que cada dataset se probó en una sesión nueva (`\c`).

## 10. Uso de IA

Se usó Claude (IA) como apoyo para revisar el código, detectar los errores, redactar las correcciones, escribir los scripts de `tests/` y redactar este informe. Las pruebas se ejecutaron en el entorno Docker del grupo y los resultados de la sección 5 provienen de esas ejecuciones.

## 11. Conclusión

En PostgreSQL 18.6, dentro del Docker del grupo, la estructura no pierde claves, no da falsos positivos y no acepta reinserciones en ninguno de los 6 datasets (D1 y D2 de 100 000, 500 000 y 1 000 000). La revisión interna no encontró errores después de un millón de inserciones.

Se corrigieron tres errores: el límite de profundidad que bloqueaba inserciones válidas (645 → 100 000 en el caso extremo), la inserción que no terminaba cuando faltaba memoria, y las inserciones fallidas que parecían claves repetidas. El benchmark debe medirse con el código de la rama `iair-correcciones` una vez que se integre a `main`.
