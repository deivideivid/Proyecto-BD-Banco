"""Prueba la conexión a la base antes de arrancar el servidor (lo usa iniciar_local.ps1).

Sale con 0 si entra, 2 si la contraseña no sirve y 1 si la base no responde.
"""
import os
import sys

import psycopg

try:
    psycopg.connect(os.environ["DATABASE_URL"], connect_timeout=5).close()
    print("Conexión a la base: OK")
    sys.exit(0)
except psycopg.OperationalError as e:
    texto = str(e).lower()
    if "password" in texto or "autentific" in texto or "authentication" in texto:
        print("PostgreSQL no aceptó esa contraseña.")
        sys.exit(2)
    print("No pudimos llegar a PostgreSQL. ¿Está prendido el servicio en este computador?")
    sys.exit(1)
