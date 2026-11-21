8.3 Definición de replicación

**Responsable:** Fabricio Stelman
**Carpeta:** `replicacion/`
**Base:** informe 8.1 y 8.2 de Iair Suico (`fragmentacion_asignacion/INFORME_8.1y8.2.md`)
**Rúbrica:** secciones 6.3 y 6.3.1 (tres nodos A, B y C; latencias A-B = 20 ms, A-C = 40 ms, B-C = 25 ms; relación principal con al menos 1 000 000 de registros; carga de 70 % lecturas y 30 % escrituras)

1. Qué hice

- Definí **qué se replica, dónde queda cada réplica y cómo se mantiene al día** (secciones 3 y 4), partiendo de la asignación de 8.2 y de lo que Iair sugirió en su sección 6.
- Comparé dos formas de ubicar las réplicas y dos modos de replicar (asíncrono y síncrono) con el mismo cálculo de costo de red de 8.1/8.2 (sección 4).
- Revisé qué le pasa al **Extendible Hashing** del proyecto cuando hay réplicas, porque su estructura vive en memoria y eso cambia lo que se puede replicar (sección 5).
- Dejé el plan como **tablas SQL** (`plan_replicacion.sql`), con las comprobaciones y el costo esperado calculados con consultas, y los comandos de PostgreSQL para armar la replicación en los nodos (`replicacion_nodos.sql`).

El levantamiento de los nodos (9.1) y las pruebas de indisponibilidad (10.2) no son parte de esta entrega. En la sección 8 dejo lo que esas actividades necesitan de este diseño.

2. Punto de partida (8.1 y 8.2)

Recojo del informe de Iair solo lo que se usa aquí.

| Nodo | Fragmentos principales | Datos |
|---|---|---|
| **A** | `rutas_norte`, `buses_norte`, `viajes_norte` | 30 % |
| **B** (nodo central) | `rutas_centro`, `buses_centro`, `viajes_centro` y la copia principal de `conductores` | 40 % |
| **C** | `rutas_sur`, `buses_sur`, `viajes_sur` | 30 % |

- Relación principal: `viajes`, 1 200 000 filas. Reparto: Norte 360 000, Centro 480 000, Sur 360 000. Los buses son 100 000 (30 000 / 40 000 / 30 000).
- Costo de red esperado **sin réplicas**: 4,48 ms por operación (sección 4.4 de 8.1/8.2), con la mezcla de 4.3: 35 % L1, 20 % L2, 10 % L3, 5 % L4, 25 % E1 y 5 % E2.
- Problemas que 8.1/8.2 dejó para esta actividad (secciones 4.5 y 7):
  - Si cae **B** se pierde Centro, la copia principal de `conductores` y el mejor coordinador.
  - Si cae **A o C** se pierde su zona y los reportes globales no se pueden completar.
  - Si Sur pasa de 30 % a 60 % del tráfico, **C se sobrecarga**.
  - La clave foránea `viajes.id_conductor` solo se puede declarar en un nodo que tenga una copia de `conductores`.

3. Qué se replica

| Objeto | Filas | ¿Se replica? | Por qué |
|---|---|---|---|
| `viajes_norte`, `viajes_centro`, `viajes_sur` | 360 000 / 480 000 / 360 000 | Sí, **una réplica cada uno** | Son los datos grandes; sin réplica, una zona entera depende de un solo nodo |
| `buses_norte`, `buses_centro`, `buses_sur` | 30 000 / 40 000 / 30 000 | Sí, **en el mismo nodo que la réplica de sus viajes** | El join viaje–bus tiene que seguir siendo local también en la réplica |
| `conductores` | 5 000 | Sí, **a A y C** (copia principal en B) | Es chica, casi solo de lectura y la usan todas las zonas |
| `rutas` | 10 | Sí, **completa en los tres nodos** | Casi no cambia; se carga igual en cada nodo, sin replicación lógica |

No se hace más de una réplica por fragmento de `viajes`: con tres nodos, una réplica por fragmento ya permite sobrevivir a la caída de cualquier nodo, y cada réplica extra aumenta el costo de escritura y el espacio.

4. Dónde van las réplicas y cómo se mantienen

4.1 Ubicación de las réplicas

Es el plan que sugería Iair, y lo dejo como tabla en `plan_replicacion.sql` (tabla `replicas`):

| Objeto | Principal | Réplica | Distancia principal–réplica |
|---|---|---|---|
| `viajes_norte`, `buses_norte` | A | **B** | 20 ms |
| `viajes_centro`, `buses_centro` | B | **A** | 20 ms |
| `viajes_sur`, `buses_sur` | C | **B** | 25 ms |
| `conductores` | B | **A y C** | 20 y 25 ms |
| `rutas` | todos | todos | — |

