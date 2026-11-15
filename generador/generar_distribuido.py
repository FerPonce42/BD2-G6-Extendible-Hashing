# generar_distribuido.py
# Grupo 6 - BD2 - Etapa II, semana 9: generador de datos del esquema distribuido (Iair Suico)
#
# Genera los datos de las 4 relaciones de la actividad 8.1 (esquema_global.sql):
#   rutas        10          (fijas, ya las crea 01_comun.sql en cada nodo)
#   conductores  5 000
#   buses        100 000     (10 000 por ruta)
#   viajes       1 200 000   (12 por bus)  <- relacion principal
#
# Los buses y los viajes salen ya separados por zona, en un CSV por fragmento,
# con el mismo nombre que la tabla del nodo (buses_norte, viajes_centro, ...).
# Asi cada archivo se carga directo en el nodo principal de su zona:
#   A: buses_norte,  viajes_norte
#   B: conductores,  buses_centro, viajes_centro
#   C: buses_sur,    viajes_sur
#
# Reglas de la actividad 8.1 (seccion 2 del informe) que se cumplen:
#   1. Cada bus trabaja en una sola ruta.
#   2. viajes.id_ruta es la ruta del bus del viaje (la clave foranea doble
#      (id_bus, id_ruta) de los nodos de la 9.1 rechaza la carga si no).
#   Ademas, el reparto por zona es 30/40/30 (Norte/Centro/Sur), exacto.
#
# Otras decisiones:
#   - Semilla fija (SEMILLA = 42): siempre salen exactamente los mismos datos.
#   - Las salidas van del 2026-01-01 al 2026-10-31. Los viajes que inserta la
#     prueba E1 de la 9.2 usan fechas desde 2026-11-01 y se borran con
#     "salida >= '2026-11-01'", asi que nunca se mezclan con estos.
#   - pasajeros va de 0 a la capacidad del bus.
#   - id_bus e id_viaje se reparten al azar entre las zonas (no por bloques),
#     como pasaria en un sistema real.
#
# Dos estrategias de fragmentacion (actividad 10.1). Las FILAS son exactamente las
# mismas en las dos (misma semilla); solo cambia en que archivo cae cada una:
#   zona (Alt. 1 de 8.1, la elegida): buses/viajes_norte, _centro, _sur -> A, B, C
#   hash (Alt. 2 de 8.1): buses_hK con K = id_bus mod 3 y viajes_hK con K = id_viaje mod 3
#                         h0 -> A, h1 -> B, h2 -> C
#
# Uso (desde la raiz del repositorio):
#   python generador/generar_distribuido.py              -> zona, tamano de diseno (1 200 000 viajes)
#   python generador/generar_distribuido.py 1 hash       -> hash, tamano de diseno
#   python generador/generar_distribuido.py 0.01         -> zona al 1 % (50 conductores, 1 000 buses, 12 000 viajes)
#
# Los archivos quedan en data/distribuido/ (zona) o data/distribuido_hash/ (hash).
# data/ esta en el .gitignore.

import csv
import os
import random
import sys
from datetime import date, datetime, timedelta

SEMILLA = 42
CARPETA = os.path.join("data", "distribuido")   # se cambia en main() segun la estrategia

# Las mismas 10 rutas y zonas de esquema_global.sql (actividad 8.1)
RUTAS = [
    # id_ruta, codigo, zona
    (1, "1A", "norte"),
    (2, "2B", "norte"),
    (3, "3C", "norte"),
    (4, "5A", "centro"),
    (5, "7B", "centro"),
    (6, "10", "centro"),
    (7, "12C", "centro"),
    (8, "15", "sur"),
    (9, "20A", "sur"),
    (10, "C1", "sur"),
]
ZONAS = ["norte", "centro", "sur"]
HASH = ["h0", "h1", "h2"]
NODO = {"norte": "A", "centro": "B", "sur": "C", "h0": "A", "h1": "B", "h2": "C"}

# Tamanos de diseno (escala 1)
CONDUCTORES = 5000
BUSES_POR_RUTA = 10000   # 3 + 4 + 3 rutas -> 30 000 / 40 000 / 30 000 buses
VIAJES_POR_BUS = 12      # -> 1 200 000 viajes

CAPACIDADES = [20, 30, 40, 50]
# Tarifa fija por ruta (inventada, en soles)
TARIFA_RUTA = {1: "1.50", 2: "1.50", 3: "2.00", 4: "1.00", 5: "1.00",
               6: "1.20", 7: "1.20", 8: "1.80", 9: "2.00", 10: "2.50"}

LETRAS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
NOMBRES = ["Juan", "Carlos", "Luis", "Jose", "Miguel", "Jorge", "Pedro", "Victor",
           "Raul", "Cesar", "Ana", "Maria", "Rosa", "Carmen", "Lucia", "Elena",
           "Diego", "Mario", "Hugo", "Oscar"]
APELLIDOS = ["Quispe", "Mamani", "Flores", "Huaman", "Condori", "Rojas", "Ramos",
             "Chavez", "Vargas", "Torres", "Diaz", "Mendoza", "Gutierrez", "Salas",
             "Cruz", "Apaza", "Ccama", "Zuniga", "Paredes", "Medina"]

INICIO_SALIDAS = date(2026, 1, 1)
DIAS_SALIDAS = (date(2026, 10, 31) - INICIO_SALIDAS).days + 1   # 304 dias


