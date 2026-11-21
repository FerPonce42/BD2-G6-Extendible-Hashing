## Registro de métricas en los tres tamaños de dataset

En esta parte se juntaron en un solo lugar las métricas que el grupo midió en las actividades 5.2, 7.1 y 7.2, para los tres tamaños de D2: 100 000, 500 000 y 1 000 000 filas. No se hicieron mediciones nuevas: se leyeron los archivos de resultados de cada actividad y se sacó la mediana de cada medición con un script en Python (`bench\_7.3/calcular\_metricas.py`), para que cualquiera pueda comprobar de dónde sale cada número.

Se registraron las métricas mínimas que pide la rúbrica: tiempo de búsqueda, tiempo de construcción, comportamiento de inserción, tamaño del índice y evolución al aumentar el volumen de datos.

### Condiciones de las mediciones

Las mediciones no se hicieron todas en la misma computadora. Por eso, en cada tabla se indica de qué PC viene cada columna.

|Actividad|Qué se midió|PC|
|-|-|-|
|5.2 (Etapa I)|Búsqueda y construcción con B-tree y con hash, tamaño del B-tree|PC de Iair Suico: Intel Core i5-13420H, 12 núcleos, 7759 MB|
|7.1|Búsqueda e inserción sin índice|PC de Fernando Ponce: Intel Core i5-12450H, 12 núcleos, 7776 MB|
|7.2|Inserción con B-tree y con hash|PC de Nicol Rocha: Intel Core i7-1185G7, 16 GB, Windows 11 (dato de sus notas de la actividad 7.2)|

En todas se usó lo mismo: **PostgreSQL 18.6** dentro del Docker del grupo con la configuración por defecto (`shared\_buffers` = 128 MB, `work\_mem` = 4 MB), los datos D2 generados con la semilla 42 y **5 repeticiones** por medición.

**Medida central.** En todas las tablas se usa la **mediana** de las 5 repeticiones, igual que en las actividades 5.2 y 7.1. En varias series hay una repetición suelta mucho más lenta que las demás. Por ejemplo, en la inserción con B-tree de 500 000 filas se obtuvo 101, 107, 108, 131 y 155 ms: la media da 120,4 ms porque la jalan los dos valores altos, mientras que la mediana da 107,7 ms. Por eso, algunas cifras de inserción no coinciden con la nota de la actividad 7.2, que usó la media.

### Búsqueda

Se buscaron 20 000 claves por repetición: 10 000 que existen (W1) y 10 000 que no (W2). Mediana en **microsegundos (µs) por consulta**.

|D2|Sin índice (PC Fernando)|B-tree (PC Iair)|Hash por SQL (PC Iair)|Hash directo (PC Iair)|Consulta vacía (PC Iair)|
|-|-|-|-|-|-|
|100 000|2 843,5|3,27|1,02|0,15|1,05|
|500 000|14 564,4|4,02|1,26|0,19|0,93|
|1 000 000|29 107,9|3,83|1,18|0,22|0,91|

* **Hash por SQL** es la comparación justa con el B-tree, porque los dos hacen una consulta SQL por cada clave.
* **Hash directo** es el costo de la estructura sola, sin pasar por el ejecutor de consultas de PostgreSQL.
* **Consulta vacía** es lo que cuesta ejecutar una consulta que no busca nada.

En todas las corridas se encontraron las 10 000 claves de W1 y ninguna de W2.

### Construcción

Tiempo para construir el índice sobre la tabla ya cargada. Mediana de 5 repeticiones (PC Iair).

|D2|B-tree (ms)|Hash (ms)|B-tree (µs por fila)|Hash (µs por fila)|
|-|-|-|-|-|
|100 000|27,9|9,9|0,28|0,10|
|500 000|181,5|90,1|0,36|0,18|
|1 000 000|389,3|308,4|0,39|0,31|

El B-tree se construyó con un solo proceso, igual que el hash, para que la comparación sea pareja.

### Inserción (W3)

Se insertaron claves nuevas equivalentes al 10 % del tamaño del dataset: 10 000, 50 000 y 100 000 claves, a continuación del `id\_bus` más alto. Mediana de 5 repeticiones.

|D2|Inserciones|Sin índice (PC Fernando)|B-tree (PC Nicol)|Hash (PC Nicol)|
|-|-|-|-|-|
|100 000|10 000|4,6 ms (0,46 µs c/u)|21,7 ms (2,17 µs c/u)|5,1 ms (0,51 µs c/u)|
|500 000|50 000|21,9 ms (0,44 µs c/u)|107,7 ms (2,15 µs c/u)|21,1 ms (0,42 µs c/u)|
|1 000 000|100 000|48,1 ms (0,48 µs c/u)|184,3 ms (1,84 µs c/u)|50,4 ms (0,50 µs c/u)|

**Esta comparación favorece al hash**, porque no hacen el mismo trabajo:

