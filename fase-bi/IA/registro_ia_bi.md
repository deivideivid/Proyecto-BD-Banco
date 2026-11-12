# Registro de uso de IA en la fase BI

Seguimos la misma regla del laboratorio: la IA propone, nosotros revisamos, PostgreSQL ejecuta
y las pruebas deciden. Aquí anotamos cada vez que la usamos en esta fase.

| Fecha | Gate | Herramienta | Qué le pedimos | Qué usamos | Cómo lo comprobamos |
|---|---|---|---|---|---|
| 12/11/2026 | Plan | Claude | Analizar lo que pidió el profesor, buscar incongruencias y proponer los gates B0 a B8 y los perfiles | El plan de gates, los 5 perfiles y la estructura de carpetas | Lo revisamos en grupo y ajustamos: plan B para los tableros, perfil Cliente, auditor de datos y evaluación con el grupo al final |
| 12/11/2026 | B0 | Claude | Pasar la documentación de G0 a G8 a nuestra voz y quitar el tono de instrucciones | Los documentos reescritos, el informe y el resumen con sus PDF | Revisamos que ningún número cambiara y que las rutas siguieran funcionando después de sacar todo a la raíz |
| 12/11/2026 | B1 | Claude | Convertir lo que pidió el profesor en una lista, proponer qué ve y hace cada perfil según las funciones de la base, y dibujar los bocetos | `requisitos.md`, `perfiles.md`, `pantallas.md`, `tecnologias.md` y los 7 bocetos | Comparamos cada acción con los permisos de `seg.rol_permiso` y las funciones de `14_functions.sql`; los bocetos los revisamos en grupo |
| 12/11/2026 | Despliegue | Claude | Revisar qué le pide nuestro SQL a un proveedor en la nube y comparar opciones gratis y de prueba (Neon, Render, Azure, Aiven, Supabase, Railway, Replit, Koyeb, Oracle) | La comparación de `despliegue/DESPLIEGUE.md` (propuesta: Neon + Render), `preparar_nube.sql` para el ajuste de `SET ROLE` de PostgreSQL 16 y `medir_nube.sql` | Pendiente: la aprobamos en grupo y la confirmamos corriendo `g8_reconstruir_todo.sql` en Neon (esperamos G8 = PASS y `g4_data_profile.csv` sin cambios) |
| 12/11/2026 | B2 | Claude | Proponer el modelo estrella, el procedimiento de carga, el rol de solo lectura para Power BI, la validación contra el banco y el catálogo de indicadores | Los 5 scripts de `B2_modelo_estrella/sql`, `ejecutar_b2.bat` y los documentos del gate | Lo probamos primero en una copia reconstruida de la base: 14 de 14 controles en PASS, la carga repetida dio la misma huella y el ticket promedio coincidió con el perfil de G4 |