Qué guarda cada nodo, con la vista `v_almacenamiento`:

| Nodo | Viajes que guarda | Proporción |
|---|---|---|
| A | Norte (principal) + Centro (réplica) | 70 % |
| B | Centro (principal) + Norte y Sur (réplicas) | 100 % |
| C | Sur (principal) | 30 % |

**Por qué estas ubicaciones:** cada réplica va al nodo más cercano al principal posible y B, el nodo central, queda como respaldo de los dos extremos. La réplica de Centro va a A y no a C porque A está a 20 ms de B y C a 25 ms. Con esto, **la caída de cualquier nodo deja una copia viva de todo** (vista `v_tolerancia`, sin filas con `copias_vivas = 0`).

**Alternativa descartada: réplicas en círculo** (Norte → B, Centro → C, Sur → A). Reparte mejor el espacio (A 60 %, B 70 %, C 70 %) y también tolera la caída de un nodo, pero la réplica de Sur queda en A, a 40 ms, y las lecturas de otra zona y los reportes salen más caros (tabla de 4.3).

4.2 Modo de replicación: copia principal y asíncrona

- **Copia principal.** Todas las escrituras de un fragmento van a su nodo principal (el de 8.2). Las réplicas solo reciben. No hay escrituras en dos nodos a la vez, así que **no hay conflictos que resolver**.
- **Asíncrona.** El nodo principal confirma la escritura sin esperar a la réplica. Se implementa con **replicación lógica de PostgreSQL** (una publicación por nodo principal y una suscripción por réplica; los comandos están en `replicacion_nodos.sql`). Se usa la lógica y no la física porque la física copia todo el clúster y aquí cada nodo guarda solo algunos fragmentos.
- **Dónde se lee.** Lo de la propia zona (L1, L2, E1, E2) se lee y escribe siempre en el principal, así que no se ven datos atrasados. Las lecturas de otra zona (L3) y los reportes globales (L4) pueden usar la copia más cercana, aunque puede ir unos instantes atrasada.

4.3 Costo de red esperado

Mismo modelo que la sección 4.4 de 8.1/8.2: solo latencia de red, la mezcla de operaciones de 4.3 y cada cliente conectado al nodo de su zona. Se calcula con la vista `v_costo_esperado`.

| Opción | L3 (ms) | L4 (ms) | Espera por escritura (ms) | **Por operación (ms)** |
|---|---|---|---|---|
| Sin réplicas (8.1/8.2) | 27,75 | 34,00 | 0 | 4,48 |
| **Plan elegido, asíncrona** | 10,50 | 13,50 | 0 (no se espera) | **1,73** |
| Plan elegido, síncrona | 10,50 | 13,50 | 21,50 | 8,18 |
| Réplicas en círculo, asíncrona | 10,75 | 21,50 | 0 | 2,15 |
| Réplicas en círculo, síncrona | 10,75 | 21,50 | 28,00 | 10,55 |

Cómo se calculó:
- **L3:** de la copia más cercana de la otra zona, promedio de las dos zonas ajenas.
- **L4:** se pregunta en paralelo; manda la copia más lejana de las tres zonas.
- **Escritura síncrona:** se espera a la réplica más lejana de la zona. Con A, B y C pesa 20, 20 y 25 ms por escritura; ponderado por tráfico da 21,5 ms. Las escrituras son el 30 % de las operaciones (E2 se toma como actualización de un bus).
- **Por operación:** 0,10 · L3 + 0,05 · L4 + 0,30 · escritura.

**Decisión: réplicas de la sección 4.1, asíncronas.**
- Con réplicas asíncronas, el costo esperado **baja** de 4,48 a 1,73 ms, porque las lecturas de otra zona y los reportes encuentran una copia cercana.
- Con réplicas síncronas **sube** a 8,18 ms: con un 30 % de escrituras, esperar a la réplica pesa más que lo que se gana leyendo.
- Lo que se paga con la asíncrona: una lectura en réplica puede ir atrasada, y si cae un nodo se pueden perder las últimas escrituras que no llegaron (sección 6).

Estos números son una estimación: solo cuentan latencia de red, con la mezcla supuesta de 8.1/8.2. Los valores medidos tienen que salir de 9.2 y 10.1.

5. Qué necesita el Extendible Hashing

Esta es la parte propia del proyecto. Lo que sigue sale de leer `pg_hashing.c` y de los resultados de las etapas anteriores.

