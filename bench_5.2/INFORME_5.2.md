# 5.2 Comparación preliminar con B-tree

**Responsable:** Iair Suico
**Rama:** `iair-5.2-v2` (incluye `main` en `68ac794`, con el benchmark verificado de Fabricio Stelman)
**Fecha de ejecución:** 03/10/2026 (hora de Lima)

## 1. Objetivo

Hacer una primera comparación entre nuestra estructura (Extendible Hashing) y el índice B-tree de PostgreSQL, como pide la rúbrica para el parcial (sección 5.2). Se comparan el tiempo de búsqueda, el tiempo de construcción y el tamaño. Como referencia también se incluye el acceso sin índice, que midió el 5.1.

Es una comparación **preliminar**. El benchmark completo de la etapa II (D1, inserciones W3, caso sin índice en los tres tamaños) queda pendiente.

## 2. Entorno

| Elemento | Valor |
|---|---|
| DBMS | PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2), 64-bit (aparece al inicio de cada `.txt`) |
| Contenedor | `bd2_g6_hashing`, reconstruido desde cero (`docker compose down -v` y `docker compose up --build`) |
| Host | Windows 11 + Docker Desktop (WSL2, kernel `6.18.40.1-microsoft-standard-WSL2`) |
| CPU / memoria visibles en el contenedor | Intel Core i5-13420H, 12 núcleos, 7759 MB |
| Configuración | `shared_buffers` = 128 MB, `work_mem` = 4 MB, `max_parallel_workers_per_gather` = 2, `jit` = on (valores por defecto) |
| Parámetros de la estructura | `PROF_INICIAL` = 2, `TAM_BUCKET` = 50, `PROF_MAXIMA` = 24 |
| Datos | D2 (claves aleatorias únicas, semilla 42) en 100 000, 500 000 y 1 000 000 filas |

Los datos de máquina y configuración se registran en `bench_5.2/resultados/00_entorno.txt`.

## 3. Metodología

### 3.1 Scripts

Se usaron los scripts del benchmark verificado del grupo (`benchmark/`, actividad 5.1, Fabricio Stelman) **sin modificarlos**, más dos scripts propios de la 5.2:

| Script | Qué hace |
|---|---|
| `benchmark/00_preparar_claves.sql` | Genera 20 000 claves de búsqueda: 10 000 que existen (W1) y 10 000 que no (W2), con `setseed(0.42)`, intercaladas |
| `benchmark/02_btree.sql` | Crea el índice B-tree y busca las 20 000 claves, 5 repeticiones |
| `benchmark/03_hashing.sql` | Construye nuestra estructura y busca las mismas 20 000 claves, 5 repeticiones |
| `bench_5.2/construccion_tamano.sql` | Construcción de B-tree y de hash con 5 repeticiones cada una, y tamaño del índice B-tree |
| `bench_5.2/correr_5.2.sh` | Corre todo lo anterior para cada tamaño de D2 |

Se comprobó que la carpeta `benchmark/` de la rama es idéntica a la de `main` (`git diff origin/main -- benchmark` sin diferencias).

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

Cada medición tiene una corrida de calentamiento que se descarta y luego 5 repeticiones medidas, como pide la rúbrica. Se reporta la **mediana** porque varias series tienen una repetición aislada mucho más lenta que el resto (ver 4.5), y la media se movería con ella. En los `.txt` también están el mínimo y el máximo.

En cada corrida se comprueba que W1 encuentre las 10 000 claves y W2 ninguna (`resultados_correctos = t`).

## 4. Resultados

### 4.1 Búsqueda (20 000 claves por repetición: 10 000 W1 + 10 000 W2)

Mediana de 5 repeticiones, en **µs por consulta**:

| D2 | B-tree | Hash por SQL | Consulta vacía | Hash directo | B-tree / Hash por SQL |
|---|---|---|---|---|---|
| 100 000 | 3,27 | 1,02 | 1,05 | 0,15 | 3,2× |
| 500 000 | 4,02 | 1,26 | 0,93 | 0,19 | 3,2× |
| 1 000 000 | 3,83 | 1,18 | 0,91 | 0,22 | 3,2× |

Tiempos totales (mediana, en ms para 20 000 consultas):

| D2 | B-tree | Hash por SQL | Consulta vacía | Hash directo |
|---|---|---|---|---|
| 100 000 | 65,3 | 20,4 | 21,1 | 2,9 |
| 500 000 | 80,4 | 25,1 | 18,7 | 3,8 |
| 1 000 000 | 76,5 | 23,7 | 18,3 | 4,4 |

En las tres corridas `resultados_correctos = t`, tanto en B-tree como en hash.

### 4.2 Referencia: acceso sin índice (actividad 5.1)

Dato de `benchmark/resultados/01_sin_indice.txt` (Fabricio), solo con D2 de 100 000, porque cada búsqueda recorre la tabla entera:

| Método (misma corrida del 5.1, D2 100 000) | µs por consulta (mediana) |
|---|---|
| Sin índice (`Seq Scan`) | 2 505,7 |
| B-tree | 2,81 |
| Hash por SQL | 1,01 |

