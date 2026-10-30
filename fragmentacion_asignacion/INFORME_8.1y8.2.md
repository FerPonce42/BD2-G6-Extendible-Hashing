8.1 Fragmentación y 8.2 Asignación

Responsable: Iair Suico Carpeta: fragmentacion_asignacion/ Rúbrica: secciones 6.3 y 6.3.1 (tres nodos A, B y C; latencias A-B = 20 ms, A-C = 40 ms, B-C = 25 ms; al menos cuatro relaciones; relación principal con al menos 1 000 000 de registros; carga de 70 % lecturas y 30 % escrituras)

1. Qué hice
Definí el esquema de 4 tablas de la parte distribuida (esquema_global.sql), basado en la tabla buses de la etapa I.
8.1: decidí qué se fragmenta, cómo y con qué criterio. Comparé dos alternativas completas y descarté otras dos (sección 3).
8.2: asigné cada fragmento a un nodo usando las latencias de la rúbrica, y comparé las opciones con un cálculo del costo de red esperado (sección 4).
Escribí fragmentos.sql, que define los fragmentos como vistas sobre el esquema global y comprueba que la fragmentación es correcta: completitud, disyunción, reconstrucción y co-localización. Lo probé con datos sintéticos.

La replicación (8.3, Fabricio) y el levantamiento de los nodos (9.1) no son parte de esta entrega. En la sección 6 dejo lo que esas actividades necesitan de este diseño.

2. Esquema

Usé el mismo dominio de la etapa I (buses de transporte urbano), para que la tabla buses y las 10 rutas del generador (scripts/generar_datos.py) encajen sin cambios.

Relación	Filas	Clave	Relaciones
rutas	10	id_ruta	Cada ruta pertenece a una zona: Norte, Centro o Sur
conductores	5 000	id_conductor	—
buses	100 000	id_bus	id_ruta → rutas
viajes (principal)	1 200 000	id_viaje	id_bus → buses, id_conductor → conductores, id_ruta → rutas

La relación principal es viajes. Pasa del millón de registros que pide la rúbrica y es la que recibe casi todas las lecturas y escrituras. Tiene 1 200 000 filas en vez de 1 000 000 justo para pasar el mínimo con margen.

Las rutas se reparten en tres zonas, con los mismos códigos del generador:

Zona	Rutas	Proporción de buses y viajes
Norte	1A, 2B, 3C	30 %
Centro	5A, 7B, 10, 12C	40 %
Sur	15, 20A, C1	30 %

Las proporciones salen del generador actual, que elige la ruta de cada bus al azar entre las 10: 3, 4 y 3 rutas por zona dan 30/40/30.

Hay dos reglas que el generador de datos tiene que respetar:

Un bus trabaja siempre en una sola ruta.
viajes.id_ruta es la ruta del bus del viaje.

La ruta se guarda en el viaje para que, mirando solo esa fila, se sepa a qué fragmento va. La segunda regla garantiza que el viaje quede en el mismo nodo que su bus. fragmentos.sql comprueba las dos.

3. Fragmentación (8.1)
3.1 Qué se fragmenta y qué no
Relación	¿Se fragmenta?	Por qué
viajes	Sí, horizontal	Es la tabla grande y la que más se consulta
buses	Sí, horizontal	Cada viaje se cruza con su bus; conviene que estén en el mismo nodo
rutas	Sí, horizontal (define las zonas)	Es la que da el criterio de fragmentación
conductores	No	Son 5 000 filas y los usan todas las zonas; fragmentarla obligaría a ir a otro nodo cada vez que se cruza con un viaje. Es candidata a replicarse (8.3)
3.2 Alternativa 1 (elegida): horizontal por zona

La fragmentación es horizontal primaria en rutas, según el atributo zona, y horizontal derivada en buses y viajes, mediante un semijoin con el fragmento de rutas:

$$
\begin{aligned}
\text{rutas}_z &= \sigma_{\text{zona}=z}(\text{rutas}) \\
\text{buses}_z &= \text{buses} \ltimes_{\text{id\_ruta}} \text{rutas}_z \\
\text{viajes}_z &= \text{viajes} \ltimes_{\text{id\_ruta}} \text{rutas}_z
\end{aligned}
\qquad z \in \{\text{Norte}, \text{Centro}, \text{Sur}\}
$$

