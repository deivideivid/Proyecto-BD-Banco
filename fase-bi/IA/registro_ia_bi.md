# Registro de uso de IA en la fase BI

Seguimos la misma regla del laboratorio: la IA propone, nosotros revisamos, PostgreSQL ejecuta
y las pruebas deciden. Aquí anotamos cada vez que la usamos en esta fase.

| Fecha | Gate | Herramienta | Qué le pedimos | Qué usamos | Cómo lo comprobamos |
|---|---|---|---|---|---|
| 12/11/2026 | Plan | Claude | Analizar lo que pidió el profesor, buscar incongruencias y proponer los gates B0 a B8 y los perfiles | El plan de gates, los 5 perfiles y la estructura de carpetas | Lo revisamos en grupo y ajustamos: plan B para los tableros, perfil Cliente, auditor de datos y evaluación con el grupo al final |
| 12/11/2026 | Despliegue | Claude | Revisar qué le pide nuestro SQL a un proveedor en la nube y comparar opciones gratis y de prueba (Neon, Render, Azure, Aiven, Supabase, Railway, Replit, Koyeb, Oracle) | La comparación de `despliegue/DESPLIEGUE.md` (propuesta: Neon + Render), `preparar_nube.sql` para el ajuste de `SET ROLE` de PostgreSQL 16 y `medir_nube.sql` | Pendiente: la aprobamos en grupo y la confirmamos corriendo `g8_reconstruir_todo.sql` en Neon (esperamos G8 = PASS y `g4_data_profile.csv` sin cambios) |
