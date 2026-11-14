-- =====================================================================
-- B5 · Lo que necesita el aplicativo en la base
--
-- 1. Esquema app: los accesos del aplicativo (usuario, contraseña cifrada con
--    bcrypt y a qué empleado o cliente corresponde) y la bitácora de ingresos.
--    La base del banco no guarda contraseñas (seg.usuario no tiene esa columna).
-- 2. Usuario técnico del canal digital: un empleado "de sistema" con un rol
--    nuevo que solo tiene TX_TRANSFERIR. Con él se hacen las transferencias del
--    Cliente, porque las funciones del banco piden siempre un empleado (RN-10).
-- 3. Funciones del Cliente: solo ven y mueven las cuentas de las que el cliente
--    es titular. La revisión de que la cuenta sea suya también está en la base,
--    no solo en el servidor.
-- 4. Conexión del servidor: un solo usuario, app_servidor, que no tiene ningún
--    permiso propio. Para cada petición se "pone" el rol del perfil que inició
--    sesión (SET LOCAL ROLE banco_cajero, banco_supervisor...). Si el servidor
--    se equivocara de rol, la base igual negaría lo que ese rol no puede hacer.
--
-- Se puede correr varias veces: no duplica nada. app_servidor queda SIN
-- contraseña; se la pone ejecutar_b5.bat al final (nunca va al repositorio).
-- =====================================================================
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

CREATE SCHEMA IF NOT EXISTS app;
COMMENT ON SCHEMA app IS 'Accesos del aplicativo web y funciones del perfil Cliente (fase BI, B5).';

-- ---------------------------------------------------------------------
-- 1. Accesos y bitácora de ingresos
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app.acceso (
  acceso_id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  login              varchar(40) NOT NULL UNIQUE CHECK (login ~ '^[a-z0-9._]{4,40}$'),
  perfil             varchar(15) NOT NULL CHECK (perfil IN ('CLIENTE', 'CAJERO', 'SUPERVISOR', 'AUDITOR', 'ADMINISTRADOR')),
  usuario_id         bigint REFERENCES seg.usuario (usuario_id),
  cliente_id         bigint REFERENCES core.cliente (cliente_id),
  clave_hash         text CHECK (clave_hash IS NULL OR clave_hash LIKE '$2%'),
  activo             boolean NOT NULL DEFAULT true,
  intentos_fallidos  smallint NOT NULL DEFAULT 0,
  bloqueado_hasta    timestamptz,
  ultimo_ingreso     timestamptz,
  creado_en          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_acceso_dueno CHECK (
    (perfil = 'CLIENTE' AND cliente_id IS NOT NULL AND usuario_id IS NULL) OR
    (perfil <> 'CLIENTE' AND usuario_id IS NOT NULL AND cliente_id IS NULL))
);
COMMENT ON TABLE app.acceso IS 'Quién puede entrar al aplicativo. La contraseña se guarda solo como hash bcrypt; NULL = pendiente de generar.';

CREATE TABLE IF NOT EXISTS app.ingreso (
  ingreso_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  momento      timestamptz NOT NULL DEFAULT clock_timestamp(),
  login        varchar(60) NOT NULL,
  acceso_id    integer REFERENCES app.acceso (acceso_id),
  exitoso      boolean NOT NULL,
  origen       varchar(60)
);
COMMENT ON TABLE app.ingreso IS 'Bitácora de intentos de ingreso al aplicativo (exitosos y fallidos).';

-- ---------------------------------------------------------------------
-- 2. Usuario técnico del canal digital (solo puede transferir)
-- ---------------------------------------------------------------------
INSERT INTO seg.rol (codigo, nombre)
SELECT 'CANAL_DIGITAL', 'Canal digital (banca en línea)'
WHERE NOT EXISTS (SELECT 1 FROM seg.rol WHERE codigo = 'CANAL_DIGITAL');

INSERT INTO seg.rol_permiso (rol_id, permiso_id)
SELECT r.rol_id, p.permiso_id FROM seg.rol r, seg.permiso p
WHERE r.codigo = 'CANAL_DIGITAL' AND p.codigo = 'TX_TRANSFERIR'
ON CONFLICT DO NOTHING;