Así quedan 9 fragmentos (3 por relación), más conductores entera. El código está en fragmentos.sql.

La fragmentación es correcta según los tres criterios de la teoría:

Completitud: cada ruta tiene exactamente una zona (zona es NOT NULL y tiene un CHECK con las tres zonas). Por eso cada bus y cada viaje caen en algún fragmento.
Disyunción: una ruta no puede estar en dos zonas, así que ninguna fila queda repetida.
Reconstrucción: cada relación es la unión de sus tres fragmentos: $\text{viajes} = \text{viajes}_N \cup \text{viajes}_C \cup \text{viajes}_S$.

fragmentos.sql verifica las tres. Con datos sintéticos de 20 000 buses y 120 000 viajes, la suma de los fragmentos y su unión sin repetidos fueron iguales al total, y la regla de co-localización dio 0 viajes fuera de lugar. Cuando forcé un viaje con la ruta equivocada, la comprobación lo detectó.

Por qué este criterio:

Localidad. Las consultas de cada zona (los viajes de una ruta, los buses de una zona, insertar un viaje) se resuelven en un solo nodo.
Joins locales. viajes ⋈ buses ⋈ rutas de una misma zona no necesita ir a otro nodo, porque los tres fragmentos están juntos (por eso la fragmentación es derivada).
Reparto razonable. Queda 30/40/30, sin un nodo vacío.
3.3 Alternativa 2: horizontal por hash del identificador

viajes y buses se reparten según el resto de dividir su identificador entre 3:

$$\text{viajes}_k = \sigma_{\text{id\_viaje} \bmod 3 = k}(\text{viajes}), \qquad k \in \{0, 1, 2\}$$

Lo mismo para buses con id_bus. rutas y conductores no se fragmentan.

Esta alternativa tiene dos ventajas: el reparto queda perfectamente parejo (33 % por nodo) y no depende de cuánto se use cada zona. Pero pierde la localidad:

Una búsqueda por id_viaje solo es local en 1 de cada 3 casos.
Las consultas por ruta o por fecha tienen que preguntar a los tres nodos.
Un viaje y su bus casi nunca están en el mismo nodo, así que el join es remoto.
3.4 Alternativas descartadas
Horizontal por fecha (viajes recientes en un nodo e históricos en otro): concentra casi todas las escrituras y lecturas en el nodo de los recientes, que recibiría casi toda la carga.
Vertical (separar las columnas de viajes): la tabla tiene solo 7 columnas y las consultas leen casi todas a la vez. Separarlas obligaría a juntarlas siempre con un join entre nodos.
3.5 Comparación
Criterio	Alt. 1: por zona	Alt. 2: por hash
Operaciones que van a otro nodo (con la carga de 4.3)	15 %	75 %
Latencia de red esperada por operación (4.4)	≈ 4,5 ms	≈ 22,4 ms
Join viaje–bus	Local	Casi siempre remoto
Reparto de datos	30 / 40 / 30	33 / 33 / 33
Si cambia la concentración de accesos entre zonas	Se sobrecarga un nodo	No le afecta
Si cae un nodo	Se pierde una zona entera	Se pierde un tercio de todo

Decisión: Alternativa 1. Con las latencias de la rúbrica, la localidad pesa mucho más: reduce unas 5 veces la latencia de red esperada. Su punto débil (que una zona dependa de un solo nodo y que un nodo se cargue más si cambia la concentración de accesos) es justo lo que hay que medir en las pruebas de indisponibilidad (10.2) y de cambio de carga (10.3), y lo que la replicación (8.3) tiene que cubrir. La Alternativa 2 queda como la segunda estrategia para la comparación que pide la rúbrica (10.1).

4. Asignación (8.2)
4.1 Las latencias y el nodo central
Nodo	Latencia a A	a B	a C	Suma	Peor caso
A	—	20	40	60	40
B	20	—	25	45	25
C	40	25	—	65	40

B es el nodo central: tiene la menor suma de latencias y el menor peor caso. Una consulta que necesita a los tres nodos, coordinada desde B, espera como máximo 25 ms (si pregunta en paralelo). Coordinada desde A o desde C, espera 40 ms. A y C son los extremos (40 ms entre ellos), como un Norte y un Sur con el Centro al medio.

