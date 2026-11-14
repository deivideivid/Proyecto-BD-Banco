-- =====================================================================
-- B6 · El administrador da (o quita) acceso al aplicativo a los empleados
--
-- En B5 solo existían los 5 accesos de demostración. Ahora el administrador,
-- desde su pantalla, puede darle acceso a un empleado que ya tenga el rol del
-- banco. El servidor genera una contraseña temporal, la muestra una sola vez y
-- aquí solo guardamos su hash bcrypt.
--
-- La base vuelve a revisar todo: que quien lo pide tenga SEG_ADMINISTRAR, que no
-- se dé acceso a sí mismo, que el empleado tenga vigente el rol del perfil y que
-- no sea el usuario técnico del canal digital.
-- Se puede correr varias veces.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

CREATE OR REPLACE FUNCTION app.fn_admin_accesos()
RETURNS TABLE (usuario_id bigint, login text, perfil text, activo boolean, ultimo_ingreso timestamptz, bloqueado boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
  SELECT a.usuario_id, a.login::text, a.perfil::text, a.activo, a.ultimo_ingreso,
         coalesce(a.bloqueado_hasta > clock_timestamp(), false)
  FROM app.acceso a WHERE a.usuario_id IS NOT NULL ORDER BY a.login
$$;

CREATE OR REPLACE FUNCTION app.fn_admin_dar_acceso(p_admin_id bigint, p_usuario_id bigint, p_perfil text, p_hash text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_login text;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_admin_id, 'SEG_ADMINISTRAR');
  IF p_usuario_id = p_admin_id THEN
    RAISE EXCEPTION 'Nadie se da acceso a sí mismo (como RN-50)' USING ERRCODE = 'BA001';
  END IF;
  IF p_perfil NOT IN ('CAJERO', 'SUPERVISOR', 'AUDITOR', 'ADMINISTRADOR') THEN
    RAISE EXCEPTION 'Perfil no válido: %', p_perfil USING ERRCODE = 'BA017';
  END IF;
  IF p_hash IS NULL OR p_hash NOT LIKE '$2%' THEN
    RAISE EXCEPTION 'La contraseña debe llegar cifrada con bcrypt' USING ERRCODE = 'BA017';
  END IF;
  SELECT u.login INTO v_login FROM seg.usuario u WHERE u.usuario_id = p_usuario_id AND u.estado = 'ACTIVO';
  IF v_login IS NULL THEN
    RAISE EXCEPTION 'El usuario % no existe o está inactivo', p_usuario_id USING ERRCODE = 'BA016';
  END IF;
  IF v_login = 'canal.digital' THEN
    RAISE EXCEPTION 'El usuario técnico del canal digital no entra al aplicativo' USING ERRCODE = 'BA017';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM seg.usuario_rol ur JOIN seg.rol r ON r.rol_id = ur.rol_id
                 WHERE ur.usuario_id = p_usuario_id AND r.codigo = app.fn_rol_de_perfil(p_perfil)
                   AND ur.vigente_desde <= clock_timestamp()
                   AND (ur.vigente_hasta IS NULL OR ur.vigente_hasta > clock_timestamp())) THEN
    RAISE EXCEPTION 'El usuario no tiene vigente el rol del perfil %', p_perfil USING ERRCODE = 'BA001';
  END IF;

  -- Si ya tenía acceso, se reemplaza la contraseña y el perfil (sirve para restablecerla)
  UPDATE app.acceso SET perfil = p_perfil, clave_hash = p_hash, activo = true,
                        intentos_fallidos = 0, bloqueado_hasta = NULL
  WHERE usuario_id = p_usuario_id;
  IF NOT FOUND THEN
    INSERT INTO app.acceso (login, perfil, usuario_id, clave_hash) VALUES (v_login, p_perfil, p_usuario_id, p_hash);
  END IF;
  RETURN v_login;
END $$;

