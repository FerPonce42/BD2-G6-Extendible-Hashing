#!/bin/sh
# correr_5.2.sh
# Grupo 6 - BD2 - Actividad 5.2: comparacion preliminar con B-tree (Iair Suico)
#
# Usa los scripts de benchmark/ (Fabricio, 5.1) sin modificarlos y agrega
# construccion_tamano.sql. Para cada dataset D2:
#   00_preparar_claves.sql  -> 20 000 claves (10 000 existen + 10 000 ausentes)
#   02_btree.sql            -> busquedas con B-tree (5 repeticiones)
#   03_hashing.sql          -> busquedas con nuestra estructura (5 repeticiones)
#   construccion_tamano.sql -> construccion x5 de ambos + tamano del B-tree
# 01_sin_indice.sql NO se corre aqui (tarda mucho; es parte del 5.1).
#
# Uso (dentro del contenedor):
#   docker exec -w /app bd2_g6_hashing sh bench_5.2/correr_5.2.sh
#   docker exec -w /app bd2_g6_hashing sh bench_5.2/correr_5.2.sh D2_aleatorio_100000
# Traer resultados:
#   docker cp bd2_g6_hashing:/app/bench_5.2/resultados/. bench_5.2/resultados/

DATASETS=${*:-"D2_aleatorio_100000 D2_aleatorio_500000 D2_aleatorio_1000000"}
OUT=bench_5.2/resultados
PSQL="psql -U postgres -d hashing_db -X $PSQL_EXTRA"

for ds in $DATASETS; do
    [ -f "data/$ds.csv" ] || { echo "[ERROR] Falta data/$ds.csv"; exit 1; }
done
for f in 00_preparar_claves.sql 02_btree.sql 03_hashing.sql; do
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
    $PSQL -c "SELECT name, setting, unit FROM pg_settings WHERE name IN ('shared_buffers','work_mem','max_parallel_workers_per_gather','max_parallel_maintenance_workers','jit') ORDER BY name;"
} > "$OUT/00_entorno.txt" 2>&1

for ds in $DATASETS; do
    echo ">>> $ds"
    D="$OUT/$ds"; mkdir -p "$D"
    $PSQL -q -c "DROP TABLE IF EXISTS buses;" \
             -c "CREATE TABLE buses (id_bus INTEGER, placa VARCHAR(7), ruta VARCHAR(5), capacidad INTEGER);" \
             -c "\copy buses FROM 'data/$ds.csv' WITH (FORMAT csv, HEADER true)" || exit 1
    echo "    claves";      $PSQL -v n_consultas=20000 -f benchmark/00_preparar_claves.sql > "$D/00_claves.txt" 2>&1
    echo "    btree";       $PSQL -f benchmark/02_btree.sql         > "$D/02_btree.txt" 2>&1
    echo "    hashing";     $PSQL -f benchmark/03_hashing.sql       > "$D/03_hashing.txt" 2>&1
    echo "    construccion y tamano"; $PSQL -f bench_5.2/construccion_tamano.sql > "$D/04_construccion_tamano.txt" 2>&1
done

# dejar buses como en el README (D2 100000)
$PSQL -q -c "DROP TABLE IF EXISTS buses;" \
         -c "CREATE TABLE buses (id_bus INTEGER, placa VARCHAR(7), ruta VARCHAR(5), capacidad INTEGER);" \
         -c "\copy buses FROM 'data/D2_aleatorio_100000.csv' WITH (FORMAT csv, HEADER true)"

echo "Listo. Resultados en $OUT/"
