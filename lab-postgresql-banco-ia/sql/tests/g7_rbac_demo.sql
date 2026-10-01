-- =====================================================================
-- g7_rbac_demo.sql · Banco Andino Colombia · G7 (seguridad)
-- Demuestra el mínimo privilegio con usuarios reales de cada rol:
-- accesos permitidos y denegados, en dos niveles:
--   1. Base de datos (GRANT/REVOKE de sql/17_roles_permissions.sql)
--   2. Aplicación (seg.fn_exigir_permiso dentro de cada función, BA001)
--
-- No deja cambios: cada acción permitida se deshace al terminar
-- (subtransacción) y los usuarios de prueba se borran al final.
-- Los usuarios de prueba son NOLOGIN (no hay contraseñas en el repositorio);
-- se usan con SET ROLE, igual que una conexión que entrara con ese usuario.
--
-- Uso (desde la carpeta lab-postgresql-banco-ia, como postgres):
--   psql -U postgres -d banco_andino_lab -f sql/tests/g7_rbac_demo.sql
--   SQL Shell: \c banco_andino_lab   \i sql/tests/g7_rbac_demo.sql
-- Resultado esperado: G7 RBAC = PASS (todas las pruebas como se esperaba).
-- =====================================================================

\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';   -- SQL Shell de Windows no usa UTF-8 por defecto: sin esto las tildes se dañan
\set QUIET on
SET client_min_messages = warning;
\pset footer off

-- 1. Usuarios de prueba: uno por rol de base de datos + uno sin rol
DO $$
DECLARE r text[];
BEGIN
  FOREACH r SLICE 1 IN ARRAY ARRAY[
      ['demo_consulta',  'banco_consulta'],
      ['demo_cajero',    'banco_cajero'],
      ['demo_supervisor','banco_supervisor'],
      ['demo_auditor',   'banco_auditor'],
      ['demo_admin_seg', 'banco_admin_seg'],
      ['demo_sin_rol',   NULL]] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r[1]) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', r[1]);
    END IF;
    IF r[2] IS NOT NULL THEN
      EXECUTE format('GRANT %I TO %I', r[2], r[1]);
    END IF;
  END LOOP;
END $$;

-- 2. Datos para las pruebas (se leen como postgres, antes de cambiar de rol)
SELECT min(u.usuario_id) FILTER (WHERE r.codigo = 'CAJERO')     AS cajero,
       min(u.usuario_id) FILTER (WHERE r.codigo = 'SUPERVISOR') AS supervisor
FROM seg.usuario u
JOIN seg.usuario_rol ur ON ur.usuario_id = u.usuario_id AND ur.vigente_hasta IS NULL
JOIN seg.rol r ON r.rol_id = ur.rol_id
WHERE u.estado = 'ACTIVO' \gset
SELECT min(cuenta_id) AS cuenta FROM core.cuenta
WHERE estado_cuenta = 'ACTIVA' AND moneda_codigo = 'COP' AND saldo_contable - saldo_retenido > 1000000 \gset
SELECT max(t.transaccion_id) AS tx_reversable
FROM fin.transaccion_financiera t JOIN core.cuenta c ON c.cuenta_id = t.cuenta_destino_id
WHERE t.tipo_codigo = 'CONSIGNACION' AND t.estado_codigo = 'POSTED' AND c.estado_cuenta = 'ACTIVA'
  AND c.saldo_contable - c.saldo_retenido > t.monto
  AND NOT EXISTS (SELECT 1 FROM fin.transaccion_financiera r WHERE r.transaccion_reversada_id = t.transaccion_id) \gset

DROP TABLE IF EXISTS pg_temp.rbac;
CREATE TEMP TABLE rbac (prueba text, usuario text, accion text, esperado text, obtenido text, detalle text);

