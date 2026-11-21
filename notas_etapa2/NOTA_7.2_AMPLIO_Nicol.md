
## Resultados 

**Entorno de Pruebas:**
* Procesador: 11th Gen Intel(R) Core(TM) i7-1185G7 @ 3.00GHz
* Memoria RAM: 16.0 GB
* Sistema Operativo: Windows 11 Pro (Git Bash)
* Motor de Base de Datos: PostgreSQL 18.6 (Docker)

**Metodología:**
Para garantizar una comparación justa, primero se cargó el dataset completo en la estructura de memoria de la sesión activa y luego se midió exclusivamente el tiempo de las inserciones nuevas (W3, equivalentes al 10% del tamaño inicial). El tiempo promedio reportado se calculó sumando los tiempos en milisegundos de las 5 repeticiones y dividiendo el resultado entre 5.

### 1. Dataset base: 100,000 filas | Inserciones nuevas (W3): 10,000
* **B-Tree tradicional:** ~21.08 ms
* **Extendible Hashing (pg_insertar):** ~5.63 ms

### 2. Dataset base: 500,000 filas | Inserciones nuevas (W3): 50,000
* **B-Tree tradicional:** ~120.40 ms
* **Extendible Hashing (pg_insertar):** ~20.95 ms

### 3. Dataset base: 1,000,000 filas | Inserciones nuevas (W3): 100,000
* **B-Tree tradicional:** ~182.32 ms
* **Extendible Hashing (pg_insertar):** ~50.90 ms
