#!/bin/bash
# caida_nodo.sh
# Grupo 6 - BD2 - Actividad 10.2: prueba de indisponibilidad de un nodo (Iair Suico)
#
# Apaga un nodo de la 9.1 y mide que operaciones de la mezcla 70/30 (8.1/8.2, seccion 4.3)
# siguen funcionando para los clientes de cada zona, cuanto cuestan, y que pasa al volver.
# Sigue la tabla de la seccion 6 del informe de la 8.3 (que hacer si cae cada nodo).
#
# Dos modos:
#   temporal  -> el nodo se apaga (docker stop) y vuelve (docker start) sin promover nada.
#                Mide: operaciones con el nodo caido, cuanto tarda en volver y en ponerse
#                al dia con las escrituras que se hicieron mientras estaba caido.
#                No cambia la configuracion: se puede correr para A, B y C seguidos.
#   promocion -> el nodo se cae de golpe (docker kill) en medio de escrituras, se promueve
#                su replica (pasos de replicacion/replicacion_nodos.sql) y se mide cuanto
#                tarda la promocion, cuantas escrituras confirmadas se perdieron y el tiempo
#                de reconstruir el Extendible Hashing en el nodo promovido.
#                CAMBIA la replicacion: al terminar hay que rearmar los nodos (ver el final).
#
# Requisitos: nodos de la 9.1 levantados, con suscripciones, y cargados con
#             generador/cargar_distribuido.sh (estrategia por zona).
#
# Uso (desde la raiz del repositorio, en Git Bash):
#   export MSYS_NO_PATHCONV=1
#   bash caida_10.2/caida_nodo.sh temporal A        (o B, o C)
# Si la ventana de Git Bash se congela, correrlo desde cmd con el bash de Git:
#   set MSYS_NO_PATHCONV=1
#   "C:\Program Files\Git\bin\bash.exe" caida_10.2/caida_nodo.sh temporal A
#   bash caida_10.2/caida_nodo.sh promocion B       (o A, o C)
#   python caida_10.2/resumen_10.2.py
#
# Resultados: caida_10.2/resultados/<modo>_<nodo>.csv  (una fila por operacion y repeticion)
#             caida_10.2/resultados/<modo>_<nodo>.txt  (tiempos y conteos)

set -u
MODO=${1:-}; X=${2:-}
if [[ ! "$MODO" =~ ^(temporal|promocion)$ || ! "$X" =~ ^[ABC]$ ]]; then
    echo "Uso: bash caida_10.2/caida_nodo.sh temporal|promocion A|B|C"; exit 1
fi
REP=${REP:-5}
source bench_9.2/lib.sh      # LAT y CONT de la 9.2 (Nicol); se corre desde la raiz
mkdir -p caida_10.2/resultados
OUT=caida_10.2/resultados/${MODO}_${X}.csv
TXT=caida_10.2/resultados/${MODO}_${X}.txt
echo "estado,cliente,operacion,nodo,copia,rep,resultado,ms_ejec,ms_red,ms_total" > "$OUT"
: > "$TXT"
nota() { echo "$*" | tee -a "$TXT"; }

# ------------------------------------------------------------ plan de la 8.3
ZONAS="norte centro sur"
declare -A PRINC=([norte]=A [centro]=B [sur]=C)     # copia principal de cada zona
declare -A REPL=([norte]=B [centro]=A [sur]=B)      # replica de cada zona
declare -A CASA=([norte]=A [centro]=B [sur]=C)      # nodo al que se conectan los clientes de la zona
declare -A OTRA=([norte]=centro [centro]=sur [sur]=norte)   # zona que lee L3
declare -A ZONA_DE=([A]=norte [B]=centro [C]=sur)
OPS="L1 L2 L3 L4 E1 E2"

conn() {   # cadena de conexion al nodo $1 (se puede cambiar con CONN_A, CONN_B, CONN_C)
    local v="CONN_$1" n; n=$(echo "$1" | tr 'ABC' 'abc')
    echo "${!v:-host=nodo_$n port=5432 dbname=distribuido user=postgres password=password123}"
}

# ------------------------------------------------------------ ayudas
ahora() { date +%s.%N; }
seg() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.1f", b-a}'; }

vivo() { [ "$(docker inspect -f '{{.State.Running}}' "${CONT[$1]}" 2>/dev/null)" = "true" ]; }

sqlv() {   # sqlv NODO "sql" -> resultado (sin tiempo); falla si el nodo no responde
    MSYS_NO_PATHCONV=1 docker exec "${CONT[$1]}" psql -U postgres -d distribuido -At -v ON_ERROR_STOP=1 -c "$2" < /dev/null 2>/dev/null
}

