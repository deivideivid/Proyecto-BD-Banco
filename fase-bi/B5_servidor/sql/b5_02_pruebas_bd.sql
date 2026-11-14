-- =====================================================================
-- B5 · Pruebas de permisos en la base (segunda capa de control)
-- Simulamos que el servidor se equivoca o que alguien se salta el servidor:
-- con cada rol de la base intentamos cosas que ese perfil NO puede hacer.
-- Todas deben fallar, y las que deben funcionar se deshacen al final de cada
-- prueba, así que este script no cambia ningún dato.
--   42501 = la base niega el permiso (rol sin EXECUTE o sin SELECT)
--   BA001 = el empleado no tiene el permiso del banco (seg.rol_permiso)
--   BA010 = la cuenta no es del cliente
-- =====================================================================
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';
\pset footer off

CREATE TEMP TABLE resultado (n serial, prueba text, rol text, esperado text, obtenido text, ok boolean);
GRANT ALL ON resultado TO PUBLIC;

-- Corre una sentencia con un rol y compara el SQLSTATE. 'OK' = debe funcionar.
-- Siempre deshace lo que haya hecho (lanza ZZ000 al final y lo atrapa).
-- Ojo: SET CONSTRAINTS ALL DEFERRED solo devuelve a diferidas las que nacieron así.
CREATE PROCEDURE pg_temp.probar(p_prueba text, p_rol text, p_esperado text, p_sql text)
LANGUAGE plpgsql AS $$
DECLARE v_estado text;
BEGIN
  BEGIN
    EXECUTE format('SET LOCAL ROLE %I', p_rol);
    EXECUTE p_sql;
    -- Las revisiones diferidas (que la transacción cuadre) también corren con el rol de la prueba,
    -- como pasaría en el COMMIT del aplicativo
    SET CONSTRAINTS ALL IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;
    RAISE EXCEPTION 'sin error' USING ERRCODE = 'ZZ000';
  EXCEPTION WHEN OTHERS THEN
    v_estado := CASE SQLSTATE WHEN 'ZZ000' THEN 'OK' ELSE SQLSTATE END;
  END;
  RESET ROLE;
  INSERT INTO resultado (prueba, rol, esperado, obtenido, ok)
  VALUES (p_prueba, p_rol, p_esperado, v_estado, v_estado = p_esperado);
END $$;

-- Datos de apoyo (solo lectura)
SELECT (SELECT usuario_id FROM app.acceso WHERE login = 'demo.cajero')     AS cajero,
       (SELECT usuario_id FROM app.acceso WHERE login = 'demo.supervisor') AS supervisor,
       (SELECT usuario_id FROM app.acceso WHERE login = 'demo.admin')      AS admin,
       (SELECT cliente_id FROM app.acceso WHERE login = 'demo.cliente')    AS cliente,
       app.fn_usuario_canal()                                             AS canal \gset
SELECT min(c.cuenta_id) AS cuenta_propia FROM core.titularidad_cuenta t JOIN core.cuenta c USING (cuenta_id)
WHERE t.cliente_id = :cliente AND t.vigente_hasta IS NULL AND c.estado_cuenta = 'ACTIVA' \gset
SELECT min(c.cuenta_id) AS cuenta_ajena FROM core.cuenta c
WHERE c.estado_cuenta = 'ACTIVA' AND NOT app.fn_es_titular(:cliente, c.cuenta_id) \gset
SELECT numero_cuenta AS numero_ajena FROM core.cuenta WHERE cuenta_id = :cuenta_ajena \gset

-- 1. app_servidor por sí solo no puede nada
CALL pg_temp.probar('app_servidor sin SET ROLE no lee cuentas', 'app_servidor', '42501', 'SELECT 1 FROM core.cuenta LIMIT 1');
CALL pg_temp.probar('app_servidor sin SET ROLE no consigna', 'app_servidor', '42501',
  format('SELECT fin.fn_consignar(%s, %s, 1000, gen_random_uuid())', :cajero, :cuenta_ajena));
