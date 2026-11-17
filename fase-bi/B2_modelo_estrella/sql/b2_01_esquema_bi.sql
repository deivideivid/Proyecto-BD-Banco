-- =====================================================================
-- B2 · Modelo estrella del Banco Andino (esquema bi)
-- Creamos el esquema bi con 6 dimensiones, 3 hechos y el procedimiento
-- bi.cargar_bi() que los llena desde las tablas del banco (ref, core, fin, aud).
-- Lo corremos desde la raíz del repositorio. Se puede correr varias veces:
-- borra y vuelve a crear solo el esquema bi; no toca las tablas del banco.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

DROP SCHEMA IF EXISTS bi CASCADE;
CREATE SCHEMA bi;
COMMENT ON SCHEMA bi IS 'Modelo estrella para Power BI y la sección Estadísticas del aplicativo (fase BI).';

-- ---------------------------------------------------------------------
-- Dimensiones
-- ---------------------------------------------------------------------
CREATE TABLE bi.dim_fecha (
  fecha_key      integer PRIMARY KEY,            -- AAAAMMDD
  fecha          date    NOT NULL UNIQUE,
  anio           smallint NOT NULL,
  trimestre      smallint NOT NULL,
  mes            smallint NOT NULL,
  nombre_mes     varchar(12) NOT NULL,
  anio_mes       char(7) NOT NULL,               -- 2026-08
  dia            smallint NOT NULL,
  dia_semana     smallint NOT NULL,              -- 1 = lunes … 7 = domingo
  nombre_dia     varchar(10) NOT NULL,
  es_fin_semana  boolean NOT NULL,
  es_quincena    boolean NOT NULL                -- días 15, 30 y último del mes
);
COMMENT ON TABLE bi.dim_fecha IS 'Calendario de la ventana de datos (una fila por día).';

CREATE TABLE bi.dim_oficina (
  oficina_key    integer PRIMARY KEY,            -- = ref.oficina.oficina_id
  codigo         varchar(10) NOT NULL,
  oficina        varchar(100) NOT NULL,
  municipio      varchar(80) NOT NULL,
  departamento   varchar(80) NOT NULL,
  activa         boolean NOT NULL
);

CREATE TABLE bi.dim_producto (
  producto_key   varchar(20) PRIMARY KEY,        -- = core.producto.producto_codigo
  producto       varchar(80) NOT NULL,
  permite_sobregiro boolean NOT NULL
);

CREATE TABLE bi.dim_tipo_transaccion (
  tipo_key       varchar(20) PRIMARY KEY,        -- = ref.tipo_transaccion.codigo
  tipo           varchar(60) NOT NULL,
  sentido        varchar(12) NOT NULL            -- ENTRADA, SALIDA, MOVIMIENTO o CORRECCION
);

CREATE TABLE bi.dim_cliente (
  cliente_key    bigint PRIMARY KEY,             -- = core.cliente.cliente_id
  tipo_cliente   varchar(10) NOT NULL,
  cliente        varchar(250) NOT NULL,          -- nombre o razón social (sintético)
  estado_cliente varchar(15) NOT NULL,
  municipio      varchar(80) NOT NULL,
  departamento   varchar(80) NOT NULL,
  fecha_vinculacion date NOT NULL,
  anio_vinculacion smallint NOT NULL
);

CREATE TABLE bi.dim_cuenta (
  cuenta_key     bigint PRIMARY KEY,             -- = core.cuenta.cuenta_id
  numero_cuenta  char(11) NOT NULL,
  producto_key   varchar(20) NOT NULL REFERENCES bi.dim_producto,
  moneda         char(3) NOT NULL,
  oficina_key    integer NOT NULL REFERENCES bi.dim_oficina,
  cliente_key    bigint NOT NULL REFERENCES bi.dim_cliente,   -- titular principal (el vigente o el último)
  estado_cuenta  varchar(15) NOT NULL,
  fecha_apertura date NOT NULL,
  anio_apertura  smallint NOT NULL
);
COMMENT ON COLUMN bi.dim_cuenta.cliente_key IS 'Titular principal vigente; si la cuenta ya no tiene uno vigente (por ejemplo, cerrada), el último que tuvo.';

