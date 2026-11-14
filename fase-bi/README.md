# Fase BI y aplicativo · Banco Andino Colombia

En esta fase tomamos la base del laboratorio (G0 a G8) y la llevamos a dos cosas nuevas:

1. Un **modelo estrella** con tableros en **Power BI** (archivo `.pbix`).
2. Un **aplicativo web del banco**, adaptable a celular, con una interfaz para cada perfil,
   una sección de estadísticas con los tableros, el equipo con sus hojas de vida y las
   tecnologías que usamos.

Trabajamos en la rama `fase-bi`. Lo de G0 a G8 quedó congelado en el tag `entrega-final`.

## Cómo vamos

| Gate | Qué es | Estado |
|---|---|---|
| B0 | Corrección previa de la documentación | Listo |
| B1 | Requisitos, perfiles y bocetos | Listo |
| B2 | Modelo estrella en la base | Listo |
| B3 | Tableros en Power BI | Listo |
| B4 | Tableros dentro del aplicativo | Listo |
| B5 | Servidor del aplicativo y permisos | Listo |
| B6 | Interfaces por perfil | Pendiente |
| B7 | Pruebas y evaluación con el grupo | Pendiente |
| B8 | Cierre | Pendiente |

El detalle de cada gate está en `PLAN_GATES_B.md` y lo que fuimos decidiendo, en `DECISIONES_B.md`.

## Carpetas

- `B1_diseno/` - requisitos del profesor, perfiles, pantallas, tecnologías y bocetos.
- `B2_modelo_estrella/` - el modelo estrella (esquema `bi`), su validación y los indicadores.
- `B3_powerbi/` - el archivo de Power BI, las medidas y la comparación con SQL.
- `B4_tableros_app/` - las funciones de Estadísticas en la base, su validación y la comparación de la página con SQL y Power BI.
- `B5_servidor/` - lo que el aplicativo necesita en la base (accesos, canal digital, `app_servidor`), la matriz de permisos y las pruebas por perfil.
- `aplicativo/` - el aplicativo web (servidor en Python y páginas). Tiene el ingreso, las operaciones de los 5 perfiles y la sección Estadísticas.
- `herramientas/` - el script que usan los `.bat` para correr SQL con la contraseña de PostgreSQL.
- `despliegue/` - dónde y cómo vamos a publicar el aplicativo (lo lleva Jerónimo).
- `equipo/hojas_de_vida/` - las hojas de vida de los 5 en PDF.
- `IA/` - el registro de cómo usamos la IA en esta fase.
