#!/usr/bin/env python3
"""
carga_sur.py
Grupo 6 - BD2 - Actividad 10.3: prueba de cambio de carga de trabajo (Fabricio Stelman)

Escenario (8.1/8.2 seccion 4.5 y 8.3 secciones 6 y 8): la concentracion de accesos cambia y
la zona Sur pasa de 30 % a 60 % del trafico. Con la fragmentacion por zona, el nodo C
(principal de Sur) se sobrecarga. Se mide si mandar las lecturas de otras zonas y los
reportes a las replicas descarga a C, y cuanto sube la carga de B (que tiene las replicas).

Que hace distinto de 10.2: aqui importa la CARGA, no un solo cliente. Por eso usa pgbench
con una tasa fija de operaciones por segundo (--rate) en cada nodo, y cada nodo se limita a
las mismas CPU (docker update --cpus) para que la saturacion de C se vea aunque los tres
contenedores esten en la misma PC. Los clientes corren en un contenedor aparte, para no
quitarle CPU a los nodos. La red entre nodos NO se mide: se suma la latencia de la rubrica
(bench_9.2/lib.sh), igual que en 9.2 y 10.2.

Cuatro corridas (escenario, politica de lectura):
  base   / principal     trafico 30/40/30, todo se lee en la copia principal (punto de partida)
  sur    / principal     Sur al 60 %, todo en la principal          -> C se sobrecarga
  sur    / replica       Sur al 60 %, L3 y L4 leen de la replica (8.3, seccion 6)
  sur    / replica_sur   igual, y ademas L1 y L2 de los clientes de Sur leen en B (lectura
                         posiblemente atrasada; las escrituras de Sur siguen en C)

Modos:
  plan       muestra cuantas operaciones por segundo recibe cada nodo en cada corrida (sin Docker)
  calibrar   mide cuanto aguanta cada nodo y sugiere --total
  capacidad  en cada corrida sube la carga total (x1,2 por paso) hasta que algun nodo se satura (confirmado en 2 intentos)
  correr     hace las 4 corridas y guarda los resultados
  resumen    calcula las tablas a partir de los CSV

Requisitos: nodos de la 9.1 levantados, con suscripciones, y cargados con
generador/cargar_distribuido.sh (estrategia por zona). Imagen bd2_g6_nodo (trae pgbench).

Uso (desde la raiz del repositorio):
  py carga_10.3/carga_sur.py plan --total 3000
  py carga_10.3/carga_sur.py calibrar
  py carga_10.3/carga_sur.py capacidad --rep 5
  py carga_10.3/carga_sur.py correr --total <80 % de la maxima de base/principal> --rep 5
  py carga_10.3/carga_sur.py resumen --total <el mismo>
"""
import argparse, collections, csv, os, re, statistics as st, subprocess, sys, tempfile, time

NODOS = ["A", "B", "C"]
CONT = {"A": "nodo_a", "B": "nodo_b", "C": "nodo_c"}
IMAGEN = "bd2_g6_nodo"
CLIENTE = "cliente_10_3"
ZONAS = ["norte", "centro", "sur"]
PRINC = {"norte": "A", "centro": "B", "sur": "C"}
REPL = {"norte": "B", "centro": "A", "sur": "B"}
CASA = {"norte": "A", "centro": "B", "sur": "C"}          # nodo al que se conectan los clientes
OTRA = {"norte": "centro", "centro": "sur", "sur": "norte"}  # zona que lee L3 (igual que 10.2)
RUTAS = {"norte": (1, 3), "centro": (4, 7), "sur": (8, 10)}
# latencias de la rubrica (ms), las mismas de bench_9.2/lib.sh
LAT = {"AA": 0, "BB": 0, "CC": 0, "AB": 20, "BA": 20, "AC": 40, "CA": 40, "BC": 25, "CB": 25}
W = {"L1": .35, "L2": .20, "L3": .10, "L4": .05, "E1": .25, "E2": .05}   # mezcla 70/30 de 8.1/8.2
CORRIDAS = [("base", "principal"), ("sur", "principal"), ("sur", "replica"), ("sur", "replica_sur")]
DIR = os.path.join("carga_10.3", "resultados")
F_CORR = os.path.join(DIR, "corridas.csv")
F_SCR = os.path.join(DIR, "scripts.csv")
F_TXT = os.path.join(DIR, "corridas.txt")
F_CAP = os.path.join(DIR, "capacidad.csv")
F_CAPTXT = os.path.join(DIR, "capacidad.txt")
F_RES = os.path.join(DIR, "resumen.txt")


