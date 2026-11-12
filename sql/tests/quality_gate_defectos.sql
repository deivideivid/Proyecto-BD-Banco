-- =====================================================================
-- quality_gate_defectos.sql · Banco Andino Colombia · G6
-- "Prueba de las pruebas": demuestra que sql/quality_gate.sql SÍ detecta
-- errores. Trabaja sobre una COPIA de la base; la base real no se toca.
--
--   1. Copia banco_andino_lab → banco_andino_qg
--   2. Mete 7 defectos a propósito (saltándose constraints y triggers,
--      como lo haría una carga mal hecha o un cambio manual)
--   3. Corre el quality gate sobre la copia → debe dar QUALITY_GATE = FAIL
--   4. Muestra qué prueba detectó cada defecto y borra la copia
--
-- Requisitos: banco_andino_lab cargada y NADIE más conectado a ella
-- (cierre pgAdmin o desconéctelo de esa base; si no, la copia falla).
-- Uso (desde la carpeta lab-postgresql-banco-ia, como postgres):
--   psql -U postgres -d postgres -f sql/tests/quality_gate_defectos.sql
--   SQL Shell: \cd 'C:/…/lab-postgresql-banco-ia'   \i sql/tests/quality_gate_defectos.sql
-- Guarda el detalle en evidence/g6_defectos_results.csv. Tarda 1-3 min.
-- =====================================================================

\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';   -- SQL Shell de Windows no usa UTF-8 por defecto: sin esto las tildes se dañan
\set QUIET on
SET client_min_messages = warning;

\echo '== 1) Copiando banco_andino_lab en banco_andino_qg'
\c postgres
DROP DATABASE IF EXISTS banco_andino_qg;
CREATE DATABASE banco_andino_qg TEMPLATE banco_andino_lab STRATEGY = FILE_COPY;
\c banco_andino_qg
SET client_min_messages = warning;

\echo '== 2) Metiendo 7 defectos en la copia'
BEGIN;
ALTER TABLE fin.asiento_contable       DISABLE TRIGGER USER;
ALTER TABLE fin.transaccion_financiera DISABLE TRIGGER USER;
ALTER TABLE core.cuenta                DISABLE TRIGGER USER;
ALTER TABLE core.cliente               DISABLE TRIGGER USER;
ALTER TABLE core.persona_natural       DISABLE TRIGGER USER;
ALTER TABLE core.titularidad_cuenta    DISABLE TRIGGER USER;

-- D1 · Ledger descuadrado: a una línea de asiento le suman 1.000 (el débito ya no iguala al crédito)
UPDATE fin.asiento_contable SET valor = valor + 1000
WHERE (transaccion_id, linea) = (SELECT a.transaccion_id, a.linea FROM fin.asiento_contable a
                                 WHERE a.cuenta_id IS NOT NULL ORDER BY a.transaccion_id, a.linea LIMIT 1);

-- D2 · Saldo alterado a mano: +50.000 en una cuenta activa sin transacción que lo respalde
UPDATE core.cuenta SET saldo_contable = saldo_contable + 50000
WHERE cuenta_id = (SELECT min(cuenta_id) FROM core.cuenta WHERE estado_cuenta = 'ACTIVA');

-- D3 · Movimiento después del cierre: la última transacción de una cuenta cerrada pasa a 10 días después del cierre
WITH c AS (SELECT cuenta_id, fecha_cierre + interval '10 days' AS nueva
           FROM core.cuenta WHERE estado_cuenta = 'CERRADA' ORDER BY cuenta_id LIMIT 1),
     x AS (SELECT max(a.transaccion_id) AS transaccion_id, c.nueva
           FROM fin.asiento_contable a JOIN c ON a.cuenta_id = c.cuenta_id GROUP BY c.nueva)
UPDATE fin.transaccion_financiera t
SET fecha_contabilizacion = x.nueva,
    fecha_contable = (x.nueva AT TIME ZONE 'America/Bogota')::date
