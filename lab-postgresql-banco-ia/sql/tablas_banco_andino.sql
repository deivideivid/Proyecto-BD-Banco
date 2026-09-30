-- =====================================================================
-- Banco Andino Colombia · Creación de tablas
-- PostgreSQL 16+
-- Basado en: docs/01_especificacion.md (G1) — reglas RN-01 a RN-54
-- Modelo revisado en G2: docs/02_modelo_logico.md (cambios marcados con "G2, hallazgo H-xx")
--
-- Ejecución recomendada (base vacía):
--   psql -h localhost -U postgres -d banco_andino_lab -v ON_ERROR_STOP=1 -f tablas_banco_andino.sql
--
-- Todo el script corre en una sola transacción: si algo falla, no queda nada a medias.
-- Para volver a ejecutarlo desde cero, primero:
--   DROP SCHEMA IF EXISTS aud, fin, core, seg, ref CASCADE;
--
-- Distribución sugerida en los archivos numerados del laboratorio:
--   01_schemas.sql         → sección 1
--   02_catalogs.sql        → sección 2
--   03_geography.sql       → sección 3
--   07_users_security.sql  → sección 4
--   04_customers.sql       → sección 5
--   05_products.sql        → sección 6
--   06_accounts.sql        → sección 7
--   08_transactions.sql    → sección 8
--   09_ledger.sql          → sección 9
--   10_audit.sql           → sección 10
-- (Usuarios se crea antes que cuentas porque los eventos y las transacciones
--  referencian al usuario que los registra.)
-- =====================================================================

SET client_encoding = 'UTF8';

BEGIN;

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

-- =====================================================================
-- 3. GEOGRAFÍA
-- =====================================================================

CREATE TABLE ref.departamento (
  departamento_codigo  char(2)     PRIMARY KEY CHECK (departamento_codigo ~ '^[0-9]{2}$'),
  nombre               varchar(80) NOT NULL UNIQUE
);
COMMENT ON TABLE ref.departamento IS 'Departamentos de Colombia con código DIVIPOLA (DANE).';

CREATE TABLE ref.municipio (
  municipio_codigo     char(5)     PRIMARY KEY CHECK (municipio_codigo ~ '^[0-9]{5}$'),
  departamento_codigo  char(2)     NOT NULL REFERENCES ref.departamento (departamento_codigo),
  nombre               varchar(80) NOT NULL,
  CONSTRAINT ck_municipio_prefijo_departamento
    CHECK (left(municipio_codigo, 2) = departamento_codigo),              -- RN-07
  CONSTRAINT uq_municipio_nombre_departamento UNIQUE (departamento_codigo, nombre)
);
COMMENT ON TABLE ref.municipio IS 'Municipios con código DIVIPOLA de 5 dígitos. El código inicia con el del departamento (RN-07). Cargar desde la fuente oficial del DANE; los códigos son texto (conservan el 0 inicial).';

CREATE TABLE ref.oficina (
  oficina_id        integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  codigo            varchar(10)  NOT NULL UNIQUE,
  nombre            varchar(100) NOT NULL,
  municipio_codigo  char(5)      NOT NULL REFERENCES ref.municipio (municipio_codigo),  -- RN-06
  activa            boolean      NOT NULL DEFAULT true
);
COMMENT ON TABLE ref.oficina IS 'Oficinas del banco (RN-06).';

-- =====================================================================
-- 4. SEGURIDAD (usuarios internos, roles y permisos)
-- =====================================================================

CREATE TABLE seg.usuario (
  usuario_id        bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  login             varchar(40)  NOT NULL UNIQUE CHECK (login ~ '^[a-z0-9._]{4,40}$'),
  tipo_documento    varchar(5)   NOT NULL REFERENCES ref.tipo_documento (codigo)
                                 CHECK (tipo_documento IN ('CC', 'CE', 'PA', 'PPT')),
  numero_documento  varchar(15)  NOT NULL CHECK (numero_documento ~ '^[A-Z0-9]{5,15}$'),
  nombres           varchar(120) NOT NULL,
  apellidos         varchar(120) NOT NULL,
  oficina_id        integer      REFERENCES ref.oficina (oficina_id),
  estado            varchar(10)  NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO', 'INACTIVO')),
  creado_en         timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT uq_usuario_documento UNIQUE (tipo_documento, numero_documento)
);
COMMENT ON TABLE seg.usuario IS 'Empleados con acceso al sistema. No tiene relación con core.cliente (RN-10). El documento permite detectar si un usuario opera cuentas propias (RN-54). No almacena contraseñas.';

