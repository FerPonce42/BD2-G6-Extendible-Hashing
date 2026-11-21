## 6.3 Dónde conviene el B-tree y dónde nuestro hash en el escenario distribuido

*Análisis a partir de resultados que ya están en el repo: 5.2 y 7.1/7.2 (índice por sí solo) y 9.2 (escenario distribuido, estrategia por zona, 1 200 000 viajes), con apoyo de 10.1 y 10.3 para el contexto. No se hicieron experimentos nuevos.*

### 1. Qué dicen las mediciones del índice (5.2, 7.1, 7.2)

Medianas de 5 repeticiones, D2 de 100 000, 500 000 y 1 000 000 filas.

| Medida | Fuente | B-tree | Hash (pg_hashing) | Sin índice |
|---|---|---|---|---|
| Búsqueda por igualdad, 1 000 000 filas (µs por consulta, ambos vía SQL) | 5.2 | 3,83 | 1,18 (3,2× más rápido) | 29 108 |
| Costo propio de la estructura, sin pasar por el ejecutor (µs) | 5.2 | — | 0,15 a 0,22 | — |
| Construcción, 1 000 000 filas (ms) | 5.2 | 389,3 | 308,4 (1,3×; era 2,8× con 100 000) | — |
| Inserciones W3, 100 000 sobre 1 000 000 filas (µs por inserción) | 7.2 / 7.1 | 1,84 | 0,50 (3,7×) | 0,48 |
| Tamaño por clave (bytes) | 5.2 | 22,5 (medido) | 7,6 (estimado) | — |

El hash gana en búsqueda por igualdad, construcción e inserción. Pero la comparación **no es entre índices equivalentes**, y eso pesa más que los factores de la tabla:

- `pg_hashing` vive en la memoria de **una sesión** (`dir_global` es una variable estática del proceso). No es persistente, no se comparte entre conexiones, no pasa por WAL y por eso no se replica.
- `pg_buscar` solo responde si la clave existe. No devuelve la fila ni su ubicación; para leer el viaje hay que ir igual a la tabla.
- Solo admite claves `INTEGER`, no tiene operación de borrado y no sirve para rangos ni orden.
- La inserción del B-tree incluye insertar la fila en la tabla; la del hash solo actualiza la estructura. Además, 7.1 y 7.2 se corrieron en PC distintas, así que la inserción "sin índice" es solo una referencia.

### 2. Qué dicen las mediciones del escenario distribuido (9.2)

Medianas de 10 repeticiones, zona con réplicas, cliente en A, 1 200 000 viajes. El tiempo de ejecución es el que reporta PostgreSQL en el nodo.

| Operación (peso) | Ejecución (ms) | Red según rúbrica (ms) |
|---|---|---|
| L1, viaje de la propia zona por `id_viaje` (35 %) | 0,935 | 0 |
| L2, ruta + rango de fechas (20 %) | 1,708 | 0 |
| L3, viaje de otra zona (10 %) | 0,987 (réplica) | 0 (réplica en A) o 20 (réplica en B) |
| L4, reporte global (5 %) | 42,5 | 20 |
| E1, inserción (25 %) | 5,722 | 0 |
| E2, actualización (5 %) | 3,075 | 0 |

Con estos números se puede dimensionar cuánto importa el índice:

- **El costo de la búsqueda en el índice es una fracción mínima de la consulta.** Según 5.2, el B-tree gasta unos 3,8 µs por búsqueda; L1 tarda 935 µs. El índice es el 0,4 % de L1. Pasar todas las búsquedas puntuales (L1, L3 y E2, el 50 % de la mezcla) a un hash ahorraría unos 2,65 µs cada una, es decir **0,0013 ms por operación ponderada**, sobre un costo total de 6,476 ms (0,02 %).
- **La red y los barridos dominan el costo.** Una lectura remota suma 20 a 41 ms, unas 20 a 40 veces lo que tarda en ejecutarse. L4 recorre las tablas completas (42,5 ms) y ningún índice lo acelera. En 10.3 los nodos se saturaron con entre 179 y 310 operaciones por segundo en total, según la corrida. L4 es una explicación probable (cada L4 barre los tres fragmentos), pero no se midió por separado, así que no se puede afirmar que sea la causa.
- **E1 cuesta 5,7 ms** frente a 0,5 a 2 µs del índice. El resto es la transacción, el WAL y la publicación a las réplicas, que un hash en memoria no elimina.

### 3. Dónde conviene cada uno