FROM x
WHERE t.transaccion_id = x.transaccion_id;

-- D4 · Documento duplicado: se quita la restricción UNIQUE y un cliente copia el documento de otro
ALTER TABLE core.cliente DROP CONSTRAINT uq_cliente_documento;
UPDATE core.cliente d SET tipo_documento = o.tipo_documento, numero_documento = o.numero_documento
FROM (SELECT min(cliente_id) AS id FROM core.cliente WHERE tipo_cliente = 'NATURAL') x,
     core.cliente o
WHERE o.cliente_id = x.id
  AND d.cliente_id = (SELECT min(cliente_id) FROM core.cliente WHERE tipo_cliente = 'NATURAL' AND cliente_id > x.id);

-- D5 · Titularidad huérfana: se quita la FK y se registra un titular que no existe (cliente 999999)
ALTER TABLE core.titularidad_cuenta DROP CONSTRAINT titularidad_cuenta_cliente_id_fkey;
INSERT INTO core.titularidad_cuenta (cuenta_id, cliente_id, vigente_desde, rol_titular)
SELECT min(cuenta_id), 999999, now(), 'COTITULAR' FROM core.cuenta WHERE estado_cuenta = 'ACTIVA';

-- D6 · Persona natural sin nombre
UPDATE core.persona_natural SET nombres = ''
WHERE cliente_id = (SELECT max(cliente_id) FROM core.persona_natural);

ALTER TABLE fin.asiento_contable       ENABLE TRIGGER USER;
ALTER TABLE fin.transaccion_financiera ENABLE TRIGGER USER;
ALTER TABLE core.cuenta                ENABLE TRIGGER USER;
ALTER TABLE core.cliente               ENABLE TRIGGER USER;
ALTER TABLE core.persona_natural       ENABLE TRIGGER USER;
ALTER TABLE core.titularidad_cuenta    ENABLE TRIGGER USER;

-- D7 · Auditoría apagada: alguien desactiva el trigger de auditoría de clientes y lo deja así
ALTER TABLE core.cliente DISABLE TRIGGER trg_auditar_cliente;
COMMIT;

\echo '== 3) Quality gate sobre la copia con defectos'
\set qg_sin_csv true
\ir ../quality_gate.sql

\echo '== 4) ¿Qué prueba detectó cada defecto?'
SELECT d.defecto, d.descripcion, string_agg(q.test_id || ' ' || q.resultado, ', ' ORDER BY q.test_id) AS detectado_por,
       CASE WHEN bool_or(q.resultado = 'FAIL') THEN 'DETECTADO' ELSE 'NO DETECTADO' END AS estado
FROM (VALUES ('D1', 'Ledger descuadrado',              ARRAY['F01', 'S01', 'S02']),
             ('D2', 'Saldo alterado a mano',           ARRAY['S01', 'S02']),
             ('D3', 'Movimiento después del cierre',   ARRAY['T01', 'T02']),
             ('D4', 'Documento de cliente duplicado',  ARRAY['U01']),
             ('D5', 'Titularidad huérfana',            ARRAY['R01', 'N02']),
             ('D6', 'Persona natural sin nombre',      ARRAY['C02']),
             ('D7', 'Trigger de auditoría desactivado', ARRAY['A01'])) AS d(defecto, descripcion, pruebas)
JOIN qg q ON q.test_id = ANY (d.pruebas)
GROUP BY d.defecto, d.descripcion ORDER BY d.defecto;

\copy (SELECT test_id, categoria, dimension, regla, tabla, esperado, obtenido, severidad, resultado, detalle FROM qg ORDER BY test_id) TO 'evidence/g6_defectos_results.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\echo 'Detalle guardado en evidence/g6_defectos_results.csv'

\echo '== 5) Borrando la copia'
\c postgres
DROP DATABASE banco_andino_qg;
\echo '== Listo: la base real banco_andino_lab no se modificó'
