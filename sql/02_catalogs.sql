-- =====================================================================
-- 02_catalogs.sql · Banco Andino Colombia
-- Catálogos controlados, plan de cuentas contable y función del dígito de verificación del NIT.
-- Se ejecuta desde sql/run_all.sql (no abre ni cierra transacción).
-- =====================================================================

-- =====================================================================
-- 2. CATÁLOGOS
-- =====================================================================

-- 2.1 Tipos de documento (RN-03)
CREATE TABLE ref.tipo_documento (
  codigo        varchar(5)  PRIMARY KEY,
  nombre        varchar(60) NOT NULL UNIQUE,
  tipo_cliente  varchar(10) NOT NULL CHECK (tipo_cliente IN ('NATURAL', 'JURIDICA')),
  CONSTRAINT uq_tipo_documento_tipo_cliente UNIQUE (codigo, tipo_cliente)
);
COMMENT ON TABLE ref.tipo_documento IS 'Documentos de identidad y el tipo de cliente que puede usarlos (RN-03).';

INSERT INTO ref.tipo_documento (codigo, nombre, tipo_cliente) VALUES
  ('CC',  'Cédula de ciudadanía',           'NATURAL'),
  ('CE',  'Cédula de extranjería',          'NATURAL'),
  ('PA',  'Pasaporte',                      'NATURAL'),
  ('PPT', 'Permiso por protección temporal','NATURAL'),
  ('NIT', 'Número de identificación tributaria', 'JURIDICA');

-- 2.2 Estados de cliente (RN-09)
CREATE TABLE ref.estado_cliente (
  codigo  varchar(15) PRIMARY KEY,
  nombre  varchar(60) NOT NULL UNIQUE
);
COMMENT ON TABLE ref.estado_cliente IS 'Estados del cliente. Los clientes se inactivan, no se eliminan (RN-09).';

INSERT INTO ref.estado_cliente (codigo, nombre) VALUES
  ('ACTIVO',   'Activo'),
  ('INACTIVO', 'Inactivo');

-- 2.3 Monedas (ISO 4217)
CREATE TABLE ref.moneda (
  codigo     char(3)     PRIMARY KEY CHECK (codigo ~ '^[A-Z]{3}$'),
  nombre     varchar(60) NOT NULL UNIQUE,
  decimales  smallint    NOT NULL CHECK (decimales BETWEEN 0 AND 4)
);
COMMENT ON TABLE ref.moneda IS 'Monedas permitidas según ISO 4217.';

INSERT INTO ref.moneda (codigo, nombre, decimales) VALUES
  ('COP', 'Peso colombiano',          2),
  ('USD', 'Dólar estadounidense',     2);

-- 2.4 Estados de cuenta
CREATE TABLE ref.estado_cuenta (
  codigo  varchar(15) PRIMARY KEY,
  nombre  varchar(60) NOT NULL UNIQUE
);
COMMENT ON TABLE ref.estado_cuenta IS 'Estados del ciclo de vida de la cuenta.';

INSERT INTO ref.estado_cuenta (codigo, nombre) VALUES
  ('CREADA',    'Creada'),
  ('ACTIVA',    'Activa'),
  ('BLOQUEADA', 'Bloqueada'),
  ('INACTIVA',  'Inactiva'),
  ('CERRADA',   'Cerrada');

-- 2.5 Tipos de evento de cuenta
CREATE TABLE ref.tipo_evento_cuenta (
  codigo  varchar(20) PRIMARY KEY,
  nombre  varchar(60) NOT NULL UNIQUE
);
COMMENT ON TABLE ref.tipo_evento_cuenta IS 'Eventos administrativos de la cuenta. No mueven dinero (RN-26).';

INSERT INTO ref.tipo_evento_cuenta (codigo, nombre) VALUES
  ('CREACION',      'Creación'),
  ('ACTIVACION',    'Activación'),
  ('BLOQUEO',       'Bloqueo'),
  ('DESBLOQUEO',    'Desbloqueo'),
  ('INACTIVACION',  'Inactivación'),
  ('CIERRE',        'Cierre'),
  ('CAMBIO_LIMITE', 'Cambio de límite');

-- 2.6 Transiciones de estado permitidas (RN-24)
CREATE TABLE ref.transicion_estado_cuenta (
  tipo_evento      varchar(20) NOT NULL REFERENCES ref.tipo_evento_cuenta (codigo),
  estado_anterior  varchar(15) NOT NULL REFERENCES ref.estado_cuenta (codigo),
  estado_nuevo     varchar(15) NOT NULL REFERENCES ref.estado_cuenta (codigo),
  PRIMARY KEY (tipo_evento, estado_anterior, estado_nuevo)
);
COMMENT ON TABLE ref.transicion_estado_cuenta IS 'Única fuente de transiciones válidas; los eventos la referencian con FK compuesta (RN-24). CREACION se controla con CHECK en core.evento_cuenta.';