4.2 Asignación elegida
Nodo	Fragmentos	Proporción de los datos
A	rutas_norte, buses_norte, viajes_norte	30 %
B	rutas_centro, buses_centro, viajes_centro y la copia principal de conductores	40 %
C	rutas_sur, buses_sur, viajes_sur	30 %

Por qué así:

Centro va a B porque es la zona con más tráfico y B es el mejor coordinador de las consultas que necesitan a varios nodos (4.4).
Norte y Sur van a los extremos (A y C), que son los dos nodos más lejanos entre sí, igual que las dos zonas.
conductores va a B porque, desde B, los otros dos nodos están a 20 y 25 ms. Si estuviera en A, C quedaría a 40 ms. Si se replica a A y C, es decisión de la 8.3.
4.3 Carga de trabajo supuesta

Para comparar las opciones con números definí una mezcla de operaciones que cumple el 70/30 de la rúbrica. Supuse que los clientes de cada zona se conectan al nodo de su zona.

Operación	Tipo	Proporción	Con la Alt. 1
L1: leer un viaje de la propia zona por id_viaje	lectura	35 %	local
L2: viajes de una ruta propia en un rango de fechas	lectura	20 %	local
L3: leer un viaje o un bus de otra zona	lectura	10 %	1 nodo remoto
L4: reporte global (por ejemplo, pasajeros por zona)	lectura	5 %	los 3 nodos
E1: registrar un viaje en la propia zona	escritura	25 %	local
E2: actualizar un bus o un conductor	escritura	5 %	local (conductor: según 8.3)
Total		70 % lecturas / 30 % escrituras	

Con la Alt. 1 van a otro nodo L3 y L4, o sea, el 15 % de las operaciones. Con la Alt. 2, L1, L3, E1 y E2 son remotas en 2 de cada 3 casos, y L2 y L4 siempre preguntan a los tres nodos: en total, el 75 %. Esta mezcla es una propuesta; la 9.2 puede ajustarla, pero lo importante es usar la misma en las dos alternativas.

4.4 Costo de red esperado

Para cada operación sumé la latencia de los nodos que tiene que consultar:

L3 (otra zona): el promedio de la latencia a los otros dos nodos.
Consultas a los tres nodos (en paralelo): el peor caso.
Operaciones por identificador con hash: el promedio de la latencia al nodo que corresponde, que puede ser el propio.

Después lo ponderé por el tráfico de cada zona (30/40/30).

Opción	Latencia de red esperada por operación
Alt. 1, con Centro en B (elegida)	4,48 ms
Alt. 1, con Centro en A	4,62 ms
Alt. 1, con Centro en C	4,65 ms
Alt. 2 (hash, repartido entre A, B y C)	22,38 ms

Este cálculo supone que conductores está replicada en los tres nodos. Por eso cuento como locales los joins de un viaje con su conductor y la actualización de un conductor (E2). Si conductores estuviera solo en B, esas operaciones serían remotas desde A y C y el costo subiría. La 8.3 tiene que confirmar esa réplica para que el número valga.

La diferencia grande la hace la fragmentación (de 22,4 a unos 4,5 ms). La asignación ajusta menos, pero en la misma dirección: poner la zona más usada en el nodo central es la mejor de las tres opciones. El cálculo es una estimación: solo cuenta la latencia de red, no el tiempo de ejecución en cada nodo. Los valores medidos tienen que salir de la 9.2 y la 10.1.

4.5 Qué pasa si cae un nodo o cambia la carga

Esta sección es información para la 8.3, la 10.2 y la 10.3.

Si cae B, se pierde la zona Centro (40 % de los datos), la copia principal de conductores y el mejor coordinador de los reportes globales. Es el nodo más crítico, así que conviene que la 8.3 lo replique primero.
Si cae A o C, se pierde su zona (30 %). Los reportes globales no pueden completarse sin réplica.
Si la concentración de accesos cambia (por ejemplo, Sur pasa de 30 % a 60 % del tráfico), C se sobrecarga mientras A y B quedan con poco trabajo. Con la Alt. 2 esto no pasaría. Es el caso que tiene que medir la 10.3.
5. Índices en cada fragmento