# ------------------------------------------------------------------ modelo de carga
def composicion(esc, sur):
    """Parte del trafico de cada zona. 'sur': Sur=sur y el resto se reparte 30:40 entre Norte y Centro."""
    if esc == "base":
        return {"norte": .30, "centro": .40, "sur": .30}
    return {"norte": (1 - sur) * 3 / 7, "centro": (1 - sur) * 4 / 7, "sur": sur}


def destinos(z, op, pol):
    """Lista de (nodo, clave) a los que va la operacion op de un cliente de la zona z."""
    if op in ("L1", "L2"):
        n = PRINC[z]
        if pol == "replica_sur" and z == "sur":
            n = REPL[z]
        return [(n, "%s_%s" % (op, z))]
    if op == "L3":                       # leer un viaje de otra zona; misma consulta que L1
        w = OTRA[z]
        return [(PRINC[w] if pol == "principal" else REPL[w], "L1_" + w)]
    if op == "L4":                       # reporte global: cada zona en una copia, en paralelo
        return [(PRINC[zz] if pol == "principal" else REPL[zz], "L4_" + zz) for zz in ZONAS]
    return [(PRINC[z], "%s_%s" % (op, z))]   # escrituras: solo en la copia principal


def tasas(esc, pol, total, sur):
    """nodo -> clave -> operaciones por segundo que le llegan, con 'total' ops/s en todo el sistema."""
    r = {n: collections.defaultdict(float) for n in NODOS}
    comp = composicion(esc, sur)
    for z in ZONAS:
        for op, w in W.items():
            for n, k in destinos(z, op, pol):
                r[n][k] += total * comp[z] * w
    return r


def costo_ponderado(esc, pol, sur, lat):
    """ms por operacion: ejecucion medida bajo carga + red de la rubrica. lat[(nodo, clave)] en ms."""
    comp = composicion(esc, sur)
    tot = {"ejec": 0.0, "red": 0.0}
    for z in ZONAS:
        for op, w in W.items():
            d = destinos(z, op, pol)
            e = [lat[(n, k)] for n, k in d]
            ejec = max(e) if op == "L4" else e[0]
            red = max(LAT[CASA[z] + n] for n, _ in d)
            tot["ejec"] += comp[z] * w * ejec
            tot["red"] += comp[z] * w * red
    return tot["ejec"], tot["red"]


# ------------------------------------------------------------------ scripts de pgbench
def sql_clave(clave, rg):
    """Texto del script de pgbench de una clave (por ejemplo L1_sur). rg: rangos de la zona."""
    op, z = clave.split("_")
    v, b = "viajes_" + z, "buses_" + z
    if op == "L1":   # primer viaje con id >= r: una sola busqueda en el indice, como un punto
        return ("\\set r random(%d, %d)\n"
                "SELECT * FROM %s WHERE id_viaje >= :r ORDER BY id_viaje LIMIT 1;\n" % (rg[z]["vmin"], rg[z]["vmax"], v))
    if op == "L2":
        a, c = RUTAS[z]
        return ("\\set ruta random(%d, %d)\n\\set d random(0, 270)\n"
                "SELECT count(*) FROM %s WHERE id_ruta = :ruta AND salida BETWEEN date '2026-01-01' + :d AND date '2026-01-01' + :d + 19;\n"
                % (a, c, v))
    if op == "L4":
        return "SELECT sum(pasajeros) FROM %s;\n" % v
    if op == "E1":   # id propio de cada cliente, fuera del rango del generador (hay que pasar -D n=0)
        return ("\\set b random(%d, %d)\n\\set n :n + 1\n\\set id 3000000 + (:client_id * 1000000) + :n\n"
                "INSERT INTO %s SELECT :id, id_bus, 1, id_ruta, timestamp '2026-12-01 08:00', 10, 1.50 "
                "FROM %s WHERE id_bus >= :b ORDER BY id_bus LIMIT 1;\n" % (rg[z]["bmin"], rg[z]["bmax"], v, b))
    if op == "E2":
        return ("\\set b random(%d, %d)\n"
                "UPDATE %s SET capacidad = capacidad WHERE id_bus = (SELECT min(id_bus) FROM %s WHERE id_bus >= :b);\n"
                % (rg[z]["bmin"], rg[z]["bmax"], b, b))
    raise ValueError(clave)


