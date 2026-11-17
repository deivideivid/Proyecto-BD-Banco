-- =====================================================================
-- 18_tests.sql · Banco Andino Colombia · Pruebas de G3
--
-- Todo corre dentro de UNA transacción que se deshace al final (ROLLBACK):
-- se puede ejecutar en una base vacía o en la base con el millón de datos
-- sin dejar rastro. Cada prueba negativa corre en su propio bloque; se
-- compara el código de error (SQLSTATE) obtenido con el esperado.
--
-- Resultado esperado: todas las filas en PASS.
-- Uso: se ejecuta desde run_all.sql, o solo:
--   psql -U postgres -d banco_andino_lab -f sql/18_tests.sql
-- =====================================================================

\set ON_ERROR_STOP on
\set QUIET on
BEGIN;
SET LOCAL client_min_messages = warning;

-- ---------------------------------------------------------------------
-- Utilidades de prueba (temporales: desaparecen al terminar)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_resultado (
  n           serial,
  prueba      text,
  descripcion text,
  esperado    text,
  obtenido    text,
  resultado   text
) ON COMMIT DROP;

CREATE TEMP TABLE t_ctx (clave text PRIMARY KEY, valor bigint) ON COMMIT DROP;

CREATE FUNCTION pg_temp.ctx(p_clave text) RETURNS bigint LANGUAGE sql AS
$$ SELECT valor FROM t_ctx WHERE clave = p_clave $$;

-- Ejecuta sentencias que DEBEN fallar con un SQLSTATE dado
CREATE PROCEDURE pg_temp.debe_fallar(p_prueba text, p_descripcion text, p_esperado text, VARIADIC p_sql text[])
LANGUAGE plpgsql AS $$
DECLARE
  s text;
BEGIN
  BEGIN
    FOREACH s IN ARRAY p_sql LOOP
      EXECUTE s;
    END LOOP;
    INSERT INTO t_resultado (prueba, descripcion, esperado, obtenido, resultado)
    VALUES (p_prueba, p_descripcion, 'error ' || p_esperado, 'se ejecutó sin error', 'FAIL');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t_resultado (prueba, descripcion, esperado, obtenido, resultado)
    VALUES (p_prueba, p_descripcion, 'error ' || p_esperado,
            SQLSTATE || ': ' || left(SQLERRM, 90),
            CASE WHEN SQLSTATE = p_esperado THEN 'PASS' ELSE 'FAIL' END);
  END;
END $$;

-- Registra una verificación positiva
CREATE FUNCTION pg_temp.verificar(p_prueba text, p_descripcion text, p_ok boolean, p_detalle text)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO t_resultado (prueba, descripcion, esperado, obtenido, resultado)
  VALUES (p_prueba, p_descripcion, 'verdadero', p_detalle, CASE WHEN p_ok THEN 'PASS' ELSE 'FAIL' END)
$$;

-- ---------------------------------------------------------------------
-- Datos de prueba (se deshacen con el ROLLBACK final)
-- ---------------------------------------------------------------------
INSERT INTO ref.departamento (departamento_codigo, nombre) VALUES ('17', 'Caldas') ON CONFLICT DO NOTHING;
INSERT INTO ref.municipio (municipio_codigo, departamento_codigo, nombre) VALUES ('17001', '17', 'Manizales') ON CONFLICT DO NOTHING;

DO $$
DECLARE
  v_oficina int; v_cajero bigint; v_super bigint; v_super2 bigint; v_cajero_titular bigint;
BEGIN
  INSERT INTO ref.oficina (codigo, nombre, municipio_codigo) VALUES ('TST-G3', 'Oficina de pruebas G3', '17001')
  RETURNING oficina_id INTO v_oficina;

  INSERT INTO seg.usuario (login, tipo_documento, numero_documento, nombres, apellidos, oficina_id)
  VALUES ('tst_cajero', 'CC', '99000001', 'Carla', 'Cajera', v_oficina) RETURNING usuario_id INTO v_cajero;
  INSERT INTO seg.usuario (login, tipo_documento, numero_documento, nombres, apellidos, oficina_id)
  VALUES ('tst_super', 'CC', '99000002', 'Sergio', 'Supervisor', v_oficina) RETURNING usuario_id INTO v_super;
  INSERT INTO seg.usuario (login, tipo_documento, numero_documento, nombres, apellidos, oficina_id)
  VALUES ('tst_super2', 'CC', '99000003', 'Sara', 'Supervisora', v_oficina) RETURNING usuario_id INTO v_super2;
  -- Cajero que además es cliente (para probar RN-54)
  INSERT INTO seg.usuario (login, tipo_documento, numero_documento, nombres, apellidos, oficina_id)
  VALUES ('tst_cajero_cliente', 'CC', '99000004', 'Tomás', 'Titular', v_oficina) RETURNING usuario_id INTO v_cajero_titular;

  INSERT INTO seg.usuario_rol (usuario_id, rol_id)
  SELECT u, (SELECT rol_id FROM seg.rol WHERE codigo = r)
  FROM (VALUES (v_cajero, 'CAJERO'), (v_super, 'SUPERVISOR'), (v_super2, 'SUPERVISOR'),
               (v_cajero_titular, 'CAJERO')) AS x(u, r);

  INSERT INTO t_ctx VALUES ('oficina', v_oficina), ('cajero', v_cajero), ('super', v_super),
                           ('super2', v_super2), ('cajero_titular', v_cajero_titular);
