## Consultas locales y multinodo con los datos de diseño (1 200 000 viajes)

*Responsable: Nicol Rocha (repetición de la actividad 9.2, semana 10)*

Esta parte repite las mediciones de la actividad 9.2, que se hicieron con el 1 % de los datos, ahora con el tamaño de diseño: 5 000 conductores, 100 000 buses y 1 200 000 viajes. Se usaron las mismas operaciones, el mismo script y las mismas latencias simuladas de la rúbrica, de modo que los resultados son comparables con los del informe anterior. Los resultados crudos están en `bench_9.2/resultados_9.2_1200k.csv`, en la rama `nicol-9.2-1200k` del repositorio. Los del 1 % siguen en `bench_9.2/resultados_9.2.csv`.

### Entorno

* PC: Dell Latitude 7320, procesador Intel Core i7-1185G7 (11.ª generación, 3,00 GHz), 16 GB de RAM (3733 MT/s), 238 GB de almacenamiento y Windows 11. Es la misma PC de la prueba con el 1 %.
* PostgreSQL 18.6 en contenedores Docker (los tres nodos en la misma PC), con la extensión `pg_hashing` de la etapa I.
* Datos: los del generador (`generador/generar_distribuido.py`, semilla 42), cargados con `generador/cargar_distribuido.sh`: 360 000 viajes en A (Norte), 480 000 en B (Centro) y 360 000 en C (Sur).
* La carga terminó con `OK`: cada réplica igual a su principal, `viajes_fuera_de_lugar = 0` en los tres nodos y suscripciones con `recibiendo = t`.

### Qué se midió

Son las seis operaciones de la mezcla 70/30 de 8.1/8.2, con un cliente conectado al nodo A (zona Norte): L1 (leer un viaje propio por id, 35 %), L2 (viajes de una ruta propia en un rango de fechas, 20 %), L3 (leer un viaje de otra zona, 10 %), L4 (reporte global de las tres zonas, 5 %), E1 (insertar un viaje en la propia zona, 25 %) y E2 (actualizar un bus propio, 5 %).

L3 y L4 se midieron en las mismas variantes que antes:

|Variante|Qué hace|Red supuesta|
|-|-|-|
|`L3_principal`|Viaje de Centro leído en su principal (B)|20 ms|
|`L3_replica`|Viaje de Centro leído en la réplica de A|0 ms|
|`L3_sur`|Viaje de Sur leído en su principal (C)|40 ms|
|`L3_sur_rep`|Viaje de Sur leído en la réplica de B|20 ms|
|`L4_desde_A`|Reporte global desde A, en paralelo a los tres principales|40 ms|
|`L4_desde_B`|Igual, coordinado desde B|25 ms|
|`L4_A_replicas`|Desde A: Norte y Centro en local y Sur en la réplica de B|20 ms|
|`L4_B_replicas`|Desde B, que guarda copia de las tres zonas|0 ms|

`L4_B_replicas` solo vale para un cliente ya conectado a B, por eso no entra en el costo ponderado (se usa `L4_A_replicas`).

### Cómo se midió

* **Tiempo de ejecución (`ms_ejec`).** Es el tiempo que reporta PostgreSQL con `\timing` en el nodo que ejecuta la consulta. Es lo único que se mide de verdad.
* **Tiempo de red (`ms_red`).** No se mide: los contenedores corren en la misma PC, así que la columna sale de las latencias constantes de `lib.sh` (A-B = 20 ms, A-C = 40 ms, B-C = 25 ms), que el script espera con `sleep`.
* **Consultas multinodo.** Se lanzan en paralelo a cada nodo. La ejecución es la del nodo más lento y la red es la del nodo más lejano (peor caso).
* **Total.** `ms_total = ms_ejec + ms_red`.
* **Repeticiones.** 10 por operación (`REP=10`); se reporta la **mediana**.
* **Escrituras.** E1 inserta viajes en `viajes_norte` y E2 actualiza un bus. Al terminar cada corrida se borraron las 30 filas insertadas por E1 (`DELETE 30`), y se comprobó que `viajes_norte` volvió a 360 000.

### Resultados

Medianas de 10 repeticiones (en ms). La ejecución es medida; la red es la latencia supuesta de la rúbrica. La última columna compara la ejecución con la del 1 % (medianas calculadas desde `resultados_9.2.csv`):