# ------------------------------------------------------------------ docker
def run(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)


def psql(nodo, sql):
    p = run(["docker", "exec", CONT[nodo], "psql", "-U", "postgres", "-d", "distribuido", "-At", "-F", ",",
             "-v", "ON_ERROR_STOP=1", "-c", sql])
    if p.returncode != 0:
        raise RuntimeError("psql en %s fallo: %s" % (CONT[nodo], p.stderr.strip()))
    return p.stdout.strip()


def rangos():
    rg = {}
    for z in ZONAS:
        n = PRINC[z]
        vmin, vmax = psql(n, "SELECT min(id_viaje), max(id_viaje) FROM viajes_%s" % z).split(",")
        bmin, bmax = psql(n, "SELECT min(id_bus), max(id_bus) FROM buses_%s" % z).split(",")
        rg[z] = {"vmin": int(vmin), "vmax": int(vmax), "bmin": int(bmin), "bmax": int(bmax)}
    return rg


def preparar_cliente(rg, cpus):
    """Limita las CPU de los nodos y levanta un contenedor cliente con pgbench y los scripts."""
    for n in NODOS:
        if run(["docker", "inspect", "-f", "{{.State.Running}}", CONT[n]]).stdout.strip() != "true":
            sys.exit("%s no esta corriendo. Levanta los 3 nodos (nodos/README.md)." % CONT[n])
    if run(["docker", "exec", CONT["A"], "pgbench", "--version"]).returncode != 0:
        sys.exit("No encuentro pgbench en la imagen. Prueba: docker exec nodo_a pgbench --version")
    red = run(["docker", "inspect", "-f", "{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}",
               CONT["A"]]).stdout.split()[0]
    run(["docker", "rm", "-f", CLIENTE])
    p = run(["docker", "run", "-d", "--name", CLIENTE, "--network", red, "-e", "PGPASSWORD=password123",
             IMAGEN, "sleep", "infinity"])
    if p.returncode != 0:
        sys.exit("No pude crear el contenedor cliente: " + p.stderr)
    carpeta = tempfile.mkdtemp()
    for z in ZONAS:
        for op in ("L1", "L2", "L4", "E1", "E2"):
            with open(os.path.join(carpeta, "%s_%s.sql" % (op, z)), "w") as f:
                f.write(sql_clave("%s_%s" % (op, z), rg))
    run(["docker", "exec", CLIENTE, "mkdir", "-p", "/scripts"])
    for nom in os.listdir(carpeta):
        run(["docker", "cp", os.path.join(carpeta, nom), CLIENTE + ":/scripts/" + nom])
    if cpus > 0:
        run(["docker", "update", "--cpus=%s" % cpus] + [CONT[n] for n in NODOS])


def limpiar_cliente(cpus):
    run(["docker", "rm", "-f", CLIENTE])
    if cpus > 0:
        run(["docker", "update", "--cpus=0"] + [CONT[n] for n in NODOS])   # 0 = sin limite


