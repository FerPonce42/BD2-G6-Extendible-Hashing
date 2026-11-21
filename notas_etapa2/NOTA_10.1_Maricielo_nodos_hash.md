## Nodos de la estrategia hash

En la 10.1 se comparan las dos formas de repartir los datos que se plantearon en 8.1/8.2: por zona, que es la que se eligió, y por hash del identificador, que era la alternativa 2. Para poder medir la segunda hacían falta sus propios nodos, así que en esta parte se armaron los tres nodos de la estrategia hash. Con ellos Iair carga sus datos y Nicol corre la mezcla 70/30. Todo quedó en la carpeta `nodos/`, al lado de los archivos de la estrategia por zona, que no se cambiaron.

### Cómo se armaron

Los nodos hash se levantan con un archivo aparte, `nodos/docker-compose.hash.yml`. Usan la misma imagen del proyecto (PostgreSQL 18.6 con `pg\_hashing`) y la misma base `distribuido` que en la semana 9.

|Nodo|Contenedor|Puerto|Fragmentos|`conductores`|
|-|-|-|-|-|
|A|`nodo\_a`|5433|`buses\_h0`, `viajes\_h0` (id mod 3 = 0)|réplica (de B)|
|B|`nodo\_b`|5434|`buses\_h1`, `viajes\_h1` (id mod 3 = 1)|principal|
|C|`nodo\_c`|5435|`buses\_h2`, `viajes\_h2` (id mod 3 = 2)|réplica (de B)|

Se dejaron los mismos nombres de contenedor, la misma base y los mismos puertos que en la estrategia por zona. La idea fue que el script de carga de Iair y las consultas de Nicol sirvan para las dos estrategias sin tener que cambiarles nada. Lo malo es que no se pueden tener las dos levantadas a la vez: para pasar de una a otra hay que bajar la que está corriendo y volver a cargar los datos.

Para las tablas se usaron los nombres que Iair ya había propuesto en su generador (`buses\_hK` y `viajes\_hK`), así que su carga las encuentra directo.

### Tablas

Cada nodo tiene `rutas` (las 10 filas) y `conductores`, igual que en la estrategia por zona, y además su fragmento. Las tablas `buses\_hK` y `viajes\_hK` tienen las mismas columnas de siempre, pero cambian algunas cosas:

* El `CHECK` ya no es por ruta sino por `id mod 3 = K`. Por eso en cada nodo terminan buses y viajes de las tres zonas mezclados.
* `viajes\_hK` no tiene clave foránea a su bus, porque el bus casi nunca está en el mismo nodo que el viaje. Esto es justo la pérdida de localidad que se explicó en la sección 3.3 de 8.1/8.2. La regla de que la ruta del viaje sea la ruta de su bus la sigue cumpliendo el generador, pero la base ya no la puede revisar, como sí lo hace en la estrategia por zona.
* Se puso el mismo B-tree sobre `(id\_ruta, salida)` que en la estrategia por zona, para que las consultas L2 se comparen en las mismas condiciones.

### Replicación

Lo único que se replica es `conductores`, igual que en la estrategia por zona: B la publica y A y C se suscriben. Los fragmentos `h0`, `h1` y `h2` no tienen réplica. Se hizo así porque la comparación de la sección 3.5 de 8.1/8.2 también se hizo sin réplicas, y así lo que se mida depende solo de cómo se reparten los datos.

Hay que tener esto en cuenta al comparar. En la estrategia por zona algunas lecturas de otra zona se pueden contestar con una réplica que está en el mismo nodo, y en la estrategia hash eso no pasa. Si se quiere comparar solo la fragmentación, conviene tomar de la estrategia por zona las operaciones que van al nodo principal.

### Pruebas

Los datos se cargaron con el generador y el script de carga de Iair (`generar\_distribuido.py 1 hash` y `cargar\_distribuido.sh hash`), sin cambiarles nada. La carga terminó con `OK` y cada nodo quedó con las filas de su CSV:

|Tabla|Nodo A|Nodo B|Nodo C|
|-|-|-|-|
|`rutas`|10|10|10|
|`conductores`|5 000 (réplica)|5 000 (principal)|5 000 (réplica)|
|`buses\_hK`|33 333|33 334|33 333|
|`viajes\_hK`|400 000|400 000|400 000|

Después se corrió el script de verificación (`hash\_verificar.sql`) en los tres nodos, y salieron dos cosas que muestran bien la diferencia con la estrategia por zona:

* Cada nodo tiene viajes de las tres zonas, más o menos en la misma proporción 30/40/30 del total. Por ejemplo, el nodo A tiene unos 120 000 viajes de Norte, 160 000 de Centro y 120 000 de Sur.
* En cada nodo, solo el 33,3 % de los viajes tiene su bus en ese mismo nodo, mientras que en la estrategia por zona es el 100 %. O sea, se confirma con datos lo que se esperaba en 8.1/8.2: juntar un viaje con su bus obliga a ir a otro nodo en 2 de cada 3 casos.

También se probó que cada fragmento rechaza las filas que no le tocan. Al intentar meter en `viajes\_h0` un viaje con `id\_viaje mod 3 = 1`, o en `buses\_h0` un bus con `id\_bus mod 3 = 1`, sale error. En cambio, un viaje de `viajes\_h0` cuyo bus está en el nodo B sí se acepta, porque no hay clave foránea al bus.

### Limitaciones

* No se pueden tener las dos estrategias levantadas al mismo tiempo, porque usan los mismos nombres de contenedor y los mismos puertos. Cada vez que se cambia de estrategia hay que bajar los nodos y volver a cargar los datos.
* Los fragmentos hash no tienen réplica, así que si se cae un nodo se pierde un tercio de todos los datos. La prueba de caída de la 10.2 se hizo con la estrategia por zona, no con esta.
* En los nodos hash la base no controla que un viaje tenga la misma ruta que su bus. Eso depende de que los datos vengan bien desde el generador.

### Uso de IA

Se utilizó Claude (IA) como herramienta de consulta para resolver algunas dudas técnicas durante la configuración de los nodos hash, principalmente en las partes más complejas del archivo docker-compose.hash.yml y de los scripts SQL. La implementación, el levantamiento de los nodos, la carga de datos con los scripts de Iair y las pruebas se realizaron en el entorno Docker del grupo. Los resultados presentados corresponden a las pruebas realizadas.