|Operación|Ejecución|Red|Total|Ejecución con 1 %|Factor|
|-|-|-|-|-|-|
|L1|0,935|0|0,935|0,820|1,1x|
|L2|1,708|0|1,708|1,067|1,6x|
|L3\_principal|0,978|20|20,977|0,858|1,1x|
|L3\_replica|0,987|0|0,987|0,864|1,1x|
|L3\_sur|0,960|40|40,960|0,857|1,1x|
|L3\_sur\_rep|0,984|20|20,984|0,857|1,1x|
|L4\_desde\_B|31,318|25|56,318|1,949|16x|
|L4\_desde\_A|34,538|40|74,538|2,321|15x|
|L4\_A\_replicas|42,474|20|62,474|2,281|19x|
|L4\_B\_replicas|40,047|0|40,047|1,965|20x|
|E1|5,722|0|5,722|5,983|~1x|
|E2|3,075|0|3,075|4,693|~1x|

* **Las consultas por clave casi no cambian con 100 veces más datos.** L1 y L3 pasan de unos 0,8–0,9 ms a unos 0,9–1,0 ms, lo que concuerda con que usan índice. L2 sube algo más (1,6x), pero sigue en menos de 2 ms.
* **Los reportes globales (L4) se disparan.** Pasan de 2 ms a entre 31 y 42 ms de ejecución (15x a 20x), porque recorren muchos más datos.
* **Con réplicas, leer de otra zona sigue bajando la red.** El viaje de Centro se lee en la réplica de A en 0,99 ms en total, contra 20,98 ms en el principal. El de Sur se lee en la réplica de B en 20,98 ms, contra 40,96 ms en C.
* **El reporte global con réplicas ejecuta más lento, pero igual gana por la red.** Desde A baja de 74,5 a 62,5 ms con réplicas, y desde B con sus propias réplicas (solo para un cliente ya en B) cuesta 40,0 ms contra 56,3 ms sin réplicas. Las variantes con réplicas ejecutan más lento (42,5 y 40,0 ms contra 34,5 y 31,3 ms), y aun así ganan porque evitan latencia. La causa de este mayor tiempo de ejecución no se investigó, pero al repetir la prueba en una segunda PC con los datos completos se reprodujo el mismo patrón (reportes globales entre 23 y 40 ms y ganancia total de las réplicas entre 29 % y 35 %).
* **Con el 1 % la red supuesta dominaba; con 1,2M ya no en L4.** Antes la ejecución era de 1 a 6 ms frente a hasta 40 ms de red. Ahora, en L4, la ejecución (31 a 42 ms) es del mismo orden que la red.
* **Las escrituras no cambian de forma apreciable.** E1 y E2 varían bastante entre repeticiones, así que sus diferencias con el 1 % no deben leerse como tendencia. Con replicación asíncrona, el principal confirma sin esperar a la réplica.

### Costo ponderado con la mezcla 70/30

Se combinaron las medianas con las proporciones de la mezcla (35 % L1, 20 % L2, 10 % L3, 5 % L4, 25 % E1 y 5 % E2). Para L3 se usó el promedio de las dos zonas ajenas, como en 8.1/8.2:

|Costo por operación|Sin réplicas|Con réplicas|Reducción|
|-|-|-|-|
|Solo red (supuesta)|5,00 ms|2,00 ms|60 %|
|Ejecución medida|4,08 ms|4,48 ms|-10 % (sube)|
|Red supuesta + ejecución medida|9,08 ms|6,48 ms|29 %|

* **Sin réplicas:** L3 = promedio de `L3_principal` y `L3_sur`, y L4 = `L4_desde_A`.
* **Con réplicas:** L3 = promedio de `L3_replica` y `L3_sur_rep`, y L4 = `L4_A_replicas`.
* Para comparar: con el 1 % el costo total bajaba de 7,43 a 4,43 ms (40 %). Con 1,2M baja de 9,08 a 6,48 ms (29 %). La reducción de red es la misma (60 %), pero ahora la ejecución sube un 10 % con réplicas y se come parte del beneficio. Casi toda la ejecución ponderada viene de L4 (1,73 ms sin réplicas y 2,12 ms con réplicas) y de E1 (1,43 ms).

