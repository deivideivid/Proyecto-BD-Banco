-- =====================================================================
-- g8_reconstruir_todo.sql · Banco Andino Colombia · G8
-- Reconstruye el laboratorio COMPLETO desde cero en un solo paso y
-- verifica los gates principales:
--   1. run_all.sql            modelo 00–17 + 49 pruebas de G3 (incluye los índices de G7)
--   2. carga_lote1.sql        10.000 clientes · 50.000 cuentas (+ registro en auditoría)
--   3. carga_lote2_…sql       1.000.000 transacciones POSTED · 2.000.000 asientos
--   4. perfil_datos_g4.sql    48 métricas de G4 → evidence/g4_data_profile.csv
--   5. quality_gate.sql       76 pruebas de G6 (sin sobrescribir la evidencia de G6)
--   6. g7_rbac_demo.sql       23 pruebas de permisos de G7
--   7. Resumen final
--
-- ¡Borra y recrea la base banco_andino_lab! Requisitos:
--   - La base banco_andino_lab existe (vacía o no).
--   - Los CSV del lote 2 existen: python src/generate_transactions.py
--   - Se ejecuta DESDE la carpeta lab-postgresql-banco-ia (rutas de \copy relativas).
-- Uso:
--   psql -U postgres -d banco_andino_lab -f sql/g8_reconstruir_todo.sql
--   SQL Shell: \cd 'C:/…/lab-postgresql-banco-ia'   \c banco_andino_lab   \i sql/g8_reconstruir_todo.sql
-- Tarda de 3 a 10 minutos según el computador.
-- Si después Git muestra evidence/g4_data_profile.csv SIN cambios, la
-- reconstrucción produjo exactamente los mismos datos.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';   -- SQL Shell de Windows no usa UTF-8 por defecto: sin esto las tildes se dañan
SELECT clock_timestamp() AS g8_inicio \gset

\echo '######## 1/6 · Modelo + pruebas de G3 (run_all.sql)'
\ir run_all.sql
\echo '######## 2/6 · Lote 1'
\ir load/carga_lote1.sql
\echo '######## 3/6 · Lote 2 (la parte más larga)'
\ir load/carga_lote2_transacciones.sql
\echo '######## 4/6 · Perfil de datos de G4'
\ir load/perfil_datos_g4.sql
\echo '######## 5/6 · Quality gate de G6'
\set qg_sin_csv true
\ir quality_gate.sql
SELECT count(*) FILTER (WHERE severidad = 'CRITICA' AND resultado = 'FAIL') AS g6_fails_criticos,
       (SELECT puntaje FROM puntaje WHERE dimension IS NULL) AS g6_puntaje FROM qg \gset
\echo '######## 6/6 · Permisos por rol de G7'
\ir tests/g7_rbac_demo.sql
SELECT count(*) FILTER (WHERE obtenido <> esperado) AS g7_rbac_fallas FROM rbac \gset

\set QUIET on
\pset footer off
\echo '######## RESUMEN FINAL G8'
SELECT x.control, x.esperado, x.obtenido, CASE WHEN x.ok THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM (VALUES
  ('Tablas del modelo (ERD final)',                 '28',      (SELECT count(*) FROM pg_tables WHERE schemaname IN ('ref','seg','core','fin','aud'))::text,
                                                               (SELECT count(*) FROM pg_tables WHERE schemaname IN ('ref','seg','core','fin','aud')) = 28),
  ('Claves foráneas (ERD final)',                   '42',      (SELECT count(*) FROM pg_constraint WHERE contype = 'f' AND connamespace::regnamespace::text IN ('ref','seg','core','fin','aud'))::text,
                                                               (SELECT count(*) FROM pg_constraint WHERE contype = 'f' AND connamespace::regnamespace::text IN ('ref','seg','core','fin','aud')) = 42),
  ('Clientes',                                      '10.000',  (SELECT count(*) FROM core.cliente)::text, (SELECT count(*) FROM core.cliente) = 10000),
  ('Cuentas',                                       '50.000',  (SELECT count(*) FROM core.cuenta)::text, (SELECT count(*) FROM core.cuenta) = 50000),
  ('Transacciones POSTED',                          '1.000.000', (SELECT count(*) FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED')::text,
                                                               (SELECT count(*) FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED') = 1000000),
  ('Asientos contables',                            '2.000.000', (SELECT count(*) FROM fin.asiento_contable)::text, (SELECT count(*) FROM fin.asiento_contable) = 2000000),
  ('Índices de G7',                                 '6',       (SELECT count(*) FROM pg_indexes WHERE indexname LIKE 'ix\_%')::text,
                                                               (SELECT count(*) FROM pg_indexes WHERE indexname LIKE 'ix\_%') = 6),
  ('Cargas registradas en la auditoría (G6, A04)',  '15',      (SELECT count(*) FROM aud.log_auditoria WHERE registro ? 'carga')::text,
                                                               (SELECT count(*) FROM aud.log_auditoria WHERE registro ? 'carga') = 15),
  ('G6 · fallas críticas del quality gate',         '0',       :'g6_fails_criticos', :'g6_fails_criticos' = '0'),
  ('G6 · puntaje general',                          '≥ 99',    :'g6_puntaje', :'g6_puntaje'::numeric >= 99),
  ('G7 · fallas en las pruebas de permisos',        '0',       :'g7_rbac_fallas', :'g7_rbac_fallas' = '0')
) AS x(control, esperado, obtenido, ok);

SELECT CASE WHEN :'g6_fails_criticos' = '0' AND :'g7_rbac_fallas' = '0'
             AND (SELECT count(*) FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED') = 1000000
            THEN 'G8 RECONSTRUCCIÓN = PASS' ELSE 'G8 RECONSTRUCCIÓN = FAIL' END AS veredicto,
       to_char(clock_timestamp() - :'g8_inicio'::timestamptz, 'MI "min" SS "s"') AS duracion;