END $$;

DO $$
DECLARE
  cj bigint := pg_temp.ctx('cajero'); su bigint := pg_temp.ctx('super'); ofi int := pg_temp.ctx('oficina');
  v_ana bigint; v_beto bigint; v_menor bigint; v_emp bigint; v_tomas bigint;
  c_ana bigint; c_beto bigint; c_ana_usd bigint; c_emp bigint; c_nomina bigint; c_tomas bigint;
BEGIN
  v_ana   := core.fn_crear_cliente_natural(cj, 'CC', '1990000001', 'Ana', 'Prueba', DATE '1990-05-10', '17001');
  v_beto  := core.fn_crear_cliente_natural(cj, 'CC', '1990000002', 'Beto', 'Prueba', DATE '1985-01-20', '17001');
  v_menor := core.fn_crear_cliente_natural(cj, 'CC', '1990000003', 'Mateo', 'Menor', (current_date - INTERVAL '15 years')::date, '17001');
  v_emp   := core.fn_crear_cliente_juridico(cj, '900000001', 'Empresa de Pruebas SAS', DATE '2010-03-01', '6201', '17001');
  v_tomas := core.fn_crear_cliente_natural(cj, 'CC', '99000004', 'Tomás', 'Titular', DATE '1992-07-07', '17001');

  c_ana     := core.fn_abrir_cuenta(cj, v_ana,  'AHORROS', 'COP', ofi, 3000000);
  c_beto    := core.fn_abrir_cuenta(cj, v_beto, 'AHORROS', 'COP', ofi, 3000000);
  c_ana_usd := core.fn_abrir_cuenta(cj, v_ana,  'AHORROS', 'USD', ofi, 1000);
  c_emp     := core.fn_abrir_cuenta(cj, v_emp,  'EMPRESARIAL', 'COP', ofi, 50000000);
  c_nomina  := core.fn_abrir_cuenta(cj, v_beto, 'NOMINA', 'COP', ofi, 2000000);
  c_tomas   := core.fn_abrir_cuenta(cj, v_tomas, 'AHORROS', 'COP', ofi, 3000000);

  PERFORM core.fn_activar_cuenta(cj, x) FROM unnest(ARRAY[c_ana, c_beto, c_ana_usd, c_emp, c_nomina, c_tomas]) AS x;

  PERFORM fin.fn_consignar(cj, c_ana, 1000000, gen_random_uuid());
  PERFORM fin.fn_consignar(cj, c_ana_usd, 500, gen_random_uuid());
  PERFORM fin.fn_consignar(cj, c_tomas, 200000, gen_random_uuid());

  INSERT INTO t_ctx VALUES ('ana', v_ana), ('beto', v_beto), ('menor', v_menor), ('emp', v_emp), ('tomas', v_tomas),
    ('c_ana', c_ana), ('c_beto', c_beto), ('c_ana_usd', c_ana_usd), ('c_emp', c_emp), ('c_nomina', c_nomina), ('c_tomas', c_tomas);
END $$;

-- ---------------------------------------------------------------------
-- A. Las 7 pruebas mínimas del laboratorio
-- ---------------------------------------------------------------------
CALL pg_temp.debe_fallar('T01', 'Dos clientes con el mismo documento', '23505',
  format($q$SELECT core.fn_crear_cliente_natural(%s, 'CC', '1990000001', 'Otra', 'Persona', DATE '1980-01-01', '17001')$q$, pg_temp.ctx('cajero')));

