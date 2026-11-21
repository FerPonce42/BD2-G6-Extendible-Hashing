## Prueba de cambio de carga de trabajo (10.3)

 Fabricio Stelman (actividad 10.3)

### 1. Qué se prueba

8.1/8.2 (sección 4.5) y 8.3 (secciones 6 y 8) dejaron planteada esta prueba. Con la fragmentación por zona, cada zona depende de un solo nodo para sus escrituras. La hipótesis de 8.1/8.2 es que, si la concentración de accesos cambia (Sur pasa de 30 % a 60 % del tráfico), C se sobrecarga mientras A y B quedan con poco trabajo. 8.3 propone una palanca: mandar a la réplica en B las lecturas de Sur que hacen otras zonas y los reportes globales. La prueba mide:

1. Qué carga máxima sostiene el sistema antes y después del cambio, y **qué nodo se satura primero**.
2. Cuánto cambia eso con la palanca de 8.3, y cuánto sube la carga de B.
3. Qué parte no se puede descargar: las escrituras de Sur (la copia principal es una sola, C).

La comparación con la estrategia hash (reparto parejo por diseño) **no está incluida**: requiere los nodos hash de 10.1 y otra versión del script.

### 2. Escenario, carga de datos y cómo se midió

- **Datos cargados (`data/distribuido`):** Estrategia por zona verificada mediante `generador/cargar_distribuido.sh` con un total de **100 000 buses**, **1 200 000 viajes** y **5 000 conductores** replicados en los tres nodos:
  - `nodo_a` (Norte + réplica Centro): `buses_norte` (30 000), `viajes_norte` (360 000), `buses_centro` (40 000), `viajes_centro` (480 000).
  - `nodo_b` (Centro + réplicas Norte y Sur): recibe el 100 % de los fragmentos de buses y viajes (30 000 Norte, 40 000 Centro, 30 000 Sur).
  - `nodo_c` (Sur): `buses_sur` (30 000), `viajes_sur` (360 000).
- **Carga de trabajo:** Misma mezcla 70/30 de 8.1/8.2 (L1 35 %, L2 20 %, L3 10 %, L4 5 %, E1 25 %, E2 5 %). Los clientes de cada zona se conectan a su nodo y L3 lee de la zona siguiente (Norte→Centro, Centro→Sur, Sur→Norte), como en 10.2.
- **Reparto de tráfico:** **Base:** 30/40/30. **Cambio:** Sur 60 %; el 40 % restante se reparte entre Norte y Centro en la proporción 30:40 (17,1 % y 22,9 %).

| Corrida | Tráfico | Dónde se lee |
|---|---|---|
| `base / principal` | 30/40/30 | Todo en la copia principal |
| `sur / principal` | Sur 60 % | Todo en la copia principal |
| `sur / replica` | Sur 60 % | L3 y L4 en la réplica (8.3, sección 6); L1, L2 y escrituras en la principal |
| `sur / replica_sur` | Sur 60 % | Como la anterior, y además L1 y L2 de los clientes de Sur en B |

`replica_sur` no está en 8.3: se agregó para ver el máximo que se podría descargar a C. Cuesta lecturas posiblemente atrasadas para los propios clientes de Sur, algo que 8.3 evita a propósito.

**Método.** El script `carga_sur.py` usa `pgbench` con una tasa fija de operaciones por segundo en cada nodo (`--rate`): una sobrecarga se ve como operaciones no logradas y atraso, y no queda escondida por un cliente que espera. Cada nodo se limita a 1 CPU (`docker update --cpus=1`, se restaura al terminar) para que C no use CPU que A y B no usan. `pgbench` corre en un contenedor aparte. La red **no se mide**, se suma la de la rúbrica (A-B = 20 ms, A-C = 40 ms, B-C = 25 ms), igual que en 9.2 y 10.2. Hay tres modos:

- **`calibrar`:** mide cuánto aguanta cada nodo con la mezcla de `sur / principal` (sección 4).
- **`capacidad`:** en cada corrida sube la carga total en pasos de ×1,2 (30 s por paso) hasta que algún nodo se satura: logra < 90 % de lo ofrecido, atraso > 20 ms o fallas. Para no confundir ruido con saturación, el paso se repite y solo cuenta si satura en 2 intentos seguidos. La máxima es el último nivel sin saturación. Se repite la búsqueda 5 veces por corrida y se informa la mediana.
- **`correr`:** con una carga fija (`--total`), mide latencia, atraso y costo ponderado por operación, con 5 repeticiones de 30 s (mínimo de la rúbrica).