ejec() {   # ejec NODO "sql" -> ms que reporta PostgreSQL; falla si el nodo no responde o hay error
    local s
    s=$(MSYS_NO_PATHCONV=1 docker exec "${CONT[$1]}" psql -U postgres -d distribuido -At -v ON_ERROR_STOP=1 \
        -c '\timing on' -c "$2" < /dev/null 2>/dev/null) || return 1
    echo "$s" | awk '/^Time:/{t=$2} END{if (t == "") exit 1; print t}'
}

copia_cercana() {   # copia_cercana ORIGEN ZONA -> nodo vivo con copia de la zona, el mas cercano
    local o=$1 z=$2 mejor="" d
    for d in ${PRINC[$z]} ${REPL[$z]}; do
        vivo "$d" || continue
        if [ -z "$mejor" ] || (( ${LAT[$o$d]} < ${LAT[$o$mejor]} )); then mejor=$d; fi
    done
    echo "$mejor"
}

esperar_listo() {   # esperar_listo NODO -> espera hasta que PostgreSQL responda (max 120 s)
    for i in $(seq 1 240); do sqlv "$1" "SELECT 1" > /dev/null && return 0; sleep 0.5; done
    return 1
}

# Filas de prueba: viajes con salida >= 2026-12-01 y conductores con id >= 900000.
# (Los datos del generador terminan el 2026-10-31.)
contar_prueba() {   # contar_prueba NODO TABLA
    if [ "$2" = conductores ]; then sqlv "$1" "SELECT count(*) FROM conductores WHERE id_conductor >= 900000"
    else sqlv "$1" "SELECT count(*) FROM $2 WHERE salida >= '2026-12-01'"; fi
}

pares_replicados() {   # "tabla principal replica" de cada copia que hoy se replica
    local z
    for z in $ZONAS; do [ -n "${REPL[$z]}" ] && echo "viajes_$z ${PRINC[$z]} ${REPL[$z]}"; done
    [ "$COND_PRINC" = B ] && echo "conductores B A" && echo "conductores B C"
    [ "$COND_PRINC" = A ] && echo "conductores A C"
}
COND_PRINC=B

limpiar_prueba() {   # borra las filas de prueba en las copias principales vivas
    local z
    for z in $ZONAS; do
        vivo "${PRINC[$z]}" && sqlv "${PRINC[$z]}" "DELETE FROM viajes_$z WHERE salida >= '2026-12-01'" > /dev/null
    done
    vivo "$COND_PRINC" && sqlv "$COND_PRINC" "DELETE FROM conductores WHERE id_conductor >= 900000" > /dev/null
}

esperar_al_dia() {   # espera a que cada replica viva tenga las mismas filas de prueba que su principal
    local maximo=${1:-300} i t p r pp rr ok
    for i in $(seq 1 "$maximo"); do
        ok=1
        while read -r t p r; do
            vivo "$p" && vivo "$r" || continue
            pp=$(contar_prueba "$p" "$t"); rr=$(contar_prueba "$r" "$t")
            [ "$pp" = "$rr" ] || ok=0
        done < <(pares_replicados)
        [ $ok = 1 ] && return 0
        sleep 1
    done
    return 1
}

# ------------------------------------------------------------ datos de las operaciones
declare -A ID_LEER BUS RUTA_BUS RUTA1
SIG_ID=3000000          # ids de los viajes que inserta E1 (fuera del rango del generador)
for z in $ZONAS; do
    p=${PRINC[$z]}
    ID_LEER[$z]=$(sqlv "$p" "SELECT min(id_viaje) FROM viajes_$z")
    BUS[$z]=$(sqlv "$p" "SELECT min(id_bus) FROM buses_$z")
    RUTA_BUS[$z]=$(sqlv "$p" "SELECT id_ruta FROM buses_$z WHERE id_bus = ${BUS[$z]}")
    RUTA1[$z]=$(sqlv "$p" "SELECT min(id_ruta) FROM buses_$z")
    if [ -z "${ID_LEER[$z]}" ] || [ -z "${BUS[$z]}" ]; then
        echo "No pude leer viajes_$z en ${CONT[$p]}. Revisa que los 3 nodos esten arriba y cargados."; exit 1
    fi
done