* El **hash** solo guarda la clave en la memoria de la sesión. No escribe la fila en la tabla.
* El **B-tree** escribe la fila completa en la tabla `buses` **y además** actualiza el índice.
* **Sin índice** solo escribe la fila en la tabla.

Que el hash tarde parecido a "sin índice" no quiere decir que sea igual de barato: el hash ni siquiera escribe la fila. Además, la columna "Sin índice" viene de otra PC, así que no se puede restar del B-tree para calcular cuánto cuesta mantener el índice.

### Tamaño del índice

|D2|B-tree (medido)|Hash (estimado)|Tabla `buses`|
|-|-|-|-|
|100 000|2 208 kB (22,6 bytes por clave)|654 kB (6,7 bytes por clave)|5 504 kB|
|500 000|11 MB (22,5 bytes por clave)|3,6 MB (7,6 bytes por clave)|25 MB|
|1 000 000|21 MB (22,5 bytes por clave)|7,2 MB (7,6 bytes por clave)|50 MB|

El tamaño del B-tree se midió desde PostgreSQL en la actividad 5.2. El de nuestra estructura no se puede medir desde SQL, porque la extensión no lo muestra, así que se **estimó** con la misma fórmula de la 5.2: cada bucket ocupa unos 224 bytes (su estructura más 50 claves de 4 bytes) y cada casilla del directorio, 8 bytes. La cantidad de buckets y casillas se obtuvo revisando la estructura por dentro después de insertar todas las claves:

|D2|Profundidad global|Casillas|Buckets|Ocupación de los buckets|
|-|-|-|-|-|
|100 000|12|4 096|2 845|70 %|
|500 000|15|32 768|15 775|63 %|
|1 000 000|16|65 536|31 547|63 %|

Estos conteos no dependen de la PC: como los datos siempre son los mismos (semilla 42), la estructura siempre queda igual.

Las cifras en kB y MB son **binarias**, igual que las muestra PostgreSQL: 1 kB = 1024 bytes y 1 MB = 1024 kB. Por ejemplo, el hash con 1 000 000 filas ocupa 7 590 816 bytes, que son 7,2 MB binarios (o unos 7,6 millones de bytes, la cifra del informe 5.2).

La comparación de tamaño tampoco es pareja: el B-tree guarda en cada entrada la ubicación de la fila en la tabla y deja espacio libre en sus páginas, mientras que nuestra estructura solo guarda la clave.

### Evolución al aumentar el volumen

Al pasar de 100 000 a 1 000 000 filas (10 veces más datos):

|Métrica|Sin índice|B-tree|Hash|
|-|-|-|-|
|Búsqueda (µs por consulta)|×10,2|+17 %|+16 % por SQL, +50 % directo|
|Construcción (µs por fila)|—|×1,4|×3,1|
|Inserción (µs por clave)|casi igual|baja un poco|casi igual|
|Tamaño (bytes por clave)|—|casi igual (22,5)|sube de 6,7 a 7,6|

* **Sin índice**, el tiempo de búsqueda crece igual que los datos: con 10 veces más filas tarda 10 veces más, porque revisa la tabla entera en cada búsqueda. Con 1 000 000 filas, las 5 repeticiones tomaron unos 48 minutos.
* **Con B-tree y con hash**, la búsqueda casi no cambia, porque no recorren la tabla. El hash directo sube un poco (de 0,15 a 0,22 µs). Una posible causa es que, con más datos, la estructura ya no entre entera en la memoria caché del procesador, pero esto no se midió.
* **En construcción**, el hash sigue siendo más rápido, pero la ventaja se achica: de 2,8 veces con 100 000 filas a 1,3 veces con 1 000 000. Una posible causa, que tampoco se midió, es que cada vez que el directorio se duplica hay que copiarlo entero.
* **En inserción**, el B-tree no se vuelve más lento con 1 000 000 filas. Una posible explicación es que las claves nuevas son consecutivas y en el B-tree caen todas al final del índice, que es el mejor caso para él.

### Limitaciones

* **Las mediciones vienen de tres PC distintas.** Solo se comparan directamente las columnas de una misma PC: B-tree con hash en búsqueda y construcción (PC Iair), y B-tree con hash en inserción (PC Nicol). La comparación con "sin índice" sirve para ver órdenes de magnitud, no para decir cuántas veces más rápido es un método que otro.
* **La comparación de inserción favorece al hash**, porque no escribe la fila en la tabla.
* **El tamaño del hash es una estimación** hecha a partir del código, no una medición.
* **Los datos de la PC de la actividad 7.2 salen de las notas de Nicol**, porque su archivo de resultados solo guarda la versión de PostgreSQL. Además, la memoria de las otras dos PC es la que ve el contenedor de Docker, no la memoria total del equipo.
* **Solo se midió D2** (claves aleatorias). Falta D1 y una carga no favorable para el hash.

### Uso de IA

Se usó Claude (IA) como apoyo para escribir el script que calcula las medianas. Las mediciones son las que hizo el grupo en las actividades 5.2, 7.1 y 7.2, y los números de esta sección salen de esos resultados.