def abrir_csv(nombre, encabezado):
    f = open(os.path.join(CARPETA, nombre + ".csv"), "w", newline="", encoding="utf-8")
    w = csv.writer(f)
    w.writerow(encabezado)
    return f, w


def generar_conductores(n):
    f, w = abrir_csv("conductores", ["id_conductor", "nombre", "licencia", "fecha_ingreso"])
    for i in range(1, n + 1):
        nombre = random.choice(NOMBRES) + " " + random.choice(APELLIDOS) + " " + random.choice(APELLIDOS)
        licencia = "Q" + str(40000000 + i)          # unica, 9 caracteres
        ingreso = date(2010, 1, 1) + timedelta(days=random.randint(0, 5843))  # hasta 2025-12-31
        w.writerow([i, nombre, licencia, ingreso.isoformat()])
    f.close()
    return n


def fragmento(estrategia, id_fila, id_ruta):
    # En que fragmento cae una fila de buses (id_bus) o de viajes (id_viaje)
    if estrategia == "hash":
        return "h" + str(id_fila % 3)
    return ZONA_DE_RUTA[id_ruta]


ZONA_DE_RUTA = {id_ruta: zona for id_ruta, _, zona in RUTAS}


def generar_buses(buses_por_ruta, estrategia, fragmentos):
    # Una lista de rutas con BUSES_POR_RUTA copias de cada una, mezclada:
    # el bus i trabaja en la ruta rutas_de_bus[i-1] (regla 1).
    rutas_de_bus = []
    for id_ruta, _, _ in RUTAS:
        rutas_de_bus += [id_ruta] * buses_por_ruta
    random.shuffle(rutas_de_bus)

    archivos = {}
    for z in fragmentos:
        archivos[z] = abrir_csv("buses_" + z, ["id_bus", "placa", "id_ruta", "capacidad"])

    buses = []   # (id_bus, id_ruta, capacidad), para armar los viajes
    for i, id_ruta in enumerate(rutas_de_bus, start=1):
        placa = "".join(random.choice(LETRAS) for _ in range(3)) + "-" + str(random.randint(100, 999))
        capacidad = random.choice(CAPACIDADES)
        archivos[fragmento(estrategia, i, id_ruta)][1].writerow([i, placa, id_ruta, capacidad])
        buses.append((i, id_ruta, capacidad))

    for f, _ in archivos.values():
        f.close()
    return buses


def generar_viajes(buses, n_conductores, estrategia, fragmentos):
    # Cada bus hace VIAJES_POR_BUS viajes; el orden se mezcla para que
    # id_viaje no quede agrupado por bus ni por zona.
    viajes_de = []
    for b in range(len(buses)):
        viajes_de += [b] * VIAJES_POR_BUS
    random.shuffle(viajes_de)

    archivos = {}
    for z in fragmentos:
        archivos[z] = abrir_csv("viajes_" + z, ["id_viaje", "id_bus", "id_conductor", "id_ruta",
                                                "salida", "pasajeros", "tarifa"])

    for id_viaje, b in enumerate(viajes_de, start=1):
        id_bus, id_ruta, capacidad = buses[b]          # regla 2: la ruta del viaje es la del bus
        salida = datetime(INICIO_SALIDAS.year, INICIO_SALIDAS.month, INICIO_SALIDAS.day) + timedelta(
            days=random.randrange(DIAS_SALIDAS),
            minutes=5 * 60 + random.randrange(18 * 60))   # entre 05:00 y 22:59
        archivos[fragmento(estrategia, id_viaje, id_ruta)][1].writerow([
            id_viaje, id_bus, random.randint(1, n_conductores), id_ruta,
            salida.strftime("%Y-%m-%d %H:%M:00"),
            random.randint(0, capacidad), TARIFA_RUTA[id_ruta]])

    for f, _ in archivos.values():
        f.close()
    return len(viajes_de)


def contar_filas(nombre):
    with open(os.path.join(CARPETA, nombre + ".csv"), encoding="utf-8") as f:
        return sum(1 for _ in f) - 1


def main():
    global CARPETA
    escala = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
    estrategia = sys.argv[2] if len(sys.argv) > 2 else "zona"
    if estrategia not in ("zona", "hash"):
        print("La estrategia tiene que ser zona o hash")
        sys.exit(1)
    fragmentos = HASH if estrategia == "hash" else ZONAS
    if estrategia == "hash":
        CARPETA = os.path.join("data", "distribuido_hash")
    n_conductores = max(1, round(CONDUCTORES * escala))
    buses_por_ruta = max(1, round(BUSES_POR_RUTA * escala))

    os.makedirs(CARPETA, exist_ok=True)
    random.seed(SEMILLA)
    print("Semilla: " + str(SEMILLA) + "   escala: " + str(escala) + "   estrategia: " + estrategia)

    generar_conductores(n_conductores)
    buses = generar_buses(buses_por_ruta, estrategia, fragmentos)
    total_viajes = generar_viajes(buses, n_conductores, estrategia, fragmentos)

    print("\nArchivo              filas   nodo principal")
    print("conductores.csv  %9d   B" % contar_filas("conductores"))
    for tabla in ["buses", "viajes"]:
        for z in fragmentos:
            nombre = tabla + "_" + z
            print("%-16s %9d   %s" % (nombre + ".csv", contar_filas(nombre), NODO[z]))
    print("\nTotal: %d buses y %d viajes en %s" % (len(buses), total_viajes, CARPETA))


main()
