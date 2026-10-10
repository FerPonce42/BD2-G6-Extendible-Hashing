# Grupo 6 - Extendible Hashing en PostgreSQL

Estructura de Extendible Hashing hecha en C y conectada a PostgreSQL 18.6 como extensión.
Desde SQL se usa con `pg_insertar(id)` y `pg_buscar(id)`.

Este README explica cómo levantar todo desde cero y cómo reproducir las pruebas y las mediciones del informe de la etapa I.

---

## Componentes

**Núcleo en C** (`src/` e `include/`)
- bucket: caja con un arreglo de claves.
- directorio: tabla de punteros a buckets.
- búsqueda (`buscar_llave`): devuelve el bucket donde está la clave, o donde debería ir.
- inserción (`insertar_llave`): mete la clave. Devuelve `true` si la insertó y `false` si ya existía o si no pudo insertar.
- split (`dividir_bucket`): parte un bucket lleno en dos. Si hace falta, duplica el directorio. Devuelve 1 si partió el bucket y 0 si no pudo.
- `main.c`: prueba por consola. No entra a la extensión.

**Puente con PostgreSQL**
- `pg_hashing.c`: define `pg_insertar` y `pg_buscar`. Crea el directorio la primera vez que se llama a una de las dos. Si una clave nueva no se pudo insertar, `pg_insertar` lanza un ERROR en lugar de devolver `f`, para no confundirlo con una clave repetida.
- `pg_hashing--1.0.sql`: declara esas dos funciones en SQL.
- `pg_hashing.control`: datos de la extensión (nombre, versión).
- `Makefile`: compila el C con PGXS.

**Entorno**
- `Dockerfile`: parte de `postgres:18.6`, compila e instala la extensión.
- `docker-compose.yml`: levanta el contenedor `bd2_g6_hashing` con la base `hashing_db`.

**Datos**
- `scripts/generar_datos.py`: genera los CSV en `data/`. D1 es secuencial y D2 es aleatorio (semilla 42).
- `sql/cargar_buses.sql`: crea la tabla `buses` (sin índice a propósito) y carga un CSV. Siempre carga `D2_aleatorio_100000.csv`; para cargar otro hay que cambiar el nombre en el script.
- `data/`: los CSV. No se suben al repo, se generan.

**Pruebas y mediciones**
- `tests/`: pruebas de correctitud y de casos límite. Los resultados de antes y después de las correcciones están en `tests/resultados/`.
- `benchmark/`: benchmark de búsqueda (sin índice, B-tree y Extendible Hashing) con D2 de 100 000 filas.
- `bench_5.2/`: comparación con B-tree con tres tamaños de D2, construcción con cinco repeticiones y tamaño del índice.

---

## Prerequisitos

- Docker Desktop abierto (Engine running).
- Python (en Windows: `py`).
- Git.
- Terminal dentro de la carpeta del proyecto.

---

## Flujo

### 1. Levantar Docker
```
docker compose up --build
```
Arma el contenedor, compila el C adentro e instala la extensión.
Deja esta terminal abierta y no escribas nada en ella (las teclas son atajos de Docker). Usa otra para lo demás.

### 2. Generar los datos (en otra terminal)
Abre una terminal nueva dentro de la carpeta del proyecto. La del paso 1 se queda abierta.
Los pasos 2 al 5 van en esta terminal nueva.
```
py scripts/generar_datos.py 100000
```
Crea los CSV en `data/`.

### 3. Copiar los datos al contenedor
```
docker cp data bd2_g6_hashing:/app/data
```
El contenedor no ve los archivos de Windows.

### 4. Crear la tabla y cargar el CSV
```
docker exec -w /app bd2_g6_hashing psql -U postgres -d hashing_db -f sql/cargar_buses.sql
```
Al final debe salir `total_filas = 100000`.

### 5. Entrar a la base
```
docker exec -it bd2_g6_hashing psql -U postgres -d hashing_db
```
El prompt cambia a `hashing_db=#`. Los pasos 6 al 9 se escriben ahí, dentro de `psql`.

### 6. Activar la extensión
```sql
CREATE EXTENSION IF NOT EXISTS pg_hashing;
```

### 7. Meter las claves a la estructura
```sql
SELECT count(*) FILTER (WHERE pg_insertar(id_bus)) AS insertadas FROM buses;
```
Debe dar `100000`.

### 8. Buscar
```sql
SELECT pg_buscar(670488);   -- t
SELECT pg_buscar(5);        -- f
```
Los dos ids son de D2 con semilla 42.