CREATE TABLE seg.rol (
  rol_id  smallint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  codigo  varchar(30)  NOT NULL UNIQUE,
  nombre  varchar(80)  NOT NULL
);
COMMENT ON TABLE seg.rol IS 'Roles internos. Los permisos se asignan a roles, no a usuarios (RN-49).';

CREATE TABLE seg.permiso (
  permiso_id   smallint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  codigo       varchar(40)  NOT NULL UNIQUE,
  descripcion  varchar(150) NOT NULL
);
COMMENT ON TABLE seg.permiso IS 'Acciones autorizables del sistema.';

CREATE TABLE seg.usuario_rol (
  usuario_id     bigint      NOT NULL REFERENCES seg.usuario (usuario_id),
  rol_id         smallint    NOT NULL REFERENCES seg.rol (rol_id),
  vigente_desde  timestamptz NOT NULL DEFAULT now(),
  vigente_hasta  timestamptz,
  asignado_por   bigint      REFERENCES seg.usuario (usuario_id),
  PRIMARY KEY (usuario_id, rol_id, vigente_desde),
  CONSTRAINT ck_usuario_rol_no_autoasignado CHECK (asignado_por <> usuario_id),   -- RN-50
  CONSTRAINT ck_usuario_rol_vigencia CHECK (vigente_hasta IS NULL OR vigente_hasta > vigente_desde)
);
COMMENT ON TABLE seg.usuario_rol IS 'Asignación de roles con vigencia (se revoca con fecha, no se borra). asignado_por NULL solo para la carga inicial del sistema.';

CREATE TABLE seg.rol_permiso (
  rol_id      smallint NOT NULL REFERENCES seg.rol (rol_id),
  permiso_id  smallint NOT NULL REFERENCES seg.permiso (permiso_id),
  PRIMARY KEY (rol_id, permiso_id)
);
COMMENT ON TABLE seg.rol_permiso IS 'Permisos incluidos en cada rol.';

INSERT INTO seg.rol (codigo, nombre) VALUES
  ('CAJERO',          'Cajero'),
  ('SUPERVISOR',      'Supervisor de oficina'),
  ('AUDITOR',         'Auditor'),
  ('ADMIN_SEGURIDAD', 'Administrador de seguridad');

INSERT INTO seg.permiso (codigo, descripcion) VALUES
  ('CLI_CREAR',          'Registrar clientes'),
  ('CLI_ACTUALIZAR',     'Actualizar datos de clientes'),
  ('CTA_ABRIR',          'Abrir cuentas'),
  ('CTA_ACTIVAR',        'Activar cuentas'),
  ('CTA_BLOQUEAR',       'Bloquear cuentas'),
  ('CTA_DESBLOQUEAR',    'Desbloquear cuentas'),
  ('CTA_CERRAR',         'Cerrar cuentas'),
  ('CTA_CAMBIAR_LIMITE', 'Cambiar límites de cuenta'),
  ('TX_CONSIGNAR',       'Registrar consignaciones'),
  ('TX_RETIRAR',         'Registrar retiros'),
  ('TX_TRANSFERIR',      'Registrar transferencias'),
  ('TX_DEBITAR',         'Registrar débitos'),
  ('TX_ACREDITAR',       'Registrar créditos'),
  ('TX_AJUSTE_CREAR',    'Crear ajustes'),
  ('TX_AJUSTE_APROBAR',  'Aprobar ajustes'),
  ('TX_REVERSAR',        'Reversar transacciones'),
  ('AUD_CONSULTAR',      'Consultar auditoría'),
  ('SEG_ADMINISTRAR',    'Administrar usuarios, roles y permisos');

