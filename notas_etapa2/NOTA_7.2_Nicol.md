# 7.2 Evaluación de Inserciones: Extendible Hashing vs B-Tree (Nicol Rocha)

**Fecha:** 24/10/2026
**Rama:** `Nicol-7.2`
**Entorno:** Intel Core i7-1185G7, 16 GB RAM, Windows 11 Pro (Git Bash). PostgreSQL 18.6 (Docker).

## Objetivo de la prueba
Medir el tiempo de inserción de claves nuevas (carga W3, equivalente al 10% del tamaño del dataset) en ambas estructuras. Para garantizar una medición justa, los datasets D2 se cargaron previamente en la memoria de la misma sesión antes de tomar los tiempos. Se evaluaron tres tamaños base (100k, 500k, 1M) con 5 repeticiones cada uno.

## Resultados 
Se reporta el tiempo promedio (en milisegundos) de las 5 repeticiones. Este tiempo abarca exclusivamente la carga W3, descartando la construcción inicial.

| Dataset Base | Inserciones W3 | Promedio B-Tree (ms) | Promedio Hash (ms) |
|---|---|---|---|
| 100 000 | 10 000 | 21,08 | 5,63 |
| 500 000 | 50 000 | 120,40 | 20,95 |
| 1 000 000 | 100 000 | 182,32 | 50,90 |

**Análisis:**
El Extendible Hashing (`pg_insertar`) superó el rendimiento del B-Tree nativo en todos los volúmenes. En el dataset de 1 millón, el hash asimiló 100 000 inserciones nuevas en ~51 ms, siendo 3,5 veces más rápido que el B-Tree (~182 ms). El árbol sufre una mayor degradación de rendimiento por el costo logarítmico del rebalanceo estructural ante inserciones masivas.

## Ajustes de Implementación
- **Aislamiento de sesiones:** Se corrigió la medición de la estructura Hash incluyendo un paso previo de carga total en el mismo bloque SQL (`\timing off`), evitando que el contenedor reiniciara la memoria temporal.
- **Entorno estricto:** Se forzó la reconstrucción del servicio (`docker-compose up --build`) para reemplazar la instancia local desactualizada y garantizar la compilación de la extensión C nativa sobre PostgreSQL 18.6.

## Uso de IA
Se utilizó Gemini como herramienta de apoyo técnico puntual para depurar bloqueos de memoria en el subsistema WSL/Docker Desktop y validar reglas de sintaxis de Bash.