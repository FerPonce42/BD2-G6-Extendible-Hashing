# bench_5.2/ — Comparación preliminar con B-tree (actividad 5.2)

Usa los scripts de `benchmark/` (actividad 5.1, Fabricio) **sin modificarlos** y les agrega lo que falta para comparar con B-tree según la rúbrica:

| Qué | De dónde sale |
|---|---|
| Claves de búsqueda (10 000 existen + 10 000 ausentes) | `benchmark/00_preparar_claves.sql` |
| Búsquedas con B-tree, 5 repeticiones | `benchmark/02_btree.sql` |
| Búsquedas con nuestra estructura, 5 repeticiones (`hashing_directo`, `hashing_via_sql`, `baseline_sql`) | `benchmark/03_hashing.sql` |
| **Construcción ×5** de B-tree y de hash, y **tamaño** del índice B-tree | `bench_5.2/construccion_tamano.sql` (nuevo) |
| **Tres tamaños** de D2 (100k, 500k y 1M) | `bench_5.2/correr_5.2.sh` (nuevo) |

`01_sin_indice.sql` no se corre aquí, porque tarda mucho y es parte del 5.1. Para el 5.2 se usa el resultado del 5.1 (D2 100k).

## Comparación justa

Se compara `btree` con `hashing_via_sql`: los dos hacen **una consulta SQL por clave**. `hashing_directo` llama a `pg_buscar` sin pasar por el ejecutor de consultas, así que solo sirve para ver el costo "puro" de la estructura. `baseline_sql` es el costo fijo de una consulta que no busca nada.

En la construcción, `CREATE INDEX` se corre con `max_parallel_maintenance_workers = 0`, o sea, con un solo proceso, igual que `pg_insertar`. Cada construcción del hash se hace en una sesión nueva, porque la estructura vive por sesión.

## Cómo correrlo

Requisitos: el contenedor levantado (PostgreSQL 18.6), los datos de los 3 tamaños generados y las carpetas `benchmark/` y `bench_5.2/` en el proyecto.

```
docker cp data/. bd2_g6_hashing:/app/data
docker cp benchmark/. bd2_g6_hashing:/app/benchmark
docker cp bench_5.2/. bd2_g6_hashing:/app/bench_5.2
docker exec -w /app bd2_g6_hashing sh bench_5.2/correr_5.2.sh
docker cp bd2_g6_hashing:/app/bench_5.2/resultados/. bench_5.2/resultados/
```

## Salidas (`resultados/`)

```
00_entorno.txt
D2_aleatorio_<N>/
  00_claves.txt  02_btree.txt  03_hashing.txt  04_construccion_tamano.txt
```

## Limitaciones

- El B-tree se guarda en disco, pasa por el buffer manager y el WAL, y lo comparten todas las sesiones. Nuestra estructura vive solo en la memoria de una sesión. La construcción no es equivalente en durabilidad.
- El tamaño de nuestra estructura no se mide desde SQL, porque la extensión no lo expone.
- Es una comparación **preliminar** para el parcial. El benchmark completo (D1, W3 inserciones y sin índice en los 3 tamaños) corresponde a la etapa II.