def borrar_prueba_y_esperar():
    """Borra las filas que insertan las corridas (salida >= 2026-12-01) y espera a que las replicas igualen."""
    for z in ZONAS:
        psql(PRINC[z], "DELETE FROM viajes_%s WHERE salida >= '2026-12-01'" % z)
    for _ in range(180):
        ok = True
        for z in ZONAS:
            c = "SELECT count(*) FROM viajes_%s WHERE salida >= '2026-12-01'" % z
            if psql(PRINC[z], c) != psql(REPL[z], c):
                ok = False
        if ok:
            return
        time.sleep(1)
    print("AVISO: las replicas no igualaron en 180 s")


# ------------------------------------------------------------------ pgbench
def argv_pgbench(nodo, tasa_nodo, claves, dur, clientes):
    a = ["docker", "exec", CLIENTE, "pgbench", "-n", "-h", CONT[nodo], "-U", "postgres", "-d", "distribuido",
         "-c", str(clientes), "-j", "2", "-T", str(dur), "-D", "n=0"]
    if tasa_nodo:
        a += ["-R", "%.2f" % tasa_nodo]
    tot = sum(claves.values())
    for k, v in claves.items():
        a += ["-f", "/scripts/%s.sql@%d" % (k, max(1, round(v / tot * 1000)))]
    return a


def parsear(txt):
    """Resumen general y latencia por script de una salida de pgbench."""
    partes = re.split(r"^SQL script \d+: ", txt, flags=re.M)
    g = partes[0]
    num = lambda pat, s: float(re.search(pat, s).group(1)) if re.search(pat, s) else None
    res = {"tps": num(r"tps = ([\d.]+)", g), "lat": num(r"latency average = ([\d.]+) ms", g),
           "desv": num(r"latency stddev = ([\d.]+) ms", g),
           "lag": num(r"schedule lag: avg ([\d.]+)", g), "lagmax": num(r"schedule lag: avg [\d.]+ \(max ([\d.]+)\)", g),
           "tx": num(r"transactions actually processed: (\d+)", g), "fallidas": num(r"failed transactions: (\d+)", g) or 0}
    scr = {}
    for b in partes[1:]:
        nombre = os.path.basename(b.split("\n")[0]).replace(".sql", "")
        scr[nombre] = {"lat": num(r"latency average = ([\d.]+) ms", b), "tx": num(r" - (\d+) transactions", b)}
    return res, scr