### 3. Lo que dice el modelo (`plan` — cálculo teórico)

Cuántas consultas le llegan a cada nodo por cada 100 operaciones del sistema (L4 cuenta como tres consultas, una por zona, sumando 110 consultas totales por cada 100 operaciones de usuario). Se incluye la proyección de `py carga_10.3/carga_sur.py plan --total 300`:

| Corrida | Consultas A / 100 ops | Consultas B / 100 ops | Consultas C / 100 ops | Carga A (`total=300`) | Carga B (`total=300`) | Carga C (`total=300`) | C respecto a la base |
|---|---|---|---|---|---|---|---|
| `base / principal` | 33,5 | 42,0 | 34,5 | 100,5 ops/s | 126,0 ops/s | 103,5 ops/s | ×1,00 |
| `sur / principal` | 25,6 | 26,1 | 58,3 | 76,7 ops/s | 78,4 ops/s | 174,9 ops/s | ×1,69 |
| `sur / replica` | 21,3 | 37,7 | 51,0 | 63,9 ops/s | 113,1 ops/s | 153,0 ops/s | ×1,48 |
| `sur / replica_sur` | 21,3 | 70,7 | 18,0 | 63,9 ops/s | 212,1 ops/s | 54,0 ops/s | ×0,52 |

Red esperada por operación con las latencias de la rúbrica: 4,5 ms (`base / principal`), 5,1 ms (`sur / principal`), 3,1 ms (`sur / replica`) y 11,4 ms (`sur / replica_sur`).

### 4. Calibración (medido)

Resultado de `py carga_10.3/carga_sur.py calibrar` (cada nodo, con 32 conexiones a máxima velocidad, 30 s, ejecutado con la mezcla de `sur / principal`):

| Nodo | Operaciones por segundo que aguanta | Latencia promedio |
|---|---|---|
| A | 134 ops/s | 238,21 ms |
| B | 102 ops/s | 314,38 ms |
| C | 266 ops/s | 120,36 ms |

A partir de estas mediciones, el script calculó una carga sugerida de `--total 387` (dimensionada para dejar a C al 85 % de su capacidad en `sur / principal`), arrojando la siguiente utilización esperada:

| Corrida | Utilización A | Utilización B | Utilización C |
|---|---|---|---|
| `base / principal` | 97 % | **160 %** | 50 % |
| `sur / principal` | 74 % | **100 %** | 85 % |
| `sur / replica` | 61 % | **144 %** | 74 % |
| `sur / replica_sur` | 61 % | **269 %** | 26 % |

**Hallazgo crítico de la calibración (problema detectado antes de correr la prueba):**

- **Capacidades bajas y dominancia de L4:** Los nodos soportan entre 102 y 266 ops/s. Esto se explica por **L4**: al ser un barrido completo sobre los fragmentos (`360 000` o `480 000` viajes según la zona) y ejecutarse **en los tres nodos por cada petición**, su peso en CPU es constante sin importar el reparto de tráfico. En `sur / principal`, L4 representa una fracción mucho mayor del total de consultas que reciben A y B (donde el tráfico transaccional cayó) en comparación con C (inundado de consultas rápidas L1/L2/E1), lo que penaliza artificialmente el throughput medido de A y B.
- **El nodo B aparece saturado en todos los escenarios:** Con la sugerencia de `--total 387`, **B supera el 100 % de utilización en las cuatro corridas** (160 % incluso en `base / principal` y 269 % en `sur / replica_sur`). Esto invalida ejecutar `correr` con `--total 387` directamente, ya que B colapsaría antes de permitir observar el comportamiento de C.
- **Necesidad de ajuste y modo `capacidad`:** Debido a que la capacidad de cada nodo varía según la proporción de L4 en cada corrida, no se puede usar un `--total` fijo basado únicamente en la mezcla `sur / principal`. Por ello se requiere ajustar el script / usar el modo `capacidad` para hallar el techo real de cada corrida paso a paso antes de fijar la carga de `correr`.

### 5. Resultados medidos

*Pendiente. Llenar con la salida de `py carga_10.3/carga_sur.py capacidad --rep 5 --inicio 60` y `correr --rep 5`.*

**5.1 Carga máxima que sostiene cada corrida (`capacidad`)**

| Corrida | Máxima (ops/s, mediana de 5) | Rango | Nodo(s) que se satura(n) primero |
|---|---|---|---|
| `base / principal` | | | |
| `sur / principal` | | | |
| `sur / replica` | | | |
| `sur / replica_sur` | | | |

La precisión es de un paso (×1,2).