CALL pg_temp.debe_fallar('T02', 'Crear cuenta con cliente inexistente', 'BA016',
  format($q$SELECT core.fn_abrir_cuenta(%s, -1, 'AHORROS', 'COP', %s, 3000000)$q$, pg_temp.ctx('cajero'), pg_temp.ctx('oficina')));

CALL pg_temp.debe_fallar('T03', 'Retiro superior al saldo sin sobregiro', 'BA003',
  format($q$SELECT fin.fn_retirar(%s, %s, 1500000, gen_random_uuid())$q$, pg_temp.ctx('cajero'), pg_temp.ctx('c_ana')));

CALL pg_temp.debe_fallar('T04', 'Transferir con origen = destino', 'BA006',
  format($q$SELECT fin.fn_transferir(%s, %s, %s, 1000, gen_random_uuid())$q$, pg_temp.ctx('cajero'), pg_temp.ctx('c_ana'), pg_temp.ctx('c_ana')));

CALL pg_temp.debe_fallar('T05a', 'Modificar el monto de una transacción POSTED', 'BA007',
  format($q$UPDATE fin.transaccion_financiera SET monto = 1 WHERE cuenta_destino_id = %s AND estado_codigo = 'POSTED'$q$, pg_temp.ctx('c_ana')));
CALL pg_temp.debe_fallar('T05b', 'Eliminar una transacción POSTED', 'BA007',
  format($q$DELETE FROM fin.transaccion_financiera WHERE cuenta_destino_id = %s$q$, pg_temp.ctx('c_ana')));
CALL pg_temp.debe_fallar('T05c', 'Modificar un asiento contable', 'BA007',
  format($q$UPDATE fin.asiento_contable SET valor = 1 WHERE cuenta_id = %s$q$, pg_temp.ctx('c_ana')));
CALL pg_temp.debe_fallar('T05d', 'Vaciar (TRUNCATE) los asientos', 'BA007',
  'SET CONSTRAINTS ALL IMMEDIATE',          -- TRUNCATE exige que no haya verificaciones diferidas pendientes
  'TRUNCATE fin.asiento_contable CASCADE');
SET CONSTRAINTS ALL DEFERRED;

-- T06: transferencia válida, atómica y cuadrada
DO $$
DECLARE
  cj bigint := pg_temp.ctx('cajero'); a bigint := pg_temp.ctx('c_ana'); b bigint := pg_temp.ctx('c_beto');
  v_tx bigint; sa0 numeric; sb0 numeric; sa1 numeric; sb1 numeric; v_lineas int; v_cuadra boolean;
BEGIN
  SELECT saldo_contable INTO sa0 FROM core.cuenta WHERE cuenta_id = a;
  SELECT saldo_contable INTO sb0 FROM core.cuenta WHERE cuenta_id = b;
  v_tx := fin.fn_transferir(cj, a, b, 250000, gen_random_uuid(), 'Prueba T06');
  SET CONSTRAINTS ALL IMMEDIATE;    -- fuerza ya la verificación diferida de doble partida
  SET CONSTRAINTS ALL DEFERRED;
  SELECT saldo_contable INTO sa1 FROM core.cuenta WHERE cuenta_id = a;
  SELECT saldo_contable INTO sb1 FROM core.cuenta WHERE cuenta_id = b;
  SELECT lineas, cuadrada INTO v_lineas, v_cuadra FROM fin.v_balance_transaccion WHERE transaccion_id = v_tx;
  PERFORM pg_temp.verificar('T06', 'Transferencia válida: débito y crédito juntos y cuadrados',
    sa1 = sa0 - 250000 AND sb1 = sb0 + 250000 AND v_lineas = 2 AND v_cuadra,
    format('origen %s→%s, destino %s→%s, %s líneas, cuadrada=%s', sa0, sa1, sb0, sb1, v_lineas, v_cuadra));
  INSERT INTO t_ctx VALUES ('tx_t06', v_tx);
END $$;

-- T07: reverso por operación compensatoria, conservando el histórico
DO $$
DECLARE
  su bigint := pg_temp.ctx('super'); a bigint := pg_temp.ctx('c_ana'); b bigint := pg_temp.ctx('c_beto');
  v_orig bigint := pg_temp.ctx('tx_t06'); v_rev bigint; o fin.transaccion_financiera%ROWTYPE;
  r fin.transaccion_financiera%ROWTYPE; sa numeric; sb numeric; v_espejo boolean;