INSERT INTO resultado (prueba, rol, esperado, obtenido, ok)
SELECT 'app_servidor puede ponerse banco_cajero pero no hereda sus permisos', 'app_servidor', 'SET sí, herencia no',
       CASE WHEN pg_has_role('app_servidor', 'banco_cajero', 'SET') THEN 'SET sí' ELSE 'SET no' END || ', ' ||
       CASE WHEN pg_has_role('app_servidor', 'banco_cajero', 'USAGE') THEN 'herencia sí' ELSE 'herencia no' END,
       pg_has_role('app_servidor', 'banco_cajero', 'SET') AND NOT pg_has_role('app_servidor', 'banco_cajero', 'USAGE');

-- 2. Cajero: no hace lo del supervisor
CALL pg_temp.probar('Cajero no reversa', 'banco_cajero', '42501', format('SELECT fin.fn_reversar(%s, 1, gen_random_uuid())', :cajero));
CALL pg_temp.probar('Cajero no desbloquea', 'banco_cajero', '42501', format('SELECT core.fn_desbloquear_cuenta(%s, %s)', :cajero, :cuenta_ajena));
CALL pg_temp.probar('Cajero no aprueba ajustes', 'banco_cajero', '42501', format('SELECT fin.fn_aprobar_ajuste(%s, 1)', :cajero));
CALL pg_temp.probar('Cajero no administra usuarios', 'banco_cajero', '42501', 'UPDATE seg.usuario SET estado = ''INACTIVO'' WHERE false');
CALL pg_temp.probar('Cajero no lee la auditoría', 'banco_cajero', '42501', 'SELECT 1 FROM aud.log_auditoria LIMIT 1');
CALL pg_temp.probar('Cajero sí consigna (se deshace)', 'banco_cajero', 'OK',
  format('SELECT fin.fn_consignar(%s, %s, 1000, gen_random_uuid(), ''Prueba B5'')', :cajero, :cuenta_ajena));

-- 3. Aunque el rol de la base lo permita, el permiso del banco manda
CALL pg_temp.probar('Rol supervisor con usuario cajero no reversa (permiso del banco)', 'banco_supervisor', 'BA001',
  format('SELECT fin.fn_reversar(%s, 1, gen_random_uuid())', :cajero));
CALL pg_temp.probar('El usuario del canal digital no consigna (solo transfiere)', 'banco_cajero', 'BA001',
  format('SELECT fin.fn_consignar(%s, %s, 1000, gen_random_uuid())', :canal, :cuenta_ajena));

-- 4. Auditor de datos: solo lee
CALL pg_temp.probar('Auditor no consigna', 'banco_auditor', '42501', format('SELECT fin.fn_consignar(%s, %s, 1000, gen_random_uuid())', :cajero, :cuenta_ajena));
CALL pg_temp.probar('Auditor no escribe en la auditoría', 'banco_auditor', '42501',
  'INSERT INTO aud.log_auditoria (esquema, tabla, registro, operacion, valores_despues) VALUES (''x'', ''x'', ''{}'', ''INSERT'', ''{}'')');
CALL pg_temp.probar('Auditor no ve contraseñas del aplicativo', 'banco_auditor', '42501', 'SELECT clave_hash FROM app.acceso LIMIT 1');
CALL pg_temp.probar('Auditor sí lee la auditoría', 'banco_auditor', 'OK', 'SELECT count(*) FROM aud.log_auditoria');

-- 5. Administrador: usuarios y roles, nada de dinero
CALL pg_temp.probar('Administrador no ve cuentas', 'banco_admin_seg', '42501', 'SELECT 1 FROM core.cuenta LIMIT 1');
CALL pg_temp.probar('Administrador no consigna', 'banco_admin_seg', '42501', format('SELECT fin.fn_consignar(%s, %s, 1000, gen_random_uuid())', :admin, :cuenta_ajena));
CALL pg_temp.probar('Administrador no se asigna roles a sí mismo (RN-50)', 'banco_admin_seg', '23514',
  format('INSERT INTO seg.usuario_rol (usuario_id, rol_id, asignado_por) SELECT %s, rol_id, %s FROM seg.rol WHERE codigo = ''CAJERO''', :admin, :admin));