1. **La estructura no se replica.** El directorio es una variable `static` del proceso (`dir_global` en `pg_hashing.c`): vive en memoria y desaparece al cerrar la sesión. No se escribe en las páginas de PostgreSQL ni en el WAL, así que ni la replicación física ni la lógica pueden copiarla. **Lo que se replica es la tabla**, y la estructura se arma otra vez en cada nodo.

2. **Cada sesión tiene su propio directorio.** Se crea en la primera llamada a `pg_insertar` o `pg_buscar`. Dos conexiones al mismo nodo no comparten nada: `pg_buscar` solo encuentra lo que esa misma sesión insertó.

3. **Las réplicas no mantienen el hash.** Las filas que llegan por replicación las aplica un proceso de PostgreSQL que no llama a `pg_insertar`. Aunque se pusiera un disparador (*trigger*) en la réplica, trabajaría con la memoria de ese proceso, no con la de las sesiones de los usuarios. Por eso:
   - en los **nodos principales** el hash se usa como en 8.1/8.2 (sección 5): búsqueda por igualdad, L1 y E1, sobre el fragmento propio;
   - en las **réplicas** las lecturas (L3, L4) usan el **B-tree de la clave primaria**, que PostgreSQL arma solo en cada nodo al copiar la tabla. El rango de fechas (L2) sigue con el B-tree sobre `(id_ruta, salida)`.

4. **Cuando hace falta el hash, se reconstruye en la sesión** con una consulta sobre la tabla local:

   ```sql
   SELECT count(*) FILTER (WHERE pg_insertar(id_viaje)) AS insertadas FROM viajes_centro;
   ```

   Costo estimado a partir de la etapa I: la construcción tardó 0,308 µs por fila con 1 000 000 de filas (`bench_5.2`), así que los 480 000 viajes de Centro tardarían del orden de 0,15 s, y la estructura ocuparía unos 3,6 MB (7,6 bytes por clave, estimación de 5.2). Es una **extrapolación**, no una medición hecha con réplicas.

5. **Una sola estructura por sesión.** Como hay un único directorio por sesión, no se pueden cargar dos tablas a la vez: `id_viaje` e `id_bus` comparten el mismo espacio de claves y `pg_buscar` no dice de qué tabla es la clave. En el nodo B, que guarda tres fragmentos de viajes, **el hash se carga solo con el fragmento principal** (`viajes_centro`). Las réplicas de Norte y Sur se leen con el B-tree.

6. **Solo guarda claves enteras y devuelve sí o no.** `pg_buscar` contesta un booleano, sin la fila. Para leer el viaje hay que ir a la tabla, que es lo que replica PostgreSQL. `id_viaje` e `id_bus` son `INTEGER`, así que encajan con la función `pg_insertar(integer)`. Las claves repetidas no son un problema al reconstruir, porque la clave primaria ya las impide.

7. **La extensión se instala en los tres nodos.** Hay que ejecutar `CREATE EXTENSION pg_hashing;` también donde solo hay réplicas, porque si ese nodo se promueve, pasa a usar el hash como principal. El `Dockerfile` ya construye la extensión en la imagen, así que los tres contenedores la tienen.


#6. Qué pasa si cae un nodo o cambia la carga

Con el plan de 4.1 (esto es información para 10.2 y 10.3):

| Cae | Qué sigue funcionando | Qué hay que hacer | Qué se puede perder |
|---|---|---|---|
| **A** | Norte desde la réplica en B (los clientes de Norte pasan a B). Centro y Sur no se ven afectados | Promover `viajes_norte` y `buses_norte` en B. Reconstruir el hash de esa tabla en cada sesión | Las últimas escrituras de Norte que no llegaron a B |
| **B** | Centro desde la réplica en A. Norte y Sur no se ven afectados. `conductores` se puede leer en A y C | Promover `viajes_centro` y `buses_centro` en A y elegir una copia principal nueva de `conductores` (en A). Reconstruir el hash | Las últimas escrituras de Centro y de `conductores` |
| **C** | Sur desde la réplica en B (los clientes de Sur pasan a B) | Promover `viajes_sur` y `buses_sur` en B | Las últimas escrituras de Sur |

Los pasos de promoción están en `replicacion_nodos.sql`. Los reportes globales siguen completándose con los dos nodos vivos, porque entre los dos tienen copia de las tres zonas. Si **dos** nodos caen a la vez, parte de los datos queda sin copia: el plan está pensado para la caída de uno.

**Si cambia la concentración de accesos** (Sur al 60 %): C sigue recibiendo todas las escrituras de Sur, porque la copia principal es una sola. Pero las lecturas de Sur de otras zonas y los reportes se pueden mandar a la réplica en B, y eso descarga a C. Es la palanca que hay que medir en 10.3. Las escrituras de Sur no se pueden descargar sin cambiar la fragmentación.


