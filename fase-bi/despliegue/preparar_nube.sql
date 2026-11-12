-- =====================================================================
-- preparar_nube.sql · Banco Andino Colombia · Fase BI (despliegue)
-- Deja lista una base PostgreSQL en la nube (Neon, Azure, Aiven, Render…)
-- para correr nuestros scripts de G0 a G8 SIN cambiarlos.
--
-- Por qué hace falta: en la nube no somos superusuario. Desde PostgreSQL 16,
-- un usuario con CREATEROLE que crea un rol no puede hacer SET ROLE a ese
-- rol si no lo pide de forma explícita (parámetro createrole_self_grant).
-- Nuestras pruebas de G3 (18_tests.sql), de G7 (g7_rbac_demo.sql) y la
-- demo de G8 usan SET LOCAL ROLE, así que sin esto fallarían con
-- "permission denied to set role".
--
-- Uso, desde la raíz del repositorio y en la MISMA conexión que la
-- reconstrucción (por eso van los dos -f en el mismo psql):
--   psql -d "<cadena directa>" -f fase-bi/despliegue/preparar_nube.sql -f sql/g8_reconstruir_todo.sql
--
-- No crea tablas ni datos: solo revisa el proveedor y fija dos ajustes.
-- =====================================================================

\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

-- 1. Versión: nuestros scripts piden PostgreSQL 16 o superior --------------
DO $$
BEGIN
  IF current_setting('server_version_num')::int < 160000 THEN
    RAISE EXCEPTION 'Este proveedor tiene PostgreSQL %; necesitamos 16 o superior', current_setting('server_version');
  END IF;
END $$;

-- 2. Qué puede hacer el usuario que nos dio el proveedor --------------------
SELECT current_user                      AS usuario,
       current_database()                AS base,
       current_setting('server_version') AS version,
       r.rolsuper                        AS superusuario,
       r.rolcreaterole                   AS crea_roles,
       r.rolcreatedb                     AS crea_bases
FROM pg_roles r
WHERE r.rolname = current_user;

DO $$
BEGIN
  IF NOT (SELECT rolsuper OR rolcreaterole FROM pg_roles WHERE rolname = current_user) THEN
    RAISE EXCEPTION 'El usuario % no puede crear roles (CREATEROLE): 17_roles_permissions.sql fallaría en este proveedor', current_user;
  END IF;
END $$;

-- 3. Poder hacer SET ROLE a los roles banco_* que vamos a crear ------------
-- Para esta conexión:
SET createrole_self_grant = 'set';
-- Y para las conexiones siguientes (si el proveedor lo permite):
DO $$
BEGIN
  EXECUTE format('ALTER ROLE %I SET createrole_self_grant = %L', current_user, 'set');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'No pudimos dejar createrole_self_grant fijo para %: %. Siempre corremos este archivo primero, en la misma conexión.', current_user, SQLERRM;
END $$;

-- 4. Hora de Colombia por defecto ------------------------------------------
-- Las cargas y el quality gate ya usan 'America/Bogota' de forma explícita
-- (los CSV traen -05:00), así que los datos no cambian. Esto es para el
-- aplicativo y las consultas sueltas: la nube suele venir en UTC.
SET timezone = 'America/Bogota';
DO $$
BEGIN
  EXECUTE format('ALTER DATABASE %I SET timezone = %L', current_database(), 'America/Bogota');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'No pudimos fijar la zona horaria de la base: %', SQLERRM;
END $$;

\echo '== preparar_nube: listo. Ahora sigue sql/g8_reconstruir_todo.sql en la misma conexión.'
