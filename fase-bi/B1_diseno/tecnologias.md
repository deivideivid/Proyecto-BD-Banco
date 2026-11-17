# B1 · Tecnologías que vamos a usar

| Parte | Tecnología | Para qué |
|---|---|---|
| Base de datos | PostgreSQL 18 | La base del banco de G0 a G8 y el modelo estrella nuevo |
| Servidor del aplicativo | Python 3.13 con FastAPI | Recibe las peticiones de las pantallas y llama a las funciones de la base |
| Conexión a la base | psycopg 3 | Conectar Python con PostgreSQL |
| Pantallas | HTML, CSS y JavaScript (sin framework) | Las interfaces, adaptables a celular |
| Gráficas | Chart.js (copiado dentro del proyecto) | Los tableros de la sección Estadísticas |
| Tableros | Power BI Desktop | El archivo `.pbix` con las 4 páginas |
| Contraseñas | Hash con bcrypt | Guardar las contraseñas del aplicativo cifradas |
| Control de versiones | Git y GitHub Desktop | Trabajar en grupo sobre el mismo repositorio |
| Apoyo | Claude (IA) | Proponer, revisar y generar código, siempre comprobado por nosotros |

Elegimos FastAPI porque es Python, como los generadores de datos de G4, y porque crea sola la
documentación de cada servicio, que nos sirve para probar. No usamos un framework de pantallas
(como React) para que el aplicativo sea liviano y cualquiera del grupo lo pueda leer.

Esta sección también es la base de la pestaña **Tecnologías** del aplicativo.
