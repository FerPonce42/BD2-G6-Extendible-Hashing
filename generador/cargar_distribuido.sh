#!/bin/bash
# cargar_distribuido.sh
# Grupo 6 - BD2 - Etapa II, semana 9: carga de los datos del generador en los nodos (Iair Suico)
#
# Carga los CSV de generar_distribuido.py SOLO en el nodo principal de cada fragmento
# (las replicas se llenan solas por la suscripcion, actividad 8.3 / 9.1):
#   1. B: conductores, buses_centro, viajes_centro      (hash: buses_h1, viajes_h1)
#   2. conductores en A y en C: si el nodo tiene suscripciones, espera la replica;
#      si no tiene ninguna, carga ahi el mismo conductores.csv
#   3. A: buses_norte, viajes_norte                     (hash: buses_h0, viajes_h0)
#   4. C: buses_sur, viajes_sur                         (hash: buses_h2, viajes_h2)
# Cada nodo se carga en una sola transaccion: si algo falla, no queda nada a medias.
#
# Requisitos:
#   - Los nodos de la 9.1 levantados (nodos/docker-compose.yml) con las suscripciones creadas.
#   - Las tablas de datos vacias (si ya tienen datos de prueba, levantar los nodos de nuevo).
#   - Haber corrido antes el generador con la misma estrategia.
#
# Uso (desde la raiz del repositorio, en Git Bash):
#   export MSYS_NO_PATHCONV=1      # solo en Git Bash de Windows
#   bash generador/cargar_distribuido.sh          -> estrategia por zona (data/distribuido)
#   bash generador/cargar_distribuido.sh hash     -> estrategia hash (data/distribuido_hash)

set -e
ESTRATEGIA=${1:-zona}
BASE=distribuido
if [ "$ESTRATEGIA" = "hash" ]; then
    DATOS=data/distribuido_hash; FA=h0; FB=h1; FC=h2
elif [ "$ESTRATEGIA" = "zona" ]; then
    DATOS=data/distribuido;      FA=norte; FB=centro; FC=sur
else
    echo "La estrategia tiene que ser zona o hash"; exit 1
fi
TABLAS="conductores buses_$FA viajes_$FA buses_$FB viajes_$FB buses_$FC viajes_$FC"

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
echo "Estrategia: $ESTRATEGIA ($DATOS)"
for f in $TABLAS; do
    [ -f "$DATOS/$f.csv" ] || { echo "Falta $DATOS/$f.csv: corre antes el generador con la estrategia $ESTRATEGIA"; exit 1; }
done
for par in "nodo_b conductores" "nodo_b viajes_$FB" "nodo_a viajes_$FA" "nodo_c viajes_$FC"; do
    set -- $par
    n=$(sql "$1" "SELECT count(*) FROM $2")
    if [ "$n" != "0" ]; then
        echo "$1.$2 ya tiene $n filas. Levanta los nodos limpios antes de cargar."; exit 1
    fi
done

# 1) B primero: tiene los conductores que usan los viajes de A y de C
cargar nodo_b conductores buses_$FB viajes_$FB

# 2) conductores en A y en C: por la replica (asincrona) o, si el nodo no tiene
#    suscripciones, cargando el CSV directamente
esperado=$(filas_csv conductores)
for nodo in nodo_a nodo_c; do
    if [ "$(sql "$nodo" "SELECT count(*) FROM pg_subscription")" = "0" ]; then
        cargar "$nodo" conductores
        continue
    fi
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
cargar nodo_a buses_$FA viajes_$FA
cargar nodo_c buses_$FC viajes_$FC

# 5) Verificacion: cada tabla (principal y replica) con las filas del CSV
echo ">>> Esperando a que terminen las replicas..."
sleep 10
echo ""
echo "tabla            esperado   nodo_a   nodo_b   nodo_c"
error=0
for t in $TABLAS; do
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
