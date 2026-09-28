# generar_datos.py
# Grupo 6 - BD2 - Extendible Hashing
# Actividad 4.2: Generador de datos de prueba (Maricielo Luna)
#
# Genera los datos de la tabla "buses" para probar el indice.
# Segun la rubrica (seccion 7.1) usamos los datasets de claves enteras:
#   D1 = claves secuenciales 1..N
#   D2 = claves aleatorias y unicas (con semilla fija)
# Tamanos obligatorios: 100000, 500000 y 1000000
#
# Procedimiento de D2 (lo pide la rubrica documentado):
#   - Se fija la semilla SEMILLA = 42 antes de generar cada archivo,
#     asi siempre salen exactamente los mismos datos.
#   - Las claves se sacan con random.sample del rango 1..10*N,
#     por eso no se repiten y ademas quedan numeros sin usar
#     (sirven despues para buscar claves que no existen).
#
# Uso:
#   python3 scripts/generar_datos.py          -> genera los 3 tamanos
#   python3 scripts/generar_datos.py 100000   -> genera solo ese tamano
#
# Los archivos se guardan en data/ (esta en el .gitignore, no se suben,
# cualquiera los puede volver a generar con este script)

import random
import sys
import os

SEMILLA = 42
TAMANOS = [100000, 500000, 1000000]
CARPETA = "data"

RUTAS = ["1A", "2B", "3C", "5A", "7B", "10", "12C", "15", "20A", "C1"]
CAPACIDADES = [20, 30, 40, 50]
LETRAS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def generar_placa():
    # placa tipo ABC-123
    placa = ""
    for i in range(3):
        placa = placa + random.choice(LETRAS)
    placa = placa + "-" + str(random.randint(100, 999))
    return placa


def escribir_csv(nombre_archivo, claves):
    ruta_archivo = os.path.join(CARPETA, nombre_archivo)
    f = open(ruta_archivo, "w")
    f.write("id_bus,placa,ruta,capacidad\n")
    for clave in claves:
        placa = generar_placa()
        ruta = random.choice(RUTAS)
        capacidad = random.choice(CAPACIDADES)
        f.write(str(clave) + "," + placa + "," + ruta + "," + str(capacidad) + "\n")
    f.close()
    print("[OK] " + ruta_archivo + " (" + str(len(claves)) + " filas)")


def generar_d1(n):
    # D1: claves secuenciales 1..N
    random.seed(SEMILLA)
    claves = list(range(1, n + 1))
    escribir_csv("D1_secuencial_" + str(n) + ".csv", claves)


def generar_d2(n):
    # D2: claves aleatorias unicas
    random.seed(SEMILLA)
    claves = random.sample(range(1, 10 * n + 1), n)
    escribir_csv("D2_aleatorio_" + str(n) + ".csv", claves)


def main():
    if not os.path.exists(CARPETA):
        os.makedirs(CARPETA)

    if len(sys.argv) > 1:
        tamanos = [int(sys.argv[1])]
    else:
        tamanos = TAMANOS

    print("Semilla usada: " + str(SEMILLA))
    for n in tamanos:
        print("\n--- Generando datos de tamano " + str(n) + " ---")
        generar_d1(n)
        generar_d2(n)

    print("\nListo.")


main()