La rúbrica pide evaluar dónde conviene el B-tree y dónde nuestra estructura. Con este diseño:

Búsqueda por igualdad (id_viaje, id_bus), operaciones L1 y E1: es el caso de Extendible Hashing (pg_insertar y pg_buscar sobre el fragmento de cada nodo). Hay que tener en cuenta dos cosas. Vive en la memoria de la sesión y no es persistente. Además, pg_buscar solo dice si la clave existe; no devuelve la fila. Para leer el viaje completo hay que ir igual a la tabla.
Rango de fechas por ruta (L2): B-tree sobre (id_ruta, salida), porque nuestra estructura no soporta rangos.
Claves primarias: PostgreSQL ya crea un B-tree para cada PRIMARY KEY.
6. Lo que necesitan las otras actividades
8.3 (replicación, Fabricio): la asignación es la de la sección 4.2. Lo que sugiero replicar:
conductores y rutas a los tres nodos, porque son tablas chicas, casi solo de lectura y se usan en los joins.
Una réplica de cada fragmento de viajes en otro nodo, empezando por el de B. Por las latencias, la réplica de Norte (A) conviene en B (20 ms) y la de Sur (C) también en B (25 ms). La de Centro (B) puede ir en A o en C.
La decisión final es de la 8.3.
9.1 (nodos, Maricielo): cada nodo crea solo sus fragmentos. Los predicados están en fragmentos.sql. Como viajes tiene claves foráneas a buses y rutas y están en el mismo nodo, se pueden declarar. La clave foránea a conductores solo se puede declarar si hay una copia de conductores en ese nodo (depende de la 8.3).
Generador de datos: tiene que cumplir las dos reglas de la sección 2. fragmentos.sql sirve para comprobarlo.
9.2 (consultas, Nicol): la mezcla de la sección 4.3 sirve como base para las consultas locales y las que necesitan varios nodos.
7. Problemas y limitaciones
Saber a qué nodo ir. Con la Alt. 1, buscar un viaje solo por id_viaje no dice en qué zona está. Lo resolví suponiendo que el cliente conoce la ruta (y por tanto la zona) de lo que consulta. Si no la conoce, hay que preguntar a los tres nodos o tener un catálogo que asocie cada id con su zona. Otra opción es reservar rangos de id_viaje por zona.
Las claves foráneas no se pueden comprobar entre nodos. Por eso es importante la co-localización: la regla "la ruta del viaje es la ruta de su bus" se verifica con fragmentos.sql antes de cargar los nodos.
El costo de la sección 4.4 es una estimación. Solo cuenta la latencia de red con una mezcla supuesta de operaciones. Sirve para elegir entre opciones, no reemplaza la medición.
El reparto no es perfectamente parejo (B tiene el 40 %), y una zona depende de un solo nodo mientras no haya replicación.
8. Archivos
Archivo	Qué contiene
INFORME_8.1y8.2.md	Este informe
esquema_global.sql	Las 4 tablas, con claves y restricciones, y las 10 rutas con su zona
fragmentos.sql	Los 9 fragmentos como vistas y las comprobaciones de completitud, disyunción, reconstrucción y co-localización

esquema_global.sql se tiene que correr en una base aparte (por ejemplo, distribuido), no en hashing_db. Empieza con DROP TABLE IF EXISTS buses, así que en hashing_db borraría la tabla buses de la etapa I.

createdb -U postgres distribuido
psql -U postgres -d distribuido -f fragmentacion_asignacion/esquema_global.sql
psql -U postgres -d distribuido -f fragmentacion_asignacion/fragmentos.sql

fragmentos.sql se corre después de cargar los datos.

9. Uso de IA

Usé Claude (Anthropic) como apoyo para proponer y comparar las alternativas de fragmentación y asignación, hacer el cálculo del costo de red de la sección 4.4, escribir esquema_global.sql y fragmentos.sql, y redactar este informe. Revisé las decisiones contra la rúbrica (6.3 y 6.3.1) y probé los dos scripts en PostgreSQL con datos sintéticos, incluida una prueba que fuerza un error para comprobar que la verificación lo detecta.
