-- =====================================================================
-- 05_products.sql · Banco Andino Colombia
-- Productos y sus parámetros (máximo de titulares, sobregiro, cuenta contable).
-- Se ejecuta desde sql/run_all.sql (no abre ni cierra transacción).
-- =====================================================================

-- =====================================================================
-- 6. PRODUCTOS
-- =====================================================================

CREATE TABLE core.producto (
  producto_codigo         varchar(20)  PRIMARY KEY,
  nombre                  varchar(80)  NOT NULL UNIQUE,
  tipo_cliente_permitido  varchar(10)  CHECK (tipo_cliente_permitido IN ('NATURAL', 'JURIDICA')),
  permite_sobregiro       boolean      NOT NULL DEFAULT false,
  max_titulares           smallint     NOT NULL CHECK (max_titulares BETWEEN 1 AND 5),
  cuenta_contable_codigo  varchar(30)  NOT NULL REFERENCES ref.cuenta_contable (cuenta_contable_codigo)
);
COMMENT ON TABLE core.producto IS 'Productos y sus parámetros. tipo_cliente_permitido NULL = ambos tipos. max_titulares por producto (S3, RN-16).';

INSERT INTO core.producto
  (producto_codigo, nombre, tipo_cliente_permitido, permite_sobregiro, max_titulares, cuenta_contable_codigo) VALUES
  ('AHORROS',     'Cuenta de ahorros',     NULL,       false, 4, 'PAS_DEP_AHORROS'),
  ('CORRIENTE',   'Cuenta corriente',      NULL,       true,  4, 'PAS_DEP_CORRIENTE'),
  ('NOMINA',      'Cuenta de nómina',      'NATURAL',  false, 1, 'PAS_DEP_NOMINA'),       -- RN-14
  ('EMPRESARIAL', 'Cuenta empresarial',    'JURIDICA', false, 1, 'PAS_DEP_EMPRESARIAL');  -- RN-15, S4