BEGIN
  v_rev := fin.fn_reversar(su, v_orig, gen_random_uuid(), 'Prueba T07');
  SELECT * INTO o FROM fin.transaccion_financiera WHERE transaccion_id = v_orig;
  SELECT * INTO r FROM fin.transaccion_financiera WHERE transaccion_id = v_rev;
  SELECT saldo_contable INTO sa FROM core.cuenta WHERE cuenta_id = a;
  SELECT saldo_contable INTO sb FROM core.cuenta WHERE cuenta_id = b;
  SELECT NOT EXISTS (
           SELECT cuenta_contable_codigo, cuenta_id, CASE naturaleza WHEN 'D' THEN 'C' ELSE 'D' END, valor
           FROM fin.asiento_contable WHERE transaccion_id = v_orig
           EXCEPT
           SELECT cuenta_contable_codigo, cuenta_id, naturaleza::text, valor
           FROM fin.asiento_contable WHERE transaccion_id = v_rev)
  INTO v_espejo;
  PERFORM pg_temp.verificar('T07', 'Reverso: nueva transacción, original intacta, saldos restituidos',
    o.estado_codigo = 'POSTED' AND o.monto = 250000 AND r.tipo_codigo = 'REVERSO'
    AND r.transaccion_reversada_id = v_orig AND r.cuenta_origen_id = b AND r.cuenta_destino_id = a
    AND sa = 1000000 AND sb = 0 AND v_espejo,
    format('original %s sigue POSTED; reverso %s con cuentas invertidas; saldos %s / %s; asientos espejo=%s',
           v_orig, v_rev, sa, sb, v_espejo));
  INSERT INTO t_ctx VALUES ('tx_rev', v_rev);
END $$;

-- ---------------------------------------------------------------------
-- B. Reglas de transacciones (RN-30 a RN-45)
-- ---------------------------------------------------------------------
CALL pg_temp.debe_fallar('T08', 'Reversar dos veces la misma transacción (RN-42)', 'BA008',
  format('SELECT fin.fn_reversar(%s, %s, gen_random_uuid())', pg_temp.ctx('super'), pg_temp.ctx('tx_t06')));
CALL pg_temp.debe_fallar('T09', 'Reversar un reverso (RN-42)', 'BA008',
  format('SELECT fin.fn_reversar(%s, %s, gen_random_uuid())', pg_temp.ctx('super'), pg_temp.ctx('tx_rev')));
CALL pg_temp.debe_fallar('T10', 'Monto con 3 decimales (RN-30)', 'BA005',
  format('SELECT fin.fn_consignar(%s, %s, 10.555, gen_random_uuid())', pg_temp.ctx('cajero'), pg_temp.ctx('c_ana')));
CALL pg_temp.debe_fallar('T11', 'Monto cero (RN-30)', 'BA005',
  format('SELECT fin.fn_consignar(%s, %s, 0, gen_random_uuid())', pg_temp.ctx('cajero'), pg_temp.ctx('c_ana')));
CALL pg_temp.debe_fallar('T12', 'Transferir entre COP y USD (RN-33)', 'BA006',
  format('SELECT fin.fn_transferir(%s, %s, %s, 100, gen_random_uuid())', pg_temp.ctx('cajero'), pg_temp.ctx('c_ana'), pg_temp.ctx('c_ana_usd')));

-- Límite diario (RN-37): límite de la cuenta de Ana = 3.000.000
DO $$
BEGIN
  PERFORM fin.fn_consignar(pg_temp.ctx('cajero'), pg_temp.ctx('c_ana'), 5000000, gen_random_uuid());
  PERFORM fin.fn_retirar(pg_temp.ctx('cajero'), pg_temp.ctx('c_ana'), 2500000, gen_random_uuid());
END $$;
CALL pg_temp.debe_fallar('T13', 'Retiros del día por encima del límite diario (RN-37)', 'BA004',
  format('SELECT fin.fn_retirar(%s, %s, 600000, gen_random_uuid())', pg_temp.ctx('cajero'), pg_temp.ctx('c_ana')));

-- Idempotencia (RN-38)
DO $$
DECLARE
  k uuid := gen_random_uuid(); v1 bigint; v2 bigint; n int;
BEGIN
  v1 := fin.fn_consignar(pg_temp.ctx('cajero'), pg_temp.ctx('c_beto'), 70000, k);
  v2 := fin.fn_consignar(pg_temp.ctx('cajero'), pg_temp.ctx('c_beto'), 70000, k);
  SELECT count(*) INTO n FROM fin.transaccion_financiera WHERE idempotency_key = k;
  PERFORM pg_temp.verificar('T14', 'Misma solicitud dos veces: una sola transacción (RN-38)',
    v1 = v2 AND n = 1, format('primera %s, segunda %s, filas con la clave: %s', v1, v2, n));
  INSERT INTO t_ctx VALUES ('tx_idem', v1);