consulta() {   # consulta ZONA OP -> SQL de la operacion para un cliente de esa zona
    local z=$1 w
    case $2 in
        L1) echo "SELECT * FROM viajes_$z WHERE id_viaje = ${ID_LEER[$z]}";;
        L2) echo "SELECT count(*) FROM viajes_$z WHERE id_ruta = ${RUTA1[$z]} AND salida BETWEEN '2026-01-01' AND '2026-01-20'";;
        L3) w=${OTRA[$z]}; echo "SELECT * FROM viajes_$w WHERE id_viaje = ${ID_LEER[$w]}";;
        E1) echo "INSERT INTO viajes_$z VALUES ($SIG_ID, ${BUS[$z]}, 1, ${RUTA_BUS[$z]}, '2026-12-01 08:00', 10, 1.50)";;
        E2) echo "UPDATE buses_$z SET capacidad = capacidad WHERE id_bus = ${BUS[$z]}";;
    esac
}

registrar() { echo "$ESTADO,$1,$2,$3,$4,$5,$6,$7,$8,$9" >> "$OUT"; }

medir_op() {   # medir_op ZONA OP  (REP repeticiones)
    local z=$1 op=$2 o=${CASA[$1]} d q e red copia i nodos zz w res emax
    for i in $(seq 1 "$REP"); do
        if [ "$op" = L4 ]; then
            # reporte global: cada zona en su copia viva mas cercana; en paralelo
            # (ejecucion = la mas lenta, red = la del nodo mas lejano, como en la 9.2)
            declare -A PARTE=(); res=OK; emax=0; red=0; nodos=""
            for zz in $ZONAS; do
                d=$(copia_cercana "$o" "$zz")
                if [ -z "$d" ]; then res=FALLA; break; fi
                PARTE[$d]="${PARTE[$d]:-}${PARTE[$d]:+ UNION ALL }SELECT pasajeros FROM viajes_$zz"
            done
            if [ $res = OK ]; then
                for d in "${!PARTE[@]}"; do
                    e=$(ejec "$d" "SELECT sum(pasajeros) FROM (${PARTE[$d]}) t") || { res=FALLA; break; }
                    emax=$(awk -v a="$emax" -v b="$e" 'BEGIN{print (b > a) ? b : a}')
                    (( ${LAT[$o$d]} > red )) && red=${LAT[$o$d]}
                    nodos="$nodos$d"
                done
            fi
            nodos=$(echo "$nodos" | grep -o . | sort | tr -d '\n')
            if [ $res = OK ]; then
                registrar "$z" L4 "$nodos" mixta "$i" OK "$emax" "$red" "$(awk -v e="$emax" -v r="$red" 'BEGIN{printf "%.3f", e + r}')"
            else
                registrar "$z" L4 "-" "-" "$i" FALLA "" "" ""
            fi
            unset PARTE
            continue
        fi
        case $op in
            L1|L2) d=$(copia_cercana "$o" "$z");          w=$z;;
            L3)    d=$(copia_cercana "$o" "${OTRA[$z]}"); w=${OTRA[$z]};;
            E1|E2) d=${PRINC[$z]}; w=$z; vivo "$d" || d="";;     # las escrituras solo van a la principal
        esac
        if [ -z "$d" ]; then registrar "$z" "$op" "-" "-" "$i" FALLA "" "" ""; continue; fi
        [ "$d" = "${PRINC[$w]}" ] && copia=principal || copia=replica
        SIG_ID=$((SIG_ID + 1))     # id nuevo para E1 (fuera de $(...) para que no se pierda)
        q=$(consulta "$z" "$op")
        if e=$(ejec "$d" "$q"); then
            red=${LAT[$o$d]}
            registrar "$z" "$op" "$d" "$copia" "$i" OK "$e" "$red" "$(awk -v e="$e" -v r="$red" 'BEGIN{printf "%.3f", e + r}')"
        else
            registrar "$z" "$op" "$d" "$copia" "$i" FALLA "" "" ""
        fi
    done
}

ronda() {   # ronda ESTADO -> la mezcla completa para los clientes de las 3 zonas
    ESTADO=$1
    local z op
    nota ">>> Ronda: $ESTADO"
    for z in $ZONAS; do for op in $OPS; do medir_op "$z" "$op"; done; done
    awk -F, -v e="$ESTADO" '$1 == e { n++; if ($7 == "FALLA") f++ } END { printf "    %d operaciones, %d fallaron\n", n, f }' "$OUT" | tee -a "$TXT"
}