INSERT INTO ref.transicion_estado_cuenta (tipo_evento, estado_anterior, estado_nuevo) VALUES
  ('ACTIVACION',    'CREADA',    'ACTIVA'),
  ('CIERRE',        'CREADA',    'CERRADA'),
  ('BLOQUEO',       'ACTIVA',    'BLOQUEADA'),
  ('DESBLOQUEO',    'BLOQUEADA', 'ACTIVA'),
  ('INACTIVACION',  'ACTIVA',    'INACTIVA'),
  ('ACTIVACION',    'INACTIVA',  'ACTIVA'),
  ('CIERRE',        'ACTIVA',    'CERRADA'),
  ('CIERRE',        'INACTIVA',  'CERRADA'),
  ('CAMBIO_LIMITE', 'ACTIVA',    'ACTIVA');

-- 2.7 Tipos de transacción
CREATE TABLE ref.tipo_transaccion (
  codigo  varchar(20) PRIMARY KEY,
  nombre  varchar(60) NOT NULL UNIQUE
);
COMMENT ON TABLE ref.tipo_transaccion IS 'Tipos de transacción financiera (sí mueven dinero).';

INSERT INTO ref.tipo_transaccion (codigo, nombre) VALUES
  ('CONSIGNACION',  'Consignación'),
  ('RETIRO',        'Retiro'),
  ('TRANSFERENCIA', 'Transferencia'),
  ('DEBITO',        'Débito'),
  ('CREDITO',       'Crédito'),
  ('AJUSTE',        'Ajuste'),
  ('REVERSO',       'Reverso');

-- 2.8 Estados de transacción (RN-40, RN-45)
CREATE TABLE ref.estado_transaccion (
  codigo  varchar(20) PRIMARY KEY,
  nombre  varchar(60) NOT NULL UNIQUE
);
COMMENT ON TABLE ref.estado_transaccion IS 'POSTED = contabilizada e inmutable; REJECTED = rechazada sin efecto financiero; PENDING_APPROVAL = ajuste pendiente.';

INSERT INTO ref.estado_transaccion (codigo, nombre) VALUES
  ('POSTED',           'Contabilizada'),
  ('REJECTED',         'Rechazada'),
  ('PENDING_APPROVAL', 'Pendiente de aprobación');

-- 2.9 Plan de cuentas contable mínimo (códigos mnemónicos)
CREATE TABLE ref.cuenta_contable (
  cuenta_contable_codigo  varchar(30)  PRIMARY KEY,
  nombre                  varchar(100) NOT NULL UNIQUE,
  naturaleza              char(1)      NOT NULL CHECK (naturaleza IN ('D', 'C')),
  es_deposito_cliente     boolean      NOT NULL DEFAULT false
);
COMMENT ON TABLE ref.cuenta_contable IS 'Plan de cuentas mínimo para la doble partida. Los depósitos de clientes son pasivo (naturaleza crédito).';

INSERT INTO ref.cuenta_contable (cuenta_contable_codigo, nombre, naturaleza, es_deposito_cliente) VALUES
  ('ACT_CAJA',               'Caja',                                  'D', false),
  ('ACT_COMPENSACION',       'Cuenta de compensación interbancaria',  'D', false),
  ('PAS_DEP_AHORROS',        'Depósitos en cuentas de ahorro',        'C', true),
  ('PAS_DEP_CORRIENTE',      'Depósitos en cuentas corrientes',       'C', true),
  ('PAS_DEP_NOMINA',         'Depósitos en cuentas de nómina',        'C', true),
  ('PAS_DEP_EMPRESARIAL',    'Depósitos en cuentas empresariales',    'C', true),
  ('PAS_AJUSTES_PENDIENTES', 'Ajustes pendientes por aplicar',        'C', false),
  ('ING_COMISIONES',         'Ingresos por comisiones',               'C', false),
  ('GAS_INTERESES',          'Gasto por intereses',                   'D', false);

-- 2.10 Dígito de verificación del NIT (algoritmo módulo 11 de la DIAN) — RN-04
CREATE FUNCTION ref.fn_dv_nit(p_nit text) RETURNS smallint
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
  SELECT (CASE WHEN s % 11 IN (0, 1) THEN s % 11 ELSE 11 - s % 11 END)::smallint
  FROM (
    SELECT sum(substr(reverse(p_nit), i, 1)::int
               * (ARRAY[3,7,13,17,19,23,29,37,41,43,47,53,59,67,71])[i]) AS s
    FROM generate_series(1, length(p_nit)) AS i
  ) t
$$;
COMMENT ON FUNCTION ref.fn_dv_nit(text) IS 'Calcula el dígito de verificación de un NIT colombiano. Ejemplo: 800197268 → 4.';
