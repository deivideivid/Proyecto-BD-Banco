-- =====================================================================
-- Pruebas de concurrencia · Preparación (G3)
-- ¡Usar una base DE PRUEBAS aparte! Estas pruebas necesitan datos
-- confirmados (COMMIT) porque participan dos sesiones distintas.
--
--   psql -U postgres -c "CREATE DATABASE banco_andino_ct"
--   psql -U postgres -d banco_andino_ct -f sql/run_all.sql
--   psql -U postgres -d banco_andino_ct -f sql/tests/concurrencia/ct_00_preparar.sql
--
-- Luego cada prueba se corre en DOS ventanas de SQL Shell (ver LEEME.md).
-- =====================================================================
\set ON_ERROR_STOP on
\set QUIET on

DO $$
BEGIN
  IF current_database() = 'banco_andino_lab' THEN
    RAISE EXCEPTION 'No ejecute las pruebas de concurrencia en la base del laboratorio: use banco_andino_ct';
  END IF;
END $$;

DROP TABLE IF EXISTS public.ct_ctx;
CREATE TABLE public.ct_ctx (clave text PRIMARY KEY, valor bigint, llave uuid);

INSERT INTO ref.departamento VALUES ('17', 'Caldas') ON CONFLICT DO NOTHING;
INSERT INTO ref.municipio VALUES ('17001', '17', 'Manizales') ON CONFLICT DO NOTHING;

DO $$
DECLARE
  v_ofi int; v_caj bigint; v_sup bigint; v_cli1 bigint; v_cli2 bigint;
  c1 bigint; c2 bigint; c3 bigint; c4 bigint; v_tx bigint;
BEGIN
  INSERT INTO ref.oficina (codigo, nombre, municipio_codigo) VALUES ('CT-01', 'Oficina concurrencia', '17001')
  RETURNING oficina_id INTO v_ofi;
  INSERT INTO seg.usuario (login, tipo_documento, numero_documento, nombres, apellidos, oficina_id)
  VALUES ('ct_cajero', 'CC', '98000001', 'Caja', 'Concurrente', v_ofi) RETURNING usuario_id INTO v_caj;
  INSERT INTO seg.usuario (login, tipo_documento, numero_documento, nombres, apellidos, oficina_id)
  VALUES ('ct_super', 'CC', '98000002', 'Super', 'Concurrente', v_ofi) RETURNING usuario_id INTO v_sup;
  INSERT INTO seg.usuario_rol (usuario_id, rol_id) VALUES
    (v_caj, (SELECT rol_id FROM seg.rol WHERE codigo = 'CAJERO')),
    (v_sup, (SELECT rol_id FROM seg.rol WHERE codigo = 'SUPERVISOR'));

  v_cli1 := core.fn_crear_cliente_natural(v_caj, 'CC', '1980000001', 'Uno', 'Concurrente', DATE '1990-01-01', '17001');
  v_cli2 := core.fn_crear_cliente_natural(v_caj, 'CC', '1980000002', 'Dos', 'Concurrente', DATE '1990-01-01', '17001');
  c1 := core.fn_abrir_cuenta(v_caj, v_cli1, 'AHORROS', 'COP', v_ofi, 3000000);   -- CT-1 doble retiro
  c2 := core.fn_abrir_cuenta(v_caj, v_cli1, 'AHORROS', 'COP', v_ofi, 3000000);   -- CT-2 origen/destino
  c3 := core.fn_abrir_cuenta(v_caj, v_cli2, 'AHORROS', 'COP', v_ofi, 3000000);   -- CT-2 origen/destino
  c4 := core.fn_abrir_cuenta(v_caj, v_cli2, 'AHORROS', 'COP', v_ofi, 3000000);   -- CT-3 y CT-4
  PERFORM core.fn_activar_cuenta(v_caj, x) FROM unnest(ARRAY[c1, c2, c3, c4]) x;

  PERFORM fin.fn_consignar(v_caj, c1, 100000, gen_random_uuid());
  PERFORM fin.fn_consignar(v_caj, c2, 500000, gen_random_uuid());
  PERFORM fin.fn_consignar(v_caj, c3, 500000, gen_random_uuid());
  v_tx := fin.fn_consignar(v_caj, c4, 300000, gen_random_uuid());

  INSERT INTO public.ct_ctx (clave, valor, llave) VALUES
    ('cajero', v_caj, NULL), ('super', v_sup, NULL),
    ('c1', c1, NULL), ('c2', c2, NULL), ('c3', c3, NULL), ('c4', c4, NULL),
    ('tx_a_reversar', v_tx, NULL),
    ('llave_ct3', NULL, gen_random_uuid()), ('llave_ct4_a', NULL, gen_random_uuid()), ('llave_ct4_b', NULL, gen_random_uuid());
END $$;

\echo 'Preparación lista: 4 cuentas con saldo inicial (c1 = 100.000, c2 = c3 = 500.000, c4 = 300.000)'
