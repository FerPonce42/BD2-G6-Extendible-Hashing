#!/bin/bash
# 9.2 - Nicol Rocha. Consultas locales y multinodo (mezcla de 8.1/8.2, sección 4.3).
source "$(dirname "$0")/lib.sh"
REP=${REP:-10}
OUT=bench_9.2/resultados_9.2.csv
echo "operacion,tipo,origen,destino,rep,ms_ejec,ms_red,ms_total" > $OUT

medir() {  # nombre tipo origen destino funcion args...
  local nombre=$1 tipo=$2 o=$3 d=$4; shift 4
  for i in $(seq 1 $REP); do
    echo "$nombre,$tipo,$o,$d,$i,$("$@" | awk '{print $1","$2","$3}')" >> $OUT
  done
}

# Nodo A = Norte (ids 1..3600, rutas 1-3). Cliente de Norte conectado a A.
# L1: leer un viaje de la propia zona por id_viaje (LOCAL)
medir L1 local A A consulta_desde A A "SELECT * FROM viajes_norte WHERE id_viaje=1800"
# L2: viajes de una ruta propia en un rango de fechas (LOCAL, usa B-tree (id_ruta,salida))
medir L2 local A A consulta_desde A A "SELECT count(*) FROM viajes_norte WHERE id_ruta=1 AND salida BETWEEN '2026-01-01' AND '2026-01-20'"
# L3: leer un viaje de otra zona (REMOTO). Con réplica: desde A, Centro está replicado en A (local); Sur está en B/C.
medir L3_principal remoto A B consulta_desde A B "SELECT * FROM viajes_centro WHERE id_viaje=5000"
medir L3_replica   local  A A consulta_desde A A "SELECT * FROM viajes_centro WHERE id_viaje=5000"
medir L3_sur       remoto A C consulta_desde A C "SELECT * FROM viajes_sur WHERE id_viaje=10000"
medir L3_sur_rep   remoto A B consulta_desde A B "SELECT * FROM viajes_sur WHERE id_viaje=10000"
# L4: reporte global (pasajeros por zona) a los 3 nodos en paralelo, coordinado desde B (el central)
Q4="SELECT sum(pasajeros) FROM (SELECT pasajeros FROM viajes_norte UNION ALL SELECT pasajeros FROM viajes_centro UNION ALL SELECT pasajeros FROM viajes_sur) t"
Q_N="SELECT sum(pasajeros) FROM viajes_norte"
Q_C="SELECT sum(pasajeros) FROM viajes_centro"
Q_S="SELECT sum(pasajeros) FROM viajes_sur"
medir L4_desde_B multinodo B "A-B-C" consulta_multinodo B "A:$Q_N" "B:$Q_C" "C:$Q_S"
medir L4_desde_A multinodo A "A-B-C" consulta_multinodo A "A:$Q_N" "B:$Q_C" "C:$Q_S"
# B tiene réplica de las 3 zonas: el reporte se resuelve sin salir del nodo (idea de 8.3)
medir L4_A_replicas multinodo A "A-B" consulta_multinodo A \
     "A:SELECT sum(pasajeros) FROM (SELECT pasajeros FROM viajes_norte UNION ALL SELECT pasajeros FROM viajes_centro) t" \
     "B:$Q_S"
medir L4_B_replicas local B B consulta_desde B B "SELECT sum(pasajeros) FROM (SELECT pasajeros FROM viajes_norte UNION ALL SELECT pasajeros FROM viajes_centro UNION ALL SELECT pasajeros FROM viajes_sur) t"
medir E1 local A A consulta_desde A A "INSERT INTO viajes_norte SELECT (SELECT max(id_viaje)+1 FROM viajes_norte), id_bus, 1, id_ruta, now(), 10, 1.50 FROM buses_norte WHERE id_bus = 1"
# E2: actualizar un bus (LOCAL en el principal)
medir E2 local A A consulta_desde A A "UPDATE buses_norte SET capacidad=30 WHERE id_bus=1"

echo "Listo: $OUT"