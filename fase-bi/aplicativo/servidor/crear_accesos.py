"""Genera las contraseñas de los accesos que todavía no tienen (los de demostración).

Lo corre iniciar_local.ps1 antes de arrancar el servidor. Las contraseñas se muestran una sola
vez en la ventana y se guardan en accesos_demo.local.txt, que NO se sube a GitHub (.gitignore).
En la base solo queda el hash bcrypt.

Para volver a generar la de un acceso (por ejemplo si se pierde el archivo), en pgAdmin como
postgres:  UPDATE app.acceso SET clave_hash = NULL WHERE login = 'demo.cajero';
y volver a arrancar el aplicativo.
"""
import secrets
from datetime import datetime
from pathlib import Path

import bcrypt

from . import db

ARCHIVO = Path(__file__).resolve().parent.parent / "accesos_demo.local.txt"
ALFABETO = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"


def nueva_clave(largo: int = 12) -> str:
    return "".join(secrets.choice(ALFABETO) for _ in range(largo))


def main() -> None:
    db.abrir()
    try:
        pendientes = db.consultar("SELECT * FROM app.fn_accesos_pendientes()", rol="banco_app_acceso")
        if not pendientes:
            print("Accesos: todos tienen contraseña" + (f" (están en {ARCHIVO.name})." if ARCHIVO.exists() else "."))
            return
        lineas = []
        for p in pendientes:
            clave = nueva_clave()
            hash_ = bcrypt.hashpw(clave.encode(), bcrypt.gensalt(rounds=12)).decode()
            ok = db.consultar("SELECT app.fn_definir_clave_inicial(%s, %s) AS ok", (p["login"], hash_),
                              rol="banco_app_acceso")[0]["ok"]
            if ok:
                lineas.append(f"{p['perfil']:<14} usuario: {p['login']:<16} contraseña: {clave}")
        if lineas:
            texto = (f"Accesos generados el {datetime.now():%Y-%m-%d %H:%M}\n" + "\n".join(lineas) + "\n")
            with ARCHIVO.open("a", encoding="utf-8") as f:
                f.write(texto + "\n")
            print("")
            print("Accesos de demostración (se muestran una sola vez; quedaron en " + ARCHIVO.name + ", que no va a GitHub):")
            print(texto)
    finally:
        db.cerrar()


if __name__ == "__main__":
    main()
