# Benchmark: sin índice vs B-tree vs Extendible Hashing

Mide cuánto tarda buscar un bus por `id_bus` en la tabla `buses` de tres formas.
Los tres scripts usan **las mismas 20 000 claves** (tabla `claves_benchmark`:
**10 000 existentes + 10 000 ausentes**) y hacen **5 repeticiones**. Se reporta mínimo,
mediana y máximo; antes de medir hay un calentamiento corto que se descarta.

| Script | Qué hace |
|---|---|
| `00_preparar_claves.sql` | Crea `claves_benchmark` (20 000 claves, semilla fija). Se corre una vez. |
| `01_sin_indice.sql` | Seq Scan: PostgreSQL revisa la tabla fila por fila. Una consulta SQL por clave. |
| `02_btree.sql` | Crea un índice B-tree y busca con la misma consulta. |
| `03_hashing.sql` | Inserta todas las claves con `pg_insertar` y busca con `pg_buscar`, **todo en la misma sesión**. |

## Cómo correrlo (PowerShell, desde la carpeta del proyecto)

Requisito: contenedor arriba (PostgreSQL 18.6) y tabla `buses` cargada con D2 de 100 000.

```powershell
docker cp benchmark/. bd2_g6_hashing:/app/benchmark

docker exec -w /app bd2_g6_hashing psql -U postgres -d hashing_db -v n_consultas=20000 -f benchmark/00_preparar_claves.sql

docker exec -w /app bd2_g6_hashing psql -U postgres -d hashing_db -f benchmark/01_sin_indice.sql | Out-File -Encoding utf8 benchmark/resultados/01_sin_indice.txt
docker exec -w /app bd2_g6_hashing psql -U postgres -d hashing_db -f benchmark/02_btree.sql      | Out-File -Encoding utf8 benchmark/resultados/02_btree.txt
docker exec -w /app bd2_g6_hashing psql -U postgres -d hashing_db -f benchmark/03_hashing.sql    | Out-File -Encoding utf8 benchmark/resultados/03_hashing.txt
```

- `01_sin_indice.sql` es lento (20 000 recorridos de la tabla por repetición): puede tardar **10 a 15 minutos**.
- Usa `-Encoding utf8`: en PowerShell, `>` guarda en UTF-16.
- Los scripts se niegan a correr si el servidor no es PostgreSQL 18 (así no se mezclan resultados de otra versión).
  Cada `.txt` empieza con `version()`, que debe decir **PostgreSQL 18.6**.
- Parámetro opcional: `-v reps=5` en los scripts 01 al 03.

## Sobre la justicia de la comparación

`sin_indice` y `btree` ejecutan **una consulta SQL por clave** (el planificador y el ejecutor
de PostgreSQL trabajan en cada búsqueda). `pg_buscar`, en cambio, es una **función en C**
llamada directamente. Esa diferencia de costo fijo no tiene que ver con el algoritmo de
búsqueda y sesga a favor del hashing. Por eso `03_hashing.sql` mide tres cosas:

| Fila | Qué mide |
|---|---|
| `hashing_directo` | `hit := pg_buscar(k)`: llamada directa, sin consulta SQL. Es el tiempo "puro" de la estructura. |
| `hashing_via_sql` | `SELECT pg_buscar(k) INTO hit`: una consulta SQL por clave, igual que `01` y `02`. **Esta es la comparación justa.** |
| `baseline_sql` | Una consulta SQL que no busca nada. Es el costo fijo de ejecutar una consulta. |

Otras limitaciones que conviene decir en la defensa:

- `pg_buscar` solo responde si la clave existe; **no devuelve la fila**. El B-tree hace una búsqueda de existencia equivalente (`SELECT EXISTS ...`), pero un índice real también tendría que llevar al registro.
- La estructura vive en la memoria de la sesión: no persiste, no se comparte entre conexiones y no pasa por el WAL ni el buffer manager.
- Con el B-tree, PostgreSQL puede usar *Index Only Scan* (el plan queda en el `.txt`).

## Declaración de uso de IA

Los scripts de esta carpeta (`00` al `03`) y este README fueron diseñados y redactados con
ayuda de **Claude (Anthropic)**. [TU NOMBRE] los revisó, los ejecutó en el entorno Docker del
grupo (PostgreSQL 18.6) y generó los archivos de `resultados/`. Las decisiones de qué comparar
y cómo medirlo se discutieron con el grupo.