-- Matriz rol × permiso (RN-28: desbloquear, cerrar y cambiar límite solo SUPERVISOR;
-- RN-51: CAJERO no reversa ni aprueba ajustes)
INSERT INTO seg.rol_permiso (rol_id, permiso_id)
SELECT r.rol_id, p.permiso_id
FROM (VALUES
  ('CAJERO', 'CLI_CREAR'), ('CAJERO', 'CLI_ACTUALIZAR'), ('CAJERO', 'CTA_ABRIR'),
  ('CAJERO', 'CTA_ACTIVAR'), ('CAJERO', 'CTA_BLOQUEAR'), ('CAJERO', 'TX_CONSIGNAR'),
  ('CAJERO', 'TX_RETIRAR'), ('CAJERO', 'TX_TRANSFERIR'), ('CAJERO', 'TX_DEBITAR'),
  ('CAJERO', 'TX_ACREDITAR'), ('CAJERO', 'TX_AJUSTE_CREAR'),
  ('SUPERVISOR', 'CLI_CREAR'), ('SUPERVISOR', 'CLI_ACTUALIZAR'), ('SUPERVISOR', 'CTA_ABRIR'),
  ('SUPERVISOR', 'CTA_ACTIVAR'), ('SUPERVISOR', 'CTA_BLOQUEAR'), ('SUPERVISOR', 'CTA_DESBLOQUEAR'),
  ('SUPERVISOR', 'CTA_CERRAR'), ('SUPERVISOR', 'CTA_CAMBIAR_LIMITE'), ('SUPERVISOR', 'TX_CONSIGNAR'),
  ('SUPERVISOR', 'TX_RETIRAR'), ('SUPERVISOR', 'TX_TRANSFERIR'), ('SUPERVISOR', 'TX_DEBITAR'),
  ('SUPERVISOR', 'TX_ACREDITAR'), ('SUPERVISOR', 'TX_AJUSTE_CREAR'), ('SUPERVISOR', 'TX_AJUSTE_APROBAR'),
  ('SUPERVISOR', 'TX_REVERSAR'),
  ('AUDITOR', 'AUD_CONSULTAR'),
  ('ADMIN_SEGURIDAD', 'SEG_ADMINISTRAR')
) AS m (rol, permiso)
JOIN seg.rol r     ON r.codigo = m.rol
JOIN seg.permiso p ON p.codigo = m.permiso;

-- =====================================================================
-- 5. CLIENTES (supertipo + subtipos)
-- =====================================================================

CREATE TABLE core.cliente (
  cliente_id           bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  tipo_cliente         varchar(10)  NOT NULL CHECK (tipo_cliente IN ('NATURAL', 'JURIDICA')),
  tipo_documento       varchar(5)   NOT NULL,
  numero_documento     varchar(15)  NOT NULL CHECK (numero_documento ~ '^[A-Z0-9]{5,15}$'),
  digito_verificacion  smallint,
  municipio_codigo     char(5)      NOT NULL REFERENCES ref.municipio (municipio_codigo),   -- RN-05
  estado_cliente       varchar(15)  NOT NULL DEFAULT 'ACTIVO' REFERENCES ref.estado_cliente (codigo),
  fecha_vinculacion    date         NOT NULL,
  email                varchar(254) CHECK (email ~* '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'),
  telefono             varchar(20)  CHECK (telefono ~ '^[0-9+ ]{7,20}$'),
  creado_en            timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT uq_cliente_documento UNIQUE (tipo_documento, numero_documento),              -- RN-01
  CONSTRAINT uq_cliente_id_tipo   UNIQUE (cliente_id, tipo_cliente),                      -- destino de FK de subtipos
  CONSTRAINT fk_cliente_tipo_documento FOREIGN KEY (tipo_documento, tipo_cliente)
    REFERENCES ref.tipo_documento (codigo, tipo_cliente),                                  -- RN-03
  CONSTRAINT ck_cliente_nit_numerico
    CHECK (tipo_documento <> 'NIT' OR numero_documento ~ '^[0-9]{9}$'),
  CONSTRAINT ck_cliente_dv_solo_nit
    CHECK ((tipo_documento = 'NIT') = (digito_verificacion IS NOT NULL)),
  CONSTRAINT ck_cliente_dv_valido
    CHECK (digito_verificacion IS NULL
           OR digito_verificacion = ref.fn_dv_nit(numero_documento))                       -- RN-04
);
COMMENT ON TABLE core.cliente IS 'Supertipo de cliente: datos comunes a personas naturales y jurídicas. Documento único (RN-01).';
COMMENT ON COLUMN core.cliente.digito_verificacion IS 'Solo para NIT; validado con ref.fn_dv_nit (RN-04).';

