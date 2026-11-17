# Fase BI y aplicativo · Banco Andino Colombia

En esta fase tomamos la base del laboratorio (G0 a G8) y la llevamos a dos cosas nuevas:

1. Un **modelo estrella** con tableros en **Power BI** (archivo `.pbix`).
2. Un **aplicativo web del banco**, adaptable a celular, con una interfaz para cada perfil,
   una sección de estadísticas con los tableros, el equipo con sus hojas de vida y las
   tecnologías que usamos.

El aplicativo está publicado en **https://banco-andino.onrender.com** (si estaba dormido, tarda
cerca de un minuto en abrir). La trabajamos en la rama `fase-bi` y al terminar B8 la unimos a `main`; Render sigue publicando desde `fase-bi`. Lo de G0 a G8 quedó congelado en el tag `entrega-final`.

## Cómo vamos

| Gate | Qué es | Estado |
|---|---|---|
| B0 | Corrección previa de la documentación | Listo |
| B1 | Requisitos, perfiles y bocetos | Listo |
| B2 | Modelo estrella en la base | Listo |
| B3 | Tableros en Power BI | Listo |
| B4 | Tableros dentro del aplicativo | Listo |
| B5 | Servidor del aplicativo y permisos | Listo |
| B6 | Interfaces por perfil | Listo |
| B7 | Despliegue en la nube (Neon + Render) | Listo: https://banco-andino.onrender.com |
| B8 | Pruebas y evaluación con el grupo | Listo: los 5 evaluamos, 7 hallazgos corregidos y 110/110 en la nube |
| B9 | Cierre | En curso: informe final, guía del aplicativo y guiones de la sustentación |

El detalle de cada gate está en `PLAN_GATES_B.md` y lo que fuimos decidiendo, en `DECISIONES_B.md`.

## Carpetas

- `B1_diseno/` - requisitos del profesor, perfiles, pantallas, tecnologías y bocetos.
- `B2_modelo_estrella/` - el modelo estrella (esquema `bi`), su validación y los indicadores.
- `B3_powerbi/` - el archivo de Power BI, las medidas y la comparación con SQL.
- `B4_tableros_app/` - las funciones de Estadísticas en la base, su validación y la comparación de la página con SQL y Power BI.
- `B5_servidor/` - lo que el aplicativo necesita en la base (accesos, canal digital, `app_servidor`), la matriz de permisos y las pruebas por perfil.
- `B6_interfaces/` - la paleta, las capturas en celular, tablet y computador y su revisión.
- `B8_evaluacion/` - la guía y la planilla de la evaluación del grupo sobre el enlace publicado.
- `aplicativo/` - el aplicativo web (servidor en Python y páginas) con las pantallas de los 5 perfiles, Equipo, Tecnologías y Estadísticas.
- `herramientas/` - el script que usan los `.bat` para correr SQL con la contraseña de PostgreSQL.
- `despliegue/` - dónde y cómo publicamos el aplicativo (gate B7: Jerónimo comparó los proveedores y David lo montó; el paso a paso está en `despliegue/GUIA_B7.md`).
- `equipo/` - los datos del equipo (`equipo.json`) y las hojas de vida en PDF, solo con datos profesionales.
- `IA/` - el registro de cómo usamos la IA en esta fase.

## Cómo montarlo en otro computador

Lo probamos en Windows con PostgreSQL 18 y Python 3.13.

1. Montamos la base del banco con G8, como dice el [README principal](../README.md).
2. Corremos, en este orden, `B2_modelo_estrella/ejecutar_b2.bat`, `B4_tableros_app/ejecutar_b4.bat`,
   `B5_servidor/ejecutar_b5.bat` y `B6_interfaces/ejecutar_b6.bat`. Cada uno pide la contraseña de
   `postgres` y termina en PASS. Al final, `ejecutar_b5.bat` pide inventar la contraseña de
   `app_servidor`, el usuario con el que el aplicativo entra a la base.
3. Abrimos `aplicativo/iniciar_local.bat`: crea el entorno de Python, crea los accesos de prueba
   (quedan en `aplicativo/accesos_demo.local.txt`, que no se sube) y abre `http://localhost:8000`.
4. El tablero de Power BI se abre con Power BI Desktop desde `B3_powerbi/BancoAndino.pbix`, con el
   usuario de solo lectura `powerbi_lector` (ver `B3_powerbi/README.md`).

Para la nube seguimos `despliegue/GUIA_B7.md`.
