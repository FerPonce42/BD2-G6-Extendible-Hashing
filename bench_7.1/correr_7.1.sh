#!/bin/sh
# correr_7.1.sh
# Grupo 6 - BD2 - Actividad 7.1: experimentos sin indice (Fernando Ponce)
#
# Usa los scripts de benchmark/ sin modificarlos. Para cada dataset D2:
#   carga la tabla buses
#   00_preparar_claves.sql -> 20 000 claves (10 000 existen + 10 000 ausentes)
#   01_sin_indice.sql      -> busquedas sin indice (5 repeticiones)
#
# Uso (dentro del contenedor):
#   docker exec -w /app bd2_g6_hashing sh bench_7.1/correr_7.1.sh D2_aleatorio_500000
#   docker exec -w /app bd2_g6_hashing sh bench_7.1/correr_7.1.sh D2_aleatorio_1000000
# Traer resultados:
#   docker cp bd2_g6_hashing:/app/bench_7.1/resultados/. bench_7.1/resultados/

DATASETS=${*:-"D2_aleatorio_500000 D2_aleatorio_1000000"}
OUT=bench_7.1/resultados
PSQL="psql -U postgres -d hashing_db -X"

for ds in $DATASETS; do
    [ -f "data/$ds.csv" ] || { echo "[ERROR] Falta data/$ds.csv"; exit 1; }
done
for f in 00_preparar_claves.sql 01_sin_indice.sql; do
    [ -f "benchmark/$f" ] || { echo "[ERROR] Falta benchmark/$f (copia la carpeta benchmark al contenedor)"; exit 1; }
done

mkdir -p "$OUT"
{
    echo "Fecha:    $(date)"
    echo "Kernel:   $(uname -srm)"
    echo "CPU:      $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')"
    echo "Nucleos:  $(nproc)"
    echo "Memoria:  $(grep MemTotal /proc/meminfo | awk '{print int($2/1024) " MB"}')"
    echo
    $PSQL -c "SELECT version();"
    $PSQL -c "SELECT name, setting, unit FROM pg_settings WHERE name IN ('shared_buffers','work_mem','max_parallel_workers_per_gather','jit') ORDER BY name;"
} > "$OUT/00_entorno.txt" 2>&1

for ds in $DATASETS; do
    echo ">>> $ds"
    D="$OUT/$ds"; mkdir -p "$D"
    echo "Inicio: $(date)" > "$D/duracion.txt"
    echo "    inicio: $(date)"
    $PSQL -q -c "DROP TABLE IF EXISTS buses;" \
             -c "CREATE TABLE buses (id_bus INTEGER, placa VARCHAR(7), ruta VARCHAR(5), capacidad INTEGER);" \
             -c "\copy buses FROM 'data/$ds.csv' WITH (FORMAT csv, HEADER true)" || exit 1
    echo "    claves";      $PSQL -v n_consultas=20000 -f benchmark/00_preparar_claves.sql > "$D/00_claves.txt" 2>&1
    echo "    sin indice";  $PSQL -v reps=5 -f benchmark/01_sin_indice.sql > "$D/01_sin_indice.txt" 2>&1
    echo "Fin:    $(date)" >> "$D/duracion.txt"
    echo "    fin: $(date)"
    tail -n 6 "$D/01_sin_indice.txt"
done

echo "Listo. Resultados en $OUT/"
