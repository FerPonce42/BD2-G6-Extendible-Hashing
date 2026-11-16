## Generador y carga de la estrategia hash (10.1)

*Responsable: Iair Suico (actividad 10.1, parte del generador y la carga)*

La actividad 10.1 compara las dos estrategias de fragmentación de 8.1/8.2: por zona (la elegida) y por hash del identificador (la alternativa 2). En esta parte agregué la estrategia hash al generador y al script de carga de la semana 9, para que Nicol pueda correr la mezcla 70/30 en las dos con los mismos datos. Los cambios están en la carpeta `generador/`.

### Qué cambia

- **`generar_distribuido.py`** tiene un segundo argumento, la estrategia (`zona` o `hash`). Con `hash`, cada bus va al fragmento `id_bus mod 3` y cada viaje al fragmento `id_viaje mod 3`, como en la sección 3.3 del informe de 8.1/8.2.
- **`cargar_distribuido.sh`** recibe la estrategia como argumento y carga cada fragmento en su nodo.

| Fragmento | Contenido | Nodo | Filas |
|---|---|---|---|
| `buses_h0`, `viajes_h0` | `id mod 3 = 0` | A | 33 333 / 400 000 |
| `buses_h1`, `viajes_h1` | `id mod 3 = 1` | B | 33 334 / 400 000 |
| `buses_h2`, `viajes_h2` | `id mod 3 = 2` | C | 33 333 / 400 000 |
| `conductores` | completa | B (principal) | 5 000 |

Los archivos quedan en `data/distribuido_hash/`, aparte de los de la estrategia por zona (`data/distribuido/`).

### Decisiones

- **Los datos son exactamente los mismos en las dos estrategias.** Se usa la misma semilla y se generan las mismas filas en el mismo orden; solo cambia el archivo en el que cae cada fila. Así la diferencia que mida Nicol se debe a la fragmentación y no a los datos. Lo comprobé: ordenadas, las filas de los tres CSV de cada estrategia son idénticas (mismo MD5), y `conductores.csv` es igual byte a byte.
- **La estrategia por zona no cambió.** Los siete CSV de `data/distribuido/` salen idénticos a los de la semana 9 (mismo MD5), así que la carga y las mediciones de 9.1 y 9.2 siguen valiendo.
- **h0 en A, h1 en B, h2 en C.** Con hash el reparto es parejo (400 000 viajes por nodo), así que no hay una zona más usada que poner en el nodo central. `conductores` se carga en B, como en la estrategia por zona.
- **`conductores` en A y en C.** Si el nodo tiene suscripciones, el script espera la réplica, como en la estrategia por zona. Si no tiene ninguna, carga ahí el mismo `conductores.csv`. Así funciona tanto si los nodos hash replican `conductores` como si no.
- **Los nombres de las tablas (`buses_hK`, `viajes_hK`) son una propuesta.** Las tablas de los nodos hash las arma Maricielo. Si usa otros nombres, basta cambiarlos en las listas `HASH` del generador y `FA`, `FB` y `FC` del script de carga.

### Pruebas

- **Generador.** Con el tamaño de diseño tarda unos 9 s y reparte 400 000 viajes por fragmento. Todos los viajes de `viajes_h1.csv` cumplen `id_viaje mod 3 = 1`, y lo mismo en los otros dos.
- **Carga hash.** La probé en una simulación de los tres nodos (tres bases en un PostgreSQL local), con tablas `buses_hK` y `viajes_hK` que tienen un `CHECK (id mod 3 = K)` y una clave foránea a `conductores`, sin replicación. Cargó todo en unos 28 s y cada nodo quedó con las filas de su CSV, incluidos los 5 000 conductores en los tres.
- **Carga por zona.** La volví a probar en una simulación con las tablas, las publicaciones y las suscripciones de `nodos/sql/` y terminó con `OK`, igual que antes.

### Limitaciones

- **Todavía no se probó en los nodos hash de Docker**, porque los arma Maricielo en esta misma semana. Cuando estén, hay que correr la carga ahí y revisar que los nombres coincidan.
- **En la estrategia hash no puede haber clave foránea entre un viaje y su bus**, porque casi nunca están en el mismo nodo (es la pérdida de localidad de la sección 3.3 de 8.1/8.2). La regla "la ruta del viaje es la ruta de su bus" la sigue garantizando el generador, pero en los nodos ya no la controla la base.

### Uso

Desde la raíz del repositorio, en Git Bash, con los nodos de la estrategia hash levantados:
```
python generador/generar_distribuido.py 1 hash
export MSYS_NO_PATHCONV=1
bash generador/cargar_distribuido.sh hash
```
La estrategia por zona se sigue usando igual que antes (sin argumentos).

### Uso de IA

Usé Claude (Anthropic) como apoyo para agregar la estrategia hash al generador y al script de carga, y para redactar este informe. Revisé que las dos estrategias tuvieran las mismas filas comparando sus CSV y que la estrategia por zona no cambiara.