CREATE TABLE core.persona_natural (
  cliente_id        bigint       PRIMARY KEY,
  tipo_cliente      varchar(10)  NOT NULL DEFAULT 'NATURAL' CHECK (tipo_cliente = 'NATURAL'),
  nombres           varchar(120) NOT NULL,
  apellidos         varchar(120) NOT NULL,
  fecha_nacimiento  date         NOT NULL CHECK (fecha_nacimiento >= DATE '1900-01-01'),
  CONSTRAINT fk_persona_natural_cliente FOREIGN KEY (cliente_id, tipo_cliente)
    REFERENCES core.cliente (cliente_id, tipo_cliente)                                     -- RN-02
);
COMMENT ON TABLE core.persona_natural IS 'Subtipo 1:1 de cliente para personas naturales. La FK compuesta impide asociarlo a un cliente jurídico (RN-02).';

CREATE TABLE core.persona_juridica (
  cliente_id           bigint       PRIMARY KEY,
  tipo_cliente         varchar(10)  NOT NULL DEFAULT 'JURIDICA' CHECK (tipo_cliente = 'JURIDICA'),
  razon_social         varchar(200) NOT NULL,
  fecha_constitucion   date         NOT NULL,
  actividad_economica  char(4)      NOT NULL CHECK (actividad_economica ~ '^[0-9]{4}$'),   -- código CIIU
  CONSTRAINT fk_persona_juridica_cliente FOREIGN KEY (cliente_id, tipo_cliente)
    REFERENCES core.cliente (cliente_id, tipo_cliente)                                     -- RN-02
);
COMMENT ON TABLE core.persona_juridica IS 'Subtipo 1:1 de cliente para personas jurídicas (RN-02).';

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

-- =====================================================================
-- 7. CUENTAS, TITULARIDAD Y EVENTOS
-- =====================================================================

CREATE TABLE core.cuenta (
  cuenta_id             bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  numero_cuenta         char(11)      NOT NULL UNIQUE CHECK (numero_cuenta ~ '^[0-9]{11}$'),   -- RN-11
  producto_codigo       varchar(20)   NOT NULL REFERENCES core.producto (producto_codigo),     -- RN-12
  moneda_codigo         char(3)       NOT NULL REFERENCES ref.moneda (codigo),
  oficina_id            integer       NOT NULL REFERENCES ref.oficina (oficina_id),
  estado_cuenta         varchar(15)   NOT NULL DEFAULT 'CREADA' REFERENCES ref.estado_cuenta (codigo),
  fecha_apertura        timestamptz   NOT NULL DEFAULT now(),
  fecha_cierre          timestamptz,
  saldo_contable        numeric(18,2) NOT NULL DEFAULT 0,
  saldo_retenido        numeric(18,2) NOT NULL DEFAULT 0 CHECK (saldo_retenido >= 0),          -- RN-19
  saldo_disponible      numeric(18,2) GENERATED ALWAYS AS (saldo_contable - saldo_retenido) STORED,  -- RN-19
  cupo_sobregiro        numeric(18,2) NOT NULL DEFAULT 0 CHECK (cupo_sobregiro >= 0),
  limite_retiro_diario  numeric(18,2) NOT NULL CHECK (limite_retiro_diario > 0),
  CONSTRAINT ck_cuenta_sobregiro
    CHECK (saldo_contable - saldo_retenido >= -cupo_sobregiro),                              -- RN-18
  CONSTRAINT ck_cuenta_cierre_con_fecha
    CHECK ((estado_cuenta = 'CERRADA') = (fecha_cierre IS NOT NULL)),
  CONSTRAINT ck_cuenta_cierre_sin_saldo
    CHECK (estado_cuenta <> 'CERRADA' OR (saldo_contable = 0 AND saldo_retenido = 0)),       -- RN-20
  CONSTRAINT ck_cuenta_fechas
    CHECK (fecha_cierre IS NULL OR fecha_cierre > fecha_apertura)                            -- RN-21
) WITH (fillfactor = 85);
COMMENT ON TABLE core.cuenta IS 'Cuentas bancarias. El saldo es una caché que debe coincidir con los asientos contables (RN-48). fillfactor 85 favorece actualizaciones HOT del saldo.';
COMMENT ON COLUMN core.cuenta.saldo_disponible IS 'Columna generada: saldo_contable - saldo_retenido (RN-19).';