Sin índice, cada búsqueda es unas 900 veces más lenta que con B-tree y unas 2 500 veces más lenta que con nuestra estructura. Estos tres valores salen de la corrida del 5.1, no de la 5.2, y por eso no se mezclan con la tabla 4.1. Aun así, sus valores de B-tree y hash coinciden en magnitud con los de la 4.1.

### 4.3 Construcción

Mediana de 5 repeticiones:

| D2 | B-tree (ms) | Hash (ms) | B-tree (µs/fila) | Hash (µs/fila) | B-tree / Hash |
|---|---|---|---|---|---|
| 100 000 | 27,9 | 9,9 | 0,279 | 0,099 | 2,8× |
| 500 000 | 181,5 | 90,1 | 0,363 | 0,180 | 2,0× |
| 1 000 000 | 389,3 | 308,4 | 0,389 | 0,308 | 1,3× |

### 4.4 Tamaño

| D2 | Índice B-tree | Tabla `buses` | Bytes por clave (B-tree) |
|---|---|---|---|
| 100 000 | 2208 kB | 5504 kB | 22,6 |
| 500 000 | 11 MB | 25 MB | 22,5 |
| 1 000 000 | 21 MB | 50 MB | 22,5 |

El tamaño de nuestra estructura no se puede medir desde SQL, porque la extensión no lo expone. Se puede **estimar** con la revisión interna de la actividad 4.4 (`tests/resultados/despues/04_revision_interna.txt`). Con D2 de 1 000 000 hay 31 547 buckets y un directorio de $2^{16}$ = 65 536 casillas:

$$31\,547 \times (24 + 50 \cdot 4)\ \text{B} + 65\,536 \times 8\ \text{B} \approx 7{,}1\ \text{MB} + 0{,}5\ \text{MB} \approx 7{,}6\ \text{MB}$$

Eso da unos 7,6 bytes por clave, sin contar lo que agrega `malloc` por cada reserva. La ocupación de los buckets es $1\,000\,000 / (31\,547 \times 50) \approx 63\,\%$. Es una estimación a partir del código, no una medición.

### 4.5 Variación entre repeticiones

- **Búsquedas con B-tree:** la primera repetición fue la más lenta en los tres tamaños (86,9, 88,6 y 104,3 ms, frente a medianas de 65,3, 80,4 y 76,5 ms). Lo más probable es que las páginas del índice todavía no estuvieran en memoria al empezar.
- **Repeticiones aisladas más lentas:** `baseline_sql` con 100 000 (39,1 ms frente a unos 17–21 ms), `baseline_sql` con 500 000 (35,6 frente a 18,7), `hashing_via_sql` con 1 000 000 (43,5 frente a 23,7) y la construcción del hash con 500 000 (130,5 frente a 90,1). Son picos de una sola repetición, probablemente por otros procesos del sistema. La mediana no se ve afectada.
- **Con 100 000, la mediana de la consulta vacía (1,05 µs) salió un poco por encima de la del hash por SQL (1,02 µs).** La diferencia está dentro del ruido de la medición: con ese tamaño, el costo propio de buscar en el hash no se distingue del costo fijo de una consulta.

## 5. Análisis

**Búsqueda.** Incluso pagando el mismo costo fijo de una consulta SQL, nuestra estructura fue unas **3,2 veces** más rápida que el B-tree en los tres tamaños. La variante directa muestra que el costo propio de la estructura es de 0,15 a 0,22 µs por búsqueda. Restando la consulta vacía, el B-tree necesita unos 2,2–3,1 µs. O sea, casi todo el tiempo del hash por SQL es el costo de ejecutar la consulta, no el de buscar.

Esto concuerda con la teoría. En Extendible Hashing, una búsqueda por igualdad es un acceso al directorio más un recorrido de un bucket de como máximo 50 claves, o sea $O(1)$. En el B-tree hay que bajar desde la raíz hasta una hoja, $O(\log n)$, y cada página pasa por el *buffer manager* de PostgreSQL.

**Crecimiento con el tamaño.** El B-tree pasó de 3,27 a 3,83 µs por consulta (+17 %) al ir de 100 000 a 1 000 000 filas. El punto de 500 000 (4,02 µs) quedó un poco por encima del de 1 000 000, así que con 5 repeticiones la tendencia no es del todo limpia. El hash directo subió de 0,15 a 0,22 µs (+47 %), aunque en teoría es $O(1)$. Lo más probable es que se deba a la memoria caché del procesador: con 1M de claves la estructura ocupa unos 7,6 MB y ya no entra entera en la caché, así que hay más accesos a memoria principal. En valores absolutos, ese aumento (0,07 µs) es mucho menor que el del B-tree.

**Construcción.** El hash fue más rápido en los tres tamaños, pero la ventaja bajó de **2,8× con 100 000 a 1,3× con 1 000 000**. Por fila, el hash pasó de 0,099 a 0,308 µs (×3,1), mientras que el B-tree solo pasó de 0,279 a 0,389 µs (×1,4). Hay dos causas probables:
1. Cada vez que el directorio se duplica, `realloc` copia todo el arreglo de punteros. Con 1M el directorio llega a $2^{16}$ casillas.
2. Las inserciones caen en posiciones aleatorias de una estructura cada vez más grande, y eso aprovecha peor la memoria caché.

