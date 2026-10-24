#!/bin/bash
# Tarea 7.2 - Nicol Rocha

DATASETS=("100000" "500000" "1000000")
REPETICIONES=5

# Copia los CSV de tu Windows hacia la raíz del contenedor
echo "Sincronizando carpeta 'data' con el contenedor..."
docker cp data bd2_g6_hashing:/data

for SIZE in "${DATASETS[@]}"; do
    echo "=========================================="
    echo "Preparando Dataset D2 - Tamaño: $SIZE filas"
    echo "=========================================="
    
    sed -i "s|'data/|'/data/|g" sql/cargar_buses.sql
    sed -i "s|/data/D2_aleatorio_[0-9]*.csv|/data/D2_aleatorio_${SIZE}.csv|g" sql/cargar_buses.sql
    
    # 2. Inyectar el SQL y cargar los datos
    echo "Cargando datos en PostgreSQL..."
    MSYS_NO_PATHCONV=1 docker exec -i bd2_g6_hashing psql -U postgres -d hashing_db < sql/cargar_buses.sql
    
    # 3. Preparar las claves usando el script del equipo
    echo "Preparando claves para el benchmark..."
    MSYS_NO_PATHCONV=1 docker exec -i bd2_g6_hashing psql -U postgres -d hashing_db -v permitir_otra_version=1 < benchmark/00_preparar_claves.sql
    
    echo "------------------------------------------"
    echo "Iniciando medición de tiempos..."
    
    for i in $(seq 1 $REPETICIONES); do
        echo "--> Repetición $i"
        
        echo "Prueba B-Tree:"
        MSYS_NO_PATHCONV=1 docker exec -i bd2_g6_hashing psql -U postgres -d hashing_db < bench_7.2/test_btree.sql
        
        echo "Prueba Estructura Propia (Extendible Hashing):"
        MSYS_NO_PATHCONV=1 docker exec -i bd2_g6_hashing psql -U postgres -d hashing_db < bench_7.2/test_custom_hash.sql
    done
    
    echo "------------------------------------------"
done