-- ---------------------------------------------------------------------
-- Hechos
-- ---------------------------------------------------------------------
-- Grano: una transacción financiera (contabilizada, rechazada o pendiente).
CREATE TABLE bi.fact_transaccion (
  transaccion_id     bigint PRIMARY KEY,
  fecha_key          integer NOT NULL REFERENCES bi.dim_fecha,
  hora               smallint NOT NULL,
  tipo_key           varchar(20) NOT NULL REFERENCES bi.dim_tipo_transaccion,
  estado             varchar(20) NOT NULL,        -- POSTED, REJECTED, PENDING_APPROVAL
  cuenta_key         bigint NOT NULL REFERENCES bi.dim_cuenta,   -- cuenta principal: origen si hay, si no destino
  cuenta_destino_key bigint REFERENCES bi.dim_cuenta,            -- solo transferencias y reversos con destino
  cliente_key        bigint NOT NULL REFERENCES bi.dim_cliente,
  oficina_key        integer NOT NULL REFERENCES bi.dim_oficina,
  producto_key       varchar(20) NOT NULL REFERENCES bi.dim_producto,
  moneda             char(3) NOT NULL,
  monto              numeric(18,2) NOT NULL,
  motivo_rechazo     varchar(200)
);
COMMENT ON TABLE bi.fact_transaccion IS 'Una fila por transacción. fecha_key usa la fecha contable si está contabilizada y la fecha de solicitud si no.';

-- Grano: una cuenta en la fecha de corte (foto del saldo).
CREATE TABLE bi.fact_saldo_cuenta (
  cuenta_key        bigint PRIMARY KEY REFERENCES bi.dim_cuenta,
  fecha_corte_key   integer NOT NULL REFERENCES bi.dim_fecha,
  cliente_key       bigint NOT NULL REFERENCES bi.dim_cliente,
  oficina_key       integer NOT NULL REFERENCES bi.dim_oficina,
  producto_key      varchar(20) NOT NULL REFERENCES bi.dim_producto,
  moneda            char(3) NOT NULL,
  estado_cuenta     varchar(15) NOT NULL,
  saldo_contable    numeric(18,2) NOT NULL,
  saldo_disponible  numeric(18,2) NOT NULL,
  cupo_sobregiro    numeric(18,2) NOT NULL,
  limite_retiro_diario numeric(18,2) NOT NULL,
  en_sobregiro      boolean NOT NULL
);
COMMENT ON TABLE bi.fact_saldo_cuenta IS 'Foto de cada cuenta al corte (la fecha contable más reciente). No se suma entre fechas.';

-- Grano: un control de cuadre o calidad en la fecha de carga.
CREATE TABLE bi.fact_control (
  control_id   varchar(10) PRIMARY KEY,
  grupo        varchar(30) NOT NULL,            -- Cuadre, Reconciliación, Auditoría, Calidad
  control      varchar(200) NOT NULL,
  esperado     varchar(40) NOT NULL,
  obtenido     numeric NOT NULL,
  resultado    varchar(10)
);

-- Resultado de las 76 pruebas del quality gate de G6 (se carga desde evidence/g6_quality_results.csv).
CREATE TABLE bi.calidad_prueba (
  test_id    varchar(10) PRIMARY KEY,
  categoria  varchar(40) NOT NULL,
  dimension  varchar(30) NOT NULL,
  regla      text NOT NULL,
  tabla      text,
  esperado   text,
  obtenido   text,
  severidad  varchar(10) NOT NULL,
  resultado  varchar(10) NOT NULL,
  detalle    text
);

-- Bitácora de cargas del modelo estrella.
CREATE TABLE bi.carga (
  carga_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  inicio      timestamptz NOT NULL,
  fin         timestamptz,
  fecha_corte date,
  filas_fact_transaccion bigint,
  filas_fact_saldo bigint
);

-- Puntaje del quality gate con la misma fórmula de G6 (peso por severidad).
CREATE VIEW bi.v_calidad_puntaje AS
SELECT coalesce(dimension, 'OVERALL') AS dimension,
       count(*) AS pruebas,
       count(*) FILTER (WHERE resultado = 'PASS') AS pass,
       count(*) FILTER (WHERE resultado = 'WARNING') AS warning,
       count(*) FILTER (WHERE resultado = 'FAIL') AS fail,
       round(100.0 * sum(w * v) / sum(w), 1) AS puntaje
FROM (SELECT dimension, resultado,
             CASE severidad WHEN 'CRITICA' THEN 4 WHEN 'ALTA' THEN 3 WHEN 'MEDIA' THEN 2 ELSE 1 END AS w,
             CASE resultado WHEN 'PASS' THEN 1 WHEN 'WARNING' THEN 0.5 ELSE 0 END AS v
      FROM bi.calidad_prueba) s
