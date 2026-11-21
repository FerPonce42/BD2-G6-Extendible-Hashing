## Consultas locales y multinodo

*Responsable: Nicol Rocha (actividad 9.2)*

En esta parte se midieron consultas locales y consultas que necesitan varios nodos sobre los tres nodos de la actividad 9.1 (A, B y C), con las latencias de la rúbrica simuladas por el script. Se usó la mezcla de operaciones de la actividad 8.1/8.2 (sección 4.3), que cumple el 70 % de lecturas y 30 % de escrituras, y se comparó el costo con y sin las réplicas de la actividad 8.3. Los scripts y los resultados crudos están en la carpeta `bench_9.2/` de la rama `Nicol-9.2` del repositorio.

### Entorno

* PC: Dell Latitude 7320, procesador Intel Core i7-1185G7 (11.ª generación, 3,00 GHz), 16 GB de RAM (3733 MT/s), 238 GB de almacenamiento y Windows 11.
* PostgreSQL 18.6 en contenedores Docker (los tres nodos en la misma PC), con la extensión `pg_hashing` de la etapa I.
* Datos: los de prueba de la actividad 9.1 (1 % del tamaño de diseño).

### Qué se midió

Se usan las seis operaciones de la mezcla de 8.1/8.2, con un cliente conectado al nodo A (zona Norte):

|Operación|Tipo|Proporción|Qué se ejecuta|
|-|-|-|-|
|L1|lectura|35 %|Leer un viaje de la propia zona por `id_viaje` (en A, `viajes_norte`)|
|L2|lectura|20 %|Viajes de una ruta propia en un rango de fechas (usa el B-tree sobre `(id_ruta, salida)`)|
|L3|lectura|10 %|Leer un viaje de otra zona (Centro o Sur)|
|L4|lectura|5 %|Reporte global: suma de pasajeros de las tres zonas|
|E1|escritura|25 %|Insertar un viaje en la propia zona (en el principal, A)|
|E2|escritura|5 %|Actualizar un bus de la propia zona (en el principal, A)|

L3 y L4 se midieron de varias formas, para comparar el plan con réplicas contra el diseño sin réplicas:

|Variante|Qué hace|Red supuesta|
|-|-|-|
|`L3_principal`|Viaje de Centro leído en su principal (B)|20 ms|
|`L3_replica`|Viaje de Centro leído en la réplica de A|0 ms|
|`L3_sur`|Viaje de Sur leído en su principal (C)|40 ms|
|`L3_sur_rep`|Viaje de Sur leído en la réplica de B|20 ms|
|`L4_desde_A`|Reporte global desde A, preguntando en paralelo a los tres principales|40 ms|
|`L4_desde_B`|Igual, pero coordinado desde B (nodo central)|25 ms|
|`L4_A_replicas`|Desde A: Norte y Centro en local y Sur en la réplica de B|20 ms|
|`L4_B_replicas`|Desde B, que guarda copia de las tres zonas|0 ms|

`L4_B_replicas` (1,97 ms) solo vale para un cliente que ya está conectado a B. Para el cliente de A, llegar a B cuesta 20 ms más, por eso esta variante no entra en el costo ponderado (se usa `L4_A_replicas`).

### Cómo se midió

