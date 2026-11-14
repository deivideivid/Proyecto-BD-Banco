-- =====================================================================
-- 00_extensions.sql · Banco Andino Colombia
-- Verifica la versión del servidor. No se requieren extensiones:
-- gen_random_uuid() y sha256() son funciones nativas de PostgreSQL 13+.
-- Se ejecuta desde sql/run_all.sql (no abre ni cierra transacción).
-- =====================================================================

DO $$
BEGIN
  IF current_setting('server_version_num')::int < 160000 THEN
    RAISE EXCEPTION 'Se requiere PostgreSQL 16 o superior (versión actual: %)', current_setting('server_version');
  END IF;
END $$;

SET client_encoding = 'UTF8';
