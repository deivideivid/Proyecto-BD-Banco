-- =====================================================================
-- 11_constraints.sql · Banco Andino Colombia
-- Claves foráneas que cruzan el orden de los archivos: core.evento_cuenta
-- (06_accounts) referencia a seg.usuario, que se crea después (07).
-- Se ejecuta desde sql/run_all.sql (no abre ni cierra transacción).
-- =====================================================================

ALTER TABLE core.evento_cuenta
  ADD CONSTRAINT evento_cuenta_registrado_por_fkey
  FOREIGN KEY (registrado_por) REFERENCES seg.usuario (usuario_id);
