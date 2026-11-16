## Prueba de indisponibilidad de un nodo

*Responsable: Iair Suico (actividad 10.2)*

En esta parte se apagó cada uno de los tres nodos de la 9.1, con los 1 200 000 viajes del generador cargados, para ver qué parte de la mezcla 70/30 de 8.1/8.2 sigue funcionando, cuánto cuesta y qué pasa al volver. Además, se simuló una caída definitiva de B, el nodo central, con la promoción de su réplica según el plan de la 8.3. Todo está en la carpeta `caida_10.2/`.

### Entorno

- PC con Windows 11 y los tres nodos en Docker (PostgreSQL 18.6, extensión `pg_hashing`), levantados con `nodos/docker-compose.yml`.
- Datos: los del generador (semilla 42): 360 000 viajes en A (Norte), 480 000 en B (Centro) y 360 000 en C (Sur), cada zona con su réplica (Norte y Sur en B, Centro en A) y `conductores` en B con réplicas en A y en C.
- Latencias: las de la rúbrica (A-B = 20 ms, A-C = 40 ms y B-C = 25 ms), tomadas de `bench_9.2/lib.sh`, igual que en la 9.2.

### Cómo se midió

El script `caida_nodo.sh` corre la mezcla de 8.1/8.2 para **los clientes de las tres zonas**: L1 (35 %), L2 (20 %), L3 (10 %), L4 (5 %), E1 (25 %) y E2 (5 %), con 5 repeticiones cada una. Usa las mismas consultas y la misma forma de medir que la 9.2: ejecución medida con `\timing` y red supuesta según el nodo al que se conecta el cliente.

Cada cliente está en su zona. Si su nodo está caído, sigue en la misma zona, pero tiene que conectarse a otro nodo y paga esa latencia. Para las reglas de enrutamiento:
- **Lecturas** (L1, L2 y L3): se usa la copia viva más cercana del fragmento, sea la principal o la réplica.
- **Reporte global** (L4): cada zona se lee en su copia viva más cercana y en paralelo. Igual que en la 9.2, la ejecución es la del nodo más lento y la red, la del más lejano.
- **Escrituras** (E1 y E2): solo en la copia principal. Si está caída, la operación falla.

Hay dos modos:
- **Caída temporal** (`temporal`): `docker stop` del nodo, una ronda de la mezcla con el nodo caído, escrituras en los fragmentos que ese nodo replica, `docker start`, y se mide cuánto tarda en responder y en tener al día sus réplicas. No cambia la configuración.
- **Caída definitiva** (`promocion`): mientras B confirma escrituras una por una en `viajes_centro`, se hace `docker kill` (corte brusco). Después se promueve la réplica de A con los pasos de `replicacion/replicacion_nodos.sql`: se borra la suscripción para que la tabla pase a ser la principal. Se mide la promoción, las escrituras perdidas y la reconstrucción del Extendible Hashing en el nodo promovido.

`resumen_10.2.py` calcula, para cada estado, la **disponibilidad** (qué parte de la mezcla se pudo hacer) y el **costo ponderado** (ms por operación, solo de las que funcionaron).

### Resultados: caída temporal

Disponibilidad y costo ponderado por cliente (ms por operación):

| Nodo caído | Estado | Clientes Norte | Clientes Centro | Clientes Sur |
|---|---|---|---|---|
| A | normal | 100 %, 3,20 | 100 %, 2,86 | 100 %, 6,48 |
| A | caído | **70 %, 22,18** | 100 %, 2,92 | 100 %, 5,88 |
| A | recuperado | 100 %, 3,36 | 100 %, 2,42 | 100 %, 5,94 |
| B | normal | 100 %, 3,61 | 100 %, 2,93 | 100 %, 6,54 |
| B | caído | 100 %, 4,26 | **70 %, 22,89** | 100 %, 8,62 |
| B | recuperado | 100 %, 3,31 | 100 %, 2,59 | 100 %, 6,25 |
| C | normal | 100 %, 3,77 | 100 %, 2,76 | 100 %, 6,38 |
| C | caído | 100 %, 3,59 | 100 %, 2,84 | **70 %, 27,21** |
| C | recuperado | 100 %, 3,64 | 100 %, 2,57 | 100 %, 6,00 |