INSERT INTO seg.usuario (login, tipo_documento, numero_documento, nombres, apellidos, oficina_id, estado)
SELECT 'canal.digital', 'CC', 'CANALDIGITAL01', 'Canal', 'Digital', NULL, 'ACTIVO'
WHERE NOT EXISTS (SELECT 1 FROM seg.usuario WHERE login = 'canal.digital');

-- Lo asigna el primer administrador de seguridad (RN-50: nadie se asigna a sí mismo)
INSERT INTO seg.usuario_rol (usuario_id, rol_id, asignado_por)
SELECT u.usuario_id, r.rol_id,
       (SELECT min(ur.usuario_id) FROM seg.usuario_rol ur JOIN seg.rol ra ON ra.rol_id = ur.rol_id
        WHERE ra.codigo = 'ADMIN_SEGURIDAD' AND ur.vigente_hasta IS NULL)
FROM seg.usuario u, seg.rol r
WHERE u.login = 'canal.digital' AND r.codigo = 'CANAL_DIGITAL'
  AND NOT EXISTS (SELECT 1 FROM seg.usuario_rol x WHERE x.usuario_id = u.usuario_id AND x.rol_id = r.rol_id AND x.vigente_hasta IS NULL);

-- ---------------------------------------------------------------------
-- 3. Accesos de demostración: uno por perfil (las contraseñas las genera el
--    aplicativo la primera vez que arranca y nunca van al repositorio)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE demo AS
WITH vig AS (
  SELECT ur.usuario_id, r.codigo AS rol, u.oficina_id
  FROM seg.usuario_rol ur JOIN seg.rol r ON r.rol_id = ur.rol_id JOIN seg.usuario u ON u.usuario_id = ur.usuario_id
  WHERE ur.vigente_hasta IS NULL AND u.estado = 'ACTIVO'
), sup AS (
  SELECT usuario_id, oficina_id FROM vig WHERE rol = 'SUPERVISOR' ORDER BY usuario_id LIMIT 1
)
SELECT 'demo.supervisor'::text AS login, 'SUPERVISOR'::text AS perfil, (SELECT usuario_id FROM sup) AS usuario_id, NULL::bigint AS cliente_id
UNION ALL
SELECT 'demo.cajero', 'CAJERO',
       (SELECT min(usuario_id) FROM vig WHERE rol = 'CAJERO' AND oficina_id = (SELECT oficina_id FROM sup)), NULL
UNION ALL
SELECT 'demo.auditor', 'AUDITOR', (SELECT min(usuario_id) FROM vig WHERE rol = 'AUDITOR'), NULL
UNION ALL
SELECT 'demo.admin', 'ADMINISTRADOR', (SELECT min(usuario_id) FROM vig WHERE rol = 'ADMIN_SEGURIDAD'), NULL
UNION ALL
-- Cliente persona natural de la misma oficina, con al menos dos cuentas activas en pesos
SELECT 'demo.cliente', 'CLIENTE', NULL,
       (SELECT c.cliente_id
        FROM core.cliente c
        JOIN core.titularidad_cuenta t ON t.cliente_id = c.cliente_id AND t.vigente_hasta IS NULL AND t.rol_titular = 'PRINCIPAL'
        JOIN core.cuenta cu ON cu.cuenta_id = t.cuenta_id
        WHERE c.tipo_cliente = 'NATURAL' AND c.estado_cliente = 'ACTIVO'
          AND cu.oficina_id = (SELECT oficina_id FROM sup) AND cu.estado_cuenta = 'ACTIVA' AND cu.moneda_codigo = 'COP'
        GROUP BY c.cliente_id HAVING count(*) >= 2
        ORDER BY c.cliente_id LIMIT 1);

INSERT INTO app.acceso (login, perfil, usuario_id, cliente_id)
SELECT login, perfil, usuario_id, cliente_id FROM demo
ON CONFLICT (login) DO NOTHING;

