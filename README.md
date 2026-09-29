# Grupo 6 - Extendible Hashing en PostgreSQL

Estructura de Extendible Hashing hecha en C y conectada a PostgreSQL como extensión.
Desde SQL se usa con `pg_insertar(id)` y `pg_buscar(id)`.

---

## Componentes

**Núcleo en C** (`src/` e `include/`)
- bucket: caja con un arreglo de claves.
- directorio: tabla de punteros a buckets.
- búsqueda (`buscar_llave`): devuelve el bucket donde está la clave, o donde debería ir.
- inserción (`insertar_llave`): mete la clave. Devuelve `true` si la insertó y `false` si ya existía.
- split (`dividir_bucket`): parte un bucket lleno en dos. Si hace falta, duplica el directorio.
- `main.c`: prueba por consola. No entra a la extensión.

**Puente con PostgreSQL**
- `pg_hashing.c`: define `pg_insertar` y `pg_buscar`. Crea el directorio la primera vez que se llama a una de las dos.
- `pg_hashing--1.0.sql`: declara esas dos funciones en SQL.
- `pg_hashing.control`: datos de la extensión (nombre, versión).
- `Makefile`: compila el C.

**Entorno**
- `Dockerfile`: arma PostgreSQL con la extensión compilada e instalada.
- `docker-compose.yml`: levanta el contenedor `bd2_g6_hashing` con la base `hashing_db`.

**Datos**
- `scripts/generar_datos.py`: genera los CSV en `data/`. D1 es secuencial y D2 es aleatorio (semilla 42).
- `sql/cargar_buses.sql`: crea la tabla `buses` (sin índice) y carga un CSV.
- `data/`: los CSV. No se suben al repo, se generan.

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

## Cómo viaja una consulta

**Insertar**

`SELECT pg_insertar(id)` -> PostgreSQL llama a `pg_insertar` (`pg_hashing.c`) -> obtiene el directorio (lo crea si es la primera vez) -> `insertar_llave` -> `buscar_llave` encuentra el bucket -> si hay espacio, guarda la clave -> si está lleno, `dividir_bucket` lo parte y se reintenta -> devuelve `true` o `false` -> PostgreSQL muestra `t` o `f`.

**Buscar**

`SELECT pg_buscar(id)` -> PostgreSQL llama a `pg_buscar` (`pg_hashing.c`) -> obtiene el directorio -> `buscar_llave` revisa el bucket -> devuelve si la encontró -> PostgreSQL muestra `t` o `f`.

---

## Notas

- El directorio vive solo mientras dure la sesión de `psql`. Al entrar de nuevo, repetir el paso 7.
- Si se cambia el código C, reconstruir con `docker compose up --build`. Se pierden los datos copiados y la tabla, así que repetir los pasos 3 y 4.
- Para salir de `psql`: `\q`.

---

## Recursos externos y herramientas de IA

- El núcleo en C (bucket, directorio, búsqueda, inserción y split) lo desarrolló el grupo.
- Se usó Claude (IA) como apoyo en:
  - La estructura del repositorio y del entorno (carpetas, Docker y archivos recomendados) y los pasos para levantarlo todo.
  - La estructura y la redacción de este README.
  - El puente `pg_hashing.c` y el cambio de `insertar_llave` (devuelve `bool`, sin `printf`). El grupo lo revisó y lo probó con los datos de prueba.