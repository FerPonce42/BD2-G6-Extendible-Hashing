# calcular_metricas.py
# Grupo 6 - BD2 - Actividad 7.3: registro de metricas (Maricielo Luna)
#
# Lee los resultados que ya estan en el repo (bench_5.2, bench_7.1 y bench_7.2),
# saca la MEDIANA de las 5 repeticiones de cada medicion y guarda todo en
# bench_7.3/metricas_7.3.csv
#
# No corre ningun benchmark: solo lee los .txt que ya se generaron.
# Asi cualquiera puede comprobar de donde sale cada numero de la tabla.
#
# Uso (desde la carpeta del proyecto):
#   python bench_7.3/calcular_metricas.py #

import os
import statistics

TAMANOS = [100000, 500000, 1000000]

# de que PC viene cada carpeta (ver los 00_entorno.txt)
PC_52 = "PC Etapa I (bench_5.2): i5-13420H"
PC_71 = "PC Fernando (bench_7.1): i5-12450H"
PC_72 = "PC Nicol (bench_7.2): CPU no registrado"

filas_csv = []   # aqui se van juntando las filas del csv


def leer(ruta):
    f = open(ruta, encoding="utf-8-sig")   # utf-8-sig por si el archivo trae BOM
    lineas = f.read().splitlines()
    f.close()
    return lineas


def columnas(linea):
    # " btree | 1 | 20000 | 54.505 | ..." -> ["btree", "1", "20000", "54.505", ...]
    return [c.strip() for c in linea.split("|")]


def agregar(metrica, metodo, n, tiempos, unidad, pc, origen, por=None):
    # guarda una fila con la mediana; "por" sirve para pasar a tiempo por operacion
    mediana = statistics.median(tiempos)
    if por is not None:
        mediana_por_op = mediana * 1000 / por    # ms -> us por operacion
    else:
        mediana_por_op = ""
    filas_csv.append([metrica, metodo, n, len(tiempos), round(mediana, 3),
                      mediana_por_op if mediana_por_op == "" else round(mediana_por_op, 3),
                      unidad, pc, origen])
    print("  %-14s %-16s %8d  reps=%d  mediana=%10.3f ms  %s" % (metrica, metodo, n, len(tiempos), mediana, pc))


def repeticiones_busqueda(ruta, metodo):
    # filas de la tabla "Resultado por repeticion": metodo | rep | n | total_ms | aciertos | esperados
    tiempos = []
    for linea in leer(ruta):
        c = columnas(linea)
        if len(c) == 6 and c[0] == metodo and c[1].isdigit():
            tiempos.append(float(c[3]))
    return tiempos


def repeticiones_construccion(ruta, metodo):
    # filas de "Construccion por repeticion": metodo | rep | filas | ms
    tiempos = []
    for linea in leer(ruta):
        c = columnas(linea)
        if len(c) == 4 and c[0] == metodo and c[1].isdigit():
            tiempos.append(float(c[3]))
    return tiempos


def tiempos_despues_de_insert(lineas):
    # el "Time:" que viene justo despues de "INSERT 0 ..." es el de la insercion
    tiempos = []
    vi_insert = False
    for linea in lineas:
        if linea.startswith("INSERT 0"):
            vi_insert = True
        elif vi_insert and linea.startswith("Time:"):
            tiempos.append(float(linea.split()[1]))
            vi_insert = False
    return tiempos


# busqueda
print("BUSQUEDA (20 000 claves: 10 000 W1 + 10 000 W2)")
for n in TAMANOS:
    ds = "D2_aleatorio_" + str(n)
    t = repeticiones_busqueda("bench_7.1/resultados/" + ds + "/01_sin_indice.txt", "sin_indice")
    agregar("busqueda", "sin_indice", n, t, "ms total", PC_71, "bench_7.1", por=20000)
    t = repeticiones_busqueda("bench_5.2/resultados/" + ds + "/02_btree.txt", "btree")
    agregar("busqueda", "btree", n, t, "ms total", PC_52, "bench_5.2", por=20000)
    for metodo in ["hashing_via_sql", "hashing_directo", "baseline_sql"]:
        t = repeticiones_busqueda("bench_5.2/resultados/" + ds + "/03_hashing.txt", metodo)
        agregar("busqueda", metodo, n, t, "ms total", PC_52, "bench_5.2", por=20000)

# construccion
print("\nCONSTRUCCION")
for n in TAMANOS:
    ruta = "bench_5.2/resultados/D2_aleatorio_" + str(n) + "/04_construccion_tamano.txt"
    agregar("construccion", "btree", n, repeticiones_construccion(ruta, "btree"), "ms total", PC_52, "bench_5.2", por=n)
    agregar("construccion", "hashing", n, repeticiones_construccion(ruta, "hashing"), "ms total", PC_52, "bench_5.2", por=n)

# insercion (W3) - se inserta al 10% del tamano
print("\nINSERCION W3 (10% del tamano)")
# sin indice: un archivo por tamano (bench_7.1)
for n in TAMANOS:
    ruta = "bench_7.1/resultados_inserciones/D2_aleatorio_" + str(n) + "/inserciones_sin_indice.txt"
    agregar("insercion", "sin_indice", n, tiempos_despues_de_insert(leer(ruta)), "ms total", PC_71, "bench_7.1", por=n // 10)

# B-tree y hash: todo en un solo archivo (bench_7.2), separado por tamano
lineas = leer("bench_7.2/resultados_crudos.txt")
bloques = {}         # tamano -> lineas de ese tamano
actual = None
for linea in lineas:
    if linea.startswith("Preparando Dataset D2 - Tama"):
        actual = int(linea.split(":")[1].split()[0])
        bloques[actual] = []
    elif actual is not None:
        bloques[actual].append(linea)

for n in TAMANOS:
    btree = []
    hashing = []
    modo = None
    vi_insert = False
    for linea in bloques[n]:
        if linea.startswith("Prueba B-Tree"):
            modo = "btree"
        elif linea.startswith("Prueba Hash"):
            modo = "hash"
        elif modo == "btree":
            if linea.startswith("INSERT 0"):
                vi_insert = True
            elif vi_insert and linea.startswith("Time:"):
                btree.append(float(linea.split()[1]))
                vi_insert = False
        elif modo == "hash" and linea.startswith("Time:"):
            # en el hash el unico Time: medido es el de las inserciones nuevas
            hashing.append(float(linea.split()[1]))
            modo = None
    agregar("insercion", "btree", n, btree, "ms total", PC_72, "bench_7.2", por=n // 10)
    agregar("insercion", "hashing", n, hashing, "ms total", PC_72, "bench_7.2", por=n // 10)
    print("    (media de Nicol, solo de referencia: btree=%.3f  hash=%.3f)" % (statistics.mean(btree), statistics.mean(hashing)))

# guardar csv
os.makedirs("bench_7.3", exist_ok=True)
f = open("bench_7.3/metricas_7.3.csv", "w", encoding="utf-8")
f.write("metrica,metodo,filas,repeticiones,mediana_ms,mediana_us_por_operacion,unidad,pc,origen\n")
for fila in filas_csv:
    f.write(",".join(str(x) for x in fila) + "\n")
f.close()
print("\nListo. Guardado en bench_7.3/metricas_7.3.csv (" + str(len(filas_csv)) + " filas)")