CALL pg_temp.probar('Administrador no borra asignaciones (se revocan con fecha)', 'banco_admin_seg', '42501', 'DELETE FROM seg.usuario_rol WHERE false');

-- 6. Cliente: solo sus cuentas
CALL pg_temp.probar('Cliente no lee la tabla de cuentas', 'banco_cliente_app', '42501', 'SELECT 1 FROM core.cuenta LIMIT 1');
CALL pg_temp.probar('Cliente no llama directo a fn_transferir', 'banco_cliente_app', '42501',
  format('SELECT fin.fn_transferir(%s, %s, %s, 1000, gen_random_uuid())', :canal, :cuenta_ajena, :cuenta_propia));
CALL pg_temp.probar('Cliente no ve movimientos de una cuenta ajena', 'banco_cliente_app', 'BA010',
  format('SELECT * FROM app.fn_cliente_movimientos(%s, %s)', :cliente, :cuenta_ajena));
CALL pg_temp.probar('Cliente no transfiere desde una cuenta ajena', 'banco_cliente_app', 'BA010',
  format('SELECT app.fn_cliente_transferir(%s, %s, ''%s'', 1000, gen_random_uuid())', :cliente, :cuenta_ajena, :numero_ajena));
CALL pg_temp.probar('Cliente no transfiere un monto inválido', 'banco_cliente_app', 'BA005',
  format('SELECT app.fn_cliente_transferir(%s, %s, ''%s'', 0, gen_random_uuid())', :cliente, :cuenta_propia, :numero_ajena));
CALL pg_temp.probar('Cliente sí ve sus cuentas', 'banco_cliente_app', 'OK', format('SELECT * FROM app.fn_cliente_cuentas(%s)', :cliente));
CALL pg_temp.probar('Cliente sí transfiere desde su cuenta (se deshace)', 'banco_cliente_app', 'OK',
  format('SELECT app.fn_cliente_transferir(%s, %s, ''%s'', 1000, gen_random_uuid(), ''Prueba B5'')', :cliente, :cuenta_propia, :numero_ajena));

-- 7. Inicio de sesión: solo por funciones
CALL pg_temp.probar('El rol de acceso no lee la tabla de accesos', 'banco_app_acceso', '42501', 'SELECT clave_hash FROM app.acceso LIMIT 1');
CALL pg_temp.probar('El rol de acceso no consigna', 'banco_app_acceso', '42501', format('SELECT fin.fn_consignar(%s, %s, 1000, gen_random_uuid())', :cajero, :cuenta_ajena));
CALL pg_temp.probar('Cinco contraseñas malas seguidas bloquean el acceso (se deshace)', 'banco_app_acceso', 'OK', $q$
  DO $d$
  DECLARE v integer := (SELECT acceso_id FROM app.fn_acceso_buscar('demo.cliente'));
  BEGIN
    FOR i IN 1..5 LOOP PERFORM app.fn_acceso_registrar(v, 'demo.cliente', false, 'prueba'); END LOOP;
    IF NOT (SELECT bloqueado FROM app.fn_acceso_buscar('demo.cliente')) THEN
      RAISE EXCEPTION 'no se bloqueó' USING ERRCODE = 'ZZ001';
    END IF;
  END $d$ $q$);
CALL pg_temp.probar('Estadísticas (banco_bi) no usa funciones del cliente', 'banco_bi', '42501', format('SELECT * FROM app.fn_cliente_cuentas(%s)', :cliente));

\echo '== Detalle'
SELECT n, prueba, rol, esperado, obtenido, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS resultado FROM resultado ORDER BY n;

\echo '== Resumen B5 (base)'
SELECT count(*) FILTER (WHERE ok) AS pass, count(*) FILTER (WHERE NOT ok) AS fail, count(*) AS total,
       CASE WHEN bool_and(ok) THEN 'B5 PERMISOS EN LA BASE = PASS' ELSE 'B5 PERMISOS EN LA BASE = FAIL' END AS veredicto
FROM resultado;
