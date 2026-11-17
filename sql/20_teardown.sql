-- =====================================================================
-- 20_teardown.sql · Banco Andino Colombia
-- Elimina TODO el modelo (esquemas, tablas, datos, funciones y vistas).
-- Lo usa run_all.sql al inicio para reconstruir desde cero.
-- ¡Cuidado! Borra también los datos cargados (lotes 1 y 2).
-- Los roles de base de datos (banco_*) se conservan: son del servidor,
-- no de esta base, y 17_roles_permissions.sql los reutiliza.
-- =====================================================================

DROP SCHEMA IF EXISTS aud, fin, core, seg, ref CASCADE;
