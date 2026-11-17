-- =====================================================================
-- B2 · Rol de solo lectura para Power BI y las estadísticas del aplicativo
-- banco_bi: rol de grupo que solo puede leer el esquema bi.
-- powerbi_lector: usuario con el que se conecta Power BI. Lo creamos SIN
-- contraseña; la contraseña la pone cada uno en su PC (nunca va al repositorio).
-- =====================================================================
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'banco_bi') THEN
    CREATE ROLE banco_bi NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'powerbi_lector') THEN
    CREATE ROLE powerbi_lector LOGIN;
  END IF;
END $$;
COMMENT ON ROLE banco_bi IS 'Solo lectura del modelo estrella (esquema bi). No ve las tablas del banco.';

GRANT CONNECT ON DATABASE banco_andino_lab TO banco_bi;
GRANT USAGE ON SCHEMA bi TO banco_bi;
GRANT SELECT ON ALL TABLES IN SCHEMA bi TO banco_bi;
REVOKE ALL ON PROCEDURE bi.cargar_bi() FROM PUBLIC;
GRANT banco_bi TO powerbi_lector;

\echo '== Prueba de permisos de banco_bi'
SET ROLE banco_bi;
SELECT 'Lee bi.fact_transaccion' AS prueba, CASE WHEN count(*) > 0 THEN 'PERMITIDO' END AS resultado FROM bi.fact_transaccion;
DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM core.cuenta LIMIT 1;
    RAISE NOTICE 'Lee core.cuenta: PERMITIDO (no debería)';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Lee core.cuenta: DENEGADO (correcto)';
  END;
  BEGIN
    INSERT INTO bi.fact_control VALUES ('X', 'X', 'X', '0', 0, 'X');
    RAISE NOTICE 'Escribe en bi: PERMITIDO (no debería)';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Escribe en bi: DENEGADO (correcto)';
  END;
END $$;
RESET ROLE;

\echo 'Rol banco_bi y usuario powerbi_lector listos. Falta ponerle contraseña a powerbi_lector en cada PC.'
