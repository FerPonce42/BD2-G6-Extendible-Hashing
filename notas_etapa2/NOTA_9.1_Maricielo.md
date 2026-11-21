## Levantamiento de los tres nodos

*Responsable: Maricielo Luna (actividad 9.1)*

En esta parte se levantaron los tres nodos de la parte distribuida (A, B y C) como contenedores Docker, cada uno con sus fragmentos según la asignación de las actividades 8.1 y 8.2, y se armó la replicación según el plan de la actividad 8.3. Todo está en la carpeta `nodos/` del repositorio.

### Cómo se armaron los nodos

Los tres nodos se levantan con un `docker-compose.yml` propio (`nodos/docker-compose.yml`), aparte del de la etapa I, que sigue igual. Cada nodo usa la misma imagen del proyecto (PostgreSQL 18.6 con la extensión `pg\_hashing` ya compilada) y una base aparte llamada `distribuido`, para no tocar la base `hashing\_db` de la etapa I.

|Nodo|Contenedor|Puerto en la PC|Principal de|Réplica de|
|-|-|-|-|-|
|A|`nodo\_a`|5433|Norte|Centro y conductores|
|B|`nodo\_b`|5434|Centro y conductores|Norte y Sur|
|C|`nodo\_c`|5435|Sur|conductores|

Los nodos se arrancan con `wal\_level = logical`, que es lo que necesita la replicación lógica de PostgreSQL. Dentro de la red de Docker se encuentran por su nombre (`nodo\_a`, `nodo\_b` y `nodo\_c`).

### Tablas de cada nodo

Los fragmentos se crearon como **tablas** con el mismo nombre en todos los nodos y no como las vistas de `fragmentos.sql`, porque una vista no se puede publicar para replicación. Se crean solas la primera vez que arranca cada nodo:

|Archivo|Qué crea|En qué nodos|
|-|-|-|
|`01\_comun.sql`|La extensión `pg\_hashing`, `rutas` (las 10 filas) y `conductores`|A, B y C|
|`02\_norte.sql`|`buses\_norte` y `viajes\_norte`|A y B|
|`03\_centro.sql`|`buses\_centro` y `viajes\_centro`|A y B|
|`04\_sur.sql`|`buses\_sur` y `viajes\_sur`|B y C|
|`05\_publicacion\_<nodo>.sql`|La publicación del nodo (paso 1 de la replicación)|Cada uno la suya|

Las columnas son las del esquema global de la actividad 8.1. Además, se agregaron restricciones para que la base misma no deje romper la fragmentación:

* **Un `CHECK` en `id\_ruta`** en cada fragmento. Por ejemplo, en `buses\_norte` y `viajes\_norte` solo entran las rutas 1, 2 y 3. Así, una fila de otra zona no puede caer en el fragmento equivocado.
* **Una clave foránea doble `(id\_bus, id\_ruta)`** de cada tabla de viajes a la tabla de buses de su zona. Esto obliga a que cada viaje tenga la misma ruta que su bus, que es la regla 2 de la actividad 8.1. Si los datos rompen esa regla, la carga falla.
* **Las claves foráneas a `rutas` y a `conductores`.** Se pueden declarar en los tres nodos porque todos tienen una copia de las dos tablas.
* **Un B-tree sobre `(id\_ruta, salida)`** en cada tabla de viajes, para las consultas de una ruta en un rango de fechas (L2), como propuso la actividad 8.1.

### Replicación

Se siguió la receta de la actividad 8.3 (`replicacion/replicacion\_nodos.sql`):

1. **Publicaciones** (se crean solas al arrancar): A publica Norte, B publica Centro y `conductores`, y C publica Sur.
2. **Suscripciones** (se crean con `suscripciones.sql` cuando los tres nodos ya están arriba): A se suscribe a Centro y a `conductores`, B a Norte y a Sur, y C a `conductores`.

El único cambio respecto a la receta es la base: las suscripciones se conectan a `dbname=distribuido` en vez de `hashing\_db`.

Como dice la actividad 8.3, los datos se cargan **solo en el nodo principal** de cada fragmento, y las réplicas se llenan solas por la suscripción.

### Pruebas