* **Tiempo de ejecución (`ms_ejec`).** Es el tiempo que reporta PostgreSQL con `\timing` en el nodo que ejecuta la consulta. No incluye el arranque de `docker exec` ni de `psql`, que sumaba unos 300 ms y no tiene que ver con la consulta. Es lo único que se mide de verdad.
* **Tiempo de red (`ms_red`).** No se mide: los contenedores corren en la misma PC, así que la columna sale de una tabla de latencias constantes en `lib.sh` (A-B = 20 ms, A-C = 40 ms, B-C = 25 ms), las mismas de 8.1/8.2 y 8.3, y el script espera ese tiempo con `sleep`. Se suma una vez por operación, igual que en el cálculo de esas actividades.
* **Consultas multinodo.** Se lanzan en paralelo a cada nodo, cada uno con la consulta sobre la tabla que tiene como principal. El tiempo de ejecución es el del nodo más lento y la espera de red es la del nodo más lejano (peor caso), como en 8.1/8.2.
* **Total.** `ms_total = ms_ejec + ms_red`.
* **Repeticiones.** Cada operación se repitió 10 veces y se reporta la **mediana**. La primera repetición suele ser más lenta (ejecución en frío), y la mediana lo absorbe.
* **Datos.** Los de prueba de la actividad 9.1: 50 conductores, 1 000 buses y 12 000 viajes (3 600 en Norte, 4 800 en Centro y 3 600 en Sur).
* **Escrituras.** E1 inserta un viaje nuevo en `viajes_norte` y E2 actualiza un bus. Las 10 filas que inserta E1 en cada corrida se borraron al terminar, y el borrado también llegó a la réplica de B.

### Resultados

Medianas de 10 repeticiones (en ms). La columna de ejecución es medida; la de red es la latencia supuesta de la rúbrica:

|Operación|Ejecución|Red|Total|
|-|-|-|-|
|L1|0,820|0|0,820|
|L2|1,067|0|1,067|
|L3\_principal|0,858|20|20,858|
|L3\_replica|0,863|0|0,863|
|L3\_sur|0,857|40|40,857|
|L3\_sur\_rep|0,857|20|20,857|
|L4\_desde\_B|1,949|25|26,949|
|L4\_desde\_A|2,321|40|42,321|
|L4\_A\_replicas|2,281|20|22,281|
|L4\_B\_replicas|1,965|0|1,965|
|E1|5,982|0|5,982|
|E2|4,692|0|4,692|

* **Las operaciones de la propia zona (L1, L2, E1 y E2) no usan la red.** Cuestan entre 0,8 y 6 ms, que es solo la ejecución en el nodo.
* **Con réplica, leer de otra zona baja de 20 y 40 ms a 0 y 20 ms de red supuesta.** El viaje de Centro se lee en la réplica de A en 0,86 ms en total, contra 20,86 ms en el principal. El de Sur se lee en la réplica de B en 20,86 ms, contra 40,86 ms en C.
* **El reporte global también mejora.** Desde A baja de 42,3 a 22,3 ms con réplicas. Coordinado desde B sin usar sus réplicas cuesta 26,9 ms, y desde B usando sus propias réplicas, que cubren las tres zonas, cuesta 1,97 ms (solo para un cliente ya conectado a B).
* **La red supuesta domina.** La ejecución medida en el nodo es de entre 1 y 6 ms, mientras que la latencia supuesta llega a 40 ms. Es consistente con la decisión de 8.1 de priorizar la localidad.
* **Las escrituras cuestan lo mismo con y sin réplicas.** Con replicación asíncrona, el principal confirma sin esperar a la réplica.

### Costo ponderado con la mezcla 70/30

Se combinaron las medianas con las proporciones de la mezcla (35 % L1, 20 % L2, 10 % L3, 5 % L4, 25 % E1 y 5 % E2). Para L3 se usó el promedio de las dos zonas ajenas (Centro y Sur), como en 8.1/8.2:

|Costo por operación|Sin réplicas|Con réplicas|Reducción|
|-|-|-|-|
|Solo red (supuesta)|5,00 ms|2,00 ms|60 %|
|Red supuesta + ejecución medida|7,43 ms|4,43 ms|40 %|

* **Sin réplicas:** L3 = promedio de `L3_principal` y `L3_sur`, y L4 = `L4_desde_A`.
* **Con réplicas:** L3 = promedio de `L3_replica` y `L3_sur_rep`, y L4 = `L4_A_replicas`.

**Comparación con las estimaciones de las actividades anteriores** (solo red):