**Comparación con las estimaciones de las actividades anteriores** (solo red):

|Fuente|Sin réplicas|Con réplicas asíncronas|Reducción|
|-|-|-|-|
|Estimado en 8.1/8.2 y 8.3 (clientes de las tres zonas)|4,48 ms|1,73 ms|61 %|
|Calculado en 9.2 con latencias supuestas (cliente en A)|5,00 ms|2,00 ms|60 %|

Los 5,00 y 2,00 ms de solo red no son una medición independiente: salen de las mismas latencias supuestas, aplicadas a un cliente en A, un nodo extremo, por eso son mayores que los 4,48 y 1,73 ms estimados. Lo medido de verdad es la ejecución en el nodo. El resultado sigue siendo consistente con el modelo, pero con los datos de diseño la ganancia total de las réplicas es del 29 % y no del 40 %, porque el costo de ejecutar el reporte global ya pesa.

### Limitaciones

* **La red no se mide, se supone.** Las latencias son las de la rúbrica; no hay medición de red real entre los nodos.
* **Se midió un solo cliente (A).** Los clientes de Centro (B) y Sur (C) no se midieron, por lo que el costo ponderado no es comparable uno a uno con el de 8.1/8.2 y 8.3, aunque sí lo es la reducción.
* **No se midió la replicación síncrona.** Fabricio la estimó en 8,18 ms por operación en 8.3; aquí solo se midió la asíncrona.
* **No se revisó el retraso de la replicación.** En `verificar.sql` el retraso salió vacío y las réplicas igualaron a sus principales; no se midió su valor. En una caída de nodo podrían perderse las últimas escrituras.
* **Con 10 repeticiones el ruido es importante.** Hay valores sueltos altos (por ejemplo, un E1 de 18 ms en la primera repetición); la mediana lo absorbe, pero las diferencias pequeñas no son concluyentes.
* **No se midió el Extendible Hashing.** Las consultas usan la clave primaria (B-tree) y el índice sobre `(id_ruta, salida)`. La estructura de `pg_hashing` vive en la memoria de cada sesión y no se replica (8.3, sección 5); su comparación con el B-tree queda para la 10.1.
* **Un solo equipo.** Los tres nodos comparten la misma PC, así que se disputan CPU y disco, y las mediciones pueden variar entre corridas.
* **No se investigó por qué L4 ejecuta más lento con réplicas.** El comportamiento se confirmó al reproducir las pruebas en una segunda PC con los 1 200 000 viajes, pero no se analizaron los planes de ejecución (`EXPLAIN ANALYZE`) para aislar su causa.

### Archivos

|Archivo|Qué contiene|
|-|-|
|`bench_9.2/resultados_9.2_1200k.csv`|Resultados crudos con 1,2M de viajes: una fila por operación y repetición|
|`bench_9.2/resultados_9.2.csv`|Resultados originales con el 1 %|
|`bench_9.2/consultas.sh`, `lib.sh`, `resumen.py`|Los mismos scripts de la 9.2, sin cambios|

El csv nuevo está ignorado por la regla `*.csv` del `.gitignore`, así que se subió con `git add -f`.

Para repetir las pruebas (con los nodos cargados con los 1 200 000 viajes, desde la raíz del repositorio):

```
export MSYS_NO_PATHCONV=1          # solo en Git Bash de Windows
REP=10 bash bench_9.2/consultas.sh
py bench_9.2/resumen.py
docker exec nodo_a psql -U postgres -d distribuido -c "DELETE FROM viajes_norte WHERE salida >= '2026-11-01';"
```

El script sobrescribe `bench_9.2/resultados_9.2.csv`: hay que copiar el resultado nuevo con otro nombre y restaurar el original con `git checkout -- bench_9.2/resultados_9.2.csv`. La última línea borra los viajes que inserta E1.

### Uso de IA

Se usó Claude (Anthropic) como apoyo para interpretar los resultados dado ya por las estructuras .sh y .py, aparte de cruzar información de las cargas entre el 1% y los 1 200 000 viajes. Yo me encargué de levantar los nodos, cargar los 1 200 000 viajes, correr las consultas previamente testeadas(9.2), revisar los resultados y limpiar los datos de E1 al terminar para que no salgan datos erroneos o extras a la prueba.