Vuelta del nodo (`docker start`):

| Nodo | Responde a los | Réplicas al día a los | Filas escritas mientras estaba caído |
|---|---|---|---|
| A | 0,7 s | 4,9 s | 1 010 (Centro y conductores) |
| B | 0,8 s | 4,9 s | 2 000 (Norte y Sur) |
| C | 0,7 s | 5,0 s | 10 (conductores) |

- **Cuando cae un nodo, sus clientes no pierden las lecturas, pero sí las escrituras.** Gracias a las réplicas de la 8.3, L1, L2, L3 y L4 siguen funcionando, y lo que falla son E1 y E2, que son el 30 % de la mezcla. Por eso la disponibilidad baja al 70 %, y no a 0 %, que es lo que pasaría sin réplicas.
- **Esas lecturas cuestan la latencia del otro nodo.** Con A caído, los clientes de Norte leen en la réplica de B: L1 pasa de 0,5 a 20,6 ms. Con C caído, los de Sur leen en B (25,7 ms). El costo ponderado de esos clientes sube de 3–6 ms a 22–27 ms.
- **Las otras zonas casi no lo notan.** Con A o C caídos, sus escrituras siguen yendo a su principal. Solo sube un poco el costo de quienes leían la zona caída: con B caído, los clientes de Sur hacen L3 en A (40,6 ms en vez de 25,7 ms) y L4 en A y C (55 ms en vez de 41 ms).
- **B es el nodo más crítico.** Su caída afecta a Centro, que es el 40 % del tráfico, y a la copia principal de `conductores`. Ponderando por el tráfico 30/40/30, la disponibilidad del sistema baja a 91 % si cae A o C (0,3 × 70 % + 0,7 × 100 %) y a 88 % si cae B (0,4 × 70 % + 0,6 × 100 %).
- **La vuelta es automática y rápida.** Las suscripciones se reconectan solas, y las filas pendientes llegan en unos 5 s. Este tiempo está redondeado al alza, porque se revisa una vez por segundo y cada revisión cuenta filas en los dos nodos. Después de volver, todas las operaciones funcionaron y los conteos quedaron iguales a los de antes.

### Resultados: caída definitiva de B con promoción

| Medida | Valor |
|---|---|
| Escrituras confirmadas por B antes del `docker kill` | 4 157 |
| Escrituras que llegaron a la réplica de A | 4 156 |
| **Escrituras perdidas** | **1** |
| Promoción (Centro y `conductores` a A, y C replicando `conductores` desde A) | 5,5 s |
| Reconstrucción del Extendible Hashing en A sobre `viajes_centro` | 484 161 claves en 77,6 ms |
| Conductor nuevo escrito en A y visto en la réplica de C | sí |

| Estado | Clientes Norte | Clientes Centro | Clientes Sur |
|---|---|---|---|
| normal | 100 %, 3,69 | 100 %, 2,76 | 100 %, 6,04 |
| caído (sin promover) | 100 %, 4,69 | 70 %, 22,95 | 100 %, 8,30 |
| promovido | 100 %, 4,20 | **100 %, 23,12** | 100 %, 8,26 |

