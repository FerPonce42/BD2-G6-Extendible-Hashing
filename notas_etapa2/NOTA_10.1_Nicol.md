# Actividad 10.1 — Comparación de estrategias de fragmentación (Zona vs. Hash)

*Responsable: Nicol Rocha | Carpeta: `bench_9.2/` | Volumen: 1 200 000 viajes*

## 1. Qué se hizo y configuración de prueba

Se ejecutó la mezcla de carga **70 % lecturas / 30 % escrituras** (definida en la actividad 8.1/8.2, sección 4.3) sobre los tres nodos Docker (`nodo_a`, `nodo_b`, `nodo_c`, base `distribuido`) con el volumen completo de diseño (**1 200 000 viajes**, **100 000 buses**, **5 000 conductores** y **10 rutas**) para comparar las dos alternativas de fragmentación:

* **Estrategia 1 (Horizontal derivada por Zona):** `viajes_norte` (360 000 filas en A), `viajes_centro` (480 000 filas en B) y `viajes_sur` (360 000 filas en C), con co-localización de buses y rutas por zona y replicación lógica entre nodos.
* **Estrategia 2 (Horizontal por Hash `id mod 3`):** `viajes_h0`, `viajes_h1` y `viajes_h2` con reparto uniforme (400 000 viajes por nodo) en A, B y C, replicando únicamente la tabla `conductores`.

Las pruebas se ejecutaron con cliente en el **Nodo A** (puerto `5433`), aplicando las latencias de la rúbrica ($A\text{-}B = 20\text{ ms}$, $A\text{-}C = 40\text{ ms}$, $B\text{-}C = 25\text{ ms}$), midiendo el tiempo interno del motor mediante `\timing on` de PostgreSQL en **10 repeticiones** (`REP=10`) por consulta y tomando la **mediana** de cada operación.

---

## 2. Resultados en la Estrategia 2 (Hash `id mod 3`)

Con hash por módulo del identificador, las operaciones puntuales (`L1`, `L3`, `E1`, `E2`) se resuelven localmente en A solo en 1 de cada 3 casos y viajan a B (`20 ms`) o C (`40 ms`) en los dos tercios restantes. Las consultas por ruta (`L2`) y el reporte global (`L4`) deben consultar los tres nodos en paralelo, quedando limitadas por el enlace más lento (`A-C = 40 ms`).

| Operación | Tipo | Destino | Ejecución (ms) | Red (ms) | Total (ms) |
| :--- | :--- | :--- | ---: | ---: | ---: |
| `L1_A` (lectura por `id_viaje`, mod 0) | Local | A | 1.157 | 0 | 1.157 |
| `L1_B` (lectura por `id_viaje`, mod 1) | Remoto | B | 1.276 | 20 | 21.276 |
| `L1_C` (lectura por `id_viaje`, mod 2) | Remoto | C | 1.075 | 40 | 41.075 |
| `L2` (rango de fechas por `id_ruta`) | Multinodo | A-B-C | 2.859 | 40 | 42.859 |
| `L3_A` (consulta puntual, mod 0) | Local | A | 1.109 | 0 | 1.109 |
| `L3_B` (consulta puntual, mod 1) | Remoto | B | 1.160 | 20 | 21.160 |
| `L3_C` (consulta puntual, mod 2) | Remoto | C | 1.100 | 40 | 41.100 |
| `L4` (suma global de pasajeros) | Multinodo | A-B-C | 40.450 | 40 | 80.450 |
| `E1_A` (inserción de viaje, mod 0) | Local | A | 7.834 | 0 | 7.834 |
| `E1_B` (inserción de viaje, mod 1) | Remoto | B | 10.831 | 20 | 30.831 |
| `E1_C` (inserción de viaje, mod 2) | Remoto | C | 7.642 | 40 | 47.642 |
| `E2_A` (actualización de bus, mod 0) | Local | A | 4.529 | 0 | 4.529 |
| `E2_B` (actualización de bus, mod 1) | Remoto | B | 3.506 | 20 | 23.505 |
| `E2_C` (actualización de bus, mod 2) | Remoto | C | 6.744 | 40 | 46.743 |

---

## 3. Comparación por operación (Zona con réplicas vs. Hash)

