-- =====================================================================
-- 09_ledger.sql · Banco Andino Colombia
-- Asientos contables de doble partida (RN-46 a RN-48).
-- Se ejecuta desde sql/run_all.sql (no abre ni cierra transacción).
-- =====================================================================

-- =====================================================================
-- 9. CONTABILIDAD (doble partida)
-- =====================================================================

CREATE TABLE fin.asiento_contable (
  transaccion_id          bigint        NOT NULL REFERENCES fin.transaccion_financiera (transaccion_id),
  linea                   smallint      NOT NULL CHECK (linea > 0),
  cuenta_contable_codigo  varchar(30)   NOT NULL REFERENCES ref.cuenta_contable (cuenta_contable_codigo),
  cuenta_id               bigint        REFERENCES core.cuenta (cuenta_id),
  naturaleza              char(1)       NOT NULL CHECK (naturaleza IN ('D', 'C')),
  valor                   numeric(18,2) NOT NULL CHECK (valor > 0),
  registrado_en           timestamptz   NOT NULL DEFAULT now(),
  PRIMARY KEY (transaccion_id, linea)
);
COMMENT ON TABLE fin.asiento_contable IS 'Líneas débito/crédito de cada transacción POSTED. Σ débitos = Σ créditos por transacción (RN-46, RN-47; se garantiza con trigger diferido en G3).';
COMMENT ON COLUMN fin.asiento_contable.cuenta_id IS 'Cuenta del cliente afectada cuando la cuenta contable es de depósitos; NULL para caja, ingresos o gastos.';
