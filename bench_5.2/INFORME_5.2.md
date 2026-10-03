# 5.2 Comparación preliminar con B-tree

**Responsable:** Iair Suico
**Rama:** `iair-5.2-v2` (sobre `main` en `1994cd7`; incluye la rama `benchmark` de Fabricio, commit `716f5c9`, y la 5.2, commit `6a02de8`)
**Fecha de ejecución:** 02/10/2026, 20:20 (hora de Lima)

## 1. Objetivo

Hacer una primera comparación entre nuestra estructura (Extendible Hashing) y el índice B-tree de PostgreSQL, como pide la rúbrica para el parcial (sección 5.2). Se comparan tres cosas: el tiempo de búsqueda, el tiempo de construcción y el tamaño.

Es una comparación **preliminar**. El benchmark completo de la etapa II (D1, inserciones W3, caso sin índice en los tres tamaños) queda pendiente.

## 2. Entorno

Los datos salen de `bench_5.2/resultados/00_entorno.txt` y de la cabecera de cada `.txt`.

| Elemento | Valor |
|---|---|
| DBMS | PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2), 64-bit |
| Contenedor | `bd2_g6_hashing`, imagen construida con `docker compose up --build` |
| Host | Windows 11 + Docker Desktop (WSL2, kernel `6.18.40.1-microsoft-standard-WSL2`) |
| CPU / memoria visibles en el contenedor | Intel Core i5-13420H, 12 núcleos, 7759 MB |
| Configuración | `shared_buffers` = 128 MB, `work_mem` = 4 MB, `max_parallel_workers_per_gather` = 2, `jit` = on (valores por defecto) |
| Parámetros de la estructura | `PROF_INICIAL` = 2, `TAM_BUCKET` = 50, `PROF_MAXIMA` = 24 |
| Datos | D2 (claves aleatorias únicas, semilla 42) en 100 000, 500 000 y 1 000 000 filas |

## 3. Metodología

### 3.1 Scripts

Se usaron los scripts del benchmark del grupo (`benchmark/`, actividad 5.1, Fabricio Stelman) **sin modificarlos**, más dos scripts propios de la 5.2:

| Script | Qué hace |
|---|---|
| `benchmark/00_preparar_claves.sql` | Genera 20 000 claves de búsqueda: 10 000 que existen (W1) y 10 000 que no (W2), con `setseed(0.42)`, intercaladas |
| `benchmark/02_btree.sql` | Crea el índice B-tree y busca las 20 000 claves, 5 repeticiones |
| `benchmark/03_hashing.sql` | Construye nuestra estructura y busca las mismas 20 000 claves, 5 repeticiones |
| `bench_5.2/construccion_tamano.sql` | Construcción de B-tree y de hash con 5 repeticiones cada una, y tamaño del índice B-tree |
| `bench_5.2/correr_5.2.sh` | Corre todo lo anterior para cada tamaño de D2 |

### 3.2 Qué significa "buscar"

`pg_buscar` solo responde si la clave existe. Para que la comparación sea equivalente, el B-tree hace lo mismo: `SELECT EXISTS (SELECT 1 FROM buses WHERE id_bus = k)`, sin traer la fila. Cada búsqueda se hace por separado, dentro de un bucle PL/pgSQL, y las claves se cargan en un arreglo antes de empezar a medir.

`03_hashing.sql` mide tres variantes:

| Variante | Qué ejecuta | Para qué sirve |
|---|---|---|
| `hashing_via_sql` | `SELECT pg_buscar(k) INTO hit` | **La comparación justa con B-tree**: las dos hacen una consulta SQL por clave |
| `hashing_directo` | `hit := pg_buscar(k)` | Costo de la estructura sola, sin pasar por el ejecutor de consultas |
| `baseline_sql` | `SELECT (k IS NOT NULL) INTO hit` | Costo fijo de ejecutar una consulta que no busca nada |

### 3.3 Construcción

- **B-tree:** `CREATE INDEX idx_buses_btree ON buses USING btree (id_bus)` con `max_parallel_maintenance_workers = 0`, o sea, con un solo proceso, igual que nuestra estructura.
- **Hash:** `SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) FROM buses`. Cada repetición se hace en una sesión nueva (`\c`), porque la estructura vive solo mientras dura la sesión.

### 3.4 Repeticiones y medida central

Cada medición tiene una corrida de calentamiento que se descarta y luego 5 repeticiones medidas, como pide la rúbrica. Se reporta la **mediana** porque es menos sensible a una repetición lenta aislada. Por ejemplo, en D2 de 500 000 la primera búsqueda con B-tree tardó 144,9 ms y las siguientes entre 76 y 104 ms (ver 5.4). En los `.txt` también están el mínimo y el máximo.

En cada corrida se comprueba que W1 encuentre las 10 000 claves y W2 ninguna (`resultados_correctos = t`).

## 4. Resultados

### 4.1 Búsqueda (20 000 claves por repetición: 10 000 W1 + 10 000 W2)

