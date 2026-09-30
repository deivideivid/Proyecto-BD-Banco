-- =====================================================================
-- 01_schemas.sql · Banco Andino Colombia
-- Esquemas del modelo (DM-10).
-- Se ejecuta desde sql/run_all.sql (no abre ni cierra transacción).
-- =====================================================================

-- =====================================================================
-- 1. ESQUEMAS
-- =====================================================================
CREATE SCHEMA ref;   -- catálogos y geografía
CREATE SCHEMA seg;   -- usuarios internos, roles y permisos
CREATE SCHEMA core;  -- clientes, productos, cuentas y eventos
CREATE SCHEMA fin;   -- transacciones y contabilidad
CREATE SCHEMA aud;   -- auditoría

COMMENT ON SCHEMA ref  IS 'Catálogos controlados y geografía (DIVIPOLA).';
COMMENT ON SCHEMA seg  IS 'Usuarios internos del banco y control de acceso por roles.';
COMMENT ON SCHEMA core IS 'Clientes, productos, cuentas, titularidad y eventos de cuenta.';
COMMENT ON SCHEMA fin  IS 'Transacciones financieras y asientos contables de doble partida.';
COMMENT ON SCHEMA aud  IS 'Registro de auditoría de operaciones críticas.';
