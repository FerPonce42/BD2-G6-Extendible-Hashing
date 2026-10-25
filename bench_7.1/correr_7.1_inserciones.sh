#!/bin/sh
# correr_7.1_inserciones.sh
# Grupo 6 - BD2 - Actividad 7.1: inserciones (W3) sin indice (Fernando Ponce)
#
# Mismo metodo que bench_7.2 (Nicol): claves max+1..max+n, BEGIN, INSERT, ROLLBACK,
# 5 repeticiones, una sesion de psql por repeticion.
# Para cada tamano recarga la tabla buses (sin ningun indice) y comprueba que
# tenga las filas esperadas y 0 indices antes de medir.
# No modifica archivos del repo: solo escribe en bench_7.1/resultados_inserciones/
#
# Uso (dentro del contenedor):
#   docker exec -w /app bd2_g6_hashing sh bench_7.1/correr_7.1_inserciones.sh
# Traer resultados:
#   docker cp bd2_g6_hashing:/app/bench_7.1/resultados_inserciones/. bench_7.1/resultados_inserciones/

DATASETS="100000 500000 1000000"
INSERTS="10000 50000 100000"
REPS=5
OUT=bench_7.1/resultados_inserciones
PSQL="psql -U postgres -d hashing_db -X"

for size in $DATASETS; do
    [ -f "data/D2_aleatorio_$size.csv" ] || { echo "[ERROR] Falta data/D2_aleatorio_$size.csv"; exit 1; }
done
[ -f bench_7.1/inserciones_sin_indice.sql ] || { echo "[ERROR] Falta bench_7.1/inserciones_sin_indice.sql (copia bench_7.1 al contenedor)"; exit 1; }

mkdir -p "$OUT"
RESUMEN="$OUT/resumen.txt"
echo "Inserciones (W3) sin indice: mediana de $REPS repeticiones" > "$RESUMEN"
printf "%-10s %-12s %-12s %s\n" "filas" "inserciones" "mediana_ms" "tiempos_ms" >> "$RESUMEN"

set -- $INSERTS
for size in $DATASETS; do
    n=$1; shift
    echo ">>> D2 con $size filas | $n inserciones"
    D="$OUT/D2_aleatorio_$size"; mkdir -p "$D"
    F="$D/inserciones_sin_indice.txt"

    $PSQL -q -c "DROP TABLE IF EXISTS buses;" \
             -c "CREATE TABLE buses (id_bus INTEGER, placa VARCHAR(7), ruta VARCHAR(5), capacidad INTEGER);" \
             -c "\copy buses FROM 'data/D2_aleatorio_$size.csv' WITH (FORMAT csv, HEADER true)" || exit 1

    filas=$($PSQL -t -A -c "SELECT count(*) FROM buses;")
    indices=$($PSQL -t -A -c "SELECT count(*) FROM pg_indexes WHERE tablename = 'buses';")
    [ "$filas" = "$size" ] || { echo "[ERROR] buses tiene $filas filas y se esperaban $size"; exit 1; }
    [ "$indices" = "0" ] || { echo "[ERROR] buses tiene $indices indices y debe tener 0"; exit 1; }

    {
        echo "Dataset: D2_aleatorio_$size"
        echo "Filas en buses: $filas"
        echo "Indices en buses: $indices"
        echo "Inserciones por repeticion: $n"
        echo "Fecha: $(date)"
        $PSQL -t -A -c "SELECT version();"
    } > "$F"

    i=1
    while [ $i -le $REPS ]; do
        echo "--> Repeticion $i" >> "$F"
        $PSQL -v n_inserts=$n -f bench_7.1/inserciones_sin_indice.sql >> "$F" 2>&1
        i=$((i + 1))
    done

    tiempos=$(awk '/^INSERT 0/ {f=1; next} f && /^Time:/ {print $2; f=0}' "$F")
    cantidad=$(echo "$tiempos" | wc -l)
    [ "$cantidad" = "$REPS" ] || { echo "[ERROR] se leyeron $cantidad tiempos y se esperaban $REPS (revisa $F)"; exit 1; }
    mediana=$(echo "$tiempos" | sort -n | sed -n "$(( (REPS + 1) / 2 ))p")
    lista=$(echo "$tiempos" | tr '\n' ' ')

    printf "%-10s %-12s %-12s %s\n" "$size" "$n" "$mediana" "$lista" >> "$RESUMEN"
    echo "    mediana: $mediana ms"
done

echo
cat "$RESUMEN"
echo "Listo. Resultados en $OUT/"