Mediana de 5 repeticiones, en **µs por consulta**:

| D2 | B-tree | Hash por SQL | Consulta vacía | Hash directo | B-tree / Hash por SQL |
|---|---|---|---|---|---|
| 100 000 | 3,03 | 0,98 | 0,82 | 0,13 | 3,1× |
| 500 000 | 3,98 | 1,09 | 0,87 | 0,19 | 3,7× |
| 1 000 000 | 4,18 | 1,12 | 0,84 | 0,22 | 3,7× |

Tiempos totales (mediana, en ms para 20 000 consultas): B-tree 60,6 / 79,6 / 83,6; hash por SQL 19,6 / 21,8 / 22,3; consulta vacía 16,4 / 17,4 / 16,9; hash directo 2,7 / 3,7 / 4,5.

En las tres corridas `resultados_correctos = t`, tanto en B-tree como en hash.

### 4.2 Construcción

Mediana de 5 repeticiones:

| D2 | B-tree (ms) | Hash (ms) | B-tree (µs/fila) | Hash (µs/fila) | B-tree / Hash |
|---|---|---|---|---|---|
| 100 000 | 27,6 | 9,4 | 0,276 | 0,094 | 2,9× |
| 500 000 | 183,6 | 94,1 | 0,367 | 0,188 | 2,0× |
| 1 000 000 | 419,5 | 305,8 | 0,420 | 0,306 | 1,4× |

### 4.3 Tamaño

| D2 | Índice B-tree | Tabla `buses` | Bytes por clave (B-tree) |
|---|---|---|---|
| 100 000 | 2208 kB | 5504 kB | 22,6 |
| 500 000 | 11 MB | 25 MB | 22,5 |
| 1 000 000 | 21 MB | 50 MB | 22,5 |

El tamaño de nuestra estructura no se puede medir desde SQL, porque la extensión no lo expone. Se puede **estimar** con la revisión interna de la actividad 4.4 (`tests/resultados/despues/04_revision_interna.txt`). Con D2 de 1 000 000 hay 31 547 buckets y un directorio de $2^{16}$ = 65 536 casillas:

$$31\,547 \times (24 + 50 \cdot 4)\ \text{B} + 65\,536 \times 8\ \text{B} \approx 7{,}1\ \text{MB} + 0{,}5\ \text{MB} \approx 7{,}6\ \text{MB}$$

Eso da unos 7,6 bytes por clave, sin contar lo que agrega `malloc` por cada reserva. La ocupación de los buckets es $1\,000\,000 / (31\,547 \times 50) \approx 63\,\%$. Es una estimación a partir del código, no una medición.

### 4.4 Variación entre repeticiones

- En las búsquedas con B-tree, la primera repetición fue la más lenta en 500 000 (144,9 ms frente a una mediana de 79,6) y en 1 000 000 (125,5 ms frente a 83,6). Lo más probable es que las páginas del índice todavía no estuvieran en memoria al empezar.
- Nuestra estructura varió poco en todas las mediciones (por ejemplo, hash por SQL con 1 000 000: entre 21,4 y 23,6 ms).
- En la construcción del B-tree con 500 000, una repetición tardó 302,8 ms, frente a una mediana de 183,6 ms.

## 5. Análisis

**Búsqueda.** Incluso pagando el mismo costo fijo de una consulta SQL, nuestra estructura fue entre 3,1 y 3,7 veces más rápida que el B-tree. Si a cada método se le resta el costo de la consulta vacía (unos 0,8 µs), el costo propio de la búsqueda queda en unos 2,2–3,3 µs para el B-tree y unos 0,16–0,28 µs para el hash. O sea, la mayor parte del tiempo del hash por SQL es el costo de ejecutar la consulta, no el de buscar.

Esto concuerda con la teoría. En Extendible Hashing, una búsqueda por igualdad es un acceso al directorio más un recorrido de un bucket de como máximo 50 claves, o sea $O(1)$. En el B-tree hay que bajar desde la raíz hasta una hoja, $O(\log n)$, y cada página pasa por el *buffer manager* de PostgreSQL.

**Crecimiento con el tamaño.** El B-tree pasa de 3,03 a 4,18 µs por consulta (+38 %) al ir de 100 000 a 1 000 000 filas, como se espera de una búsqueda logarítmica. Nuestra estructura también crece un poco (hash directo: de 0,13 a 0,22 µs), aunque en teoría es $O(1)$. Lo más probable es que se deba a la memoria caché del procesador: con 1M de claves la estructura ocupa unos 7,6 MB y ya no entra entera en la caché, así que hay más accesos a memoria principal.

**Construcción.** El hash fue más rápido en los tres tamaños, pero la diferencia se achica: 2,9× con 100 000 y 1,4× con 1 000 000. Por fila, el hash pasó de 0,094 a 0,306 µs (×3,3), mientras que el B-tree solo pasó de 0,276 a 0,420 µs (×1,5). Hay dos causas probables:
1. Cada vez que el directorio se duplica, `realloc` copia todo el arreglo de punteros. Con 1M el directorio llega a $2^{16}$ casillas.
2. Las inserciones caen en posiciones aleatorias de una estructura cada vez más grande, y eso aprovecha peor la memoria caché.