END $$;
CALL pg_temp.debe_fallar('T15', 'Misma clave con otro monto (RN-38)', 'BA015',
  format($q$SELECT fin.fn_consignar(%s, %s, 99999, (SELECT idempotency_key FROM fin.transaccion_financiera WHERE transaccion_id = %s))$q$,
         pg_temp.ctx('cajero'), pg_temp.ctx('c_beto'), pg_temp.ctx('tx_idem')));

-- Cuenta bloqueada (S1): recibe créditos, no origina débitos (RN-34, RN-35, RN-43)
DO $$
DECLARE
  v_tx bigint;
BEGIN
  PERFORM core.fn_bloquear_cuenta(pg_temp.ctx('cajero'), pg_temp.ctx('c_beto'), 'Prueba de bloqueo');
  v_tx := fin.fn_consignar(pg_temp.ctx('cajero'), pg_temp.ctx('c_beto'), 30000, gen_random_uuid());
  PERFORM pg_temp.verificar('T16', 'Cuenta BLOQUEADA recibe una consignación (S1, RN-35)', v_tx IS NOT NULL,
    format('consignación %s contabilizada', v_tx));
  INSERT INTO t_ctx VALUES ('tx_a_bloqueada', v_tx);
END $$;
CALL pg_temp.debe_fallar('T17', 'Retiro desde cuenta BLOQUEADA (S1, RN-34)', 'BA002',
  format('SELECT fin.fn_retirar(%s, %s, 1000, gen_random_uuid())', pg_temp.ctx('cajero'), pg_temp.ctx('c_beto')));
CALL pg_temp.debe_fallar('T18', 'Reversar una consignación hecha a cuenta ahora BLOQUEADA (RN-43)', 'BA002',
  format('SELECT fin.fn_reversar(%s, %s, gen_random_uuid())', pg_temp.ctx('super'), pg_temp.ctx('tx_a_bloqueada')));
CALL pg_temp.debe_fallar('T19', 'Cajero intenta desbloquear (RN-28)', 'BA001',
  format('SELECT core.fn_desbloquear_cuenta(%s, %s)', pg_temp.ctx('cajero'), pg_temp.ctx('c_beto')));
SELECT core.fn_desbloquear_cuenta(pg_temp.ctx('super'), pg_temp.ctx('c_beto')) AS evento_desbloqueo \gset

CALL pg_temp.debe_fallar('T20', 'Cajero intenta reversar (RN-51)', 'BA001',
  format('SELECT fin.fn_reversar(%s, %s, gen_random_uuid())', pg_temp.ctx('cajero'), pg_temp.ctx('tx_idem')));
CALL pg_temp.debe_fallar('T21', 'Usuario opera una cuenta de la que es titular (RN-54)', 'BA009',
  format('SELECT fin.fn_retirar(%s, %s, 1000, gen_random_uuid())', pg_temp.ctx('cajero_titular'), pg_temp.ctx('c_tomas')));

-- Ajustes con maker-checker (RN-44)
DO $$
DECLARE
  v_aj bigint;
BEGIN
  v_aj := fin.fn_crear_ajuste(pg_temp.ctx('super'), pg_temp.ctx('c_ana'), 12345.67, 'C', gen_random_uuid(), 'Ajuste de prueba');
  INSERT INTO t_ctx VALUES ('ajuste', v_aj);
END $$;
CALL pg_temp.debe_fallar('T22', 'El creador aprueba su propio ajuste (RN-44)', 'BA013',
  format('SELECT fin.fn_aprobar_ajuste(%s, %s)', pg_temp.ctx('super'), pg_temp.ctx('ajuste')));
DO $$
DECLARE
  t fin.transaccion_financiera%ROWTYPE;
BEGIN
  PERFORM fin.fn_aprobar_ajuste(pg_temp.ctx('super2'), pg_temp.ctx('ajuste'));
  SELECT * INTO t FROM fin.transaccion_financiera WHERE transaccion_id = pg_temp.ctx('ajuste');
  PERFORM pg_temp.verificar('T23', 'Ajuste aprobado por otro supervisor queda POSTED con asientos',
    t.estado_codigo = 'POSTED' AND t.aprobado_por = pg_temp.ctx('super2')
    AND (SELECT count(*) FROM fin.asiento_contable WHERE transaccion_id = t.transaccion_id) = 2,
    format('estado %s, aprobado por %s', t.estado_codigo, t.aprobado_por));