CREATE TABLE core.titularidad_cuenta (
  cuenta_id      bigint       NOT NULL REFERENCES core.cuenta (cuenta_id),
  cliente_id     bigint       NOT NULL REFERENCES core.cliente (cliente_id),
  vigente_desde  timestamptz  NOT NULL DEFAULT now(),
  rol_titular    varchar(10)  NOT NULL CHECK (rol_titular IN ('PRINCIPAL', 'COTITULAR')),
  vigente_hasta  timestamptz,
  PRIMARY KEY (cuenta_id, cliente_id, vigente_desde),
  CONSTRAINT ck_titularidad_vigencia CHECK (vigente_hasta IS NULL OR vigente_hasta > vigente_desde)
);
COMMENT ON TABLE core.titularidad_cuenta IS 'Relación N:M cliente-cuenta con rol y vigencia.';

-- Máximo un titular principal vigente por cuenta (RN-13, parte "máximo uno")
CREATE UNIQUE INDEX uq_titularidad_principal_vigente
  ON core.titularidad_cuenta (cuenta_id)
  WHERE rol_titular = 'PRINCIPAL' AND vigente_hasta IS NULL;

-- Un cliente no puede tener dos titularidades vigentes sobre la misma cuenta
-- (G2, hallazgo H-06: la PK con vigente_desde lo permitía)
CREATE UNIQUE INDEX uq_titularidad_cliente_vigente
  ON core.titularidad_cuenta (cuenta_id, cliente_id)
  WHERE vigente_hasta IS NULL;

CREATE TABLE core.evento_cuenta (
  evento_id        bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  cuenta_id        bigint       NOT NULL REFERENCES core.cuenta (cuenta_id),
  tipo_evento      varchar(20)  NOT NULL REFERENCES ref.tipo_evento_cuenta (codigo),
  estado_anterior  varchar(15)  REFERENCES ref.estado_cuenta (codigo),
  estado_nuevo     varchar(15)  NOT NULL REFERENCES ref.estado_cuenta (codigo),
  motivo           varchar(200),
  ocurrido_en      timestamptz  NOT NULL DEFAULT now(),
  registrado_por   bigint       NOT NULL REFERENCES seg.usuario (usuario_id),
  CONSTRAINT uq_evento_id_tipo UNIQUE (evento_id, tipo_evento),                              -- destino de FK de cambio_limite
  CONSTRAINT fk_evento_transicion FOREIGN KEY (tipo_evento, estado_anterior, estado_nuevo)
    REFERENCES ref.transicion_estado_cuenta (tipo_evento, estado_anterior, estado_nuevo),     -- RN-24
  CONSTRAINT ck_evento_creacion_sin_estado_anterior
    CHECK ((tipo_evento = 'CREACION') = (estado_anterior IS NULL)),
  CONSTRAINT ck_evento_creacion_estado_creada
    CHECK (tipo_evento <> 'CREACION' OR estado_nuevo = 'CREADA'),
  CONSTRAINT ck_evento_bloqueo_con_motivo
    CHECK (tipo_evento <> 'BLOQUEO' OR motivo IS NOT NULL)                                   -- RN-29
);
COMMENT ON TABLE core.evento_cuenta IS 'Historial del ciclo de vida de la cuenta. No mueve dinero (RN-26). Las transiciones válidas se controlan con FK a ref.transicion_estado_cuenta (RN-24).';

CREATE TABLE core.cambio_limite (
  evento_id       bigint        PRIMARY KEY,
  tipo_evento     varchar(20)   NOT NULL DEFAULT 'CAMBIO_LIMITE' CHECK (tipo_evento = 'CAMBIO_LIMITE'),
  valor_anterior  numeric(18,2) NOT NULL CHECK (valor_anterior > 0),
  valor_nuevo     numeric(18,2) NOT NULL CHECK (valor_nuevo > 0),
  CONSTRAINT ck_cambio_limite_distinto CHECK (valor_nuevo <> valor_anterior),                -- RN-27
  CONSTRAINT fk_cambio_limite_evento FOREIGN KEY (evento_id, tipo_evento)
    REFERENCES core.evento_cuenta (evento_id, tipo_evento)
);
COMMENT ON TABLE core.cambio_limite IS 'Detalle de eventos CAMBIO_LIMITE. La FK compuesta impide asociarlo a otro tipo de evento (RN-27).';

-- =====================================================================
-- 8. TRANSACCIONES FINANCIERAS
-- =====================================================================

