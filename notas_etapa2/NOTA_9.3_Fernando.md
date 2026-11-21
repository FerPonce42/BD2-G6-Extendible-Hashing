# Entorno distribuido: tres nodos PostgreSQL

Actividad 9.3 (documentación del entorno). Responsable: Fernando Ponce.

Este documento explica cómo levantar, cargar, verificar y probar la parte distribuida del proyecto desde cero, usando solo lo que hay en el repositorio. Los pasos son los que se ejecutaron y comprobaron en una PC distinta a la de quien escribió cada script.

## 1. Qué es este entorno

Tres nodos PostgreSQL 18.6 en contenedores Docker (A, B y C), cada uno con la base `distribuido` y la extensión `pg_hashing` de la etapa I. Los datos están fragmentados por zona y replicados con replicación lógica asíncrona, según las actividades 8.1, 8.2 y 8.3.

| Nodo | Contenedor | Puerto en la PC | Principal de | Réplica de |
|---|---|---|---|---|
| A | `nodo_a` | 5433 | Norte | Centro y `conductores` |
| B | `nodo_b` | 5434 | Centro y `conductores` | Norte y Sur |
| C | `nodo_c` | 5435 | Sur | `conductores` |

Es independiente del entorno de la etapa I (`docker-compose.yml` de la raíz, contenedor `bd2_g6_hashing`, base `hashing_db`), que no se toca.

| Carpeta | Qué contiene | Actividad |
|---|---|---|
| `nodos/` | `docker-compose.yml` y los scripts SQL de cada nodo | 9.1 |
| `generador/` | Generador de datos y script de carga | apoyo de 9.1 y 9.2 |
| `bench_9.2/` | Consultas locales y multinodo con latencia simulada | 9.2 |
| `fragmentacion_asignacion/` | Diseño de fragmentación y asignación | 8.1 y 8.2 |
| `replicacion/` | Plan de replicación | 8.3 |

## 2. Requisitos

* Docker Desktop abierto y funcionando.
* Git y Python 3 (en Windows, el comando es `py`).
* Una terminal Git Bash en Windows para los scripts `.sh`.
* Los puertos 5433, 5434 y 5435 libres.
* Todos los comandos se ejecutan **desde la raíz del repositorio**.

En Git Bash hay que ejecutar esto una vez por terminal, antes de los `docker exec`. Si no, Git Bash convierte rutas como `/nodos/...` en rutas de Windows y Docker las rechaza:

```
export MSYS_NO_PATHCONV=1
```

## 3. Levantar los tres nodos

```
docker compose -f nodos/docker-compose.yml up -d --build
docker ps
```

La primera vez tarda un par de minutos porque construye la imagen y compila la extensión (en la prueba, unos 90 segundos). Después tarda segundos. Deben aparecer `nodo_a`, `nodo_b` y `nodo_c` con estado `Up`. Conviene esperar unos 30 segundos antes del paso siguiente.

Al arrancar por primera vez, cada nodo crea solo sus tablas y su publicación (`nodos/sql/01_comun.sql` a `05_publicacion_<nodo>.sql`).

## 4. Crear las suscripciones

Las suscripciones conectan los nodos para que las réplicas se llenen solas. Se crean una vez, cuando los tres nodos ya están arriba:

```
docker exec nodo_a psql -U postgres -d distribuido -v nodo=A -f /nodos/suscripciones.sql
docker exec nodo_b psql -U postgres -d distribuido -v nodo=B -f /nodos/suscripciones.sql
docker exec nodo_c psql -U postgres -d distribuido -v nodo=C -f /nodos/suscripciones.sql
```

Resultado esperado: cinco `CREATE SUBSCRIPTION` en total (dos en A, dos en B y una en C) y una tabla con las suscripciones en `activa = t`.

## 5. Cargar los datos

Hay dos opciones. **No se usan juntas**: si los nodos ya tienen datos, hay que apagarlos y levantarlos limpios (sección 8).

### Opción A: datos de prueba (1 % del tamaño de diseño)

50 conductores, 1 000 buses y 12 000 viajes. B se carga primero, porque tiene los conductores que usan los viajes de A y C:

```
docker exec nodo_b psql -U postgres -d distribuido -v nodo=B -f /nodos/datos_prueba.sql
# esperar unos 10 segundos
docker exec nodo_a psql -U postgres -d distribuido -v nodo=A -f /nodos/datos_prueba.sql
docker exec nodo_c psql -U postgres -d distribuido -v nodo=C -f /nodos/datos_prueba.sql
```

### Opción B: datos de diseño (1 200 000 viajes)

El generador usa la semilla 42, así que siempre produce los mismos datos. Los archivos quedan en `data/distribuido/` y no se suben al repositorio.

```
py generador/generar_distribuido.py
bash generador/cargar_distribuido.sh
```

* El generador tarda unos segundos y produce unos 58 MB.
* La carga tarda unos minutos. Carga B, espera a que los conductores lleguen a A y a C, carga A y C, y compara las filas de cada tabla con los CSV.
* Mientras corre, no conviene tocar la ventana.

Resultado esperado al final: `OK: todos los nodos tienen las mismas filas que los CSV.`, con esta tabla (el `-` indica una tabla que ese nodo no tiene):