conteo_completo() {   # filas de cada copia de viajes en cada nodo vivo
    local z n
    for z in $ZONAS; do
        for n in ${PRINC[$z]} ${REPL[$z]}; do
            vivo "$n" && nota "    viajes_$z en ${CONT[$n]}: $(sqlv "$n" "SELECT count(*) FROM viajes_$z")"
        done
    done
}

# ------------------------------------------------------------ 0) punto de partida
nota "=== 10.2 - modo $MODO, nodo ${CONT[$X]} - $(date '+%Y-%m-%d %H:%M:%S') - REP=$REP"
for n in A B C; do vivo "$n" || { echo "${CONT[$n]} no esta corriendo. Levanta los 3 nodos antes."; exit 1; }; done
limpiar_prueba
esperar_al_dia 120 || { echo "Las replicas no estan al dia antes de empezar. Revisa las suscripciones."; exit 1; }
nota "Antes de la caida:"
conteo_completo

ronda normal

# ------------------------------------------------------------ modo temporal
if [ "$MODO" = temporal ]; then
    t=$(ahora); docker stop "${CONT[$X]}" > /dev/null; nota "docker stop ${CONT[$X]}: $(seg "$t" "$(ahora)") s"

    ronda caido

    # Escrituras mientras X esta caido en las copias que X replica: tiene que recibirlas al volver
    pendientes=0
    for z in $ZONAS; do
        if [ "${REPL[$z]}" = "$X" ]; then
            sqlv "${PRINC[$z]}" "INSERT INTO viajes_$z SELECT 3500000 + g, ${BUS[$z]}, 1, ${RUTA_BUS[$z]}, '2026-12-01 09:00', 10, 1.50 FROM generate_series(1, 1000) g" > /dev/null
            nota "Escritas 1000 filas en viajes_$z (${CONT[${PRINC[$z]}]}) mientras su replica en ${CONT[$X]} estaba caida"
            pendientes=$((pendientes + 1000))
        fi
    done
    if [ "$X" != B ]; then
        sqlv B "INSERT INTO conductores SELECT 900000 + g, 'Prueba 10.2', 'P' || (900000 + g), DATE '2026-12-01' FROM generate_series(1, 10) g" > /dev/null
        nota "Escritos 10 conductores en nodo_b mientras su replica en ${CONT[$X]} estaba caida"
        pendientes=$((pendientes + 10))
    fi

    t=$(ahora); docker start "${CONT[$X]}" > /dev/null
    esperar_listo "$X" || { nota "${CONT[$X]} no volvio a responder en 120 s"; exit 1; }
    t_listo=$(seg "$t" "$(ahora)")
    if esperar_al_dia 300; then t_dia=$(seg "$t" "$(ahora)"); else t_dia="mas de 300"; fi
    nota "docker start ${CONT[$X]}: responde a los $t_listo s y las replicas estan al dia a los $t_dia s ($pendientes filas pendientes)"

    ronda recuperado

    nota "Despues de volver (sin contar las filas de prueba, todo tiene que ser igual a antes):"
    limpiar_prueba; esperar_al_dia 120
    conteo_completo
fi