El B-tree, en cambio, ordena todas las claves y llena las hojas en orden, de forma secuencial. Con más datos, esa ventaja podría dar vuelta el resultado. Hay que comprobarlo en la etapa II.

**Tamaño.** El B-tree ocupa unos 22,5 bytes por clave, casi constante, más o menos el 43 % de la tabla. Según la estimación, nuestra estructura ocuparía unos 7,6 bytes por clave, pero no es una comparación directa: el B-tree guarda en cada entrada la dirección de la fila en la tabla (TID), las páginas tienen metadatos y espacio libre, y nuestra estructura solo guarda la clave.

## 6. Limitaciones y amenazas a la validez

- **No es un índice equivalente.** El B-tree se guarda en disco, pasa por el *buffer manager* y el WAL, se comparte entre sesiones y lleva a la fila. Nuestra estructura vive solo en la memoria de una sesión, no es persistente y solo responde si la clave existe. Parte de la ventaja del hash viene de no hacer ese trabajo.
- **Visibilidad en el B-tree.** El plan usa *Index Only Scan*, pero la tabla se carga sin `VACUUM`. Si el mapa de visibilidad no está actualizado, PostgreSQL puede tener que ir a la tabla para revisar cada fila, lo que encarece la búsqueda con B-tree. En la etapa II conviene correr `VACUUM ANALYZE` antes de medir y revisar `Heap Fetches` con `EXPLAIN ANALYZE`.
- **Construcción en `02_btree.sql`.** Ese script mide una sola construcción con los trabajadores paralelos por defecto (2). Las cifras de la sección 4.2 vienen de `construccion_tamano.sql`, que fija un solo proceso para comparar en igualdad de condiciones con `pg_insertar`.
- **Tamaño del hash estimado.** Sale de una fórmula a partir del código y de los contadores de la 4.4, no de una medición.
- **Una sola máquina** (portátil con WSL2) y una sola ejecución de la serie completa. Las mediciones absolutas pueden cambiar en otro equipo, aunque la relación entre métodos debería mantenerse.
- **Alcance preliminar.** Solo D2. No incluye D1, ni inserciones W3, ni el caso sin índice: ese se mide en el 5.1 (`benchmark/01_sin_indice.sql`), solo con D2 de 100 000 por lo que tarda.

## 7. Reproducción y evidencia

Con el contenedor levantado, los datos de los tres tamaños generados y las carpetas `benchmark/` y `bench_5.2/` en el proyecto:

```
docker cp data/. bd2_g6_hashing:/app/data
docker cp benchmark/. bd2_g6_hashing:/app/benchmark
docker cp bench_5.2/. bd2_g6_hashing:/app/bench_5.2
docker exec -w /app bd2_g6_hashing sh bench_5.2/correr_5.2.sh
```

Las salidas quedan en `bench_5.2/resultados/`:

```
00_entorno.txt
D2_aleatorio_100000/   00_claves.txt  02_btree.txt  03_hashing.txt  04_construccion_tamano.txt
D2_aleatorio_500000/   (igual)
D2_aleatorio_1000000/  (igual)
```

La rama `iair-5.2-v2` ya incluye la carpeta `benchmark/` de Fabricio (rama `benchmark`, commit `716f5c9`). Se comprobó con `fc` que sus scripts `00`, `02` y `03` son idénticos a los usados en las mediciones.

## 8. Uso de IA

Se usó Claude (IA) como apoyo para diseñar `construccion_tamano.sql` y `correr_5.2.sh`, revisar los scripts del benchmark y redactar este informe. Las mediciones se ejecutaron en el entorno Docker del grupo (PostgreSQL 18.6) y los números de la sección 4 salen de esas ejecuciones.

## 9. Conclusión preliminar

Con D2 en 100 000, 500 000 y 1 000 000 filas, en PostgreSQL 18.6:

- **Búsqueda por igualdad:** nuestra estructura fue entre 3,1 y 3,7 veces más rápida que el B-tree, comparando las dos con una consulta SQL por clave. Además, su tiempo creció menos al aumentar los datos.
- **Construcción:** el hash fue más rápido en los tres tamaños, pero la ventaja bajó de 2,9× a 1,4×. Hay que confirmar en la etapa II si se mantiene con más datos o con D1.
- **Tamaño:** el B-tree ocupa unos 22,5 bytes por clave. Nuestra estructura se estima en unos 7,6, pero no guarda la ubicación de la fila ni es persistente.

Estos resultados favorecen a Extendible Hashing para búsquedas por igualdad, que es la única consulta que soporta. No dicen nada de búsquedas por rango, que el B-tree sí permite y nuestra estructura no.