| tabla | esperado | nodo_a | nodo_b | nodo_c |
|---|---|---|---|---|
| conductores | 5000 | 5000 | 5000 | 5000 |
| buses_norte | 30000 | 30000 | 30000 | - |
| viajes_norte | 360000 | 360000 | 360000 | - |
| buses_centro | 40000 | 40000 | 40000 | - |
| viajes_centro | 480000 | 480000 | 480000 | - |
| buses_sur | 30000 | - | 30000 | 30000 |
| viajes_sur | 360000 | - | 360000 | 360000 |

## 6. Verificar

```
docker exec nodo_a psql -U postgres -d distribuido -v nodo=A -f /nodos/verificar.sql
docker exec nodo_b psql -U postgres -d distribuido -v nodo=B -f /nodos/verificar.sql
docker exec nodo_c psql -U postgres -d distribuido -v nodo=C -f /nodos/verificar.sql
```

Debe cumplirse, en cada nodo:

* Las filas por tabla son las esperadas (principal y réplica iguales).
* `viajes_fuera_de_lugar` es 0: ningún viaje tiene una ruta distinta a la de su bus.
* Las suscripciones tienen `recibiendo = t` y los suscriptores están en `streaming`.
* La extensión `pg_hashing` aparece instalada (versión 1.0).

Con la carga grande, la tabla de suscripciones puede mostrar dos filas por suscripción, una de ellas sin `ultimo_dato`, y el retraso puede aparecer vacío. Es lo que se observó en la prueba y no indica un error mientras `recibiendo` sea `t`.

## 7. Consultas locales y multinodo (actividad 9.2)

Con los nodos levantados y con datos:

```
REP=10 bash bench_9.2/consultas.sh
py bench_9.2/resumen.py
```

* Tarda de 1 a 2 minutos, porque el script espera de verdad las latencias simuladas y arranca muchas veces `docker exec`.
* **La red no se configura en los contenedores ni se mide.** El script usa las latencias de la rúbrica (A-B 20 ms, A-C 40 ms, B-C 25 ms) como constantes y las suma al tiempo que reporta el servidor. Lo único medido de verdad es la ejecución en el nodo.
* **El script sobrescribe `bench_9.2/resultados_9.2.csv`**, que está en el repositorio. Para repetir la prueba sin dejar ese archivo modificado, se guarda la copia fuera del repositorio y se restaura el original:

```
cp bench_9.2/resultados_9.2.csv ~/resultados_9.2_copia.csv && git checkout -- bench_9.2/resultados_9.2.csv
```

* La prueba de escritura E1 inserta viajes con fecha desde el 2026-11-01. Para dejar los datos como estaban:

```
docker exec nodo_a psql -U postgres -d distribuido -c "DELETE FROM viajes_norte WHERE salida >= '2026-11-01';"
```

## 8. Apagar y empezar de cero

```
docker compose -f nodos/docker-compose.yml down -v
```

Borra los tres nodos y todos sus datos. No toca el contenedor `bd2_g6_hashing` de la etapa I. Para volver a cargar datos hay que empezar siempre desde este paso, porque las réplicas solo deben cambiar por la suscripción y borrar a mano no es válido.

## 9. Problemas conocidos

* **Git Bash y las rutas.** Sin `export MSYS_NO_PATHCONV=1`, los `docker exec ... -f /nodos/...` fallan.
* **El orden de carga importa.** B se carga primero. Si A o C se cargan antes de que lleguen los conductores, la clave foránea rechaza los viajes. Los scripts avisan o esperan.
* **No cargar dos veces.** Las tablas de datos deben estar vacías al cargar.
* **No usar `hashing_db`.** `fragmentacion_asignacion/esquema_global.sql` empieza con `DROP TABLE` y borraría tablas de la etapa I. El entorno distribuido usa la base `distribuido`.
* **Git Bash puede congelarse en cargas pesadas.** El autor del generador lo vio una vez; en la prueba de reproducción no ocurrió. Si pasa, se cierra la terminal, se apaga todo con `down -v` y se repite: cada nodo se carga en una sola transacción, así que no quedan datos a medias.
* **Escribir a mano en una réplica la desordena** respecto del principal.
* **La estructura de Extendible Hashing no se replica.** Vive en la memoria de cada sesión; en cada nodo hay que volver a armarla con `pg_insertar` (ver `replicacion/INFORME_8.3.md`).
* **La contraseña (`password123`) es solo para laboratorio.**

## 10. Prueba de reproducción

Los pasos 3 a 6 con la opción B se ejecutaron desde cero en otra PC distinta a la de quienes escribieron los scripts:

* PC: Intel Core i5-12450H, 12 núcleos, 7,7 GB de memoria visibles para Docker, Windows con Docker sobre WSL2.
* PostgreSQL 18.6 con `pg_hashing` 1.0 en los tres nodos.
* La carga terminó con `OK`: 1 200 000 viajes como principales (360 000 en A, 480 000 en B y 360 000 en C), con cada réplica igual a su principal y 0 viajes fuera de lugar.
* La carga se hizo en Git Bash y no se congeló.

## 11. Lo que falta

* Repetir las consultas de la 9.2 con los datos de diseño: su informe usó el 1 %.
* Los experimentos de la semana 10: comparación de dos estrategias de distribución, prueba de caída de un nodo y de cambio de carga.
* La promoción de una réplica cuando cae un nodo es manual y no está automatizada (ver `replicacion/INFORME_8.3.md`).

## 12. Uso de IA

Se usó Claude (Anthropic) como apoyo para ordenar y redactar este documento. Los pasos y las comprobaciones salen de la ejecución real descrita en la sección 10, hecha por el responsable de esta actividad.
