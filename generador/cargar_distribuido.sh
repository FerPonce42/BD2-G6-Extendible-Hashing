#!/bin/bash
# cargar_distribuido.sh
# Grupo 6 - BD2 - Etapa II, semana 9: carga de los datos del generador en los nodos (Iair Suico)
#
# Carga los CSV de generar_distribuido.py SOLO en el nodo principal de cada fragmento
# (las replicas se llenan solas por la suscripcion, actividad 8.3 / 9.1):
#   1. B: conductores, buses_centro, viajes_centro
#   2. espera a que la replica de conductores llegue a A y a C
#   3. A: buses_norte, viajes_norte
#   4. C: buses_sur, viajes_sur
# Cada nodo se carga en una sola transaccion: si algo falla, no queda nada a medias.
#
# Requisitos:
#   - Los nodos de la 9.1 levantados (nodos/docker-compose.yml) con las suscripciones creadas.
#   - Las tablas de datos vacias (si ya tienen datos de prueba, levantar los nodos de nuevo).
#   - Haber corrido antes: python generador/generar_distribuido.py
#
# Uso (desde la raiz del repositorio, en Git Bash):
#   export MSYS_NO_PATHCONV=1      # solo en Git Bash de Windows
#   bash generador/cargar_distribuido.sh

set -e
DATOS=data/distribuido
BASE=distribuido

sql() {   # sql <contenedor> <consulta>  -> resultado sin encabezado
    docker exec "$1" psql -U postgres -d "$BASE" -v ON_ERROR_STOP=1 -tAc "$2"
}

filas_csv() {   # filas de datos de un CSV (sin el encabezado)
    echo $(( $(wc -l < "$DATOS/$1.csv") - 1 ))
}

cargar() {   # cargar <contenedor> <tabla1> <tabla2> ...
    local nodo=$1; shift
    local copias=""
    for t in "$@"; do
        # sin mensajes: en Git Bash, si la ventana se congela, docker cp se queda esperando
        docker cp "$DATOS/$t.csv" "$nodo:/tmp/$t.csv" > /dev/null 2>&1
        copias="$copias COPY $t FROM '/tmp/$t.csv' WITH (FORMAT csv, HEADER true);"
    done
    echo ">>> $nodo: $*"
    sql "$nodo" "BEGIN; $copias COMMIT;" > /dev/null
}

# 0) Comprobaciones previas
for f in conductores buses_norte buses_centro buses_sur viajes_norte viajes_centro viajes_sur; do
    [ -f "$DATOS/$f.csv" ] || { echo "Falta $DATOS/$f.csv: corre antes generador/generar_distribuido.py"; exit 1; }
done
for par in "nodo_b conductores" "nodo_b viajes_centro" "nodo_a viajes_norte" "nodo_c viajes_sur"; do
    set -- $par
    n=$(sql "$1" "SELECT count(*) FROM $2")
    if [ "$n" != "0" ]; then
        echo "$1.$2 ya tiene $n filas. Levanta los nodos limpios antes de cargar."; exit 1
    fi
done

# 1) B primero: tiene los conductores que usan los viajes de A y de C
cargar nodo_b conductores buses_centro viajes_centro

# 2) Esperar la replica de conductores en A y en C (es asincrona)
esperado=$(filas_csv conductores)
for nodo in nodo_a nodo_c; do
    for i in $(seq 1 60); do
        n=$(sql "$nodo" "SELECT count(*) FROM conductores")
        [ "$n" = "$esperado" ] && break
        sleep 1
    done
    if [ "$n" != "$esperado" ]; then
        echo "En $nodo llegaron $n de $esperado conductores despues de 60 s. Revisa la suscripcion."; exit 1
    fi
    echo "    conductores replicados en $nodo ($n)"
done

# 3) y 4) A y C
cargar nodo_a buses_norte viajes_norte
cargar nodo_c buses_sur viajes_sur

# 5) Verificacion: cada tabla (principal y replica) con las filas del CSV
echo ">>> Esperando a que terminen las replicas..."
sleep 10
echo ""
echo "tabla            esperado   nodo_a   nodo_b   nodo_c"
error=0
for t in conductores buses_norte viajes_norte buses_centro viajes_centro buses_sur viajes_sur; do
    esp=$(filas_csv "$t")
    linea=$(printf "%-15s %9s" "$t" "$esp")
    for nodo in nodo_a nodo_b nodo_c; do
        if [ "$(sql "$nodo" "SELECT to_regclass('$t') IS NOT NULL")" = "t" ]; then
            n=$(sql "$nodo" "SELECT count(*) FROM $t")
            [ "$n" = "$esp" ] || error=1
        else
            n="-"
        fi
        linea="$linea $(printf "%8s" "$n")"
    done
    echo "$linea"
done
echo ""
if [ $error = 0 ]; then
    echo "OK: todos los nodos tienen las mismas filas que los CSV."
else
    echo "Hay diferencias: si es una replica, espera unos segundos y vuelve a contar."
fi