- **Con la replicación asíncrona se pierde lo último que confirmó el nodo.** B confirmó 4 157 escrituras, pero solo 4 156 alcanzaron a llegar a A antes del corte. Si el cliente recibió la confirmación de esa última escritura, el dato está perdido después de promover. Es el riesgo que anotó la 8.3. Para evitarlo hace falta replicación síncrona, que en la 8.3 se estimó en 8,18 ms por operación.
- **La promoción es manual, pero rápida.** Los comandos tardaron 5,5 s. En la prueba, desde la caída pasaron 96,8 s, pero ese tiempo incluye la ronda de medición con B caído. En un caso real depende de cuánto se tarde en notar la caída, porque no hay detección automática.
- **Después de promover, Centro vuelve al 100 %,** pero sus clientes siguen pagando unos 20 ms por operación, porque ahora todo lo de Centro está en A. E1 y E2 pasan de fallar a costar 23–24 ms.
- **El Extendible Hashing se tiene que volver a armar.** Vive en la memoria de la sesión y no se replica (8.3, sección 5). En A se reconstruyó sobre los 484 161 viajes de Centro en 78 ms, y `pg_buscar` encontró una clave que existe y rechazó una que no existe.
- **Centro queda sin réplica.** Si ahora cae A, se pierde Centro hasta que B se rearme.

### Problemas y limitaciones

- **Con `docker exec -i`, la ventana de Git Bash se trabó.** La primera corrida quedó detenida después de 4 consultas: con `-i`, `docker exec` queda esperando una entrada desde la ventana. Lo quité y corrí las pruebas desde cmd con el `bash.exe` de Git, y así terminaron sin problemas.
- **La red no se mide, se supone.** Los tres nodos están en la misma PC. Igual que en la 9.2, la ejecución es medida y las latencias son las de la rúbrica.
- **La promoción definitiva solo se probó con B en Docker.** Es el caso más complejo, porque también mueve la copia principal de `conductores` y C pasa a replicar desde A. Las promociones de A y de C siguen el mismo procedimiento con una sola suscripción.
- **El nodo caído vuelve con datos que nadie más tiene.** Para contar sus escrituras confirmadas se levantó B un momento después de la promoción. Esa fila perdida existe en B pero no en A. Por eso, después de la caída definitiva hay que rearmar los nodos (`down -v` y volver a cargar). B no se puede volver a conectar tal como quedó.
- **5 repeticiones por operación**, con la mediana. Las diferencias de 1–2 ms entre rondas son ruido; lo que se lee en los resultados son los saltos de 20 ms o más que agrega la red.

### Archivos

| Archivo | Qué contiene |
|---|---|
| `caida_10.2/caida_nodo.sh` | La prueba (modos `temporal` y `promocion`) |
| `caida_10.2/resumen_10.2.py` | Disponibilidad, costo ponderado y detalle por operación |
| `caida_10.2/resultados/*.csv` | Resultados crudos: una fila por estado, cliente, operación y repetición |
| `caida_10.2/resultados/*.txt` | Tiempos y conteos de cada prueba, y el resumen (`resumen_10.2.txt`) |
| `caida_10.2/INFORME_10.2.md` | Este informe |

Para repetirla (desde la raíz del repositorio, con los nodos cargados con `generador/cargar_distribuido.sh`), en cmd:
```
set MSYS_NO_PATHCONV=1
"C:\Program Files\Git\bin\bash.exe" caida_10.2/caida_nodo.sh temporal A
"C:\Program Files\Git\bin\bash.exe" caida_10.2/caida_nodo.sh temporal B
"C:\Program Files\Git\bin\bash.exe" caida_10.2/caida_nodo.sh temporal C
"C:\Program Files\Git\bin\bash.exe" caida_10.2/caida_nodo.sh promocion B
"C:\Program Files\Git\bin\bash.exe" -c "python caida_10.2/resumen_10.2.py"
```
La prueba de promoción va al final, porque deja B apagado y la replicación cambiada.

### Uso de IA

Usé Claude (Anthropic) como apoyo para escribir el script de la prueba y el del resumen, y para redactar este informe. Le pasé la rúbrica (6.3 y 6.3.1) y los informes de 8.1/8.2, 8.3, 9.1 y 9.2. Yo corrí las pruebas en mis nodos de Docker con los 1 200 000 viajes, revisé los resultados y comprobé que los conteos volvieran a ser los de antes después de cada caída temporal.
