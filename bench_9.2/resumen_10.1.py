import csv, statistics as s, collections

def cargar_medianas(ruta):
    d = collections.defaultdict(lambda: {"ejec": [], "red": [], "total": []})
    with open(ruta, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            d[r["operacion"]]["ejec"].append(float(r["ms_ejec"]))
            d[r["operacion"]]["red"].append(float(r["ms_red"]))
            d[r["operacion"]]["total"].append(float(r["ms_total"]))
    return {k: {m: s.median(v) for m, v in x.items()} for k, x in d.items()}

def avg(med, m, *ks):
    return sum(med[k][m] for k in ks) / len(ks)

import os
ruta_zona = "bench_9.2/resultados_9.2_1200k.csv" if os.path.exists("bench_9.2/resultados_9.2_1200k.csv") else "bench_9.2/resultados_9.2.csv"
print("Usando baseline zona:", ruta_zona)
med_zona = cargar_medianas(ruta_zona)
med_hash = cargar_medianas("bench_9.2/resultados_10.1_hash.csv")

print("=== TABLA 1: MEDIANAS ESTRATEGIA HASH (1 200 000 viajes, cliente en A) ===")
print("%-15s%11s%10s%12s" % ("operacion", "ejec (ms)", "red (ms)", "total (ms)"))
for k, x in med_hash.items():
    print("%-15s%11.3f%10.0f%12.3f" % (k, x["ejec"], x["red"], x["total"]))

W = {"L1": 0.35, "L2": 0.20, "L3": 0.10, "L4": 0.05, "E1": 0.25, "E2": 0.05}

def resumen_ops_zona(med, con_replicas=True):
    res = {}
    for m in ("ejec", "red", "total"):
        res[m] = {
            "L1": med["L1"][m],
            "L2": med["L2"][m],
            "L3": avg(med, m, "L3_replica", "L3_sur_rep") if con_replicas else avg(med, m, "L3_principal", "L3_sur"),
            "L4": med["L4_A_replicas"][m] if con_replicas else med["L4_desde_A"][m],
            "E1": med["E1"][m],
            "E2": med["E2"][m],
        }
    return res

def resumen_ops_hash(med):
    res = {}
    for m in ("ejec", "red", "total"):
        res[m] = {
            "L1": avg(med, m, "L1_A", "L1_B", "L1_C"),
            "L2": med["L2"][m],
            "L3": avg(med, m, "L3_A", "L3_B", "L3_C"),
            "L4": med["L4"][m],
            "E1": avg(med, m, "E1_A", "E1_B", "E1_C"),
            "E2": avg(med, m, "E2_A", "E2_B", "E2_C"),
        }
    return res

z_sin = resumen_ops_zona(med_zona, con_replicas=False)
z_con = resumen_ops_zona(med_zona, con_replicas=True)
h_ops = resumen_ops_hash(med_hash)

print("\n=== TABLA 2: COMPARACION POR OPERACION (Zona con replicas vs Hash - 1.2M) ===")
print("%-5s%6s | %10s%9s%10s | %10s%9s%10s" % ("Op", "Peso", "Zona ejec", "Zona red", "Zona tot", "Hash ejec", "Hash red", "Hash tot"))
for op in W:
    print("%-5s%5d%% | %10.3f%9.2f%10.3f | %10.3f%9.2f%10.3f" % (
        op, int(W[op]*100),
        z_con["ejec"][op], z_con["red"][op], z_con["total"][op],
        h_ops["ejec"][op], h_ops["red"][op], h_ops["total"][op]
    ))

def ponderado(ops_dict, m):
    return sum(W[op] * ops_dict[m][op] for op in W)

print("\n=== TABLA 3: COSTO PONDERADO MEZCLA 70/30 (cliente en A, 1 200 000 viajes) ===")
print("%-32s%11s%10s%12s" % ("Estrategia", "ejec (ms)", "red (ms)", "total (ms)"))
print("%-32s%11.3f%10.3f%12.3f" % ("Estrategia 1: Zona (sin rep.)", ponderado(z_sin,"ejec"), ponderado(z_sin,"red"), ponderado(z_sin,"total")))
print("%-32s%11.3f%10.3f%12.3f" % ("Estrategia 1: Zona (con rep.)", ponderado(z_con,"ejec"), ponderado(z_con,"red"), ponderado(z_con,"total")))
print("%-32s%11.3f%10.3f%12.3f" % ("Estrategia 2: Hash (id mod 3)", ponderado(h_ops,"ejec"), ponderado(h_ops,"red"), ponderado(h_ops,"total")))