CREATE TABLE fin.transaccion_financiera (
  transaccion_id            bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  tipo_codigo               varchar(20)   NOT NULL REFERENCES ref.tipo_transaccion (codigo),
  estado_codigo             varchar(20)   NOT NULL REFERENCES ref.estado_transaccion (codigo),
  cuenta_origen_id          bigint        REFERENCES core.cuenta (cuenta_id),
  cuenta_destino_id         bigint        REFERENCES core.cuenta (cuenta_id),
  monto                     numeric(18,2) NOT NULL CHECK (monto > 0),                        -- RN-30
  idempotency_key           uuid          NOT NULL UNIQUE,                                   -- RN-38
  hash_solicitud            bytea,
  transaccion_reversada_id  bigint        UNIQUE REFERENCES fin.transaccion_financiera (transaccion_id),  -- RN-42
  descripcion               varchar(140),
  fecha_solicitud           timestamptz   NOT NULL DEFAULT now(),
  fecha_contabilizacion     timestamptz,
  fecha_contable            date,
  creado_por                bigint        NOT NULL REFERENCES seg.usuario (usuario_id),
  aprobado_por              bigint        REFERENCES seg.usuario (usuario_id),
  motivo_rechazo            varchar(200),

  -- Cuentas coherentes con el tipo (RN-32: origen ≠ destino en transferencias)
  CONSTRAINT ck_tx_cuentas_por_tipo CHECK (
    CASE tipo_codigo
      WHEN 'CONSIGNACION'  THEN cuenta_origen_id IS NULL     AND cuenta_destino_id IS NOT NULL
      WHEN 'CREDITO'       THEN cuenta_origen_id IS NULL     AND cuenta_destino_id IS NOT NULL
      WHEN 'RETIRO'        THEN cuenta_origen_id IS NOT NULL AND cuenta_destino_id IS NULL
      WHEN 'DEBITO'        THEN cuenta_origen_id IS NOT NULL AND cuenta_destino_id IS NULL
      WHEN 'TRANSFERENCIA' THEN cuenta_origen_id IS NOT NULL AND cuenta_destino_id IS NOT NULL
                                AND cuenta_origen_id <> cuenta_destino_id
      ELSE num_nonnulls(cuenta_origen_id, cuenta_destino_id) >= 1          -- AJUSTE, REVERSO
    END
  ),
  -- Solo los reversos referencian otra transacción (RN-41)
  CONSTRAINT ck_tx_reverso_referencia
    CHECK ((tipo_codigo = 'REVERSO') = (transaccion_reversada_id IS NOT NULL)),
  CONSTRAINT ck_tx_no_se_reversa_a_si_misma
    CHECK (transaccion_reversada_id IS NULL OR transaccion_reversada_id <> transaccion_id),
  -- Contabilizada exige fecha de contabilización y fecha contable
  CONSTRAINT ck_tx_posted_con_fechas
    CHECK (estado_codigo <> 'POSTED' OR (fecha_contabilizacion IS NOT NULL AND fecha_contable IS NOT NULL)),
  -- Y al revés: rechazada o pendiente no tiene fechas contables (G2, hallazgo H-07)
  CONSTRAINT ck_tx_fechas_solo_posted
    CHECK (estado_codigo = 'POSTED' OR (fecha_contabilizacion IS NULL AND fecha_contable IS NULL)),
  -- Rechazada exige motivo (RN-45)
  CONSTRAINT ck_tx_rechazo_con_motivo
    CHECK (estado_codigo <> 'REJECTED' OR motivo_rechazo IS NOT NULL),
  -- Solo los ajustes pueden quedar pendientes de aprobación
  CONSTRAINT ck_tx_pendiente_solo_ajuste
    CHECK (estado_codigo <> 'PENDING_APPROVAL' OR tipo_codigo = 'AJUSTE'),
  -- Ajuste contabilizado requiere aprobador distinto del creador (RN-44)
  CONSTRAINT ck_tx_ajuste_aprobado
    CHECK (NOT (tipo_codigo = 'AJUSTE' AND estado_codigo = 'POSTED') OR aprobado_por IS NOT NULL),
  CONSTRAINT ck_tx_aprobador_distinto
    CHECK (aprobado_por IS NULL OR aprobado_por <> creado_por),
  -- Solo los ajustes llevan aprobador (G2, hallazgo H-08)
  CONSTRAINT ck_tx_aprobador_solo_ajuste
    CHECK (aprobado_por IS NULL OR tipo_codigo = 'AJUSTE')
);
COMMENT ON TABLE fin.transaccion_financiera IS 'Movimientos de dinero. POSTED es inmutable (RN-40, se protege con triggers en G3). Los errores se corrigen con REVERSO (RN-41).';
COMMENT ON COLUMN fin.transaccion_financiera.idempotency_key IS 'Identificador único de la solicitud: una solicitud repetida no genera un segundo movimiento (RN-38).';
COMMENT ON COLUMN fin.transaccion_financiera.hash_solicitud IS 'Huella del contenido de la solicitud para detectar reutilización de la clave con otros datos.';

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

