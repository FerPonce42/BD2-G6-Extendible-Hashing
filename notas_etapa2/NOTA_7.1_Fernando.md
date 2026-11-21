# 7.1 Experimentos sin índice (Fernando Ponce)

Fecha de las corridas: 22/10/2026, de noche en hora de Perú (el contenedor registra las horas en UTC, por eso en `duracion.txt` y `00_entorno.txt` figura 23/10). Rama `fernando-7.1`, ya mergeada a `main` (commit 6a6d568).

## Qué hice

Medí cuánto tarda buscar un bus por `id_bus` sin ningún índice, con D2 (claves enteras aleatorias, semilla 42) en los tres tamaños: 100 000, 500 000 y 1 000 000 filas.

- Script nuevo: `bench_7.1/correr_7.1.sh`. Para cada tamaño recarga la tabla `buses`, prepara las 20 000 claves con `benchmark/00_preparar_claves.sql` (10 000 existentes y 10 000 ausentes) y corre `benchmark/01_sin_indice.sql`. No modifiqué nada de `benchmark/`.
- Resultados en `bench_7.1/resultados/`: un `.txt` por tamaño, la duración de cada corrida y `00_entorno.txt` con los datos de mi PC.
- Condiciones: PostgreSQL 18.6 en el contenedor `bd2_g6_hashing`, una consulta SQL por clave, un calentamiento corto que se descarta y 5 repeticiones por tamaño. Se reporta la mediana. Corrí en mi PC (Intel i5-12450H, Docker sobre WSL2 con unos 7,7 GB de memoria), con la corriente conectada y sin otros programas pesados.
- Paralelismo: el script de sin índice pone `max_parallel_workers_per_gather = 0` solo durante su sesión, para que el recorrido sea fila por fila. El `00_entorno.txt` muestra el valor por defecto del servidor (2), por eso ahí aparece distinto.

## Por qué

La rúbrica pide el acceso sin índice como escenario obligatorio, en al menos tres tamaños y con 5 repeticiones. Hasta la Etapa I solo teníamos medido el tamaño de 100 000. Este es el punto de referencia contra el que se compara el B-tree y nuestra estructura.

## Resultados

El plan de ejecución de los tres tamaños dice `Seq Scan on buses`, o sea que la base recorrió la tabla completa. En las 15 repeticiones los aciertos coincidieron con los esperados (`resultados_correctos = t`).

| D2 | Mediana (ms, 20 000 consultas) | Mín (ms) | Máx (ms) | ms por consulta | Duración de la corrida |
|---|---|---|---|---|---|
| 100 000 | 56 870,140 | 56 614,960 | 58 965,679 | 2,84351 | 4 min 47 s |
| 500 000 | 291 287,666 | 289 982,896 | 294 282,436 | 14,56438 | 24 min 21 s |
| 1 000 000 | 582 158,216 | 576 945,966 | 589 448,173 | 29,10791 | 48 min 47 s |

- De 100 000 a 500 000 filas el tiempo se multiplicó por 5,1. De 500 000 a 1 000 000 se multiplicó por 2,0. De 100 000 a 1 000 000, por 10,2.
- Interpretación: sin índice cada búsqueda recorre la tabla, así que el costo crece en línea recta con el número de filas. Con 1 000 000 de filas cada búsqueda cuesta unos 29 ms, frente a los microsegundos que midió la Etapa I para B-tree y hashing.
- Las repeticiones salieron muy parejas en los tres tamaños (diferencia entre mínimo y máximo de entre 2 y 4%), así que la mediana es estable.

## Inserciones sin índice (W3)

Rama `fernando-7.1-inserciones`, ya mergeada a `main` (commit 097e061). Corrida el 24/10/2026 en mi PC.

Mismo método que `bench_7.2` (Nicol): claves nuevas `max + 1, max + 2...`, `BEGIN`, `INSERT`, `ROLLBACK`, 5 repeticiones y mediana. La tabla `buses` se recarga desde cero sin ningún índice, y el script comprueba que tenga las filas esperadas y 0 índices antes de medir. El máximo se calcula antes de medir, porque sin índice costaría recorrer la tabla y se sumaría al tiempo de la inserción.

| D2 | Inserciones (10%) | Mediana (ms) | Las 5 repeticiones (ms) |
|---|---|---|---|
| 100 000 | 10 000 | 4,632 | 4,509 / 4,632 / 4,485 / 4,669 / 8,245 |
| 500 000 | 50 000 | 21,923 | 20,340 / 21,250 / 21,923 / 22,436 / 22,219 |
| 1 000 000 | 100 000 | 48,140 | 46,604 / 48,140 / 50,269 / 57,423 / 45,436 |

Archivos: `bench_7.1/correr_7.1_inserciones.sh`, `bench_7.1/inserciones_sin_indice.sql` y `bench_7.1/resultados_inserciones/`.

**Comparación en mi misma PC.** Corrí el script de Nicol para verificarlo y saqué estas medianas (solo de verificación, no están en el repo; las cifras oficiales de Nicol están en `bench_7.2/resultados_crudos.txt`):

| D2 | Sin índice (ms) | B-tree (ms) | Hash (ms) |
|---|---|---|---|
| 100 000 | 4,63 | 11,72 | 3,29 |
| 500 000 | 21,92 | 68,82 | 15,08 |
| 1 000 000 | 48,14 | 125,97 | 40,74 |

- Mantener el índice B-tree cuesta unas 2,5 a 3 veces más que insertar sin índice.
- El hash sale por debajo de "sin índice" porque inserta solo en la memoria de la sesión y no escribe filas en la tabla. Por eso esa comparación favorece al hash y debe leerse con cautela.
- Las claves nuevas son secuenciales, no aleatorias como D2, lo que favorece al B-tree.

## Problemas y cuidados

- En Git Bash, `docker exec -w /app` falla con `Cwd must be an absolute path`. Se arregla poniendo `MSYS_NO_PATHCONV=1` delante del comando.
- Mi PC no es la misma que usó Iair en la comparación con B-tree de la Etapa I (ahí el entorno era un i5-13420H; el mío es un i5-12450H). Para 100 000 el repo tenía 50 114 ms (otra PC) y yo medí 56 870 ms, un 13% más. Por eso la comparación formal entre sin índice, B-tree y hash conviene hacerla en el 7.3 aclarando de qué máquina viene cada cifra.
- La corrida de 1 000 000 tarda casi una hora. Hay que dejar la PC sin suspenderse.

## Cómo reproducirlo

1. Levantar el contenedor con `docker compose up --build`.
2. Generar los datos con `scripts/generar_datos.py` y copiarlos al contenedor.
3. Copiar `benchmark/` y `bench_7.1/` al contenedor y ejecutar `sh bench_7.1/correr_7.1.sh <dataset>` dentro de `/app`.

## Uso de IA

Los scripts `correr_7.1.sh` y `correr_7.1_inserciones.sh` (con su archivo SQL) los armé con ayuda de Claude (Anthropic), tomando como base `correr_5.2.sh` y `bench_7.2`. Yo generé los datos, ejecuté las corridas en mi PC y revisé los resultados.
