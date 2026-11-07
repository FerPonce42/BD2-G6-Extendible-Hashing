#!/bin/bash
# 9.2 - Nicol Rocha. Funciones comunes.
# Latencias de la rúbrica (ms) entre nodos.
declare -A LAT=( [AA]=0 [BB]=0 [CC]=0 [AB]=20 [BA]=20 [AC]=40 [CA]=40 [BC]=25 [CB]=25 )
declare -A PUERTO=( [A]=5433 [B]=5434 [C]=5435 )
declare -A CONT=( [A]=nodo_a [B]=nodo_b [C]=nodo_c )

# sql_en NODO "consulta" -> ejecuta en ese nodo (sin simular latencia)
sql_en() { MSYS_NO_PATHCONV=1 docker exec -i "${CONT[$1]}" psql -U postgres -d distribuido -At -c "$2"; }

# ms_ahora -> tiempo en milisegundos (con decimales)
ms_ahora() { date +%s.%N | awk '{printf "%.3f", $1*1000}'; }

# consulta_desde ORIGEN DESTINO "sql"
# Ejecuta en DESTINO y suma la latencia simulada ORIGEN->DESTINO (ida y vuelta = 1 vez, como en 8.1/8.2).
# tiempo_servidor NODO "sql" -> ms que tardó la consulta según PostgreSQL
tiempo_servidor() {
  MSYS_NO_PATHCONV=1 docker exec -i "${CONT[$1]}" psql -U postgres -d distribuido -At \
    -c '\timing on' -c "$2" | awk '/^Time:/{t=$2} END{print t}'
}

# consulta_desde ORIGEN DESTINO "sql" -> imprime: ms_ejec ms_red ms_total
consulta_desde() {
  local o=$1 d=$2 q=$3 e red
  e=$(tiempo_servidor "$d" "$q")
  red=${LAT[$o$d]}
  sleep "$(awk -v r="$red" 'BEGIN{print r/1000}')"
  awk -v e="$e" -v r="$red" 'BEGIN{printf "%.3f %d %.3f\n", e, r, e+r}'
}

# consulta_multinodo ORIGEN "NODO:sql" "NODO:sql" ...
# En paralelo: ejecución = la más lenta, red = la del nodo más lejano.
consulta_multinodo() {
  local o=$1; shift
  local maxred=0 par d q r tmp f
  tmp=$(mktemp -d)
  for par in "$@"; do
    d=${par%%:*}; q=${par#*:}
    ( tiempo_servidor "$d" "$q" > "$tmp/$d" ) &
    r=${LAT[$o$d]}; (( r > maxred )) && maxred=$r
  done
  wait
  local maxe=0 v
  for f in "$tmp"/*; do
    v=$(cat "$f"); maxe=$(awk -v a="$maxe" -v b="$v" 'BEGIN{print (b>a)?b:a}')
  done
  rm -rf "$tmp"
  sleep "$(awk -v r="$maxred" 'BEGIN{print r/1000}')"
  awk -v e="$maxe" -v r="$maxred" 'BEGIN{printf "%.3f %d %.3f\n", e, r, e+r}'
}