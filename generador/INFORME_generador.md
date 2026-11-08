## Generador de datos del esquema distribuido

*Responsable: Iair Suico (semana 9, apoyo a 9.1 y 9.2; no estaba en el cronograma)*

La rúbrica pide que los datos de la parte distribuida salgan de un generador del repositorio. En esta parte escribí ese generador para las 4 relaciones de la actividad 8.1, y un script que carga lo generado en los nodos de la actividad 9.1. Todo está en la carpeta `generador/`.

### Qué genera

| Relación | Filas | Archivos | Nodo principal |
|---|---|---|---|
| `rutas` | 10 | — (ya las crea `01_comun.sql` en cada nodo) | A, B y C |
| `conductores` | 5 000 | `conductores.csv` | B |
| `buses` | 100 000 | `buses_norte.csv`, `buses_centro.csv`, `buses_sur.csv` | A, B y C |
| `viajes` (principal) | 1 200 000 | `viajes_norte.csv`, `viajes_centro.csv`, `viajes_sur.csv` | A, B y C |

Los buses y los viajes salen ya separados por zona, en un CSV por fragmento y con el mismo nombre que la tabla del nodo. Así cada archivo se carga directo en su nodo principal, sin pasar por una base global. Los archivos quedan en `data/distribuido/`, que está en el `.gitignore`: no se suben, cualquiera los vuelve a generar.

Con el argumento de escala se generan versiones más chicas. Con `0.01` salen exactamente los tamaños de prueba que usó la 9.1 (50 conductores, 1 000 buses y 12 000 viajes).

### Reglas que cumple

Son las de la sección 2 del informe de 8.1 y 8.2:
1. Cada bus trabaja en una sola ruta.
2. La ruta de cada viaje es la ruta de su bus. La clave foránea doble `(id_bus, id_ruta)` que agregó Maricielo en los nodos rechaza la carga si esto no se cumple.

Además, el reparto por zona es exactamente 30/40/30: cada ruta tiene 10 000 buses (3, 4 y 3 rutas por zona) y cada bus hace 12 viajes. Así salen 360 000, 480 000 y 360 000 viajes.

### Decisiones

- **Semilla fija (42).** Se generan siempre los mismos datos, como en el generador de la etapa I.
- **Los ids no van por bloques.** `id_bus` e `id_viaje` se reparten al azar entre las zonas, como pasaría en un sistema real. Por eso, para saber la zona de un viaje hay que mirar su `id_ruta` (el problema de ruteo de la sección 7 del informe de 8.1).
- **Fechas del 2026-01-01 al 2026-10-31**, entre las 05:00 y las 22:59. La prueba E1 de la 9.2 inserta viajes desde el 2026-11-01 y después los borra con `salida >= '2026-11-01'`, así que nunca toca los datos del generador.
- **`pasajeros` va de 0 a la capacidad del bus**, y la tarifa es fija por ruta (valores inventados, en soles).
- **`conductores`:** nombre armado con listas de nombres y apellidos, licencia única (`Q40000001`, …) y fecha de ingreso entre 2010 y 2025.

### Carga en los nodos

`cargar_distribuido.sh` sigue el orden que pide la 9.1:
1. Carga B (`conductores`, `buses_centro` y `viajes_centro`).
2. Espera a que la réplica de `conductores` llegue a A y a C (hasta 60 s). Si no llega, se detiene sin cargar nada.
3. Carga A (Norte) y C (Sur).
4. Cuenta las filas de cada tabla en los tres nodos, principales y réplicas, y las compara con los CSV.

Cada nodo se carga en una sola transacción con `COPY`, así que si algo falla no quedan datos a medias. Antes de empezar revisa que las tablas estén vacías, para no cargar dos veces.

### Pruebas

**Generador (tamaño completo).** Tarda unos 9 s y genera 58 MB. Cargué los CSV en una base con `esquema_global.sql` (con todas sus claves foráneas) y corrí `fragmentos.sql`:

| Relación | Norte (A) | Centro (B) | Sur (C) | Total |
|---|---|---|---|---|
| `rutas` | 3 | 4 | 3 | 10 |
| `buses` | 30 000 | 40 000 | 30 000 | 100 000 |
| `viajes` | 360 000 | 480 000 | 360 000 | 1 200 000 |

- La completitud y la disyunción se cumplen: la suma de los fragmentos y la unión sin repetidos dan el total.
- Hay 0 viajes con el bus en otra zona (co-localización) y 0 viajes con más pasajeros que la capacidad del bus.
- Las salidas van del 2026-01-01 05:00 al 2026-10-31 22:59.
- Los 5 000 conductores aparecen en algún viaje.
- Si se corre dos veces, salen archivos idénticos (mismo MD5).

