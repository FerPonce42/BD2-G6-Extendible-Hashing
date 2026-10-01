#!/bin/sh
# correr_tests.sh
# Grupo 6 - BD2 - Actividad 4.4 (Iair Suico)
#
# Corre TODAS las pruebas de la 4.4 dentro del contenedor y guarda las salidas en
# tests/resultados/<etiqueta>/ (dentro del contenedor).
#
# Requisitos: contenedor levantado, CSV de los 3 tamanos copiados a /app/data
# y la carpeta tests/ copiada a /app/tests.
#
# Uso (desde la carpeta del proyecto, en la terminal 2):
#   docker exec -w /app bd2_g6_hashing sh tests/correr_tests.sh antes
#   docker exec -w /app bd2_g6_hashing sh tests/correr_tests.sh despues
# y luego para traer los resultados a tu PC:
#   docker cp bd2_g6_hashing:/app/tests/resultados/. tests/resultados/

ETIQUETA=${1:-resultado}
OUT=tests/resultados/$ETIQUETA
PSQL="psql -U postgres -d hashing_db -X"

mkdir -p "$OUT"

for f in D1_secuencial_100000 D2_aleatorio_100000 D1_secuencial_500000 \
         D2_aleatorio_500000 D1_secuencial_1000000 D2_aleatorio_1000000; do
    if [ ! -f "data/$f.csv" ]; then
        echo "[ERROR] Falta data/$f.csv. Genera los 3 tamanos y copialos al contenedor."
        exit 1
    fi
done

echo "[1/5] Entorno"
{
    echo "Etiqueta: $ETIQUETA"
    echo "Fecha:    $(date)"
    echo "Kernel:   $(uname -srm)"
    echo "CPU:      $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')"
    echo "Nucleos:  $(nproc)"
    echo "Memoria:  $(grep MemTotal /proc/meminfo | awk '{print int($2/1024) " MB"}')"
    echo
    $PSQL -c "SELECT version();"
    $PSQL -c "SHOW server_version;"
    $PSQL -c "SELECT name, setting, unit FROM pg_settings WHERE name IN ('shared_buffers','work_mem','max_parallel_workers_per_gather') ORDER BY name;"
} > "$OUT/00_entorno.txt" 2>&1

echo "[2/5] Datasets (puede tardar unos minutos)"
$PSQL -f tests/01_datasets.sql > "$OUT/01_datasets.txt" 2>&1

echo "[3/5] Casos limite"
$PSQL -f tests/02_casos_limite.sql > "$OUT/02_casos_limite.txt" 2>&1

echo "[4/5] Tope de profundidad"
$PSQL -f tests/03_tope_profundidad.sql > "$OUT/03_tope_profundidad.txt" 2>&1

echo "[5/5] Revision interna en C (D1 y D2 de 1 000 000)"
{
    gcc -O2 -Iinclude -o /tmp/revision_interna tests/revision_interna.c \
        src/bucket.c src/busqueda.c src/directorio.c src/inserccion.c src/split.c &&
    /tmp/revision_interna data/D1_secuencial_1000000.csv &&
    echo &&
    /tmp/revision_interna data/D2_aleatorio_1000000.csv
} > "$OUT/04_revision_interna.txt" 2>&1

echo "Listo. Resultados en $OUT/"