CREATE OR REPLACE FUNCTION app.fn_admin_quitar_acceso(p_admin_id bigint, p_usuario_id bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM seg.fn_exigir_permiso(p_admin_id, 'SEG_ADMINISTRAR');
  IF p_usuario_id = p_admin_id THEN
    RAISE EXCEPTION 'No puede quitarse su propio acceso' USING ERRCODE = 'BA001';
  END IF;
  UPDATE app.acceso SET activo = false WHERE usuario_id = p_usuario_id AND activo;
  RETURN FOUND;
END $$;

REVOKE EXECUTE ON FUNCTION app.fn_admin_accesos(), app.fn_admin_dar_acceso(bigint, bigint, text, text),
                           app.fn_admin_quitar_acceso(bigint, bigint) FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO banco_admin_seg;
GRANT EXECUTE ON FUNCTION app.fn_admin_accesos(), app.fn_admin_dar_acceso(bigint, bigint, text, text),
                          app.fn_admin_quitar_acceso(bigint, bigint) TO banco_admin_seg;

-- Pruebas rápidas (no cambian datos: todo se deshace)
\echo '== Pruebas de las funciones de acceso del administrador'
CREATE TEMP TABLE r6 (prueba text, esperado text, obtenido text);
GRANT ALL ON r6 TO PUBLIC;
DO $$
DECLARE
  v_admin bigint := (SELECT usuario_id FROM app.acceso WHERE login = 'demo.admin');
  v_cajero bigint := (SELECT usuario_id FROM app.acceso WHERE login = 'demo.cajero');
  v_estado text;
  h text := '$2b$12$abcdefghijklmnopqrstuuSjD0n6lP7m1k3U1zQ7c5vYx9yQx7b2a';
BEGIN
  -- El cajero no puede dar accesos (rol de la base)
  BEGIN
    SET LOCAL ROLE banco_cajero;
    PERFORM app.fn_admin_dar_acceso(v_cajero, v_admin, 'CAJERO', h);
    v_estado := 'OK';
  EXCEPTION WHEN OTHERS THEN v_estado := SQLSTATE; END;
  RESET ROLE; INSERT INTO r6 VALUES ('El cajero no da accesos', '42501', v_estado);
  -- Con el rol del administrador pero el usuario de un cajero: el permiso del banco lo frena
  BEGIN
    SET LOCAL ROLE banco_admin_seg;
    PERFORM app.fn_admin_dar_acceso(v_cajero, v_admin, 'CAJERO', h);
    v_estado := 'OK';
  EXCEPTION WHEN OTHERS THEN v_estado := SQLSTATE; END;
  RESET ROLE; INSERT INTO r6 VALUES ('Rol admin con usuario cajero no da accesos', 'BA001', v_estado);
  -- El administrador no se da acceso a sí mismo
  BEGIN
    SET LOCAL ROLE banco_admin_seg;
    PERFORM app.fn_admin_dar_acceso(v_admin, v_admin, 'ADMINISTRADOR', h);
    v_estado := 'OK';
  EXCEPTION WHEN OTHERS THEN v_estado := SQLSTATE; END;
  RESET ROLE; INSERT INTO r6 VALUES ('El administrador no se da acceso a sí mismo', 'BA001', v_estado);
  -- Perfil que no corresponde al rol del empleado (el cajero no es auditor)
  BEGIN
    SET LOCAL ROLE banco_admin_seg;
    PERFORM app.fn_admin_dar_acceso(v_admin, v_cajero, 'AUDITOR', h);
    v_estado := 'OK';
  EXCEPTION WHEN OTHERS THEN v_estado := SQLSTATE; END;
  RESET ROLE; INSERT INTO r6 VALUES ('No se da un perfil sin el rol vigente', 'BA001', v_estado);
END $$;
SELECT prueba, esperado, obtenido, CASE WHEN esperado = obtenido THEN 'PASS' ELSE 'FAIL' END AS resultado FROM r6;
SELECT CASE WHEN bool_and(esperado = obtenido) THEN 'B6 ACCESOS = PASS' ELSE 'B6 ACCESOS = FAIL' END AS veredicto FROM r6;
