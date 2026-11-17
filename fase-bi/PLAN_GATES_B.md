# Plan de la fase BI por gates (B0 a B9)

Seguimos la misma regla de G0 a G8: no pasamos al siguiente gate hasta que el anterior cumpla
su criterio. El plan lo aprobamos en grupo el 12 de noviembre de 2026. El 15 de noviembre lo
ampliamos a B9: el despliegue quedó como un gate propio (B7) porque es más que una línea del
cierre, y la evaluación del grupo la hacemos sobre el enlace publicado.

| Gate | Qué hacemos | Cuándo lo damos por cerrado |
|---|---|---|
| **B0** Corrección previa | Pasamos a la rama `fase-bi`. Reescribimos toda la documentación de G0 a G8 en nuestra voz ("hicimos, encontramos, nos dio") y quitamos el tono de instrucciones. La matriz IA y el registro de prompts se quedan, también narrados por nosotros. | Ningún documento queda en tono de orden y los números no cambian. |
| **B1** Requisitos y diseño | Armamos la lista de lo que pidió el profesor, los 5 perfiles con lo que puede ver y hacer cada uno, y los bocetos de las pantallas en celular y computador. | Los 5 aprobamos la lista y los bocetos. |
| **B2** Modelo estrella | Creamos el esquema `bi` en la misma base: hechos de transacciones y de saldos, y dimensiones de fecha, cliente, cuenta y producto, oficina y canal. Un rol de solo lectura para Power BI. | Los totales del modelo estrella cuadran al peso con la base original. |
| **B3** Power BI | Conectamos Power BI al esquema `bi`, creamos las medidas y armamos 4 páginas: Resumen, Transacciones, Clientes y cuentas, Control y auditoría de datos. Incluimos la vista para celular. | Mínimo 7 indicadores dan igual en SQL y en Power BI. Queda el archivo `.pbix`. |
| **B4** Tableros en el aplicativo | Como Power BI no se puede meter directo en la página, hacemos los mismos tableros dentro del aplicativo con gráficas propias (plan B). | Los indicadores de la página dan igual que en Power BI y en SQL. |
| **B5** Servidor del aplicativo | Hacemos el servidor en Python que se conecta a la base con los permisos de cada perfil y usa las operaciones seguras que ya teníamos (consignar, retirar, transferir, bloquear, etc.). | Cada perfil solo puede hacer lo suyo, y lo probamos con intentos que deben fallar. |
| **B6** Interfaces | Pantallas de Cliente, Cajero, Supervisor, Auditor de datos y Administrador; sección de Estadísticas; Equipo con hojas de vida; Tecnologías usadas. Todo adaptable a celular. | Se ve bien en celular, tablet y computador (con capturas). |
| **B7** Despliegue | Lo lleva Jerónimo, siguiendo `despliegue/DESPLIEGUE.md`. Creamos las cuentas de Neon (base) y Render (servidor), sin tarjeta. Montamos la base completa con `preparar_nube.sql` y `g8_reconstruir_todo.sql`, y luego los scripts de B2, B4, B5 y B6. Medimos el espacio con `medir_nube.sql`. Publicamos el servidor con sus variables de entorno (`DATABASE_URL` con `app_servidor`, `APP_SECRET`, `APP_HTTPS=1`). Ninguna contraseña va al repositorio. | El enlace abre desde el celular, `medir_nube.sql` dice que cabe y las pruebas de perfiles pasan contra la nube. Si no cabe en 1 GB, pasamos al plan B (Azure for Students). |
| **B8** Pruebas y evaluación | Corremos las pruebas finales de cada perfil y cada operación. Hacemos la evaluación con el grupo (human in the loop): cada uno usa el aplicativo desde el enlace publicado y anotamos lo que encontramos. Si el despliegue se demora, la hacemos en local para no frenar. | Todo en PASS y la evaluación del grupo registrada. |
| **B9** Cierre | README, informe, registro de IA, commit y tag. | Otra persona puede montar todo siguiendo el README. |
