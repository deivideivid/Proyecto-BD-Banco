-- =====================================================================
-- 17_roles_permissions.sql · Banco Andino Colombia
-- Roles de BASE DE DATOS y mínimo privilegio (DCL).
--
-- Dos niveles que se complementan:
--   1. Roles de base de datos (este archivo): qué puede ejecutar o leer una
--      conexión. Nadie de la aplicación tiene INSERT/UPDATE/DELETE sobre
--      las tablas de negocio: el dinero solo se mueve con las funciones.
--   2. Roles de la aplicación (seg.rol / seg.permiso): qué puede hacer cada
--      usuario interno; lo valida seg.fn_exigir_permiso dentro de cada función.
--
-- Los roles son del servidor (no de la base): se crean solo si no existen.
-- Son NOLOGIN (grupos). Para conectarse se crea un usuario con LOGIN y se le
-- otorga el grupo, por ejemplo:
--   CREATE ROLE ana_cajera LOGIN PASSWORD '…';  GRANT banco_cajero TO ana_cajera;
--
-- Se ejecuta desde sql/run_all.sql (no abre ni cierra transacción).
-- =====================================================================

DO $$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['banco_consulta', 'banco_cajero', 'banco_supervisor', 'banco_auditor', 'banco_admin_seg'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', r);
    END IF;
  END LOOP;
END $$;

COMMENT ON ROLE banco_consulta   IS 'Lectura de catálogos, clientes, cuentas y transacciones. Sin seguridad ni auditoría.';
COMMENT ON ROLE banco_cajero     IS 'Consulta + operaciones de caja: clientes, apertura, consignación, retiro, transferencia, ajustes (crear).';
COMMENT ON ROLE banco_supervisor IS 'Cajero + desbloquear, cerrar, cambiar límite, reversar, aprobar ajustes e inactivar cuentas.';
COMMENT ON ROLE banco_auditor    IS 'Solo lectura de todo, incluida la auditoría y la seguridad. No ejecuta operaciones.';
COMMENT ON ROLE banco_admin_seg  IS 'Administra usuarios internos y sus roles. No ve ni mueve dinero.';

-- 17.1 Nada para PUBLIC -----------------------------------------------
-- Las funciones nacen con EXECUTE para PUBLIC: se quita explícitamente.
REVOKE ALL ON SCHEMA ref, seg, core, fin, aud FROM PUBLIC;
REVOKE ALL ON ALL TABLES    IN SCHEMA ref, seg, core, fin, aud FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA ref, seg, core, fin, aud FROM PUBLIC;
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA ref, seg, core, fin, aud FROM PUBLIC;

-- 17.2 banco_consulta ---------------------------------------------------
GRANT USAGE  ON SCHEMA ref, core, fin TO banco_consulta;
GRANT SELECT ON ALL TABLES IN SCHEMA ref, core, fin TO banco_consulta;   -- incluye las vistas de control
GRANT EXECUTE ON FUNCTION fin.fn_fecha_contable(timestamptz), ref.fn_dv_nit(text) TO banco_consulta;

-- 17.3 banco_cajero -----------------------------------------------------
GRANT banco_consulta TO banco_cajero;
GRANT EXECUTE ON FUNCTION
  core.fn_crear_cliente_natural(bigint, text, text, text, text, date, text, text, text),
  core.fn_crear_cliente_juridico(bigint, text, text, date, text, text, text, text),
  core.fn_abrir_cuenta(bigint, bigint, text, text, integer, numeric, numeric),
  core.fn_agregar_titular(bigint, bigint, bigint),
  core.fn_activar_cuenta(bigint, bigint),
  core.fn_bloquear_cuenta(bigint, bigint, text),
  fin.fn_consignar(bigint, bigint, numeric, uuid, text),
  fin.fn_retirar(bigint, bigint, numeric, uuid, text),
  fin.fn_transferir(bigint, bigint, bigint, numeric, uuid, text),
  fin.fn_crear_ajuste(bigint, bigint, numeric, char, uuid, text),
  fin.fn_registrar_rechazo(bigint, text, bigint, bigint, numeric, uuid, text)
TO banco_cajero;

-- 17.4 banco_supervisor -------------------------------------------------
GRANT banco_cajero TO banco_supervisor;
GRANT EXECUTE ON FUNCTION
  core.fn_desbloquear_cuenta(bigint, bigint),
  core.fn_cambiar_limite(bigint, bigint, numeric),
  core.fn_cerrar_cuenta(bigint, bigint),
  fin.fn_reversar(bigint, bigint, uuid, text),
  fin.fn_aprobar_ajuste(bigint, bigint),
  fin.fn_rechazar_ajuste(bigint, bigint, text)
TO banco_supervisor;
GRANT EXECUTE ON PROCEDURE core.pr_inactivar_cuentas_sin_movimiento(bigint, integer, integer) TO banco_supervisor;

-- 17.5 banco_auditor ----------------------------------------------------
GRANT USAGE  ON SCHEMA ref, seg, core, fin, aud TO banco_auditor;
GRANT SELECT ON ALL TABLES IN SCHEMA ref, seg, core, fin, aud TO banco_auditor;

-- 17.6 banco_admin_seg --------------------------------------------------
GRANT USAGE ON SCHEMA seg, ref TO banco_admin_seg;
GRANT SELECT ON seg.rol, seg.permiso, ref.oficina, ref.tipo_documento TO banco_admin_seg;
GRANT SELECT, INSERT, UPDATE ON seg.usuario, seg.usuario_rol, seg.rol_permiso TO banco_admin_seg;
GRANT USAGE ON SEQUENCE seg.usuario_usuario_id_seq TO banco_admin_seg;
-- Sin DELETE: los roles se revocan con fecha (vigente_hasta), no se borran.
