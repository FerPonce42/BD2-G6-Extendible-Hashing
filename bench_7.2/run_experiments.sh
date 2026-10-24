#!/bin/bash
# Tarea 7.2 - Nicol Rocha

DATASETS=("100000" "500000" "1000000")
INSERTS=("10000" "50000" "100000")
REPETICIONES=5
OUTPUT="bench_7.2/resultados_crudos.txt"

> $OUTPUT
echo "==========================================" | tee -a $OUTPUT
echo "Iniciando Benchmark 7.2" | tee -a $OUTPUT
MSYS_NO_PATHCONV=1 docker exec -i bd2_g6_hashing psql -U postgres -d hashing_db -c "SELECT version();" | tee -a $OUTPUT
echo "==========================================" | tee -a $OUTPUT

echo "Sincronizando carpeta 'data' con el contenedor..."
docker cp data bd2_g6_hashing:/data

# Iterar usando el índice del arreglo
for idx in "${!DATASETS[@]}"; do
    SIZE="${DATASETS[$idx]}"
    N_INSERTS="${INSERTS[$idx]}"
    
    echo "==========================================" | tee -a $OUTPUT
    echo "Preparando Dataset D2 - Tamaño: $SIZE filas | Inserciones W3: $N_INSERTS" | tee -a $OUTPUT
    
    sed -i "s|'data/|'/data/|g" sql/cargar_buses.sql
    sed -i "s|/data/D2_aleatorio_[0-9]*.csv|/data/D2_aleatorio_${SIZE}.csv|g" sql/cargar_buses.sql
    
    echo "Cargando datos base..."
    MSYS_NO_PATHCONV=1 docker exec -i bd2_g6_hashing psql -U postgres -d hashing_db < sql/cargar_buses.sql > /dev/null
    
    # Preparar claves solo para mantener compatibilidad
    MSYS_NO_PATHCONV=1 docker exec -i bd2_g6_hashing psql -U postgres -d hashing_db -v permitir_otra_version=1 < benchmark/00_preparar_claves.sql > /dev/null
    
    echo "------------------------------------------" | tee -a $OUTPUT
    echo "Midiendo tiempos..." | tee -a $OUTPUT
    
    for i in $(seq 1 $REPETICIONES); do
        echo "--> Repetición $i" | tee -a $OUTPUT
        
        echo "Prueba B-Tree:" | tee -a $OUTPUT
        MSYS_NO_PATHCONV=1 docker exec -i bd2_g6_hashing psql -U postgres -d hashing_db -v n_inserts=$N_INSERTS < bench_7.2/test_btree.sql >> $OUTPUT 2>&1
        
        echo "Prueba Hash:" | tee -a $OUTPUT
        MSYS_NO_PATHCONV=1 docker exec -i bd2_g6_hashing psql -U postgres -d hashing_db -v n_inserts=$N_INSERTS < bench_7.2/test_custom_hash.sql >> $OUTPUT 2>&1
    done
done