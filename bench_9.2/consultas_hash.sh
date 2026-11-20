#!/bin/bash
# 10.1 - Nicol Rocha. Mezcla 70/30 sobre estrategia por Hash (id mod 3).
source "$(dirname "$0")/lib.sh"
REP=${REP:-10}
OUT=bench_9.2/resultados_10.1_hash.csv
echo "operacion,tipo,origen,destino,rep,ms_ejec,ms_red,ms_total" > $OUT

medir() {
  local nombre=$1 tipo=$2 o=$3 d=$4; shift 4
  for i in $(seq 1 $REP); do
    echo "$nombre,$tipo,$o,$d,$i,$("$@" | awk '{print $1","$2","$3}')" >> $OUT
  done
}

# L1 (35%): leer viaje por id_viaje (1/3 local en A, 1/3 remoto en B, 1/3 remoto en C)
medir L1_A local  A A consulta_desde A A "SELECT * FROM viajes_h0 WHERE id_viaje=3"
medir L1_B remoto A B consulta_desde A B "SELECT * FROM viajes_h1 WHERE id_viaje=4"
medir L1_C remoto A C consulta_desde A C "SELECT * FROM viajes_h2 WHERE id_viaje=5"

# L2 (20%): viajes de una ruta en rango de fechas (siempre multinodo)
Q_L2_0="SELECT count(*) FROM viajes_h0 WHERE id_ruta=1 AND salida BETWEEN '2026-01-01' AND '2026-01-20'"
Q_L2_1="SELECT count(*) FROM viajes_h1 WHERE id_ruta=1 AND salida BETWEEN '2026-01-01' AND '2026-01-20'"
Q_L2_2="SELECT count(*) FROM viajes_h2 WHERE id_ruta=1 AND salida BETWEEN '2026-01-01' AND '2026-01-20'"
medir L2 multinodo A "A-B-C" consulta_multinodo A "A:$Q_L2_0" "B:$Q_L2_1" "C:$Q_L2_2"

# L3 (10%): leer otro viaje puntual por id_viaje (1/3 A, 1/3 B, 1/3 C)
medir L3_A local  A A consulta_desde A A "SELECT * FROM viajes_h0 WHERE id_viaje=300"
medir L3_B remoto A B consulta_desde A B "SELECT * FROM viajes_h1 WHERE id_viaje=301"
medir L3_C remoto A C consulta_desde A C "SELECT * FROM viajes_h2 WHERE id_viaje=302"

# L4 (5%): reporte global de pasajeros en los 3 nodos en paralelo
medir L4 multinodo A "A-B-C" consulta_multinodo A \
     "A:SELECT sum(pasajeros) FROM viajes_h0" \
     "B:SELECT sum(pasajeros) FROM viajes_h1" \
     "C:SELECT sum(pasajeros) FROM viajes_h2"

# E1 (25%): insertar viaje nuevo (+3 conserva id_viaje mod 3)
medir E1_A local  A A consulta_desde A A "INSERT INTO viajes_h0 SELECT (SELECT max(id_viaje)+3 FROM viajes_h0), id_bus, 1, id_ruta, now(), 10, 1.50 FROM buses_h0 WHERE id_bus = 3"
medir E1_B remoto A B consulta_desde A B "INSERT INTO viajes_h1 SELECT (SELECT max(id_viaje)+3 FROM viajes_h1), id_bus, 1, id_ruta, now(), 10, 1.50 FROM buses_h1 WHERE id_bus = 4"
medir E1_C remoto A C consulta_desde A C "INSERT INTO viajes_h2 SELECT (SELECT max(id_viaje)+3 FROM viajes_h2), id_bus, 1, id_ruta, now(), 10, 1.50 FROM buses_h2 WHERE id_bus = 5"

# E2 (5%): actualizar un bus segun id_bus mod 3
medir E2_A local  A A consulta_desde A A "UPDATE buses_h0 SET capacidad=30 WHERE id_bus=3"
medir E2_B remoto A B consulta_desde A B "UPDATE buses_h1 SET capacidad=30 WHERE id_bus=4"
medir E2_C remoto A C consulta_desde A C "UPDATE buses_h2 SET capacidad=30 WHERE id_bus=5"

echo "Listo: $OUT"
