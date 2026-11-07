import csv, statistics as s, collections

d = collections.defaultdict(lambda: {"ejec": [], "red": [], "total": []})
for r in csv.DictReader(open("bench_9.2/resultados_9.2.csv")):
    d[r["operacion"]]["ejec"].append(float(r["ms_ejec"]))
    d[r["operacion"]]["red"].append(float(r["ms_red"]))
    d[r["operacion"]]["total"].append(float(r["ms_total"]))
med = {k: {m: s.median(v) for m, v in x.items()} for k, x in d.items()}

print(f"{'operacion':15}{'ejec':>9}{'red':>7}{'total':>9}")
for k, x in med.items():
    print(f"{k:15}{x['ejec']:9.3f}{x['red']:7.0f}{x['total']:9.3f}")

W = {"L1": .35, "L2": .20, "L3": .10, "L4": .05, "E1": .25, "E2": .05}
def avg(m, *ks): return sum(med[k][m] for k in ks) / len(ks)

print("\nCosto ponderado por operacion (cliente en A), mezcla 70/30 de 8.1/8.2")
for m in ("total", "red"):
    sin = {"L1": med["L1"][m], "L2": med["L2"][m],
           "L3": avg(m, "L3_principal", "L3_sur"), "L4": med["L4_desde_A"][m],
           "E1": med["E1"][m], "E2": med["E2"][m]}
    con = dict(sin, L3=avg(m, "L3_replica", "L3_sur_rep"), L4=med["L4_A_replicas"][m])
    f = lambda c: sum(W[o] * c[o] for o in W)
    print(f"{m:6} sin replicas: {f(sin):7.3f} ms | con replicas: {f(con):7.3f} ms")
    