GROUP BY ROLLUP (dimension);

-- ---------------------------------------------------------------------
-- Procedimiento de carga
-- ---------------------------------------------------------------------
CREATE PROCEDURE bi.cargar_bi()
LANGUAGE plpgsql AS $$
DECLARE
  v_carga integer;
  v_corte date;
  v_desde date;
  v_hasta date;
BEGIN
  INSERT INTO bi.carga (inicio) VALUES (clock_timestamp()) RETURNING carga_id INTO v_carga;

  TRUNCATE bi.fact_transaccion, bi.fact_saldo_cuenta, bi.fact_control,
           bi.dim_cuenta, bi.dim_cliente, bi.dim_tipo_transaccion,
           bi.dim_producto, bi.dim_oficina, bi.dim_fecha;

  SELECT max(fecha_contable) INTO v_corte FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED';
  SELECT least(min(coalesce(fecha_contable, fecha_solicitud::date)), (SELECT min(fecha_apertura::date) FROM core.cuenta)),
         greatest(max(coalesce(fecha_contable, fecha_solicitud::date)), v_corte)
    INTO v_desde, v_hasta
  FROM fin.transaccion_financiera;

  -- Calendario
  INSERT INTO bi.dim_fecha
  SELECT to_char(d, 'YYYYMMDD')::integer, d,
         extract(year FROM d), extract(quarter FROM d), extract(month FROM d),
         (ARRAY['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'])[extract(month FROM d)],
         to_char(d, 'YYYY-MM'), extract(day FROM d), extract(isodow FROM d),
         (ARRAY['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'])[extract(isodow FROM d)],
         extract(isodow FROM d) IN (6, 7),
         extract(day FROM d) IN (15, 30) OR d = (date_trunc('month', d) + interval '1 month - 1 day')::date
  FROM generate_series(v_desde, v_hasta, interval '1 day') AS g(t), LATERAL (SELECT t::date AS d) x;

  INSERT INTO bi.dim_oficina
  SELECT o.oficina_id, o.codigo, o.nombre, m.nombre, d.nombre, o.activa
  FROM ref.oficina o
  JOIN ref.municipio m ON m.municipio_codigo = o.municipio_codigo
  JOIN ref.departamento d ON d.departamento_codigo = m.departamento_codigo;

  INSERT INTO bi.dim_producto
  SELECT producto_codigo, nombre, permite_sobregiro FROM core.producto;

  INSERT INTO bi.dim_tipo_transaccion
  SELECT codigo, nombre,
         CASE codigo WHEN 'CONSIGNACION' THEN 'ENTRADA' WHEN 'CREDITO' THEN 'ENTRADA'
                     WHEN 'RETIRO' THEN 'SALIDA' WHEN 'DEBITO' THEN 'SALIDA'
                     WHEN 'TRANSFERENCIA' THEN 'MOVIMIENTO' ELSE 'CORRECCION' END
  FROM ref.tipo_transaccion;

  INSERT INTO bi.dim_cliente
  SELECT c.cliente_id, c.tipo_cliente,
         coalesce(pn.nombres || ' ' || pn.apellidos, pj.razon_social),
         c.estado_cliente, m.nombre, d.nombre, c.fecha_vinculacion, extract(year FROM c.fecha_vinculacion)
  FROM core.cliente c
  JOIN ref.municipio m ON m.municipio_codigo = c.municipio_codigo
  JOIN ref.departamento d ON d.departamento_codigo = m.departamento_codigo
  LEFT JOIN core.persona_natural pn ON pn.cliente_id = c.cliente_id
  LEFT JOIN core.persona_juridica pj ON pj.cliente_id = c.cliente_id;

  INSERT INTO bi.dim_cuenta
  SELECT c.cuenta_id, c.numero_cuenta, c.producto_codigo, c.moneda_codigo, c.oficina_id,
         p.cliente_id, c.estado_cuenta, c.fecha_apertura::date, extract(year FROM c.fecha_apertura)
  FROM core.cuenta c
  JOIN LATERAL (
    SELECT t.cliente_id FROM core.titularidad_cuenta t
    WHERE t.cuenta_id = c.cuenta_id AND t.rol_titular = 'PRINCIPAL'
    ORDER BY (t.vigente_hasta IS NULL) DESC, t.vigente_desde DESC
    LIMIT 1) p ON true;

  INSERT INTO bi.fact_transaccion
  SELECT t.transaccion_id,
         to_char(coalesce(t.fecha_contable, t.fecha_solicitud::date), 'YYYYMMDD')::integer,
         extract(hour FROM coalesce(t.fecha_contabilizacion, t.fecha_solicitud)),
         t.tipo_codigo, t.estado_codigo,
         coalesce(t.cuenta_origen_id, t.cuenta_destino_id),
         CASE WHEN t.cuenta_origen_id IS NOT NULL THEN t.cuenta_destino_id END,
         dc.cliente_key, dc.oficina_key, dc.producto_key, dc.moneda,
         t.monto, t.motivo_rechazo
  FROM fin.transaccion_financiera t
  JOIN bi.dim_cuenta dc ON dc.cuenta_key = coalesce(t.cuenta_origen_id, t.cuenta_destino_id);

  INSERT INTO bi.fact_saldo_cuenta
  SELECT c.cuenta_id, to_char(v_corte, 'YYYYMMDD')::integer, dc.cliente_key, c.oficina_id,
         c.producto_codigo, c.moneda_codigo, c.estado_cuenta, c.saldo_contable, c.saldo_disponible,
         c.cupo_sobregiro, c.limite_retiro_diario, c.saldo_contable < 0
  FROM core.cuenta c
  JOIN bi.dim_cuenta dc ON dc.cuenta_key = c.cuenta_id;

  INSERT INTO bi.fact_control VALUES
    ('C01', 'Cuadre', 'Transacciones contabilizadas con débitos distintos de créditos', '0',
       (SELECT count(*) FROM fin.v_balance_transaccion WHERE NOT cuadrada), NULL),
    ('C02', 'Reconciliación', 'Cuentas con saldo distinto del ledger', '0',
       (SELECT count(*) FROM core.v_saldo_vs_ledger WHERE diferencia <> 0), NULL),
    ('C03', 'Reconciliación', 'Cuentas con estado distinto de su último evento', '0',
       (SELECT count(*) FROM core.v_estado_vs_eventos WHERE NOT coincide), NULL),
    ('C04', 'Auditoría', 'Cargas masivas registradas en la auditoría', '>= 15',
       (SELECT count(*) FROM aud.log_auditoria WHERE registro ? 'carga'), NULL),
    ('C05', 'Calidad', 'Pruebas del quality gate en FAIL crítico', '0',
       (SELECT count(*) FROM bi.calidad_prueba WHERE severidad = 'CRITICA' AND resultado = 'FAIL'), NULL),
    ('C06', 'Calidad', 'Puntaje general del quality gate', '>= 99',
       coalesce((SELECT puntaje FROM bi.v_calidad_puntaje WHERE dimension = 'OVERALL'), 0), NULL);
  UPDATE bi.fact_control SET resultado = CASE
    WHEN esperado = '0' THEN CASE WHEN obtenido = 0 THEN 'PASS' ELSE 'FAIL' END
    WHEN esperado LIKE '>=%' THEN CASE WHEN obtenido >= replace(esperado, '>= ', '')::numeric THEN 'PASS' ELSE 'FAIL' END
  END;

  UPDATE bi.carga SET fin = clock_timestamp(), fecha_corte = v_corte,
         filas_fact_transaccion = (SELECT count(*) FROM bi.fact_transaccion),
         filas_fact_saldo = (SELECT count(*) FROM bi.fact_saldo_cuenta)
  WHERE carga_id = v_carga;
END $$;
COMMENT ON PROCEDURE bi.cargar_bi() IS 'Llena el modelo estrella desde cero a partir de las tablas del banco.';

-- Índices para las uniones de Power BI y del aplicativo
CREATE INDEX ix_fact_tx_fecha    ON bi.fact_transaccion (fecha_key);
CREATE INDEX ix_fact_tx_cuenta   ON bi.fact_transaccion (cuenta_key);
CREATE INDEX ix_fact_tx_cliente  ON bi.fact_transaccion (cliente_key);
CREATE INDEX ix_fact_tx_oficina  ON bi.fact_transaccion (oficina_key);
CREATE INDEX ix_fact_saldo_cliente ON bi.fact_saldo_cuenta (cliente_key);

\echo 'Esquema bi creado.'
