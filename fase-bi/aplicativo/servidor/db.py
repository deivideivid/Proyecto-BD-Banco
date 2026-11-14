"""Conexión del aplicativo a PostgreSQL.

La cadena de conexión sale de la variable de entorno DATABASE_URL y nunca va escrita en el
código (así lo acordamos con Jerónimo para el despliegue). La contraseña puede ir dentro de
DATABASE_URL (en la nube) o en PGPASSWORD (en local, la pide iniciar_local.ps1 y no se guarda).

El servidor entra con un solo usuario, app_servidor, que no tiene permisos propios. Cada
consulta corre dentro de una transacción en la que primero se "pone" el rol de la base que le
toca a ese perfil (SET LOCAL ROLE). Al terminar la transacción el rol se quita solo.
"""
import os
from contextlib import contextmanager

from psycopg import sql
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

_pool: ConnectionPool | None = None

# Los únicos roles que el servidor puede ponerse
ROLES = {"banco_cajero", "banco_supervisor", "banco_auditor", "banco_admin_seg",
         "banco_bi", "banco_app_acceso", "banco_cliente_app"}


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
            max_size=int(os.environ.get("DB_MAX_CONEXIONES", "6")),
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


@contextmanager
def transaccion(rol: str, usuario_id: int | None = None):
    """Abre una transacción con el rol del perfil. Si algo falla, se deshace completa."""
    if rol not in ROLES:
        raise ValueError(f"Rol no permitido: {rol}")
    if _pool is None:
        abrir()
    with _pool.connection() as con:
        with con.transaction():
            con.execute(sql.SQL("SET LOCAL ROLE {}").format(sql.Identifier(rol)))
            if usuario_id is not None:
                # Quién opera: lo leen los triggers de auditoría del banco
                con.execute("SELECT set_config('banco.usuario_id', %s, true)", (str(usuario_id),))
            yield con


def consultar(consulta: str, parametros: tuple | dict = (), rol: str = "banco_bi",
              usuario_id: int | None = None) -> list[dict]:
    with transaccion(rol, usuario_id) as con:
        return con.execute(consulta, parametros).fetchall()


def uno(consulta: str, parametros: tuple | dict = (), rol: str = "banco_bi",
        usuario_id: int | None = None) -> dict | None:
    filas = consultar(consulta, parametros, rol, usuario_id)
    return filas[0] if filas else None