| Operación | Índice | Razón |
|---|---|---|
| **L2** (ruta y rango de fechas) | **B-tree** `(id_ruta, salida)` | Necesita rango y orden; el hash no los soporta. |
| **L1, L3, E2** (por clave) | **B-tree hoy; hash solo si fuera persistente** | El hash es 3,2× más rápido, pero la ganancia (2,65 µs) es despreciable frente a 0,9 ms de consulta y 20 a 40 ms de red. |
| **E1** (inserción) | **B-tree** | El hash inserta unas 3,7× más rápido en 7.2, pero sin fila, sin WAL y sin réplica. Con ids crecientes, el B-tree inserta casi siempre al final de la hoja. |
| **L4** (reporte global) | **Ninguno** | Es un barrido completo. |
| **Claves primarias** | **B-tree** | PostgreSQL lo crea y lo mantiene con la restricción. |

Por qué el hash no se puede usar hoy en el escenario distribuido:

1. **Sesión y memoria.** En 10.3 cada nodo recibe 32 conexiones de `pgbench`; cada una sería una sesión con su propio directorio vacío.
2. **Réplicas y caídas.** Lo que se replica por replicación lógica son tablas e índices de PostgreSQL. El directorio no se copia a B, por lo que las lecturas desviadas a la réplica (8.3) no pueden usarlo, y se pierde al caer el nodo (10.2).
3. **Consultas de la prueba.** En 10.3, L1 y E2 se escribieron con `id >= r` porque los ids de cada zona están salteados. Esa forma solo la resuelve un B-tree. Es una decisión de la prueba y no una propiedad del escenario, así que este punto no pesa tanto como los dos anteriores.

Para que valiera la pena, el hash tendría que ser persistente, devolver la ubicación de la fila y poder replicarse. Entonces sería útil para igualdad pura sobre claves enteras en L1, L3 y E2, en nodos donde las búsquedas puntuales fueran el cuello de botella. 10.3 no muestra que las búsquedas puntuales sean el cuello de botella: la saturación no se atribuyó a ninguna operación (L4 es una hipótesis, no medida por separado).

### 4. Fragmentación hash (10.1) no es lo mismo que nuestro índice

La estrategia "hash" de 10.1 reparte por `id mod 3`; no usa Extendible Hashing. Cuesta **30,6 ms** por operación ponderada contra **6,5 ms** de la zona con réplicas (4,7×), sobre todo por la red: L1 pasa de 0,9 a 21,2 ms y L2 de 1,7 a 42,9 ms, porque dos de cada tres accesos salen del nodo y L2 tiene que preguntar a los tres. A cambio, reparte la carga por diseño. Esa ventaja **no se midió**: 10.3 no incluye la estrategia hash, solo la de zona. Así que el B-tree sobre cada fragmento sirve con cualquiera de las dos estrategias, y el hash no cambia esa decisión.

### 5. Conclusión

- **Índice por defecto en todos los nodos: B-tree.** Cubre rangos (L2), claves primarias, inserciones con WAL y réplicas, que es lo que el escenario necesita.
- **Nuestro hash gana en laboratorio** (3,2× en búsqueda, y 3,7× en inserción, aunque ahí el hash no incluye la fila), pero en el escenario distribuido esa ventaja es de microsegundos frente a ms de consulta y de red, y no cumple los requisitos de persistencia y replicación.
- **Lugar posible para el hash:** búsqueda por igualdad sobre claves enteras en lecturas L1/L3/E2, si se hiciera persistente, replicable y devolviera la fila.

### 6. Limitaciones

- Las cifras de 5.2, 7.1/7.2 y 9.2 salen de PC y corridas distintas (5.2 en i5-13420H, 7.1 en i5-12450H, 7.2 sin CPU registrado); se comparan órdenes de magnitud, no décimas.
- El tiempo de ejecución de 9.2 incluye el costo fijo de planificar y ejecutar cada consulta; por eso se usa como cota para el peso del índice, no como medición de él.
- El tamaño del hash (7,6 bytes por clave) es una estimación a partir del código (5.2, sección 4.4).
- 10.3 ya tiene resultados de capacidad y latencia, pero no atribuyen la saturación a ninguna operación. Que L4 domine el CPU es una hipótesis (informe 10.3, secciones 4 y 7) y no se usa aquí como argumento.
- La estrategia hash de 10.1 no se midió bajo carga en 10.3, así que su ventaja de reparto parejo queda sin comprobar.