END $$;

-- Rechazo registrado (RN-45)
DO $$
DECLARE
  v_rj bigint;
BEGIN
  v_rj := fin.fn_registrar_rechazo(pg_temp.ctx('cajero'), 'RETIRO', pg_temp.ctx('c_beto'), NULL, 9999999, gen_random_uuid(), 'Fondos insuficientes');
  PERFORM pg_temp.verificar('T24', 'Rechazo registrado con motivo, sin asientos ni efecto en saldo (RN-45)',
    (SELECT estado_codigo = 'REJECTED' AND motivo_rechazo IS NOT NULL FROM fin.transaccion_financiera WHERE transaccion_id = v_rj)
    AND NOT EXISTS (SELECT 1 FROM fin.asiento_contable WHERE transaccion_id = v_rj),
    format('transacción %s REJECTED sin asientos', v_rj));
END $$;

-- ---------------------------------------------------------------------
-- C. Doble partida (RN-46, RN-47): insertar a mano una transacción descuadrada
-- ---------------------------------------------------------------------
CALL pg_temp.debe_fallar('T25', 'Transacción POSTED con un solo asiento (RN-46, RN-47)', 'BA014',
  format($q$INSERT INTO fin.transaccion_financiera (transaccion_id, tipo_codigo, estado_codigo, cuenta_destino_id, monto, idempotency_key,
            fecha_contabilizacion, fecha_contable, creado_por)
          VALUES (-25, 'CONSIGNACION', 'POSTED', %s, 100, gen_random_uuid(), now(), current_date, %s)$q$,
         pg_temp.ctx('c_ana'), pg_temp.ctx('cajero')),
  format($q$INSERT INTO fin.asiento_contable (transaccion_id, linea, cuenta_contable_codigo, cuenta_id, naturaleza, valor)
          VALUES (-25, 1, 'ACT_CAJA', NULL, 'D', 100)$q$),
  'SET CONSTRAINTS ALL IMMEDIATE');
SET CONSTRAINTS ALL DEFERRED;

CALL pg_temp.debe_fallar('T26', 'Asiento con cuenta contable que no corresponde al producto (G2, H-03)', 'BA014',
  format($q$INSERT INTO fin.transaccion_financiera (transaccion_id, tipo_codigo, estado_codigo, cuenta_destino_id, monto, idempotency_key,
            fecha_contabilizacion, fecha_contable, creado_por)
          VALUES (-26, 'CONSIGNACION', 'POSTED', %s, 100, gen_random_uuid(), now(), current_date, %s)$q$,
         pg_temp.ctx('c_ana'), pg_temp.ctx('cajero')),
  format($q$INSERT INTO fin.asiento_contable (transaccion_id, linea, cuenta_contable_codigo, cuenta_id, naturaleza, valor)
          VALUES (-26, 1, 'ACT_CAJA', NULL, 'D', 100), (-26, 2, 'PAS_DEP_CORRIENTE', %s, 'C', 100)$q$, pg_temp.ctx('c_ana')));
SET CONSTRAINTS ALL DEFERRED;

-- ---------------------------------------------------------------------
-- D. Clientes, titularidad y ciclo de vida (RN-02, RN-08, RN-14 a RN-27)
-- ---------------------------------------------------------------------
CALL pg_temp.debe_fallar('T27', 'Cliente sin subtipo (RN-02)', 'BA017',
  $q$INSERT INTO core.cliente (tipo_cliente, tipo_documento, numero_documento, municipio_codigo, fecha_vinculacion)
     VALUES ('NATURAL', 'CC', '1990000099', '17001', current_date)$q$,
  'SET CONSTRAINTS ALL IMMEDIATE');
SET CONSTRAINTS ALL DEFERRED;
CALL pg_temp.debe_fallar('T28', 'Titular menor de 18 años (RN-08, S2)', 'BA010',
  format($q$SELECT core.fn_abrir_cuenta(%s, %s, 'AHORROS', 'COP', %s, 3000000)$q$, pg_temp.ctx('cajero'), pg_temp.ctx('menor'), pg_temp.ctx('oficina')));
CALL pg_temp.debe_fallar('T29', 'Cuenta EMPRESARIAL para persona natural (RN-15, S4)', 'BA010',
  format($q$SELECT core.fn_abrir_cuenta(%s, %s, 'EMPRESARIAL', 'COP', %s, 3000000)$q$, pg_temp.ctx('cajero'), pg_temp.ctx('ana'), pg_temp.ctx('oficina')));
