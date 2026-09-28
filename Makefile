MODULE_big = pg_hashing

# Se incluyen todos los archivos fuente excepto main.c
OBJS = pg_hashing.o src/bucket.o src/busqueda.o src/directorio.o src/inserccion.o src/split.o

EXTENSION = pg_hashing
DATA = pg_hashing--1.0.sql

# Indica al compilador dónde buscar los archivos de cabecera (.h)
PG_CPPFLAGS = -I$(CURDIR)/include

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)