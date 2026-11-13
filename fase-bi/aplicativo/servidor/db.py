"""Conexión del aplicativo a PostgreSQL.

La cadena de conexión sale de la variable de entorno DATABASE_URL y nunca va escrita en el
código (así lo acordamos con Jerónimo para el despliegue). La contraseña puede ir dentro de
DATABASE_URL (en la nube) o en PGPASSWORD (en local, la pide iniciar_local.ps1 y no se guarda).
"""
import os

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

_pool: ConnectionPool | None = None


def cadena_conexion() -> str:
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        raise RuntimeError(
            "Falta la variable DATABASE_URL. En local la pone iniciar_local.bat; "
            "en la nube va en la configuración del servicio."
        )
    return url


def abrir() -> None:
    global _pool
    if _pool is None:
        _pool = ConnectionPool(
            cadena_conexion(),
            min_size=1,
            max_size=int(os.environ.get("DB_MAX_CONEXIONES", "4")),
            timeout=15,  # si la base no responde, avisamos en 15 s en vez de dejar la página esperando
            kwargs={"row_factory": dict_row, "autocommit": True,
                    "options": "-c statement_timeout=60000 -c TimeZone=America/Bogota"},
            open=True,
        )


def cerrar() -> None:
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


def consultar(sql: str, parametros: tuple | dict = ()) -> list[dict]:
    if _pool is None:
        abrir()
    with _pool.connection() as con:
        return con.execute(sql, parametros).fetchall()