7. Problemas y limitaciones

- **Lecturas atrasadas.** Con replicación asíncrona, L3 y L4 pueden ver datos un poco atrasados. Aceptable para un reporte; no lo sería para leer lo que acabo de escribir, por eso lo de la propia zona se lee en el principal.
- **`id_conductor` entre nodos.** La réplica de `conductores` también es asíncrona. Si se crea un conductor en B y enseguida se registra un viaje en A con ese conductor, puede fallar la clave foránea porque la réplica todavía no llegó. Hay que esperar a que llegue o dar de alta los conductores antes de usarlos. Los conductores no se borran, se dan de baja.
- **Las claves foráneas no se aplican en las réplicas.** La replicación lógica no ejecuta los disparadores de integridad al aplicar los cambios; la integridad la garantiza el nodo principal.
- **Las réplicas no se escriben.** Nada impide técnicamente que alguien escriba en una tabla de réplica. Hay que dar permisos de escritura solo en las tablas principales de cada nodo.
- **Los identificadores se asignan solo en el nodo principal.** Si una réplica se promueve, tiene que continuar desde el mayor `id_viaje` que recibió.
- **El hash no se replica ni sobrevive a un reinicio.** Es una limitación de la implementación actual (no es persistente), no de este diseño. Hacerlo persistente y compartido entre sesiones sería un cambio del núcleo en C que no se plantea aquí.
- **No hay conmutación automática.** La promoción de una réplica es manual (sección 6). Una conmutación automática necesitaría una herramienta extra que no se incluye.
- **Estimación.** Los costos de 4.3 son solo de red. El tiempo de aplicar los cambios en la réplica y el retraso real (*lag*) se miden en 9.2 y 10.1 con `pg_stat_replication`.

8. Lo que necesitan las otras actividades

- **9.1 (nodos, Maricielo):**
  - Arrancar cada nodo con `wal_level = logical` (en `docker-compose.yml`, `command: ["postgres", "-c", "wal_level=logical"]`).
  - Crear los fragmentos como **tablas con el mismo nombre en todos los nodos** (no como las vistas de `fragmentos.sql`, que no se pueden publicar). La lista de tablas por nodo está en la cabecera de `replicacion_nodos.sql`.
  - Cargar los datos solo en el nodo principal de cada fragmento y dejar vacías las tablas de réplica: `copy_data = true` las llena.
  - Como cada nodo tiene `conductores` (principal o réplica), ya se puede declarar la clave foránea `viajes.id_conductor` en los tres. Y como `viajes` y `buses` de la misma zona están juntos, también las otras dos.
- **9.2 (consultas, Nicol):** las lecturas L3 y L4 de la mezcla de 8.1/8.2 deben medirse leyendo de la copia más cercana (por ejemplo, desde B las de Norte y Sur son locales, y desde A la de Centro). Para comparar, medirlas también contra el nodo principal.
- **10.2 (indisponibilidad):** apagar cada nodo uno por uno y seguir la tabla de la sección 6. Medir cuánto tarda la promoción y cuántas filas faltan.
- **10.3 (cambio de carga):** comprobar si mandar las lecturas de Sur a la réplica en B descarga a C.

9. Archivos

| Archivo | Qué contiene |
|---|---|
| `INFORME_8.3.md` | Este informe |
| `plan_replicacion.sql` | Tablas de nodos, latencias, zonas, objetos y réplicas; vistas de copias, tolerancia a la caída de un nodo, almacenamiento por nodo y costo esperado |
| `replicacion_nodos.sql` | Publicaciones y suscripciones de PostgreSQL por nodo, y pasos de promoción tras una caída |

Para ver el plan y comprobar los números de este informe, en una base cualquiera:

```
psql -U postgres -d <base> -f replicacion/plan_replicacion.sql
```
```sql
SELECT * FROM v_tolerancia WHERE copias_vivas = 0;   -- debe dar 0 filas
SELECT * FROM v_almacenamiento ORDER BY nodo;        -- A 70 %, B 100 %, C 30 %
SELECT * FROM v_costo_esperado;                      -- 10.50 | 13.50 | 21.50 | 1.73 | 8.18
```

`replicacion_nodos.sql` no se corre en una sola base: se usa en la 9.1, con los tres nodos levantados.

10. Uso de IA

Usé Claude como apoyo para armar el plan de réplicas, calcular los costos de la sección 4.3, escribir `plan_replicacion.sql` y `replicacion_nodos.sql`. La lógica de las vistas de `plan_replicacion.sql` se comprobó en SQLite.