### 9. Insertar una clave nueva
```sql
SELECT pg_insertar(1);   -- t (no estaba)
SELECT pg_buscar(1);     -- t
SELECT pg_insertar(1);   -- f (ya existe)
```

---

## Prueba por consola (sin PostgreSQL)

Prueba la estructura sola, con buckets de 4 claves, antes de pasar por el motor. Desde la carpeta del proyecto:
```
gcc -Wall src/*.c -o main_demo && ./main_demo
```
Hace 4 pruebas: crecimiento con 20 múltiplos de 4, clave repetida, claves perdidas y clave inexistente. Todas deben salir `[OK]`.

---

## Pruebas de correctitud

Se ejecutan dentro del contenedor, con el proyecto y los CSV ya copiados (pasos 1 al 3):
```
docker exec -it -w /app bd2_g6_hashing sh tests/correr_tests.sh
```
Cada salida se guarda en un `.txt` dentro de `tests/`. Prueban D1 y D2 con 100 000, 500 000 y 1 000 000 claves (claves perdidas, reinsertadas y falsos positivos), 18 casos límite y el tope de profundidad. `tests/revision_interna.c` inserta 1 000 000 de claves directamente en C y revisa el directorio. Los resultados guardados están en `tests/resultados/antes/` (código original) y `tests/resultados/despues/` (con las correcciones).

---

## Benchmark y comparación con B-tree

**Búsqueda (D2, 100 000 filas).** Los scripts están en `benchmark/` (`00_preparar_claves.sql`, `01_sin_indice.sql`, `02_btree.sql`, `03_hashing.sql`) y sus pasos en `benchmark/README.md`. Usan 20 000 claves (10 000 existentes y 10 000 ausentes), un calentamiento descartado y 5 repeticiones por método; se reporta la mediana.

**Comparación con B-tree (D2 de 100 000, 500 000 y 1 000 000).** Agrega la construcción con cinco repeticiones y el tamaño del índice. Se ejecuta con:
```
docker exec -it -w /app bd2_g6_hashing sh bench_5.2/correr_5.2.sh
```
Los detalles y resultados están en `bench_5.2/README.md` y `bench_5.2/INFORME_5.2.md`.

Los tiempos dependen de la máquina, así que al repetirlos los números pueden variar un poco; lo que debe mantenerse es el orden de magnitud entre métodos.

---

## Cómo viaja una consulta

**Insertar**

`SELECT pg_insertar(id)` -> PostgreSQL llama a `pg_insertar` (`pg_hashing.c`) -> obtiene el directorio (lo crea si es la primera vez) -> `insertar_llave` -> `buscar_llave` encuentra el bucket -> si hay espacio, guarda la clave -> si está lleno, `dividir_bucket` lo parte y se reintenta -> devuelve `true` o `false` -> PostgreSQL muestra `t` o `f`. Si la clave no estaba y no se pudo insertar (falta de memoria o límite de profundidad), `pg_insertar` lanza un ERROR.

**Buscar**

`SELECT pg_buscar(id)` -> PostgreSQL llama a `pg_buscar` (`pg_hashing.c`) -> obtiene el directorio -> `buscar_llave` revisa el bucket -> devuelve si la encontró -> PostgreSQL muestra `t` o `f`.

---

## Notas

- El directorio vive solo mientras dure la sesión de `psql`. Al entrar de nuevo, repetir el paso 7.
- La estructura no es persistente, no se comparte entre conexiones y solo responde si la clave existe (no devuelve la fila).
- Si se cambia el código C, reconstruir con `docker compose up --build`. Se pierden los datos copiados y la tabla, así que repetir los pasos 3 y 4.
- Para salir de `psql`: `\q`.

---

## Recursos externos y herramientas de IA

Como grupo usamos herramientas de IA como apoyo: Claude (Anthropic) y, en una parte menor, Gemini (Google).

- Se usaron para escribir y revisar partes del código (por ejemplo, el split, la extensión para PostgreSQL y los scripts de pruebas y de benchmark), para depurar errores, para la estructura del repositorio y del entorno Docker, y para la redacción de este README y del informe.
- El directorio y los buckets (`src/directorio.c` y `src/bucket.c`) se desarrollaron sin IA.
- En todos los casos revisamos lo que generó la herramienta contra el código del repositorio y ejecutamos las pruebas y las mediciones en el Docker del grupo (PostgreSQL 18.6).