| Op. | Descripción | Peso | Zona ejec (ms) | Zona red (ms) | Zona total (ms) | Hash ejec (ms) | Hash red (ms) | Hash total (ms) |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **L1** | Lectura puntual por `id_viaje` | 35 % | 0.935 | 0.00 | **0.935** | 1.169 | 20.00 | **21.169** |
| **L2** | Viajes de una ruta en rango de fechas | 20 % | 1.708 | 0.00 | **1.708** | 2.859 | 40.00 | **42.859** |
| **L3** | Lectura de otra zona / puntual | 10 % | 0.986 | 10.00 | **10.986** | 1.123 | 20.00 | **21.123** |
| **L4** | Reporte global de pasajeros | 5 % | 42.474 | 20.00 | **62.474** | 40.450 | 40.00 | **80.450** |
| **E1** | Inserción de un nuevo viaje | 25 % | 5.722 | 0.00 | **5.722** | 8.769 | 20.00 | **28.769** |
| **E2** | Actualización de un bus | 5 % | 3.075 | 0.00 | **3.075** | 4.926 | 20.00 | **24.926** |

### Qué muestran los números

* **Localidad y uso del índice B-tree (`L2`):** En Zona, todos los viajes de una ruta viven en un solo nodo y usan directamente el índice compuesto `(id_ruta, salida)` sin red (`1.708 ms`). En Hash, la misma ruta queda repartida entre los tres contenedores y obliga a consultar los tres nodos (`42.859 ms`, 25 veces más lento).
* **Operaciones frecuentes (`L1` y `E1`, 60 % de la carga):** En Zona se resuelven en el nodo local sin latencia de red (`0.935 ms` y `5.722 ms`), mientras que en Hash 2 de cada 3 peticiones cruzan la red (`21.169 ms` y `28.769 ms`).
* **Balanceo frente a co-localización:** Hash logra repartir exactamente el almacenamiento (`33.3 %` por nodo frente al `30 / 40 / 30 %` de Zona), pero rompe la co-localización entre viajes y buses (solo `33.3 %` locales frente al `100 %` en Zona) y dispara el tráfico entre nodos.

---

## 4. Costo ponderado total (Mezcla 70/30)

| Estrategia | Ejecución ponderada (ms) | Red ponderada (ms) | Total ponderado (ms) |
| :--- | ---: | ---: | ---: |
| **Estrategia 1: Zona (sin réplicas)** | 4.077 | 5.000 | **9.077** |
| **Estrategia 1: Zona (con réplicas)** | 4.476 | 2.000 | **6.476** |
| **Estrategia 2: Hash (`id mod 3`)** | 5.554 | 25.000 | **30.554** |

* **Contraste con el modelo teórico (8.1/8.2, sección 4.4):** El diseño estimó `4.48 ms` de red esperada en Zona frente a `22.38 ms` en Hash (~5 veces mayor). Las mediciones reales desde el Nodo A (`5.000 ms` sin réplicas / `2.000 ms` con réplicas vs. `25.000 ms` en Hash) confirman esa diferencia: en Hash la red representa el **81.8 %** del tiempo total (`25.000 ms` de `30.554 ms`), mientras que la fragmentación por zona reduce el tiempo total ponderado en un **78.8 %** (`6.476 ms` frente a `30.554 ms`).

---

## 5. Archivos de esta entrega

* `bench_9.2/consultas_hash.sh`: script de ejecución de la mezcla 70/30 sobre los fragmentos `h0`, `h1` y `h2`.
* `bench_9.2/resultados_10.1_hash.csv`: mediciones crudas (10 repeticiones por operación) en la estrategia Hash.
* `bench_9.2/resumen_10.1.py`: cálculo de medianas y comparación ponderada contra `resultados_9.2_1200k.csv`.

## 6. Uso de IA

Se usó Claude y Gemini (IA) como apoyo para adaptar los scripts (consultas_hash.sh y resumen_10.1.py) a las tablas de hash y dar formato a las tablas comparativas. Por mi parte, yo me encargué de levantar los contenedores, generar y cargar los 1 200 000 viajes, correr las repeticiones en los tres nodos, limpiar los datos de prueba de E1 y analizar los resultados frente a la estrategia por zona y resultados previamente optenidos en la parte de 9.2.