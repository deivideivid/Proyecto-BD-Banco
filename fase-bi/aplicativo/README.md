# Aplicativo del Banco Andino

Aplicativo web del banco: servidor en Python (FastAPI) que se conecta a PostgreSQL y páginas en
HTML, CSS y JavaScript, adaptables a celular. Lo vamos construyendo por gates:

| Gate | Qué le agregamos | Estado |
|---|---|---|
| B4 | Sección **Estadísticas** (los tableros de Power BI con gráficas propias) | Listo |
| B5 | Inicio de sesión, perfiles y operaciones contra la base | Pendiente |
| B6 | Interfaces de cada perfil, Equipo y Tecnologías | Pendiente |

## Carpetas

- `servidor/` - `main.py` (arranque y rutas), `db.py` (conexión) y `estadisticas.py`.
- `web/` - las páginas. `vendor/chart.umd.js` es Chart.js 4.4.1 (licencia MIT, en `vendor/`).
- `requirements.txt` - librerías de Python.
- `iniciar_local.bat` - lo arranca en este computador y abre `http://localhost:8000`.

## Rutas que tiene hoy

| Ruta | Qué hace |
|---|---|
| `/` | Lleva a `estadisticas.html` |
| `/salud` | Responde `{"estado": "ok"}` sin consultar la base (para despertar el servidor en la nube) |
| `/api/estadisticas/filtros` | Meses, productos y departamentos para los filtros |
| `/api/estadisticas/{pagina}` | Una página (`resumen`, `transacciones`, `clientes`, `control`) con `mes`, `producto` y `departamento` opcionales |
| `/docs` | La documentación automática de FastAPI, que usamos para probar |

## Conexión

La cadena sale de la variable `DATABASE_URL` y nunca va en el código. En local la arma
`iniciar_local.ps1` con el usuario `powerbi_lector` y la contraseña que uno escribe al arrancar.
Antes de arrancar, `iniciar_local.ps1` prueba la contraseña
(`servidor/probar_conexion.py`) y la vuelve a pedir si PostgreSQL no la acepta, hasta 3 veces. Si
no la recordamos, en pgAdmin, como `postgres`, le ponemos una nueva con
`ALTER ROLE powerbi_lector PASSWORD '...';` y la actualizamos también en Power BI. Si con el
servidor ya prendido la base deja de responder, la página muestra el aviso en vez de quedarse
cargando. En la nube va en la configuración del servicio. Para Render, el comando de arranque es
`uvicorn servidor.main:app --host 0.0.0.0 --port $PORT`, con la carpeta `fase-bi/aplicativo`
como raíz (ver `fase-bi/despliegue/DESPLIEGUE.md`).