-- Ejecuta p_sql como p_usuario. La subtransacción siempre se deshace:
-- si la acción se permitió, se lanza '__deshacer__' para no dejar cambios.
CREATE OR REPLACE FUNCTION pg_temp.probar(p_prueba text, p_usuario text, p_accion text, p_sql text, p_esperado text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_obtenido text; v_detalle text;
BEGIN
  BEGIN
    EXECUTE format('SET LOCAL ROLE %I', p_usuario);
    EXECUTE p_sql;
    RAISE EXCEPTION '__deshacer__';
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_obtenido := 'DENEGADO';     v_detalle := SQLERRM;
    WHEN raise_exception THEN
      IF SQLERRM = '__deshacer__' THEN v_obtenido := 'PERMITIDO'; v_detalle := 'ejecutó (cambios deshechos)';
      ELSE v_obtenido := 'ERROR'; v_detalle := SQLERRM; END IF;
    WHEN OTHERS THEN
      IF SQLSTATE = 'BA001' THEN v_obtenido := 'DENEGADO (app)'; ELSE v_obtenido := 'ERROR ' || SQLSTATE; END IF;
      v_detalle := SQLERRM;
  END;
  INSERT INTO rbac VALUES (p_prueba, p_usuario, p_accion, p_esperado, v_obtenido, left(v_detalle, 90));
END $$;

-- 3. Pruebas -----------------------------------------------------------
-- Usuario de CONSULTA
SELECT pg_temp.probar('S01', 'demo_consulta', 'Leer saldos de cuentas',              'SELECT count(*) FROM core.cuenta', 'PERMITIDO') \gset
SELECT pg_temp.probar('S02', 'demo_consulta', 'Leer la auditoría',                   'SELECT count(*) FROM aud.log_auditoria', 'DENEGADO') \gset
SELECT pg_temp.probar('S03', 'demo_consulta', 'Leer usuarios internos (seguridad)',  'SELECT count(*) FROM seg.usuario', 'DENEGADO') \gset
SELECT pg_temp.probar('S04', 'demo_consulta', 'Cambiar un saldo directamente',       'UPDATE core.cuenta SET saldo_contable = 0 WHERE cuenta_id = ' || :cuenta, 'DENEGADO') \gset
SELECT pg_temp.probar('S05', 'demo_consulta', 'Hacer un retiro',                     format('SELECT fin.fn_retirar(%s, %s, 10000, gen_random_uuid())', :cajero, :cuenta), 'DENEGADO') \gset

-- Usuario OPERATIVO (cajero)
SELECT pg_temp.probar('S06', 'demo_cajero', 'Consignar con la función segura',       format('SELECT fin.fn_consignar(%s, %s, 10000, gen_random_uuid())', :cajero, :cuenta), 'PERMITIDO') \gset
SELECT pg_temp.probar('S07', 'demo_cajero', 'Retirar con la función segura',         format('SELECT fin.fn_retirar(%s, %s, 10000, gen_random_uuid())', :cajero, :cuenta), 'PERMITIDO') \gset
SELECT pg_temp.probar('S08', 'demo_cajero', 'Insertar una transacción a mano',
  'INSERT INTO fin.transaccion_financiera (tipo_codigo, estado_codigo, cuenta_destino_id, monto, idempotency_key, fecha_solicitud, creado_por) VALUES (''CONSIGNACION'', ''POSTED'', ' || :cuenta || ', 1000000, gen_random_uuid(), now(), ' || :cajero || ')', 'DENEGADO') \gset
SELECT pg_temp.probar('S09', 'demo_cajero', 'Cambiar un saldo directamente',         'UPDATE core.cuenta SET saldo_contable = saldo_contable + 1000000 WHERE cuenta_id = ' || :cuenta, 'DENEGADO') \gset
SELECT pg_temp.probar('S10', 'demo_cajero', 'Reversar una transacción',              format('SELECT fin.fn_reversar(%s, %s, gen_random_uuid())', :cajero, :tx_reversable), 'DENEGADO') \gset
SELECT pg_temp.probar('S11', 'demo_cajero', 'Leer la auditoría',                     'SELECT count(*) FROM aud.log_auditoria', 'DENEGADO') \gset

-- SUPERVISOR: permitido en la base, pero la aplicación exige el rol del usuario interno
SELECT pg_temp.probar('S12', 'demo_supervisor', 'Reversar (usuario interno SUPERVISOR)', format('SELECT fin.fn_reversar(%s, %s, gen_random_uuid())', :supervisor, :tx_reversable), 'PERMITIDO') \gset
SELECT pg_temp.probar('S13', 'demo_supervisor', 'Reversar (usuario interno CAJERO)',     format('SELECT fin.fn_reversar(%s, %s, gen_random_uuid())', :cajero, :tx_reversable), 'DENEGADO (app)') \gset

-- AUDITOR
SELECT pg_temp.probar('S14', 'demo_auditor', 'Leer la auditoría',                    'SELECT count(*) FROM aud.log_auditoria', 'PERMITIDO') \gset
SELECT pg_temp.probar('S15', 'demo_auditor', 'Leer usuarios y roles internos',       'SELECT count(*) FROM seg.usuario_rol', 'PERMITIDO') \gset
SELECT pg_temp.probar('S16', 'demo_auditor', 'Leer el ledger',                       'SELECT count(*) FROM fin.asiento_contable WHERE transaccion_id = 1', 'PERMITIDO') \gset
SELECT pg_temp.probar('S17', 'demo_auditor', 'Modificar la auditoría',               'UPDATE aud.log_auditoria SET usuario_bd = ''x'' WHERE auditoria_id = 1', 'DENEGADO') \gset
SELECT pg_temp.probar('S18', 'demo_auditor', 'Borrar asientos contables',            'DELETE FROM fin.asiento_contable WHERE transaccion_id = 1', 'DENEGADO') \gset
SELECT pg_temp.probar('S19', 'demo_auditor', 'Consignar',                            format('SELECT fin.fn_consignar(%s, %s, 10000, gen_random_uuid())', :cajero, :cuenta), 'DENEGADO') \gset

-- ADMINISTRADOR DE SEGURIDAD
SELECT pg_temp.probar('S20', 'demo_admin_seg', 'Administrar usuarios internos',      'UPDATE seg.usuario SET estado = estado WHERE usuario_id = ' || :cajero, 'PERMITIDO') \gset
SELECT pg_temp.probar('S21', 'demo_admin_seg', 'Ver saldos de cuentas',              'SELECT count(*) FROM core.cuenta', 'DENEGADO') \gset

-- SIN ROL
SELECT pg_temp.probar('S22', 'demo_sin_rol', 'Leer cuentas',                         'SELECT count(*) FROM core.cuenta', 'DENEGADO') \gset
SELECT pg_temp.probar('S23', 'demo_sin_rol', 'Ejecutar una función del banco',       'SELECT ref.fn_dv_nit(''900123456'')', 'DENEGADO') \gset

-- 4. Resultados ----------------------------------------------------------
\echo '== G7 · Pruebas de acceso por rol'
SELECT prueba, usuario, accion, esperado, obtenido,
       CASE WHEN obtenido = esperado THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM rbac ORDER BY prueba;

\echo '== Detalle de los accesos denegados (mensaje de PostgreSQL)'
SELECT prueba, detalle FROM rbac WHERE obtenido LIKE 'DENEGADO%' ORDER BY prueba;

\echo '== Matriz de privilegios de los roles de base de datos'
SELECT g.rol,
       has_table_privilege(g.rol, 'core.cuenta', 'SELECT')               AS cuenta_select,
       has_table_privilege(g.rol, 'core.cuenta', 'UPDATE')               AS cuenta_update,
       has_table_privilege(g.rol, 'fin.transaccion_financiera', 'INSERT') AS tx_insert,
       has_table_privilege(g.rol, 'fin.asiento_contable', 'DELETE')      AS asiento_delete,
       has_table_privilege(g.rol, 'aud.log_auditoria', 'SELECT')         AS auditoria_select,
       has_table_privilege(g.rol, 'seg.usuario', 'UPDATE')               AS usuario_update,
       has_function_privilege(g.rol, 'fin.fn_retirar(bigint, bigint, numeric, uuid, text)', 'EXECUTE')  AS retirar,
       has_function_privilege(g.rol, 'fin.fn_reversar(bigint, bigint, uuid, text)', 'EXECUTE')          AS reversar
FROM (VALUES ('banco_consulta'), ('banco_cajero'), ('banco_supervisor'), ('banco_auditor'), ('banco_admin_seg')) AS g(rol);

\echo '== Veredicto'
SELECT count(*) AS pruebas,
       count(*) FILTER (WHERE obtenido LIKE 'PERMITIDO%') AS permitidos,
       count(*) FILTER (WHERE obtenido LIKE 'DENEGADO%')  AS denegados,
       count(*) FILTER (WHERE obtenido <> esperado)      AS fallas,
       CASE WHEN count(*) FILTER (WHERE obtenido <> esperado) = 0 THEN 'G7 RBAC = PASS' ELSE 'G7 RBAC = FAIL' END AS resultado
FROM rbac;

-- 5. Limpieza: se borran los usuarios de prueba
DO $$
DECLARE u text;
BEGIN
  FOREACH u IN ARRAY ARRAY['demo_consulta', 'demo_cajero', 'demo_supervisor', 'demo_auditor', 'demo_admin_seg', 'demo_sin_rol'] LOOP
    EXECUTE format('DROP ROLE IF EXISTS %I', u);
  END LOOP;
END $$;
\echo 'Usuarios de prueba borrados; la base no cambió.'