**5.2 Latencia bajo una carga fija (`correr`)**

Carga usada: total = ___ ops/s (propuesta: el 80 % de la máxima medida de `base / principal`), Sur = 60 %, 30 s por corrida, 5 repeticiones.

| Corrida | Nodo | Ofrecidas | Logradas | Latencia (ms) | Atraso (ms) | Fallidas |
|---|---|---|---|---|---|---|
| `base / principal` | A / B / C | | | | | |
| `sur / principal` | A / B / C | | | | | |
| `sur / replica` | A / B / C | | | | | |
| `sur / replica_sur` | A / B / C | | | | | |

| Corrida | Ejecución (ms) | Red (ms) | Total por operación (ms) |
|---|---|---|---|
| `base / principal` | | | |
| `sur / principal` | | | |
| `sur / replica` | | | |
| `sur / replica_sur` | | | |

### 6. Conclusión

*A completar con los datos de la sección 5. Responderá: (a) qué nodo limita al sistema antes y después del cambio y si el cuello de botella real está en C o en B; (b) si la palanca de 8.3 (`sur / replica`) aumenta la capacidad total sostenida; (c) qué costo de saturación en B y latencia en Sur introduce `replica_sur`.*

### 7. Limitaciones

- **Un solo PC:** Los tres nodos comparten procesador, memoria y disco. El límite de 1 CPU por nodo reparte el procesador, pero no la E/S de disco ni la memoria.
- **La red es supuesta:** Las latencias de red son las definidas por la rúbrica.
- **Carga programada, no usuarios reales:** Las operaciones llegan a tasa fija (`--rate`), sin tiempo de reflexión ni reintentos.
- **L4 domina el CPU:** El barrido de L4 sobre tablas de 360k–480k registros consume mucho más CPU que su 5 % nominal y afecta por igual a los tres nodos, enmascarando parcialmente el desbalance por zona.
- **Primera corrida de `capacidad` descartada:** con pasos de 20 s, umbral de 95 % y sin confirmar, el ruido de `pgbench` (±5-8 % a 10-30 ops/s por nodo) marcaba saturaciones falsas desde 50 ops/s (por ejemplo, C "saturado" con 13 ops/s ofrecidas). Se endureció el criterio (90 %, 30 s, confirmación en 2 intentos) y se repitió; la corrida descartada queda en `resultados_corrida1/`.
- **Precisión de un paso:** `capacidad` escala la carga en factores de ×1,2 (margen de hasta 20 % entre pasos).
- **Sin comparación con hash y sin medición de lag de replicación:** No se mide el retraso de replicación lógica en B bajo picos de escritura en C.

### 8. Archivos y cómo repetir

| Archivo | Qué contiene |
|---|---|
| `generador/cargar_distribuido.sh` | Script de carga inicial y verificación de réplicas (`100 000` buses, `1 200 000` viajes) |
| `carga_10.3/carga_sur.py` | Modelo de carga (`plan`), calibración (`calibrar`), búsqueda de techo (`capacidad`) y prueba fija (`correr`) |
| `carga_10.3/INFORME_10.3.md` | Este informe |
| `carga_10.3/resultados/capacidad.csv` | Un paso de carga por fila y nodo (se crea al correr `capacidad`) |
| `carga_10.3/resultados/capacidad.txt` | Salida cruda de `pgbench` de cada paso y tabla resumen de `capacidad` |
| `carga_10.3/resultados/corridas.csv`, `scripts.csv`, `corridas.txt` | Resultados de `correr` (se crean al correr) |
| `carga_10.3/resultados_corrida1/` | Primera corrida de `capacidad`, descartada por ruido (ver sección 7) |
| `carga_10.3/resultados/resumen.txt` | Tablas de `resumen` (capacidad máxima, latencias y costo ponderado) |

Con los nodos levantados y cargados con `generador/cargar_distribuido.sh`, desde la raíz del repositorio:

```powershell
py carga_10.3/carga_sur.py plan --total 300
py carga_10.3/carga_sur.py calibrar
py carga_10.3/carga_sur.py capacidad --rep 5 --inicio 60
py carga_10.3/carga_sur.py correr --total <80 % de la máxima de base/principal> --rep 5
py carga_10.3/carga_sur.py resumen --total <el mismo>
```

### 9. Uso de IA
Se utilizó asistencia de IA (Claude y Gemini) para estructurar carga_sur.py, redactar y actualizar este informe a partir de las salidas reales de PowerShell (cargar_distribuido.sh, plan y calibrar) y diagnosticar el sesgo introducido por L4 en la calibración por nodo.