CALL pg_temp.debe_fallar('T30', 'Segundo titular en cuenta NOMINA (máximo 1, RN-16, S3)', 'BA010',
  format('SELECT core.fn_agregar_titular(%s, %s, %s)', pg_temp.ctx('cajero'), pg_temp.ctx('c_nomina'), pg_temp.ctx('ana')));
CALL pg_temp.debe_fallar('T31', 'Cupo de sobregiro en cuenta de AHORROS (RN-17)', 'BA017',
  format($q$SELECT core.fn_abrir_cuenta(%s, %s, 'AHORROS', 'COP', %s, 3000000, 500000)$q$, pg_temp.ctx('cajero'), pg_temp.ctx('ana'), pg_temp.ctx('oficina')));
CALL pg_temp.debe_fallar('T32', 'Cambiar la moneda de una cuenta (RN-22)', 'BA017',
  format($q$UPDATE core.cuenta SET moneda_codigo = 'USD' WHERE cuenta_id = %s$q$, pg_temp.ctx('c_beto')));
CALL pg_temp.debe_fallar('T33', 'Cambiar el estado sin registrar evento (RN-25)', 'BA011',
  format($q$UPDATE core.cuenta SET estado_cuenta = 'INACTIVA' WHERE cuenta_id = %s$q$, pg_temp.ctx('c_beto')));
CALL pg_temp.debe_fallar('T34', 'Evento con transición no permitida (RN-24)', 'BA011',
  format($q$SELECT core.fn_registrar_evento(%s, %s, 'ACTIVACION', 'ACTIVA')$q$, pg_temp.ctx('super'), pg_temp.ctx('c_beto')));
CALL pg_temp.debe_fallar('T35', 'Cerrar una cuenta con saldo (RN-20)', 'BA012',
  format('SELECT core.fn_cerrar_cuenta(%s, %s)', pg_temp.ctx('super'), pg_temp.ctx('c_ana')));
CALL pg_temp.debe_fallar('T36', 'Borrar un cliente (RN-09)', 'BA007',
  format('DELETE FROM core.cliente WHERE cliente_id = %s', pg_temp.ctx('ana')));

-- Cambio de límite y cierre válido
DO $$
DECLARE
  v_lim numeric; v_estado text; v_cierre timestamptz; v_ok_evento boolean;
BEGIN
  PERFORM core.fn_cambiar_limite(pg_temp.ctx('super'), pg_temp.ctx('c_nomina'), 1500000);
  SELECT limite_retiro_diario INTO v_lim FROM core.cuenta WHERE cuenta_id = pg_temp.ctx('c_nomina');
  PERFORM core.fn_cerrar_cuenta(pg_temp.ctx('super'), pg_temp.ctx('c_nomina'));
  SELECT estado_cuenta, fecha_cierre INTO v_estado, v_cierre FROM core.cuenta WHERE cuenta_id = pg_temp.ctx('c_nomina');
  SELECT coincide INTO v_ok_evento FROM core.v_estado_vs_eventos WHERE cuenta_id = pg_temp.ctx('c_nomina');
  PERFORM pg_temp.verificar('T37', 'Cambio de límite y cierre actualizan la cuenta a través de eventos (RN-25, RN-27)',
    v_lim = 1500000 AND v_estado = 'CERRADA' AND v_cierre IS NOT NULL AND v_ok_evento,
    format('límite %s, estado %s, estado = último evento: %s', v_lim, v_estado, v_ok_evento));
END $$;
CALL pg_temp.debe_fallar('T38', 'Consignar en una cuenta CERRADA (RN-35)', 'BA002',
  format('SELECT fin.fn_consignar(%s, %s, 1000, gen_random_uuid())', pg_temp.ctx('cajero'), pg_temp.ctx('c_nomina')));

-- ---------------------------------------------------------------------
-- E. Auditoría (RN-52, RN-53)
-- ---------------------------------------------------------------------
DO $$
DECLARE
  n int; v_usuario bigint;
BEGIN
  SELECT count(*), max(usuario_id) INTO n, v_usuario
  FROM aud.log_auditoria
  WHERE tabla = 'transaccion_financiera' AND operacion = 'INSERT'
    AND registro = jsonb_build_object('transaccion_id', pg_temp.ctx('tx_t06'));
  PERFORM pg_temp.verificar('T39', 'La transferencia quedó auditada con usuario, registro y valores (RN-52)',
    n = 1 AND v_usuario = pg_temp.ctx('cajero'), format('%s registro(s) de auditoría, usuario %s', n, v_usuario));
