# Aplicativo del Banco Andino

Aplicativo web del banco: servidor en Python (FastAPI) que se conecta a PostgreSQL y páginas en
HTML, CSS y JavaScript, adaptables a celular. Lo vamos construyendo por gates:

| Gate | Qué le agregamos | Estado |
|---|---|---|
| B4 | Sección **Estadísticas** (los tableros de Power BI con gráficas propias) | Listo |
| B5 | Inicio de sesión, perfiles y operaciones contra la base | Listo |
| B6 | Interfaces de cada perfil, Equipo y Tecnologías | Pendiente |

## Carpetas

- `servidor/` - `main.py` (arranque y seguridad), `db.py` (conexión con el rol de cada perfil),
  `sesion.py` (ingreso y perfiles), `errores.py` (mensajes sencillos), `comun.py`, una ruta por
  perfil (`rutas_cliente.py`, `rutas_caja.py`, `rutas_supervisor.py`, `rutas_auditor.py`,
  `rutas_admin.py`), `estadisticas.py`, `crear_accesos.py` y `probar_conexion.py`.
- `web/` - las páginas. `vendor/chart.umd.js` es Chart.js 4.4.1 (licencia MIT, en `vendor/`).
- `requirements.txt` - librerías de Python.
- `iniciar_local.bat` - lo arranca en este computador y abre `http://localhost:8000`.

## Rutas que tiene hoy

| Ruta | Quién | Qué hace |
|---|---|---|
| `/` | Todos | Lleva a `ingresar.html` |
| `/salud` | Todos | Responde `{"estado": "ok"}` sin consultar la base (para despertar el servidor en la nube) |
| `/api/sesion/ingresar`, `/salir`, `/api/sesion` | Todos | Entrar, salir y ver quién inició sesión |
| `/api/cliente/...` | Cliente | Cuentas, movimientos, resumen mensual y transferir |
| `/api/caja/...` | Cajero y Supervisor | Buscar, fichas, registrar clientes, abrir y activar cuentas, consignar, retirar, transferir, bloquear y crear ajustes |
| `/api/supervisor/...` | Supervisor | Ajustes pendientes (aprobar o rechazar), reversar, desbloquear, límite, cerrar e inactivar |
| `/api/auditor/...` | Auditor de datos | Cuadres, bitácora de auditoría, ingresos al aplicativo y calidad |
| `/api/admin/...` | Administrador | Usuarios internos, roles y estados |
| `/api/estadisticas/...` | Administrador, Supervisor (su oficina), Auditor (Control y calidad) | Los tableros de B4 |
| `/docs` | Todos | La documentación automática de FastAPI con todas las rutas |

El detalle de quién puede qué está en `fase-bi/B5_servidor/matriz_permisos.md`.

## Conexión

La cadena sale de la variable `DATABASE_URL` y nunca va en el código. Desde B5 el servidor entra
con `app_servidor`, que no tiene permisos propios y en cada petición se pone el rol del perfil
(ver `fase-bi/B5_servidor/README.md`). En local la arma `iniciar_local.ps1` con la contraseña que
uno escribe al arrancar.
Antes de arrancar, `iniciar_local.ps1` prueba la contraseña
(`servidor/probar_conexion.py`) y la vuelve a pedir si PostgreSQL no la acepta, hasta 3 veces. Si
no la recordamos, volvemos a correr `fase-bi/B5_servidor/ejecutar_b5.bat`, que al final la pide de
nuevo. Si con el
servidor ya prendido la base deja de responder, la página muestra el aviso en vez de quedarse
cargando. En la nube va en la configuración del servicio. Para Render, el comando de arranque es
`uvicorn servidor.main:app --host 0.0.0.0 --port $PORT`, con la carpeta `fase-bi/aplicativo`
como raíz (ver `fase-bi/despliegue/DESPLIEGUE.md`).

En la nube, además de `DATABASE_URL` (con `app_servidor`), el servicio necesita `APP_SECRET` (una
clave larga al azar para firmar la cookie de sesión) y `APP_HTTPS=1`. Las contraseñas de los
accesos de demostración se generan corriendo una vez `python -m servidor.crear_accesos` con esas
mismas variables.
