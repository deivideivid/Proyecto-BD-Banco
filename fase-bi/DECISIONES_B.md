# Decisiones de la fase BI

Lo que fuimos decidiendo en grupo y por qué.

1. **Seguimos en el mismo repositorio**, en la rama `fase-bi`. Lo de G0 a G8 quedó en el tag
   `entrega-final`.
2. **El modelo estrella se queda** y va en la misma base, en un esquema aparte (`bi`).
3. **Los tableros del aplicativo los hacemos nosotros con gráficas propias (plan B).** Power BI
   no se puede meter directo en una página sin publicarlo en su servicio en la nube, así que
   entregamos el `.pbix` y en la página mostramos los mismos indicadores.
4. **El aplicativo hace operaciones de verdad** contra la base, usando las funciones seguras
   que ya probamos en G3 y G7.
5. **Los perfiles son 5:** Cliente, Cajero, Supervisor, Auditor de datos y Administrador.
   - "Usuario" en el aplicativo quiere decir **cliente del banco**.
   - El Auditor es **auditor de datos**: revisa calidad, cuadres y la bitácora, pero no opera.
6. **El perfil Cliente es nuevo.** En la base los usuarios son empleados y no están ligados a
   los clientes (regla RN-10), así que el cliente entra con un acceso aparte que solo ve sus
   propias cuentas.
7. **"Evaluar" es la evaluación con el grupo (human in the loop)** y la hacemos al final, en B7.
8. **La matriz IA y el registro de prompts se quedan**, porque el laboratorio es "aumentado
   con IA", pero narrados por nosotros.
9. **El despliegue lo lleva Jerónimo.** Las opciones están en `despliegue/DESPLIEGUE.md`.
10. **Trabajamos con la base en el computador de Juan Diego**, con PostgreSQL local. En B0
    revisamos que siga cargada y con los mismos conteos.
11. **Aprobamos los bocetos de B1** con un cambio: menú lateral plegable con botón ☰, como el de
    Opera, para que el contenido se agrande. La interfaz final va minimalista, estilo glass, con
    botones e íconos animados y simples. La paleta de colores la definimos antes de B6.
12. **El modelo estrella tiene dos hechos que comparten dimensiones**: transacciones (una fila
    por transacción) y saldos (una foto por cuenta al corte). Cada transacción se asigna a una
    sola cuenta para que los montos cuadren con el banco.
13. **Fijamos 13 indicadores con sus valores oficiales en SQL** y dos escenarios de prueba (A:
    todo; B: agosto de 2026 y AHORROS). Power BI y el aplicativo tienen que dar lo mismo.
14. **Power BI entra con `powerbi_lector`**, que solo ve el esquema `bi`. Quitamos las relaciones
    de `dim_cuenta` hacia cliente, oficina y producto para que no hubiera caminos dobles, y
    dejamos inactiva la relación uno a uno entre saldos y cuentas.
15. **Las páginas de Power BI las generamos como archivos (formato PBIR)** en vez de arrastrar
    cada gráfica a mano. Así quedan iguales en computador y en celular y se pueden volver a
    generar. El tema de colores lo aplicamos cuando definamos la paleta.
