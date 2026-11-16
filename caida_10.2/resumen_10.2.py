# resumen_10.2.py
# Grupo 6 - BD2 - Actividad 10.2 (Iair Suico)
# Resume los CSV de caida_nodo.sh: para cada prueba, estado y zona de los clientes,
#   - disponibilidad: que parte de la mezcla 70/30 (8.1/8.2, seccion 4.3) se pudo hacer
#   - costo ponderado: ms por operacion (ejecucion medida + red supuesta), solo de las que funcionaron
#   - detalle por operacion: mediana del total, en que nodo y si fue la principal o la replica
# Uso (desde la raiz del repositorio): python caida_10.2/resumen_10.2.py
# El resumen tambien se guarda en caida_10.2/resultados/resumen_10.2.txt

import csv
import glob
import os
import statistics

PESO = {"L1": 0.35, "L2": 0.20, "L3": 0.10, "L4": 0.05, "E1": 0.25, "E2": 0.05}
ORDEN_ESTADOS = ["normal", "caido", "recuperado", "promovido"]
ZONAS = ["norte", "centro", "sur"]
CARPETA = os.path.join("caida_10.2", "resultados")

salida = []


def p(texto=""):
    print(texto)
    salida.append(texto)


for archivo in sorted(glob.glob(os.path.join(CARPETA, "*.csv"))):
    filas = list(csv.DictReader(open(archivo, encoding="utf-8")))
    if not filas:
        continue
    nombre = os.path.basename(archivo)[:-4]
    p("=" * 78)
    p("Prueba: " + nombre)
    estados = [e for e in ORDEN_ESTADOS if any(f["estado"] == e for f in filas)]

    p("")
    p("Disponibilidad de la mezcla y costo ponderado (ms por operacion que funciono)")
    p("%-11s" % "estado" + "".join("%-24s" % ("clientes " + z) for z in ZONAS))
    for e in estados:
        linea = "%-11s" % e
        for z in ZONAS:
            disp = 0.0
            costo = 0.0
            for op, peso in PESO.items():
                rep = [f for f in filas if f["estado"] == e and f["cliente"] == z and f["operacion"] == op]
                ok = [f for f in rep if f["resultado"] == "OK"]
                if not rep:
                    continue
                frac = len(ok) / len(rep)
                disp += peso * frac
                if ok:
                    costo += peso * frac * statistics.median(float(f["ms_total"]) for f in ok)
            costo_ok = costo / disp if disp > 0 else 0
            linea += "%-24s" % ("%5.1f %%  %7.2f ms" % (disp * 100, costo_ok))
        p(linea)

    p("")
    p("Detalle: mediana del total en ms [nodo, copia] o FALLA")
    for e in estados:
        p("  " + e)
        for z in ZONAS:
            partes = []
            for op in PESO:
                rep = [f for f in filas if f["estado"] == e and f["cliente"] == z and f["operacion"] == op]
                ok = [f for f in rep if f["resultado"] == "OK"]
                if not rep:
                    continue
                if not ok:
                    partes.append("%s FALLA" % op)
                    continue
                med = statistics.median(float(f["ms_total"]) for f in ok)
                copia = {"principal": "P", "replica": "R", "mixta": "P+R"}.get(ok[0]["copia"], ok[0]["copia"])
                extra = "" if len(ok) == len(rep) else " (%d/%d)" % (len(ok), len(rep))
                partes.append("%s %.1f [%s %s]%s" % (op, med, ok[0]["nodo"], copia, extra))
            p("    %-7s %s" % (z, "  ".join(partes)))
    p("")
    txt = os.path.join(CARPETA, nombre + ".txt")
    if os.path.exists(txt):
        p("Tiempos y conteos (" + os.path.basename(txt) + "):")
        for l in open(txt, encoding="utf-8"):
            if not l.startswith(">>>") and not l.startswith("    ") and "operaciones," not in l:
                p("  " + l.rstrip())
    p("")

with open(os.path.join(CARPETA, "resumen_10.2.txt"), "w", encoding="utf-8") as f:
    f.write("\n".join(salida) + "\n")