|Fuente|Sin réplicas|Con réplicas asíncronas|Reducción|
|-|-|-|-|
|Estimado en 8.1/8.2 y 8.3 (clientes de las tres zonas)|4,48 ms|1,73 ms|61 %|
|Calculado en 9.2 con latencias supuestas (cliente en A)|5,00 ms|2,00 ms|60 %|

Los 5,00 y 2,00 ms de solo red **no son una medición independiente**: salen de las mismas latencias supuestas de 8.1/8.2 y 8.3, aplicadas a un cliente en A, que es un nodo extremo y paga más red que el promedio de las tres zonas (por eso son mayores que los 4,48 y 1,73 ms estimados). Lo que sí se midió es la ejecución en el nodo (entre 0,8 y 6 ms), que es pequeña frente a la red supuesta. El resultado es **consistente con el modelo**: con réplicas asíncronas el costo de red baja en un 60 %, pero esa conclusión depende de las latencias supuestas y no de latencias medidas.

### Limitaciones

* **La red no se mide, se supone.** Las latencias son las de la rúbrica, aplicadas con una espera en el script; no hay medición de red real entre los nodos.
* **Los datos son de prueba.** Se usó el 1 % del tamaño de diseño. Con tan pocas filas, el tiempo de ejecución es de milisegundos y casi no se nota. Con los 1 200 000 viajes del generador de la actividad de Iair hay que repetir la medición.
* **Se midió un solo cliente (A).** Los clientes de Centro (B) y Sur (C) no se midieron, por lo que el costo ponderado no es comparable uno a uno con el de 8.1/8.2 y 8.3, aunque sí lo es la reducción.
* **No se midió la replicación síncrona.** Fabricio la estimó en 8,18 ms por operación en 8.3, y aquí solo se midió la asíncrona.
* **Las lecturas en réplica pueden ir atrasadas.** El retraso medido en `pg_stat_replication` fue de unas décimas de milisegundo, pero en una caída de nodo podrían perderse las últimas escrituras.
* **No se midió el Extendible Hashing.** Las consultas usan la clave primaria (B-tree) y el B-tree sobre `(id_ruta, salida)`. La estructura de `pg_hashing` vive en la memoria de cada sesión y no se replica (actividad 8.3, sección 5), por lo que compararla con el B-tree en los nodos queda para la actividad 10.1.
* **El tiempo de ejecución es el que reporta el servidor.** No cuenta el arranque de `docker exec` ni de `psql`.
* **Un solo equipo.** Los tres nodos comparten la misma PC, así que se disputan CPU y disco, y las mediciones pueden variar entre corridas.

### Archivos

|Archivo|Qué contiene|
|-|-|
|`bench_9.2/lib.sh`|Funciones para ejecutar una consulta en un nodo, medir el tiempo del servidor y simular la latencia (local y multinodo)|
|`bench_9.2/consultas.sh`|Las operaciones de la mezcla (L1 a E2) con sus variantes, repetidas `REP` veces|
|`bench_9.2/resultados_9.2.csv`|Resultados crudos: una fila por operación y repetición|
|`bench_9.2/resumen.py`|Calcula las medianas y el costo ponderado|

Para repetir las pruebas (con los nodos de la actividad 9.1 ya levantados y con datos, desde la raíz del repositorio):

```
export MSYS_NO_PATHCONV=1          # solo en Git Bash de Windows
REP=10 bash bench_9.2/consultas.sh
python bench_9.2/resumen.py
docker exec nodo_a psql -U postgres -d distribuido -c "DELETE FROM viajes_norte WHERE salida >= '2026-11-01';"
```

La última línea borra los viajes que inserta E1, para dejar los datos de prueba como estaban.

### Uso de IA

Se usó Claude y Gemini (IA) como herramienta de apoyo para proponer la estructura de los scripts `lib.sh` y `consultas.sh`, corregir la forma de medir el tiempo y la consulta multinodo (una consulta distinta por nodo). Yo me encargué de adaptar los scripts a los datos de la actividad 9.1, correrlos sobre los tres nodos, revisar los resultados y las medianas, y limpiar los datos de prueba al terminar.