-- ---------------------------------------------------------------------
-- 4. Funciones de acceso (el servidor nunca lee la tabla directamente)
-- ---------------------------------------------------------------------
-- Rol de la base que corresponde a cada perfil
CREATE OR REPLACE FUNCTION app.fn_rol_de_perfil(p_perfil text)
RETURNS text LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE p_perfil WHEN 'CAJERO' THEN 'CAJERO' WHEN 'SUPERVISOR' THEN 'SUPERVISOR'
                       WHEN 'AUDITOR' THEN 'AUDITOR' WHEN 'ADMINISTRADOR' THEN 'ADMIN_SEGURIDAD' END
$$;

CREATE OR REPLACE FUNCTION app.fn_acceso_buscar(p_login text)
RETURNS TABLE (acceso_id integer, perfil text, clave_hash text, bloqueado boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
  SELECT a.acceso_id, a.perfil::text, a.clave_hash, coalesce(a.bloqueado_hasta > clock_timestamp(), false)
  FROM app.acceso a
  WHERE a.login = lower(btrim(p_login)) AND a.activo
$$;
COMMENT ON FUNCTION app.fn_acceso_buscar(text) IS 'Devuelve el hash para que el servidor compare la contraseña. No dice si el login existe o no al usuario final.';

-- Registra el intento. Con 5 fallos seguidos, el acceso queda bloqueado 15 minutos.
CREATE OR REPLACE FUNCTION app.fn_acceso_registrar(p_acceso_id integer, p_login text, p_exitoso boolean, p_origen text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  INSERT INTO app.ingreso (login, acceso_id, exitoso, origen)
  VALUES (left(lower(btrim(coalesce(p_login, ''))), 60), p_acceso_id, p_exitoso, left(p_origen, 60));
  IF p_acceso_id IS NULL THEN RETURN; END IF;
  IF p_exitoso THEN
    UPDATE app.acceso SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_ingreso = clock_timestamp()
    WHERE acceso_id = p_acceso_id;
  ELSE
    UPDATE app.acceso
    SET intentos_fallidos = CASE WHEN intentos_fallidos + 1 >= 5 THEN 0 ELSE intentos_fallidos + 1 END,
        bloqueado_hasta  = CASE WHEN intentos_fallidos + 1 >= 5 THEN clock_timestamp() + interval '15 minutes' ELSE bloqueado_hasta END
    WHERE acceso_id = p_acceso_id;
  END IF;
END $$;

-- Datos de la sesión. Se consulta en cada petición: si el administrador le quita
-- el rol a un empleado, o se desactiva, pierde el acceso de inmediato.
CREATE OR REPLACE FUNCTION app.fn_sesion(p_acceso_id integer)
RETURNS TABLE (acceso_id integer, login text, perfil text, usuario_id bigint, cliente_id bigint,
               oficina_id integer, oficina text, nombre text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
  SELECT a.acceso_id, a.login::text, a.perfil::text, a.usuario_id, NULL::bigint, u.oficina_id, o.nombre::text,
         (u.nombres || ' ' || u.apellidos)::text
  FROM app.acceso a
  JOIN seg.usuario u ON u.usuario_id = a.usuario_id AND u.estado = 'ACTIVO'
  LEFT JOIN ref.oficina o ON o.oficina_id = u.oficina_id
  WHERE a.acceso_id = p_acceso_id AND a.activo AND a.perfil <> 'CLIENTE'
    AND EXISTS (SELECT 1 FROM seg.usuario_rol ur JOIN seg.rol r ON r.rol_id = ur.rol_id
                WHERE ur.usuario_id = a.usuario_id AND r.codigo = app.fn_rol_de_perfil(a.perfil)
                  AND ur.vigente_desde <= clock_timestamp()
                  AND (ur.vigente_hasta IS NULL OR ur.vigente_hasta > clock_timestamp()))
  UNION ALL
  SELECT a.acceso_id, a.login::text, a.perfil::text, NULL::bigint, a.cliente_id, NULL::integer, NULL::text,
         coalesce(pn.nombres || ' ' || pn.apellidos, pj.razon_social)::text
  FROM app.acceso a
  JOIN core.cliente c ON c.cliente_id = a.cliente_id AND c.estado_cliente = 'ACTIVO'
  LEFT JOIN core.persona_natural pn ON pn.cliente_id = c.cliente_id
  LEFT JOIN core.persona_juridica pj ON pj.cliente_id = c.cliente_id
  WHERE a.acceso_id = p_acceso_id AND a.activo AND a.perfil = 'CLIENTE'
$$;

CREATE OR REPLACE FUNCTION app.fn_accesos_pendientes()
RETURNS TABLE (login text, perfil text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
  SELECT login::text, perfil::text FROM app.acceso WHERE clave_hash IS NULL AND activo ORDER BY acceso_id
$$;

-- Solo sirve la primera vez (cuando no hay contraseña). Cambiarla después es otra cosa.
CREATE OR REPLACE FUNCTION app.fn_definir_clave_inicial(p_login text, p_hash text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF p_hash IS NULL OR p_hash NOT LIKE '$2%' THEN
    RAISE EXCEPTION 'La contraseña debe llegar cifrada con bcrypt' USING ERRCODE = 'BA017';
  END IF;
  UPDATE app.acceso SET clave_hash = p_hash WHERE login = p_login AND clave_hash IS NULL;
  RETURN FOUND;
END $$;

-- ---------------------------------------------------------------------
-- 5. Funciones del Cliente (solo sus propias cuentas)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_es_titular(p_cliente_id bigint, p_cuenta_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM core.titularidad_cuenta t
                 WHERE t.cliente_id = p_cliente_id AND t.cuenta_id = p_cuenta_id AND t.vigente_hasta IS NULL)
$$;

CREATE OR REPLACE FUNCTION app.fn_exigir_titular(p_cliente_id bigint, p_cuenta_id bigint)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NOT app.fn_es_titular(p_cliente_id, p_cuenta_id) THEN
    RAISE EXCEPTION 'La cuenta % no es del cliente %', p_cuenta_id, p_cliente_id USING ERRCODE = 'BA010';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION app.fn_cliente_cuentas(p_cliente_id bigint)
RETURNS TABLE (cuenta_id bigint, numero_cuenta text, producto text, moneda text, estado text,
               rol_titular text, saldo_contable numeric, saldo_disponible numeric, limite_retiro_diario numeric)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
  SELECT c.cuenta_id, c.numero_cuenta::text, p.nombre::text, c.moneda_codigo::text, c.estado_cuenta::text,
         t.rol_titular::text, c.saldo_contable, c.saldo_disponible, c.limite_retiro_diario
  FROM core.titularidad_cuenta t
  JOIN core.cuenta c ON c.cuenta_id = t.cuenta_id
  JOIN core.producto p ON p.producto_codigo = c.producto_codigo
  WHERE t.cliente_id = p_cliente_id AND t.vigente_hasta IS NULL
  ORDER BY c.estado_cuenta <> 'ACTIVA', c.numero_cuenta
$$;

CREATE OR REPLACE FUNCTION app.fn_cliente_movimientos(
  p_cliente_id bigint, p_cuenta_id bigint, p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL, p_limite integer DEFAULT 100)
RETURNS TABLE (transaccion_id bigint, fecha timestamptz, tipo text, estado text, descripcion text,
               valor numeric, contraparte text, motivo_rechazo text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM app.fn_exigir_titular(p_cliente_id, p_cuenta_id);
  RETURN QUERY
  SELECT t.transaccion_id, coalesce(t.fecha_contabilizacion, t.fecha_solicitud), tt.nombre::text, t.estado_codigo::text,
         t.descripcion::text,
         CASE WHEN t.cuenta_destino_id = p_cuenta_id THEN t.monto ELSE -t.monto END,
         (SELECT x.numero_cuenta::text FROM core.cuenta x
          WHERE x.cuenta_id = CASE WHEN t.cuenta_destino_id = p_cuenta_id THEN t.cuenta_origen_id ELSE t.cuenta_destino_id END),
         t.motivo_rechazo::text
  FROM fin.transaccion_financiera t
  JOIN ref.tipo_transaccion tt ON tt.codigo = t.tipo_codigo
  WHERE (t.cuenta_origen_id = p_cuenta_id OR t.cuenta_destino_id = p_cuenta_id)
    AND (p_desde IS NULL OR coalesce(t.fecha_contable, t.fecha_solicitud::date) >= p_desde)
    AND (p_hasta IS NULL OR coalesce(t.fecha_contable, t.fecha_solicitud::date) <= p_hasta)
  ORDER BY coalesce(t.fecha_contabilizacion, t.fecha_solicitud) DESC, t.transaccion_id DESC
  LIMIT least(greatest(coalesce(p_limite, 100), 1), 500);
END $$;

-- Entradas y salidas por mes de todas sus cuentas en pesos ("Mis estadísticas")
CREATE OR REPLACE FUNCTION app.fn_cliente_resumen_mensual(p_cliente_id bigint)
RETURNS TABLE (anio_mes text, entradas numeric, salidas numeric)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
  WITH mias AS (
    SELECT c.cuenta_id FROM core.titularidad_cuenta t JOIN core.cuenta c ON c.cuenta_id = t.cuenta_id
    WHERE t.cliente_id = p_cliente_id AND t.vigente_hasta IS NULL AND c.moneda_codigo = 'COP'
  )
  SELECT to_char(t.fecha_contable, 'YYYY-MM'),
         coalesce(sum(t.monto) FILTER (WHERE t.cuenta_destino_id IN (SELECT cuenta_id FROM mias)), 0),
         coalesce(sum(t.monto) FILTER (WHERE t.cuenta_origen_id IN (SELECT cuenta_id FROM mias)), 0)
  FROM fin.transaccion_financiera t
  WHERE t.estado_codigo = 'POSTED'
    AND (t.cuenta_origen_id IN (SELECT cuenta_id FROM mias) OR t.cuenta_destino_id IN (SELECT cuenta_id FROM mias))
  GROUP BY 1 ORDER BY 1
$$;

CREATE OR REPLACE FUNCTION app.fn_usuario_canal()
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
  SELECT usuario_id FROM seg.usuario WHERE login = 'canal.digital'
$$;

CREATE OR REPLACE FUNCTION app.fn_cuenta_por_numero(p_numero text)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_id bigint;
BEGIN
  SELECT cuenta_id INTO v_id FROM core.cuenta WHERE numero_cuenta = btrim(p_numero);
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'No existe la cuenta %', p_numero USING ERRCODE = 'BA016';
  END IF;
  RETURN v_id;
END $$;

-- Transferencia de la banca en línea: revisa que la cuenta de origen sea del
-- cliente y llama a la misma función segura del banco con el usuario del canal.
-- Al final corre ya (SET CONSTRAINTS ALL IMMEDIATE) la revisión diferida de que la transacción
-- cuadre (trg_transaccion_cuadrada). Si se dejara para el COMMIT, correría con el rol del cliente,
-- que no puede leer fin.transaccion_financiera, y la base negaría la operación.
CREATE OR REPLACE FUNCTION app.fn_cliente_transferir(
  p_cliente_id bigint, p_cuenta_origen_id bigint, p_numero_destino text, p_monto numeric,
  p_idempotency_key uuid, p_descripcion text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_id bigint;
BEGIN
  PERFORM app.fn_exigir_titular(p_cliente_id, p_cuenta_origen_id);
  v_id := fin.fn_transferir(app.fn_usuario_canal(), p_cuenta_origen_id, app.fn_cuenta_por_numero(p_numero_destino),
                            p_monto, p_idempotency_key,
                            coalesce(nullif(btrim(p_descripcion), ''), 'Transferencia por banca en línea'));
  SET CONSTRAINTS ALL IMMEDIATE;
  RETURN v_id;
END $$;

-- Deja constancia de una transferencia rechazada (RN-45), también solo desde sus cuentas
CREATE OR REPLACE FUNCTION app.fn_cliente_registrar_rechazo(
  p_cliente_id bigint, p_cuenta_origen_id bigint, p_numero_destino text, p_monto numeric, p_motivo text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_destino bigint;
BEGIN
  PERFORM app.fn_exigir_titular(p_cliente_id, p_cuenta_origen_id);
  SELECT cuenta_id INTO v_destino FROM core.cuenta WHERE numero_cuenta = btrim(p_numero_destino);
  v_destino := fin.fn_registrar_rechazo(app.fn_usuario_canal(), 'TRANSFERENCIA', p_cuenta_origen_id, v_destino,
                                       p_monto, gen_random_uuid(), p_motivo);
  SET CONSTRAINTS ALL IMMEDIATE;
  RETURN v_destino;
END $$;

-- ---------------------------------------------------------------------
-- 6. Roles de la base para el aplicativo
-- ---------------------------------------------------------------------
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['banco_app_acceso', 'banco_cliente_app'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', r);
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_servidor') THEN
    CREATE ROLE app_servidor LOGIN NOINHERIT;
  END IF;
END $$;
COMMENT ON ROLE banco_app_acceso  IS 'Solo las funciones de inicio de sesión del aplicativo (app.fn_acceso_*, app.fn_sesion).';
COMMENT ON ROLE banco_cliente_app IS 'Perfil Cliente: solo las funciones app.fn_cliente_* (sus cuentas, movimientos y transferencias).';
COMMENT ON ROLE app_servidor      IS 'Usuario con el que se conecta el servidor del aplicativo. No tiene permisos propios: en cada petición se pone el rol del perfil (SET LOCAL ROLE).';

REVOKE ALL ON SCHEMA app FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA app FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC;

GRANT USAGE ON SCHEMA app TO banco_app_acceso, banco_cliente_app, banco_auditor;
GRANT EXECUTE ON FUNCTION app.fn_acceso_buscar(text), app.fn_acceso_registrar(integer, text, boolean, text),
                          app.fn_sesion(integer), app.fn_accesos_pendientes(), app.fn_definir_clave_inicial(text, text)
  TO banco_app_acceso;
GRANT EXECUTE ON FUNCTION app.fn_cliente_cuentas(bigint), app.fn_cliente_movimientos(bigint, bigint, date, date, integer),
                          app.fn_cliente_resumen_mensual(bigint),
                          app.fn_cliente_transferir(bigint, bigint, text, numeric, uuid, text),
                          app.fn_cliente_registrar_rechazo(bigint, bigint, text, numeric, text)
  TO banco_cliente_app;
-- El auditor de datos también revisa quién entra al aplicativo
GRANT SELECT ON app.ingreso TO banco_auditor;
GRANT SELECT (acceso_id, login, perfil, usuario_id, cliente_id, activo, intentos_fallidos, bloqueado_hasta, ultimo_ingreso, creado_en)
  ON app.acceso TO banco_auditor;

-- app_servidor puede "ponerse" cada rol, pero no hereda sus permisos (INHERIT FALSE):
-- sin SET ROLE no puede hacer nada.
GRANT banco_cajero, banco_supervisor, banco_auditor, banco_admin_seg, banco_bi, banco_app_acceso, banco_cliente_app
  TO app_servidor WITH INHERIT FALSE, SET TRUE;
DO $$ BEGIN EXECUTE format('GRANT CONNECT ON DATABASE %I TO app_servidor', current_database()); END $$;

\echo '== Accesos de demostración'
SELECT a.login, a.perfil, coalesce(u.login, 'cliente ' || a.cliente_id) AS corresponde_a,
       CASE WHEN a.clave_hash IS NULL THEN 'pendiente (la genera el aplicativo al arrancar)' ELSE 'definida' END AS contrasena
FROM app.acceso a LEFT JOIN seg.usuario u ON u.usuario_id = a.usuario_id
ORDER BY a.acceso_id;

\echo 'Esquema app, usuario del canal digital y app_servidor listos.'