# ------------------------------------------------------------ modo promocion
if [ "$MODO" = promocion ]; then
    Z=${ZONA_DE[$X]}; R=${REPL[$Z]}
    # 1) Escrituras seguidas en la principal de Z (una transaccion por fila) y caida de golpe
    nota "Escribiendo en viajes_$Z (${CONT[$X]}) y matando el nodo a los 3 s..."
    MSYS_NO_PATHCONV=1 docker exec "${CONT[$X]}" psql -U postgres -d distribuido -q -c \
        "DO \$\$ BEGIN FOR i IN 1..10000000 LOOP
             INSERT INTO viajes_$Z VALUES (4000000 + i, ${BUS[$Z]}, 1, ${RUTA_BUS[$Z]}, '2026-12-02 08:00', 10, 1.50);
             COMMIT;
         END LOOP; END \$\$;" < /dev/null > /dev/null 2>&1 &
    escritor=$!
    sleep 3
    docker kill "${CONT[$X]}" > /dev/null; t_caida=$(ahora)
    wait $escritor 2> /dev/null
    nota "docker kill ${CONT[$X]}"

    ronda caido

    # 2) Promocion (replicacion/replicacion_nodos.sql, seccion CAIDA DE UN NODO)
    nota "Promoviendo la replica de $Z en ${CONT[$R]}..."
    t=$(ahora)
    sub="sub_$(echo "$R" | tr 'ABC' 'abc')_$Z"
    sqlv "$R" "ALTER SUBSCRIPTION $sub DISABLE" > /dev/null
    sqlv "$R" "ALTER SUBSCRIPTION $sub SET (slot_name = NONE)" > /dev/null
    sqlv "$R" "DROP SUBSCRIPTION $sub" > /dev/null
    PRINC[$Z]=$R; REPL[$Z]=""
    if [ "$X" = B ]; then
        # conductores: nueva copia principal en A, y C pasa a replicarla desde A
        sqlv A "ALTER SUBSCRIPTION sub_a_conductores DISABLE" > /dev/null
        sqlv A "ALTER SUBSCRIPTION sub_a_conductores SET (slot_name = NONE)" > /dev/null
        sqlv A "DROP SUBSCRIPTION sub_a_conductores" > /dev/null
        sqlv A "CREATE PUBLICATION pub_conductores_a FOR TABLE conductores" > /dev/null
        sqlv C "ALTER SUBSCRIPTION sub_c_conductores DISABLE" > /dev/null
        sqlv C "ALTER SUBSCRIPTION sub_c_conductores SET (slot_name = NONE)" > /dev/null
        sqlv C "DROP SUBSCRIPTION sub_c_conductores" > /dev/null
        sqlv C "CREATE SUBSCRIPTION sub_c_conductores_a CONNECTION '$(conn A)' PUBLICATION pub_conductores_a WITH (copy_data = false)" > /dev/null
        COND_PRINC=A
    fi
    t_promo=$(seg "$t" "$(ahora)")
    nota "Promocion: $t_promo s (desde la caida: $(seg "$t_caida" "$(ahora)") s)"
    if [ -n "$(sqlv "$R" "SELECT 1 FROM pg_subscription WHERE subname = '$sub'")" ]; then
        nota "AVISO: la suscripcion $sub sigue existiendo en ${CONT[$R]}"
    fi

    # 3) Cuantas escrituras llegaron a la replica antes de la caida
    llegaron=$(sqlv "$R" "SELECT count(*) FROM viajes_$Z WHERE id_viaje BETWEEN 4000001 AND 13999999")

    # 4) Reconstruir el Extendible Hashing en el nodo promovido (vive en la memoria de la sesion, 8.3)
    t=$(ahora)
    hash=$(MSYS_NO_PATHCONV=1 docker exec "${CONT[$R]}" psql -U postgres -d distribuido -At \
        -c '\timing on' -c "SELECT count(*) FILTER (WHERE pg_insertar(id_viaje)) FROM viajes_$Z" \
        -c "SELECT pg_buscar(${ID_LEER[$Z]}), pg_buscar(-1)" < /dev/null 2>&1)
    nota "Extendible Hashing reconstruido en ${CONT[$R]} sobre viajes_$Z: $(echo "$hash" | grep -E '^[0-9]+$' | head -1) claves en $(echo "$hash" | awk '/^Time:/{print $2; exit}') ms; pg_buscar(existe, no existe) = $(echo "$hash" | grep '|' | head -1)"

    ronda promovido

    # 5) Cuantas escrituras habia confirmado el nodo caido: se lo levanta solo para contarlas
    docker start "${CONT[$X]}" > /dev/null; esperar_listo "$X"
    confirmadas=$(sqlv "$X" "SELECT count(*) FROM viajes_$Z WHERE id_viaje BETWEEN 4000001 AND 13999999")
    docker stop "${CONT[$X]}" > /dev/null
    nota "Escrituras confirmadas en ${CONT[$X]} antes de la caida: $confirmadas"
    nota "Llegaron a la replica (${CONT[$R]}): $llegaron"
    nota "Perdidas: $((confirmadas - llegaron))"
    if [ "$X" = B ]; then   # comprobar que C ahora recibe conductores desde A
        sqlv A "INSERT INTO conductores VALUES (900001, 'Prueba 10.2', 'P900001', DATE '2026-12-01')" > /dev/null
        sleep 3
        nota "Conductor nuevo escrito en nodo_a, visto en nodo_c: $(sqlv C "SELECT count(*) FROM conductores WHERE id_conductor = 900001") (1 = la nueva replica funciona)"
    fi
    limpiar_prueba; esperar_al_dia 60
    nota "Despues de la promocion (sin las filas de prueba):"
    conteo_completo
    nota ""
    nota "${CONT[$X]} quedo apagado y la replicacion cambio. Para volver al estado normal, rearmar los nodos:"
    nota "  docker compose -f nodos/docker-compose.yml down -v   (y los pasos de nodos/README.md + generador/cargar_distribuido.sh)"
fi

limpiar_prueba
nota "Listo: $OUT"