-- =====================================================================
-- 10. AUDITORÍA
-- =====================================================================

CREATE TABLE aud.log_auditoria (
  auditoria_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ocurrido_en      timestamptz  NOT NULL DEFAULT clock_timestamp(),
  usuario_id       bigint       REFERENCES seg.usuario (usuario_id),
  usuario_bd       text         NOT NULL DEFAULT session_user,
  esquema          varchar(63)  NOT NULL,
  tabla            varchar(63)  NOT NULL,
  registro         jsonb        NOT NULL,
  operacion        varchar(8)   NOT NULL CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
  valores_antes    jsonb,
  valores_despues  jsonb,
  CONSTRAINT ck_auditoria_imagenes CHECK (
       (operacion = 'INSERT' AND valores_antes IS NULL     AND valores_despues IS NOT NULL)
    OR (operacion = 'UPDATE' AND valores_antes IS NOT NULL AND valores_despues IS NOT NULL)
    OR (operacion = 'DELETE' AND valores_antes IS NOT NULL AND valores_despues IS NULL)
  )
);
COMMENT ON TABLE aud.log_auditoria IS 'Quién, qué, cuándo, sobre qué registro y valores antes/después de operaciones críticas (RN-52). Solo inserción (RN-53, se protege en G3).';
COMMENT ON COLUMN aud.log_auditoria.registro IS 'Clave primaria del registro afectado, por ejemplo {"cuenta_id": 125}.';

COMMIT;

-- =====================================================================
-- REGLAS QUE ESTAS TABLAS NO PUEDEN GARANTIZAR SOLAS
-- Requieren funciones, triggers o pruebas de calidad (G3 y G6), porque
-- dependen de otras tablas, del orden en el tiempo o de la concurrencia:
--
--   RN-02  (mínimo)  todo cliente tiene su subtipo
--   RN-08            titular natural mayor de 18 años a la fecha de apertura
--   RN-09            no eliminar clientes (privilegios / trigger)
--   RN-13  (mínimo)  toda cuenta no cerrada tiene un titular principal
--   RN-14, RN-15     tipo de cliente permitido por producto
--   RN-16            máximo de titulares por producto
--   RN-17            solo CORRIENTE con cupo de sobregiro
--   RN-22            la moneda de la cuenta no cambia
--   RN-23, RN-25     primer evento CREACION; estado actual = último evento
--   RN-28, RN-51     permisos por rol al ejecutar operaciones
--   RN-30  (decimales) numeric(18,2) REDONDEA 10.555 a 10.56 sin error:
--                    la función de operación debe rechazar más de 2 decimales
--   RN-31            fondos suficientes (con bloqueo de fila)
--   RN-33            transferencias solo entre cuentas de la misma moneda
--   RN-34, RN-35     débitos solo desde ACTIVA; créditos solo a ACTIVA o BLOQUEADA
--   RN-36, RN-37     periodo válido de la cuenta y límite diario
--   RN-39            atomicidad de la transferencia (una sola transacción SQL)
--   RN-40, RN-53     inmutabilidad de POSTED y de la auditoría (triggers)
--   RN-41, RN-43     reverso con mismo monto, cuentas invertidas y mismas reglas
--   RN-45 (asientos) una transacción REJECTED no tiene asientos
--   RN-46, RN-47     al menos un débito y un crédito, y Σ D = Σ C (trigger diferido)
--   RN-48            saldo almacenado = saldo según asientos (prueba G6)
--   RN-52            registro de auditoría (triggers)
--   RN-54            usuario que opera cuentas propias
-- =====================================================================