El B-tree, en cambio, ordena todas las claves y llena las hojas en orden, de forma secuencial. Si la tendencia sigue, con más datos el B-tree podría llegar a construirse más rápido. Hay que comprobarlo en la etapa II.

**Tamaño.** El B-tree ocupa unos 22,5 bytes por clave, casi constante, más o menos el 43 % de la tabla. Según la estimación, nuestra estructura ocuparía unos 7,6 bytes por clave, pero no es una comparación directa: el B-tree guarda en cada entrada la dirección de la fila en la tabla (TID), las páginas tienen metadatos y espacio libre, y nuestra estructura solo guarda la clave.

## 6. Limitaciones y amenazas a la validez

- **No es un índice equivalente.** El B-tree se guarda en disco, pasa por el *buffer manager* y el WAL, se comparte entre sesiones y lleva a la fila. Nuestra estructura vive solo en la memoria de una sesión, no es persistente y solo responde si la clave existe. Parte de la ventaja del hash viene de no hacer ese trabajo.
- **Visibilidad en el B-tree.** El plan usa *Index Only Scan*, pero la tabla se carga sin `VACUUM`. Si el mapa de visibilidad no está actualizado, PostgreSQL puede tener que ir a la tabla para revisar cada fila, lo que encarece la búsqueda con B-tree. En la etapa II conviene correr `VACUUM ANALYZE` antes de medir y revisar `Heap Fetches` con `EXPLAIN ANALYZE`.
- **Construcción en `02_btree.sql`.** Ese script mide una sola construcción con los trabajadores paralelos por defecto (2). Las cifras de la sección 4.3 vienen de `construccion_tamano.sql`, que fija un solo proceso para comparar en igualdad de condiciones con `pg_insertar`.
- **Tamaño del hash estimado.** Sale de una fórmula a partir del código y de los contadores de la 4.4, no de una medición.
- **Ruido de medición.** Las mediciones son de decenas de milisegundos, en un portátil con WSL2 y otros procesos activos. Hay picos aislados (sección 4.5) y diferencias pequeñas, como la de la consulta vacía con el hash por SQL en 100 000, que no son significativas. Las relaciones grandes, como el ~3,2× en búsqueda o el 2,8× → 1,3× en construcción, sí se repitieron en la corrida anterior de la 5.2, hecha con los mismos scripts.
- **El caso sin índice viene de otra corrida.** El dato de la sección 4.2 sale de la ejecución del 5.1, no de la 5.2.
- **Alcance preliminar.** Solo D2. No incluye D1 ni inserciones W3.

## 7. Reproducción y evidencia

Con el contenedor levantado, los datos de los tres tamaños generados (`py scripts/generar_datos.py`) y la rama `iair-5.2-v2`:

```
docker cp data/. bd2_g6_hashing:/app/data
docker cp benchmark/. bd2_g6_hashing:/app/benchmark
docker cp bench_5.2/. bd2_g6_hashing:/app/bench_5.2
docker exec -w /app bd2_g6_hashing sh bench_5.2/correr_5.2.sh
docker cp bd2_g6_hashing:/app/bench_5.2/resultados/. bench_5.2/resultados/
```

Las salidas quedan en `bench_5.2/resultados/`:

```
00_entorno.txt
D2_aleatorio_100000/   00_claves.txt  02_btree.txt  03_hashing.txt  04_construccion_tamano.txt
D2_aleatorio_500000/   (igual)
D2_aleatorio_1000000/  (igual)
```

## 8. Uso de IA

Se usó Claude (IA) como apoyo para diseñar `construccion_tamano.sql` y `correr_5.2.sh`, revisar los scripts del benchmark y redactar este informe. Las mediciones se ejecutaron en el entorno Docker del grupo (PostgreSQL 18.6) y los números de la sección 4 salen de esas ejecuciones.

## 9. Conclusión preliminar

Con D2 en 100 000, 500 000 y 1 000 000 filas, en PostgreSQL 18.6:

- **Búsqueda por igualdad:** nuestra estructura fue unas 3,2 veces más rápida que el B-tree en los tres tamaños, comparando las dos con una consulta SQL por clave. El costo propio de la estructura (0,15–0,22 µs) es mucho menor que el del B-tree (2,2–3,1 µs). Sin índice, cada búsqueda tarda unos 2,5 ms con solo 100 000 filas.
- **Construcción:** el hash fue más rápido en los tres tamaños, pero la ventaja bajó de 2,8× a 1,3×. Hay que confirmar en la etapa II si se mantiene con más datos o con D1.
- **Tamaño:** el B-tree ocupa unos 22,5 bytes por clave. Nuestra estructura se estima en unos 7,6, pero no guarda la ubicación de la fila ni es persistente.

Estos resultados favorecen a Extendible Hashing para búsquedas por igualdad, que es la única consulta que soporta. No dicen nada de búsquedas por rango, que el B-tree sí permite y nuestra estructura no.