def ejecutar(plan, dur, clientes, usar_tasa=True):
    """Lanza pgbench en los tres nodos a la vez. plan: nodo -> clave -> ops/s. Devuelve nodo -> (texto, resumen, scripts)."""
    procs = {}
    for n in NODOS:
        tasa = sum(plan[n].values()) if usar_tasa else None
        procs[n] = subprocess.Popen(argv_pgbench(n, tasa, plan[n], dur, clientes),
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    out = {}
    for n, p in procs.items():
        txt = p.communicate()[0]
        res, scr = parsear(txt)
        out[n] = (txt, res, scr)
    return out


class Tee_append:
    """Como Tee, pero sobre un archivo ya abierto."""
    def __init__(self, f):
        self.f, self.o = f, sys.stdout

    def write(self, x):
        self.o.write(x); self.f.write(x)

    def flush(self):
        self.o.flush(); self.f.flush()


class Tee:
    """Escribe en pantalla y en un archivo de texto a la vez."""
    def __init__(self, ruta):
        self.f = open(ruta, "w", encoding="utf-8")
        self.o = sys.stdout

    def write(self, x):
        self.o.write(x); self.f.write(x)

    def flush(self):
        self.o.flush(); self.f.flush()


def con_copia(ruta, fn, *args):
    """Ejecuta fn mostrando su salida en pantalla y guardandola en ruta."""
    os.makedirs(DIR, exist_ok=True)
    t = Tee(ruta)
    sys.stdout = t
    try:
        fn(*args)
    finally:
        sys.stdout = t.o
        t.f.close()
    print("Guardado en %s" % ruta)


# ------------------------------------------------------------------ modos
def modo_plan(a):
    print("Operaciones por segundo que recibe cada nodo (total = %g ops/s, Sur = %.0f %%)\n" % (a.total, a.sur * 100))
    print("%-22s %9s %9s %9s   %s" % ("corrida", "A", "B", "C", "C respecto a la base"))
    base_c = None
    for esc, pol in CORRIDAS:
        t = tasas(esc, pol, a.total, a.sur)
        s = {n: sum(t[n].values()) for n in NODOS}
        base_c = base_c or s["C"]
        print("%-22s %9.1f %9.1f %9.1f   x%.2f" % ("%s / %s" % (esc, pol), s["A"], s["B"], s["C"], s["C"] / base_c))


def modo_calibrar(a):
    rg = rangos()
    preparar_cliente(rg, a.cpus)
    try:
        cap = {}
        plan = tasas("sur", "principal", 1.0, a.sur)
        for n in NODOS:     # de a un nodo por vez, sin limite de tasa: cuanto aguanta con su mezcla de la corrida sur/principal
            p = subprocess.run(argv_pgbench(n, None, plan[n], a.dur, a.clientes), capture_output=True, text=True)
            res, _ = parsear(p.stdout)
            cap[n] = res["tps"]
            print("%s aguanta %.0f ops/s con su mezcla de la corrida sur/principal (latencia %.2f ms)" % (n, res["tps"], res["lat"]))
            borrar_prueba_y_esperar()
        frac_c = sum(plan["C"].values())
        total = a.util * cap["C"] / frac_c
        print("\nSugerencia: --total %d  (C al %.0f %% de lo que aguanta en la corrida sur/principal)" % (total, a.util * 100))
        print("\nUtilizacion esperada de cada nodo (ops/s ofrecidas / ops/s que aguanta):")
        for esc, pol in CORRIDAS:
            t = tasas(esc, pol, total, a.sur)
            print("  %-20s" % ("%s / %s" % (esc, pol)) + "  ".join("%s %3.0f %%" % (n, 100 * sum(t[n].values()) / cap[n]) for n in NODOS))
        print("(aproximado: la capacidad de cada nodo se midio con su mezcla de la corrida sur/principal)")
    finally:
        limpiar_cliente(a.cpus)


def saturado(plan, res_nodos, umbral_logro, umbral_lag):
    """Nodos saturados en un paso: logra < umbral_logro de lo ofrecido, atraso > umbral_lag ms o fallas."""
    malos = {}
    for n in NODOS:
        res = res_nodos[n]
        of = sum(plan[n].values())
        if res["tps"] is None:
            malos[n] = "sin salida de pgbench"
        elif res["tps"] < umbral_logro * of:
            malos[n] = "logra %.0f %% de lo ofrecido" % (100 * res["tps"] / of)
        elif (res["lag"] or 0) > umbral_lag:
            malos[n] = "atraso %.0f ms" % res["lag"]
        elif res["fallidas"] > 0:
            malos[n] = "%d fallidas" % res["fallidas"]
    return malos


def modo_capacidad(a):
    os.makedirs(DIR, exist_ok=True)
    rg = rangos()
    preparar_cliente(rg, a.cpus)
    cf = open(F_CAP, "w", newline="")
    w = csv.writer(cf)
    w.writerow(["escenario", "politica", "rep", "paso", "total_ops", "nodo", "ofrecidas", "tps", "lat_ms",
                "lag_ms", "lagmax_ms", "fallidas", "saturado", "motivo"])
    ct = open(F_CAPTXT, "w", encoding="utf-8")
    ct.write("10.3 capacidad - %s - sur=%g inicio=%g factor=%g dur_paso=%ss rep=%d clientes=%d cpus=%s\n" % (
        time.strftime("%Y-%m-%d %H:%M:%S"), a.sur, a.inicio, a.factor, a.dur_paso, a.rep, a.clientes, a.cpus))
    ct.write(run(["docker", "exec", CONT["A"], "pgbench", "--version"]).stdout)
    try:
        borrar_prueba_y_esperar()
        for esc, pol in CORRIDAS:
            for rep in range(1, a.rep + 1):
                total, paso, racha = a.inicio, 0, 0
                print(">>> %s / %s  rep %d/%d: subiendo la carga desde %g ops/s (paso x%.1f, %ds)" % (
                    esc, pol, rep, a.rep, total, a.factor, a.dur_paso))
                while paso < a.max_pasos:
                    paso += 1
                    plan = tasas(esc, pol, total, a.sur)
                    out = ejecutar(plan, a.dur_paso, a.clientes)
                    res = {n: out[n][1] for n in NODOS}
                    malos = saturado(plan, res, a.umbral, 20.0)
                    for n in NODOS:
                        ct.write("\n===== %s / %s rep %d paso %d total %.1f nodo %s =====\n%s" % (
                            esc, pol, rep, paso, total, n, out[n][0]))
                    ct.flush()
                    for n in NODOS:
                        r = res[n]
                        w.writerow([esc, pol, rep, paso, "%.1f" % total, n, "%.2f" % sum(plan[n].values()), r["tps"],
                                    r["lat"], r["lag"], r["lagmax"], r["fallidas"], int(n in malos), malos.get(n, "")])
                    cf.flush()
                    print("   total %7.1f ops/s: " % total + "  ".join(
                        "%s %5.0f/%-5.0f%s" % (n, res[n]["tps"] or 0, sum(plan[n].values()), "*" if n in malos else "")
                        for n in NODOS))
                    borrar_prueba_y_esperar()
                    if malos:
                        racha += 1
                        print("   saturado: " + ", ".join("%s (%s)" % (n, m) for n, m in malos.items()))
                        if racha >= a.confirmar:
                            break
                        print("   repito el mismo paso para confirmar (puede ser ruido)")
                        continue
                    racha = 0
                    total *= a.factor
                else:
                    print("   AVISO: no se saturo en %d pasos; sube --max_pasos o --inicio" % a.max_pasos)
    finally:
        cf.close()
        limpiar_cliente(a.cpus)
    try:
        con_copia_cap = Tee_append(ct)
        sys.stdout = con_copia_cap
        ct.write("\n\n===== RESUMEN =====\n")
        resumen_capacidad()
    finally:
        sys.stdout = con_copia_cap.o
        ct.close()


def resumen_capacidad():
    """Maxima carga sostenida y nodo que se satura primero, por corrida.
    Un nivel de carga cuenta como saturado solo si todos sus intentos saturaron (se confirma repitiendo)."""
    if not os.path.exists(F_CAP):
        return
    intentos = collections.defaultdict(lambda: collections.defaultdict(lambda: collections.defaultdict(list)))
    for r in csv.DictReader(open(F_CAP)):
        intentos[(r["escenario"], r["politica"], int(r["rep"]))][float(r["total_ops"])][int(r["paso"])].append(r)
    print("Carga maxima sostenida (mediana de las repeticiones; precision de un paso)\n")
    print("%-20s %6s %12s %12s   %s" % ("corrida", "reps", "maxima ops/s", "rango", "nodo(s) que se satura(n) primero"))
    for esc, pol in CORRIDAS:
        maximos, culpables, sin_techo = [], collections.Counter(), 0
        for (e, p, rep), niveles in intentos.items():
            if (e, p) != (esc, pol):
                continue
            ultimo_ok, culpa = None, None
            for total in sorted(niveles):
                ints = niveles[total]
                if all(any(f["saturado"] == "1" for f in fs) for fs in ints.values()):
                    ultimo = ints[max(ints)]
                    culpa = [f["nodo"] for f in ultimo if f["saturado"] == "1"]
                    break
                ultimo_ok = total
            if ultimo_ok is None:
                sin_techo += 1          # ya saturaba en el primer nivel: el techo esta por debajo de --inicio
                continue
            maximos.append(ultimo_ok)
            for n in culpa or []:
                culpables[n] += 1
        if not maximos:
            print("%-20s %6d %12s %12s   %s" % ("%s / %s" % (esc, pol), sin_techo, "< inicio", "-", "-"))
            continue
        extra = "  (+%d rep. sin techo medible)" % sin_techo if sin_techo else ""
        print("%-20s %6d %12.0f %12s   %s%s" % ("%s / %s" % (esc, pol), len(maximos), st.median(maximos),
              "%.0f-%.0f" % (min(maximos), max(maximos)),
              ", ".join("%s (%d/%d)" % (n, c, len(maximos)) for n, c in culpables.most_common()) or "-", extra))
    print()


def modo_correr(a):
    if not a.total:
        sys.exit("Falta --total. Corre primero: py carga_10.3/carga_sur.py calibrar")
    if a.rep < 5:
        print("AVISO: la rubrica pide minimo 5 repeticiones por medicion (usa --rep 5 o mas)")
    os.makedirs(DIR, exist_ok=True)
    rg = rangos()
    preparar_cliente(rg, a.cpus)
    cc = open(F_CORR, "w", newline="")
    cs = open(F_SCR, "w", newline="")
    wc, ws = csv.writer(cc), csv.writer(cs)
    wc.writerow(["escenario", "politica", "rep", "nodo", "ops_ofrecidas", "tps", "lat_ms", "desv_ms", "lag_ms", "lagmax_ms", "fallidas"])
    ws.writerow(["escenario", "politica", "rep", "nodo", "clave", "lat_ms", "transacciones"])
    txt = open(F_TXT, "w")
    txt.write("10.3 - %s - total=%g ops/s sur=%g dur=%ss rep=%d clientes=%d cpus=%s\n" % (
        time.strftime("%Y-%m-%d %H:%M:%S"), a.total, a.sur, a.dur, a.rep, a.clientes, a.cpus))
    txt.write(run(["docker", "exec", CONT["A"], "pgbench", "--version"]).stdout)
    try:
        borrar_prueba_y_esperar()
        for esc, pol in CORRIDAS:
            plan = tasas(esc, pol, a.total, a.sur)
            for rep in range(1, a.rep + 1):
                print(">>> %s / %s  rep %d/%d (%ds)" % (esc, pol, rep, a.rep, a.dur))
                out = ejecutar(plan, a.dur, a.clientes)
                for n in NODOS:
                    t, res, scr = out[n]
                    txt.write("\n===== %s / %s rep %d nodo %s =====\n%s" % (esc, pol, rep, n, t))
                    if res["tps"] is None:
                        print("   %s: no pude leer la salida de pgbench (ver %s)" % (n, F_TXT))
                        continue
                    wc.writerow([esc, pol, rep, n, "%.2f" % sum(plan[n].values()), res["tps"], res["lat"], res["desv"],
                                 res["lag"], res["lagmax"], res["fallidas"]])
                    for k, v in scr.items():
                        ws.writerow([esc, pol, rep, n, k, v["lat"], v["tx"]])
                    print("   %s: ofrecidas %.0f, logradas %.0f ops/s, latencia %.2f ms, atraso %.2f ms" % (
                        n, sum(plan[n].values()), res["tps"], res["lat"], res["lag"] or 0))
                cc.flush(); cs.flush(); txt.flush()
                borrar_prueba_y_esperar()
    finally:
        cc.close(); cs.close(); txt.close()
        limpiar_cliente(a.cpus)
    print("Listo. Ahora: py carga_10.3/carga_sur.py resumen --total %g" % a.total)


def modo_resumen(a):
    resumen_capacidad()
    if not a.total:
        if os.path.exists(F_CAP):
            return
        sys.exit("Falta --total (el mismo de la corrida)")
    g = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in csv.DictReader(open(F_CORR)):
        for c in ("tps", "lat_ms", "lag_ms", "lagmax_ms", "fallidas"):
            g[(r["escenario"], r["politica"], r["nodo"])][c].append(float(r[c] or 0))
    sc = collections.defaultdict(list)
    for r in csv.DictReader(open(F_SCR)):
        sc[(r["escenario"], r["politica"], r["nodo"], r["clave"])].append(float(r["lat_ms"]))
    m = lambda xs: st.median(xs)
    print("Medianas de las repeticiones. Ofrecidas = operaciones por segundo que el diseno manda a cada nodo.\n")
    print("%-18s %-4s %9s %9s %9s %10s %10s %8s" % ("corrida", "nodo", "ofrec.", "logradas", "lat ms", "atraso ms", "atraso max", "fallidas"))
    for esc, pol in CORRIDAS:
        t = tasas(esc, pol, a.total, a.sur)
        for n in NODOS:
            d = g[(esc, pol, n)]
            if not d["tps"]:
                continue
            print("%-18s %-4s %9.0f %9.0f %9.2f %10.2f %10.1f %8.0f" % (
                "%s / %s" % (esc, pol), n, sum(t[n].values()), m(d["tps"]), m(d["lat_ms"]), m(d["lag_ms"]), m(d["lagmax_ms"]), sum(d["fallidas"])))
        print()
    print("Costo ponderado por operacion (ms): ejecucion bajo carga + red supuesta de la rubrica")
    print("%-18s %9s %9s %9s" % ("corrida", "ejec", "red", "total"))
    for esc, pol in CORRIDAS:
        lat = {}
        for n in NODOS:
            for z in ZONAS:
                for op in ("L1", "L2", "L4", "E1", "E2"):
                    v = sc.get((esc, pol, n, "%s_%s" % (op, z)))
                    if v:
                        lat[(n, "%s_%s" % (op, z))] = m(v)
        try:
            e, r = costo_ponderado(esc, pol, a.sur, lat)
            print("%-18s %9.2f %9.2f %9.2f" % ("%s / %s" % (esc, pol), e, r, e + r))
        except KeyError as x:
            print("%-18s (falta la latencia de %s: no se ejecuto ese script en esa corrida)" % ("%s / %s" % (esc, pol), x))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("modo", choices=["plan", "calibrar", "capacidad", "correr", "resumen"])
    p.add_argument("--total", type=float, default=0, help="operaciones por segundo en todo el sistema")
    p.add_argument("--sur", type=float, default=0.6, help="parte del trafico de Sur en el escenario de cambio (0.6)")
    p.add_argument("--dur", type=int, default=30, help="segundos por corrida")
    p.add_argument("--rep", type=int, default=5, help="repeticiones por corrida (la rubrica pide minimo 5)")
    p.add_argument("--clientes", type=int, default=32, help="conexiones de pgbench por nodo")
    p.add_argument("--cpus", type=float, default=1.0, help="CPU de cada nodo (docker update --cpus); 0 = sin limite")
    p.add_argument("--util", type=float, default=0.85, help="utilizacion objetivo de C en sur/principal (calibrar)")
    p.add_argument("--inicio", type=float, default=50, help="capacidad: carga total inicial en ops/s")
    p.add_argument("--factor", type=float, default=1.2, help="capacidad: factor de subida por paso")
    p.add_argument("--dur_paso", type=int, default=30, help="capacidad: segundos por paso")
    p.add_argument("--umbral", type=float, default=0.90, help="capacidad: un nodo se satura si logra menos de esta parte de lo ofrecido")
    p.add_argument("--confirmar", type=int, default=2, help="capacidad: intentos seguidos que deben saturar para darlo por cierto")
    p.add_argument("--max_pasos", type=int, default=40, help="capacidad: tope de pasos por busqueda")
    a = p.parse_args()
    if a.modo == "resumen":
        con_copia(F_RES, modo_resumen, a)
        return
    {"plan": modo_plan, "calibrar": modo_calibrar, "capacidad": modo_capacidad, "correr": modo_correr}[a.modo](a)


if __name__ == "__main__":
    main()
