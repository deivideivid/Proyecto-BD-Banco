-- =====================================================================
-- registrar_cargas_en_auditoria.sql  (G6 — corrección del hallazgo A04)
--
-- Problema: las cargas masivas (lote 1 y lote 2) se hicieron con los
-- triggers desactivados (decisión DC-07), así que aud.log_auditoria no
-- tenía ningún rastro de quién cargó, cuándo ni cuántas filas.
--
-- Solución: deja UNA fila de auditoría por tabla cargada con el usuario de
-- base de datos, la hora, el lote, el archivo y el número de filas.
-- Es idempotente: si la tabla ya tiene su registro de carga, no repite.
-- carga_lote1.sql y carga_lote2_transacciones.sql lo llaman al terminar
-- (con carga_en_curso = true). Ejecutado solo, sirve para bases cargadas
-- antes de G6 y marca los registros como retroactivos.
--
-- Uso (desde la raíz del repositorio, como dueño de la base):
--   psql -d banco_andino_lab -f sql/load/registrar_cargas_en_auditoria.sql
-- =====================================================================
\set ON_ERROR_STOP on
\if :{?carga_en_curso}
\else
\set carga_en_curso false
\endif
SELECT set_config('banco.registro_retroactivo', (NOT :'carga_en_curso'::boolean)::text, false) AS retroactivo \gset

BEGIN;

DO $$
DECLARE
  r record;
  n bigint;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('lote1', 'ref',  'departamento',           'data/lote1/departamento.csv'),
      ('lote1', 'ref',  'municipio',              'data/lote1/municipio.csv'),
      ('lote1', 'ref',  'oficina',                'data/lote1/oficina.csv'),
      ('lote1', 'seg',  'usuario',                'data/lote1/usuario.csv'),
      ('lote1', 'seg',  'usuario_rol',            'data/lote1/usuario_rol.csv'),
      ('lote1', 'core', 'cliente',                'data/lote1/cliente.csv'),
      ('lote1', 'core', 'persona_natural',        'data/lote1/persona_natural.csv'),
      ('lote1', 'core', 'persona_juridica',       'data/lote1/persona_juridica.csv'),
      ('lote1', 'core', 'cuenta',                 'data/lote1/cuenta.csv'),
      ('lote1', 'core', 'titularidad_cuenta',     'data/lote1/titularidad_cuenta.csv'),
      ('lote1', 'core', 'evento_cuenta',          'data/lote1/evento_cuenta.csv'),
      ('lote1', 'core', 'cambio_limite',          'data/lote1/cambio_limite.csv'),
      ('lote2', 'fin',  'transaccion_financiera', 'data/lote2/transaccion_financiera.csv'),
      ('lote2', 'fin',  'asiento_contable',       'data/lote2/asiento_contable.csv')
    ) AS v(lote, esquema, tabla, archivo)
  LOOP
    IF EXISTS (SELECT 1 FROM aud.log_auditoria l
               WHERE l.esquema = r.esquema AND l.tabla = r.tabla AND l.registro ->> 'carga' = r.lote) THEN
      RAISE NOTICE '% %.%: ya tenía registro de carga', r.lote, r.esquema, r.tabla;
      CONTINUE;
    END IF;
    EXECUTE format('SELECT count(*) FROM %I.%I', r.esquema, r.tabla) INTO n;
    IF n = 0 THEN
      RAISE NOTICE '% %.%: tabla vacía, no se registra', r.lote, r.esquema, r.tabla;
      CONTINUE;
    END IF;
    INSERT INTO aud.log_auditoria (usuario_bd, esquema, tabla, registro, operacion, valores_despues)
    VALUES (session_user, r.esquema, r.tabla,
            jsonb_build_object('carga', r.lote),
            'INSERT',
            jsonb_build_object('filas', n, 'archivo', r.archivo,
                               'descripcion', 'Carga masiva con \copy (triggers desactivados, DC-07)',
                               'registro_retroactivo', current_setting('banco.registro_retroactivo')::boolean));
    RAISE NOTICE '% %.%: registrada (% filas)', r.lote, r.esquema, r.tabla, n;
  END LOOP;

  -- El lote 2 también recalculó los saldos de las cuentas con un UPDATE masivo.
  IF EXISTS (SELECT 1 FROM fin.asiento_contable)
     AND NOT EXISTS (SELECT 1 FROM aud.log_auditoria l
                     WHERE l.esquema = 'core' AND l.tabla = 'cuenta' AND l.registro ->> 'carga' = 'lote2') THEN
    INSERT INTO aud.log_auditoria (usuario_bd, esquema, tabla, registro, operacion, valores_antes, valores_despues)
    SELECT session_user, 'core', 'cuenta', jsonb_build_object('carga', 'lote2'), 'UPDATE',
           jsonb_build_object('saldo_contable', 'saldos en 0 antes del lote 2'),
           jsonb_build_object('cuentas_con_saldo', count(*) FILTER (WHERE saldo_contable <> 0),
                              'descripcion', 'Saldos recalculados desde el ledger (Σ créditos − Σ débitos)',
                              'registro_retroactivo', current_setting('banco.registro_retroactivo')::boolean)
    FROM core.cuenta;
    RAISE NOTICE 'lote2 core.cuenta: registrado el recálculo de saldos';
  END IF;
END $$;

COMMIT;

SELECT registro ->> 'carga' AS lote, esquema || '.' || tabla AS tabla, operacion,
       coalesce(valores_despues ->> 'filas', valores_despues ->> 'cuentas_con_saldo') AS filas,
       usuario_bd, to_char(ocurrido_en AT TIME ZONE 'America/Bogota', 'YYYY-MM-DD HH24:MI') AS registrado
FROM aud.log_auditoria
WHERE registro ? 'carga'
ORDER BY auditoria_id;
