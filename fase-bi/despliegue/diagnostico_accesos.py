"""B7 · Diagnóstico de los accesos de demostración en la base de la nube.

Lo corre b7_4_diagnostico_accesos.bat con la cadena del dueño de Neon en DATABASE_URL.
Solo lee: no cambia nada en la base. No muestra contraseñas ni hashes.

1. Estado de cada acceso demo.* (si tiene contraseña, si está activo o bloqueado, intentos).
2. Los últimos intentos de ingreso registrados por el aplicativo.
3. Si cada contraseña de accesos_demo_nube.local.txt coincide con la que guarda la base.
"""
import os
import re
import sys
from pathlib import Path

import bcrypt
import psycopg

ARCHIVO = Path(__file__).resolve().parents[1] / "aplicativo" / "accesos_demo_nube.local.txt"

con = psycopg.connect(os.environ["DATABASE_URL"], connect_timeout=20)
cur = con.cursor()

print("== 1) Accesos de demostracion en la base")
cur.execute("""
    SELECT login, perfil, activo, clave_hash IS NOT NULL, intentos_fallidos,
           coalesce(bloqueado_hasta > clock_timestamp(), false),
           to_char(ultimo_ingreso AT TIME ZONE 'America/Bogota', 'YYYY-MM-DD HH24:MI')
    FROM app.acceso WHERE login LIKE 'demo.%' ORDER BY login""")
hashes = {}
for login, perfil, activo, tiene, intentos, bloqueado, ultimo in cur.fetchall():
    print(f"  {login:<16} {perfil:<14} activo={activo!s:<5} con_clave={tiene!s:<5} "
          f"fallos_seguidos={intentos} bloqueado={bloqueado!s:<5} ultimo_ingreso={ultimo}")
cur.execute("SELECT login, clave_hash FROM app.acceso WHERE login LIKE 'demo.%'")
hashes = dict(cur.fetchall())

print("\n== 2) Ultimos 15 intentos de ingreso (hora de Colombia)")
cur.execute("""
    SELECT to_char(momento AT TIME ZONE 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'), login, exitoso
    FROM app.ingreso ORDER BY momento DESC LIMIT 15""")
for momento, login, exitoso in cur.fetchall():
    print(f"  {momento}  {login:<20} {'OK' if exitoso else 'fallido'}")

print("\n== 3) Las contraseñas del archivo contra la base")
if not ARCHIVO.exists():
    print(f"  No encontramos {ARCHIVO.name}.")
    sys.exit(1)
claves = {}
for linea in ARCHIVO.read_text(encoding="utf-8").splitlines():
    m = re.search(r"usuario:\s*(\S+)\s+contrase\S*:\s*(\S+)", linea)
    if m:
        claves[m.group(1)] = m.group(2)  # si hay varias tandas, queda la última
for login, clave in sorted(claves.items()):
    h = hashes.get(login)
    if not h:
        estado = "la base NO tiene contraseña para este acceso"
    elif bcrypt.checkpw(clave.encode(), h.encode()):
        estado = "COINCIDE"
    else:
        estado = "NO coincide"
    print(f"  {login:<16} {estado}   (la contraseña del archivo tiene {len(clave)} caracteres)")
con.close()