**Carga en los nodos Docker de la 9.1 (PostgreSQL 18.6).** Levanté los nodos limpios con `nodos/docker-compose.yml`, creé las suscripciones, generé el tamaño completo y cargué. Después corrí `nodos/sql/verificar.sql` en cada nodo:

| Tabla | Nodo A | Nodo B | Nodo C |
|---|---|---|---|
| `rutas` | 10 | 10 | 10 |
| `conductores` | 5 000 (réplica) | 5 000 (principal) | 5 000 (réplica) |
| `buses_norte` / `viajes_norte` | 30 000 / 360 000 (principal) | 30 000 / 360 000 (réplica) | — |
| `buses_centro` / `viajes_centro` | 40 000 / 480 000 (réplica) | 40 000 / 480 000 (principal) | — |
| `buses_sur` / `viajes_sur` | — | 30 000 / 360 000 (réplica) | 30 000 / 360 000 (principal) |

- Cada réplica quedó con las mismas filas que su principal, y todas las suscripciones siguen recibiendo (`streaming`).
- En los tres nodos dio 0 viajes con una ruta distinta a la de su bus. La clave foránea doble tampoco rechazó ninguna fila.
- En total quedaron 1 200 000 viajes como principales, repartidos 360 000 / 480 000 / 360 000.

**Carga en la simulación.** Antes la probé en una simulación de los tres nodos: tres bases en un PostgreSQL local, con las tablas, los `CHECK`, la clave foránea doble y la replicación lógica que describe el informe de la 9.1. Cargó todo en unos 38 s, y los tres nodos quedaron con las mismas filas que los CSV, principales y réplicas. Al correrlo por segunda vez se detuvo porque las tablas ya tenían datos.

### Problemas y limitaciones

- **Si los nodos ya tienen los datos de prueba de la 9.1 (`datos_prueba.sql`), hay que levantarlos limpios** con `docker compose -f nodos/docker-compose.yml down -v`, después `up` y las suscripciones. Borrar a mano no sirve, porque las réplicas solo deben cambiar por la suscripción. El generador reemplaza a `datos_prueba.sql`; no se usan los dos juntos.
- **Git Bash se congeló durante la carga en Docker.** B cargó bien y los conductores llegaron a A y a C. Mientras se copiaba `viajes_norte.csv` a A, la ventana de Git Bash dejó de responder (los tres nodos estaban replicando a la vez) y `docker cp` se quedó esperando. Como cada nodo se carga en una sola transacción, A y C no tenían nada a medias. Cerré Git Bash y terminé A y C desde cmd con los mismos `docker cp` y `COPY` del script. Para que no vuelva a pasar, el script ya no muestra los mensajes de `docker cp`. Esa versión corregida no la volví a correr completa en Docker.
- **El orden importa.** Si se cargan A o C antes de que lleguen los conductores, la clave foránea rechaza los viajes. El script espera, pero si la suscripción no está creada, se detiene.
- **Los CSV pesan 58 MB.** No se suben al repositorio; se generan en unos segundos.

### Archivos

| Archivo | Qué contiene |
|---|---|
| `generador/generar_distribuido.py` | El generador (Python 3, sin librerías externas) |
| `generador/cargar_distribuido.sh` | La carga en los nodos principales y la verificación |
| `generador/INFORME_generador.md` | Este informe |

Para usarlo, desde la raíz del repositorio, en Git Bash:
```
docker compose -f nodos/docker-compose.yml down -v
docker compose -f nodos/docker-compose.yml up -d --build
# esperar unos segundos y crear las suscripciones (pasos 2 de nodos/docker-compose.yml)
export MSYS_NO_PATHCONV=1          # solo en Git Bash de Windows
docker exec nodo_a psql -U postgres -d distribuido -v nodo=A -f /nodos/suscripciones.sql
docker exec nodo_b psql -U postgres -d distribuido -v nodo=B -f /nodos/suscripciones.sql
docker exec nodo_c psql -U postgres -d distribuido -v nodo=C -f /nodos/suscripciones.sql
python generador/generar_distribuido.py
bash generador/cargar_distribuido.sh
```

### Uso de IA

Usé Claude (Anthropic) como apoyo para escribir el generador y el script de carga, y para redactar este informe. Le pasé la rúbrica (6.3.1), el informe de 8.1 y 8.2 y el de la 9.1. Revisé que los datos cumplieran las reglas de la 8.1 cargándolos con el esquema global y corriendo `fragmentos.sql`.