END $$;
CALL pg_temp.debe_fallar('T40', 'Modificar un registro de auditoría (RN-53)', 'BA007',
  'UPDATE aud.log_auditoria SET usuario_bd = ''otro''');
CALL pg_temp.debe_fallar('T41', 'Borrar registros de auditoría (RN-53)', 'BA007',
  'DELETE FROM aud.log_auditoria');

-- ---------------------------------------------------------------------
-- F. Mínimo privilegio (roles de base de datos, 17_roles_permissions.sql)
-- ---------------------------------------------------------------------
CALL pg_temp.debe_fallar('T42', 'Rol banco_cajero no puede hacer UPDATE directo a transacciones', '42501',
  'SET LOCAL ROLE banco_cajero',
  'UPDATE fin.transaccion_financiera SET descripcion = ''x'' WHERE false');
CALL pg_temp.debe_fallar('T43', 'Rol banco_cajero no puede ejecutar fn_reversar', '42501',
  'SET LOCAL ROLE banco_cajero',
  format('SELECT fin.fn_reversar(%s, %s, gen_random_uuid())', pg_temp.ctx('super'), pg_temp.ctx('tx_idem')));
CALL pg_temp.debe_fallar('T44', 'Rol banco_consulta no puede leer la auditoría', '42501',
  'SET LOCAL ROLE banco_consulta',
  'SELECT count(*) FROM aud.log_auditoria');
DO $$
DECLARE
  v_tx bigint; v_cajero bigint := pg_temp.ctx('cajero'); v_cuenta bigint := pg_temp.ctx('c_ana');
BEGIN
  SET LOCAL ROLE banco_cajero;    -- desde aquí la sesión solo tiene los permisos del rol
  v_tx := fin.fn_consignar(v_cajero, v_cuenta, 1000, gen_random_uuid());
  RESET ROLE;
  PERFORM pg_temp.verificar('T45', 'Rol banco_cajero sí consigna a través de la función', v_tx IS NOT NULL,
    format('consignación %s como banco_cajero', v_tx));
END $$;
RESET ROLE;

-- ---------------------------------------------------------------------
-- G. Integridad final de los datos de prueba
-- ---------------------------------------------------------------------
SET CONSTRAINTS ALL IMMEDIATE;   -- dispara ya todas las verificaciones diferidas
DO $$
DECLARE
  v_desc int; v_dif int; v_est int;
BEGIN
  -- Solo las cuentas y transacciones creadas por estas pruebas (la base puede tener el millón cargado)
  SELECT count(*) INTO v_desc FROM fin.v_balance_transaccion b
  WHERE NOT b.cuadrada AND b.transaccion_id IN (
    SELECT transaccion_id FROM fin.transaccion_financiera
    WHERE cuenta_origen_id IN (SELECT valor FROM t_ctx WHERE clave LIKE 'c\_%')
       OR cuenta_destino_id IN (SELECT valor FROM t_ctx WHERE clave LIKE 'c\_%'));
  SELECT count(*) INTO v_dif FROM core.v_saldo_vs_ledger
  WHERE diferencia <> 0 AND cuenta_id IN (SELECT valor FROM t_ctx WHERE clave LIKE 'c\_%');
  SELECT count(*) INTO v_est FROM core.v_estado_vs_eventos
  WHERE NOT coincide AND cuenta_id IN (SELECT valor FROM t_ctx WHERE clave LIKE 'c\_%');
  PERFORM pg_temp.verificar('T46', 'Todas las transacciones cuadran; saldo = ledger; estado = último evento (RN-47, RN-48, RN-25)',
    v_desc = 0 AND v_dif = 0 AND v_est = 0,
    format('descuadradas %s, cuentas con diferencia %s, estados distintos %s', v_desc, v_dif, v_est));
END $$;

\echo '== Resultado de las pruebas de G3'
SELECT prueba, descripcion, esperado, obtenido, resultado FROM t_resultado ORDER BY n;
SELECT count(*) FILTER (WHERE resultado = 'PASS') AS pass,
       count(*) FILTER (WHERE resultado = 'FAIL') AS fail,
       CASE WHEN count(*) FILTER (WHERE resultado = 'FAIL') = 0 THEN 'G3 PRUEBAS = PASS' ELSE 'G3 PRUEBAS = FAIL' END AS veredicto
FROM t_resultado;

ROLLBACK;