Para comprobar que los nodos y la replicación funcionan se usaron **datos de prueba chicos**, el 1 % del tamaño de diseño: 50 conductores, 1 000 buses y 12 000 viajes, repartidos 30/40/30 como en la actividad 8.1. Los datos reales (1 200 000 viajes) salen del generador de la actividad que hace Iair. Los datos de prueba respetan las dos reglas de la actividad 8.1: cada bus tiene una sola ruta y cada viaje se arma con la ruta de su bus.

**Filas en cada nodo después de cargar y replicar:**

|Tabla|Nodo A|Nodo B|Nodo C|
|-|-|-|-|
|`rutas`|10|10|10|
|`conductores`|50 (réplica)|50 (principal)|50 (réplica)|
|`buses\_norte` / `viajes\_norte`|300 / 3 600 (principal)|300 / 3 600 (réplica)|—|
|`buses\_centro` / `viajes\_centro`|400 / 4 800 (réplica)|400 / 4 800 (principal)|—|
|`buses\_sur` / `viajes\_sur`|—|300 / 3 600 (réplica)|300 / 3 600 (principal)|

* **Cada réplica tiene exactamente las mismas filas que su principal**, y todas las suscripciones quedaron recibiendo datos.
* **Ningún viaje quedó con una ruta distinta a la de su bus** en ningún nodo.
* **Una escritura nueva llega a la réplica.** Se insertó un viaje en `viajes\_norte` en el nodo A y apareció en la réplica del nodo B al consultarla enseguida, aunque en B nunca se insertó. Al borrarlo en A, también se borró en B.
* **Los fragmentos rechazan datos de otra zona.** Insertar en `buses\_norte` un bus de una ruta de Centro, o en `viajes\_norte` un viaje con un bus de Centro, da error.

**Precaución en la carga.** Los viajes de A y de C usan los conductores, que se cargan en B y llegan a A y C por la réplica. Como la réplica de `conductores` es asíncrona (actividad 8.3, sección 7), si los viajes se cargan antes de que lleguen los conductores, la clave foránea los rechaza. Por eso el orden es cargar B primero y esperar unos segundos. Además, el script de carga revisa que ya hayan llegado los conductores: si no, avisa que hay que esperar y no inserta nada. También carga cada nodo en una sola transacción, para que no queden datos a medias. En las pruebas, con unos 10 segundos de espera, A y C cargaron a la primera.

### Latencias

Los tres contenedores corren en la misma PC, así que entre ellos casi no hay latencia de red. Las latencias de la rúbrica (A-B = 20 ms, A-C = 40 ms y B-C = 25 ms) no se configuraron en los contenedores, sino que se simulan en el script de pruebas de la actividad 9.2: cuando una operación va a otro nodo, el script espera esos milisegundos.

### Limitaciones

* **Los datos son de prueba.** Las pruebas se hicieron con el 1 % del tamaño de diseño. Falta cargar los 1 200 000 viajes cuando esté el generador.
* **No se miden tiempos.** Esta parte solo comprueba que los nodos y la replicación funcionan; los tiempos y las latencias se miden en la actividad 9.2.
* **Nada impide escribir en una réplica.** Técnicamente se puede insertar a mano en una tabla de réplica, lo que la desordenaría respecto del principal. Como indica la actividad 8.3, las réplicas solo deben escribirse por la suscripción.
* **En las réplicas no se aplican las claves foráneas.** La replicación lógica no las revisa al copiar los cambios; la integridad la garantiza el nodo principal.
* **La estructura de Extendible Hashing no se replica.** Vive en la memoria de cada sesión, así que en cada nodo hay que volver a armarla con `pg\_insertar` sobre su tabla, como explica la actividad 8.3.
* **La promoción de una réplica si cae un nodo es manual** y no se probó aquí: corresponde a la actividad 10.2.

### Uso de IA

Se uso Claude (IA) como herramienta de apoyo para resolver algunas dudas sobre el funcionamiento de la replicación lógica en PostgreSQL, principalmente sobre las publicaciones y suscripciones entre nodos, además de ayudarme con el ordenamiento para poder redactar este informe. Yo me encargué, de adaptar y configurar los archivos docker-compose.yml y los scripts SQL, levantar los tres nodos en Docker y realizar las pruebas para comprobar que la replicación funcionara correctamente.

