-- =====================================================================
-- Banco Andino Colombia · Carga del LOTE 1 (datos sintéticos)
--   Geografía (muestra DIVIPOLA) · oficinas · usuarios internos
--   10.000 clientes · 50.000 cuentas · titularidades · eventos
--
-- Requisitos:
--   1. Tablas creadas con sql/tablas_banco_andino.sql
--   2. CSV generados con: python src/generate_data.py
--
-- Ejecutar DESDE LA RAÍZ DEL REPOSITORIO (las rutas de \copy son relativas):
--   psql -h localhost -U postgres -d banco_andino_lab -f sql/load/carga_lote1.sql
--
-- Todo se carga en una sola transacción: si algo falla, no queda nada a medias.
-- =====================================================================

\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

BEGIN;

-- 1. Geografía
\copy ref.departamento (departamento_codigo, nombre) FROM 'data/lote1/departamento.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy ref.municipio (municipio_codigo, departamento_codigo, nombre) FROM 'data/lote1/municipio.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy ref.oficina (oficina_id, codigo, nombre, municipio_codigo) FROM 'data/lote1/oficina.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- 2. Usuarios internos y roles (el rol llega por código y se traduce a rol_id)
\copy seg.usuario (usuario_id, login, tipo_documento, numero_documento, nombres, apellidos, oficina_id, estado, creado_en) FROM 'data/lote1/usuario.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

CREATE TEMP TABLE tmp_usuario_rol (
  usuario_id     bigint,
  rol_codigo     varchar(30),
  vigente_desde  timestamptz,
  vigente_hasta  timestamptz,
  asignado_por   bigint
) ON COMMIT DROP;
\copy tmp_usuario_rol FROM 'data/lote1/usuario_rol.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

INSERT INTO seg.usuario_rol (usuario_id, rol_id, vigente_desde, vigente_hasta, asignado_por)
SELECT t.usuario_id, r.rol_id, t.vigente_desde, t.vigente_hasta, t.asignado_por
FROM tmp_usuario_rol t
JOIN seg.rol r ON r.codigo = t.rol_codigo;

-- 3. Clientes
\copy core.cliente (cliente_id, tipo_cliente, tipo_documento, numero_documento, digito_verificacion, municipio_codigo, estado_cliente, fecha_vinculacion, email, telefono) FROM 'data/lote1/cliente.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy core.persona_natural (cliente_id, nombres, apellidos, fecha_nacimiento) FROM 'data/lote1/persona_natural.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy core.persona_juridica (cliente_id, razon_social, fecha_constitucion, actividad_economica) FROM 'data/lote1/persona_juridica.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- 4. Cuentas, titularidad y eventos
\copy core.cuenta (cuenta_id, numero_cuenta, producto_codigo, moneda_codigo, oficina_id, estado_cuenta, fecha_apertura, fecha_cierre, saldo_contable, saldo_retenido, cupo_sobregiro, limite_retiro_diario) FROM 'data/lote1/cuenta.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy core.titularidad_cuenta (cuenta_id, cliente_id, vigente_desde, rol_titular, vigente_hasta) FROM 'data/lote1/titularidad_cuenta.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy core.evento_cuenta (evento_id, cuenta_id, tipo_evento, estado_anterior, estado_nuevo, motivo, ocurrido_en, registrado_por) FROM 'data/lote1/evento_cuenta.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy core.cambio_limite (evento_id, valor_anterior, valor_nuevo) FROM 'data/lote1/cambio_limite.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- 5. Sincronizar secuencias de identidad.
--    La carga con IDs explícitos NO avanza las secuencias: sin este paso, el
--    primer INSERT normal fallaría con "duplicate key".
SELECT setval(pg_get_serial_sequence('ref.oficina',        'oficina_id'), (SELECT max(oficina_id) FROM ref.oficina));
SELECT setval(pg_get_serial_sequence('seg.usuario',        'usuario_id'), (SELECT max(usuario_id) FROM seg.usuario));
SELECT setval(pg_get_serial_sequence('core.cliente',       'cliente_id'), (SELECT max(cliente_id) FROM core.cliente));
SELECT setval(pg_get_serial_sequence('core.cuenta',        'cuenta_id'),  (SELECT max(cuenta_id)  FROM core.cuenta));
SELECT setval(pg_get_serial_sequence('core.evento_cuenta', 'evento_id'),  (SELECT max(evento_id)  FROM core.evento_cuenta));

COMMIT;

-- 6. Estadísticas para el planificador
ANALYZE ref.departamento, ref.municipio, ref.oficina, seg.usuario, seg.usuario_rol,
        core.cliente, core.persona_natural, core.persona_juridica, core.cuenta,
        core.titularidad_cuenta, core.evento_cuenta, core.cambio_limite;

-- =====================================================================
-- 7. VALIDACIÓN DEL LOTE (reglas que las tablas no garantizan solas)
--    Resultado esperado: todas las filas en PASS.
-- =====================================================================
WITH primer_evento AS (
  SELECT DISTINCT ON (cuenta_id) cuenta_id, tipo_evento
  FROM core.evento_cuenta
  ORDER BY cuenta_id, ocurrido_en, evento_id
), ultimo_evento AS (
  SELECT DISTINCT ON (cuenta_id) cuenta_id, estado_nuevo
  FROM core.evento_cuenta
  ORDER BY cuenta_id, ocurrido_en DESC, evento_id DESC
), ultimo_cambio AS (
  SELECT DISTINCT ON (e.cuenta_id) e.cuenta_id, cl.valor_nuevo
  FROM core.evento_cuenta e
  JOIN core.cambio_limite cl ON cl.evento_id = e.evento_id
  ORDER BY e.cuenta_id, e.ocurrido_en DESC
), controles (orden, control, esperado, obtenido) AS (
  VALUES
  (1,  'Clientes',                                          10000::bigint, (SELECT count(*) FROM core.cliente)),
  (2,  'Personas naturales',                                8500,  (SELECT count(*) FROM core.persona_natural)),
  (3,  'Personas jurídicas',                                1500,  (SELECT count(*) FROM core.persona_juridica)),
  (4,  'Cuentas',                                           50000, (SELECT count(*) FROM core.cuenta)),
  (5,  'RN-02 clientes sin subtipo o con ambos',            0,
       (SELECT count(*) FROM core.cliente c
        WHERE (EXISTS (SELECT 1 FROM core.persona_natural n WHERE n.cliente_id = c.cliente_id))
            = (EXISTS (SELECT 1 FROM core.persona_juridica j WHERE j.cliente_id = c.cliente_id)))),
  (6,  'RN-08 titulares menores de 18 años al abrir',       0,
       (SELECT count(*) FROM core.titularidad_cuenta t
        JOIN core.cuenta c          ON c.cuenta_id = t.cuenta_id
        JOIN core.persona_natural p ON p.cliente_id = t.cliente_id
        WHERE (c.fecha_apertura AT TIME ZONE 'America/Bogota')::date < p.fecha_nacimiento + INTERVAL '18 years')),
  (7,  'RN-13 cuentas no cerradas sin exactamente 1 principal', 0,
       (SELECT count(*) FROM core.cuenta c
        WHERE c.estado_cuenta <> 'CERRADA'
          AND (SELECT count(*) FROM core.titularidad_cuenta t
               WHERE t.cuenta_id = c.cuenta_id AND t.rol_titular = 'PRINCIPAL' AND t.vigente_hasta IS NULL) <> 1)),
  (8,  'RN-14/15 producto no permitido para el titular',   0,
       (SELECT count(*) FROM core.titularidad_cuenta t
        JOIN core.cuenta c   ON c.cuenta_id = t.cuenta_id
        JOIN core.producto p ON p.producto_codigo = c.producto_codigo
        JOIN core.cliente cl ON cl.cliente_id = t.cliente_id
        WHERE p.tipo_cliente_permitido IS NOT NULL AND p.tipo_cliente_permitido <> cl.tipo_cliente)),
  (9,  'RN-16 cuentas con más titulares que el máximo',    0,
       (SELECT count(*) FROM (
          SELECT c.cuenta_id FROM core.cuenta c
          JOIN core.producto p ON p.producto_codigo = c.producto_codigo
          JOIN core.titularidad_cuenta t ON t.cuenta_id = c.cuenta_id AND t.vigente_hasta IS NULL
          GROUP BY c.cuenta_id, p.max_titulares
          HAVING count(*) > p.max_titulares) x)),
  (10, 'RN-17 sobregiro fuera de CORRIENTE',                0,
       (SELECT count(*) FROM core.cuenta c JOIN core.producto p ON p.producto_codigo = c.producto_codigo
        WHERE c.cupo_sobregiro > 0 AND NOT p.permite_sobregiro)),
  (11, 'RN-23 primer evento distinto de CREACION',          0,
       (SELECT count(*) FROM core.cuenta c LEFT JOIN primer_evento pe ON pe.cuenta_id = c.cuenta_id
        WHERE pe.tipo_evento IS DISTINCT FROM 'CREACION')),
  (12, 'RN-25 estado distinto del último evento',           0,
       (SELECT count(*) FROM core.cuenta c JOIN ultimo_evento ue ON ue.cuenta_id = c.cuenta_id
        WHERE ue.estado_nuevo <> c.estado_cuenta)),
  (13, 'RN-27 límite distinto del último cambio',           0,
       (SELECT count(*) FROM core.cuenta c JOIN ultimo_cambio uc ON uc.cuenta_id = c.cuenta_id
        WHERE uc.valor_nuevo <> c.limite_retiro_diario)),
  (14, 'RN-28 desbloqueo/cierre/cambio sin SUPERVISOR',     0,
       (SELECT count(*) FROM core.evento_cuenta e
        WHERE e.tipo_evento IN ('DESBLOQUEO', 'CIERRE', 'CAMBIO_LIMITE')
          AND NOT EXISTS (SELECT 1 FROM seg.usuario_rol ur JOIN seg.rol r ON r.rol_id = ur.rol_id
                          WHERE ur.usuario_id = e.registrado_por AND r.codigo = 'SUPERVISOR'
                            AND ur.vigente_hasta IS NULL))),
  (15, 'RN-48 saldo distinto de 0 sin asientos contables',  0,
       (SELECT count(*) FROM core.cuenta WHERE saldo_contable <> 0)),
  (16, 'RN-54 usuarios que también son clientes',           0,
       (SELECT count(*) FROM seg.usuario u JOIN core.cliente c
          ON c.tipo_documento = u.tipo_documento AND c.numero_documento = u.numero_documento)),
  (17, 'Apertura anterior a la vinculación',                0,
       (SELECT count(*) FROM core.titularidad_cuenta t
        JOIN core.cuenta c  ON c.cuenta_id = t.cuenta_id
        JOIN core.cliente cl ON cl.cliente_id = t.cliente_id
        WHERE (c.fecha_apertura AT TIME ZONE 'America/Bogota')::date < cl.fecha_vinculacion)),
  (18, 'Clientes sin ninguna cuenta como titular principal', 0,
       (SELECT count(*) FROM core.cliente cl
        WHERE NOT EXISTS (SELECT 1 FROM core.titularidad_cuenta t
                          WHERE t.cliente_id = cl.cliente_id AND t.rol_titular = 'PRINCIPAL'))),
  (19, 'Clientes INACTIVO con titularidad vigente',         0,
       (SELECT count(*) FROM core.cliente cl
        WHERE cl.estado_cliente = 'INACTIVO'
          AND EXISTS (SELECT 1 FROM core.titularidad_cuenta t
                      WHERE t.cliente_id = cl.cliente_id AND t.vigente_hasta IS NULL))),
  (20, 'Personas naturales con más de 1 cuenta NOMINA', 0,
       (SELECT count(*) FROM (
          SELECT t.cliente_id FROM core.titularidad_cuenta t
          JOIN core.cuenta c ON c.cuenta_id = t.cuenta_id
          WHERE c.producto_codigo = 'NOMINA' AND t.rol_titular = 'PRINCIPAL'
          GROUP BY t.cliente_id HAVING count(*) > 1) x))
)
SELECT control, esperado, obtenido,
       CASE WHEN esperado = obtenido THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM controles
ORDER BY orden;

-- Distribuciones (informativas: deben verse NO uniformes)
SELECT estado_cuenta, count(*) AS cuentas, round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS porcentaje
FROM core.cuenta GROUP BY estado_cuenta ORDER BY cuentas DESC;

SELECT producto_codigo, count(*) AS cuentas
FROM core.cuenta GROUP BY producto_codigo ORDER BY cuentas DESC;

-- Cuentas por cliente (titular principal): debe haber cola larga (máximo >> mediana)
WITH por_cliente AS (
  SELECT cl.tipo_cliente, count(*) AS cuentas
  FROM core.titularidad_cuenta t
  JOIN core.cliente cl ON cl.cliente_id = t.cliente_id
  WHERE t.rol_titular = 'PRINCIPAL'
  GROUP BY cl.cliente_id, cl.tipo_cliente
)
SELECT tipo_cliente,
       count(*)                                                   AS clientes,
       sum(cuentas)                                               AS cuentas,
       round(avg(cuentas), 2)                                     AS promedio,
       percentile_cont(0.5)  WITHIN GROUP (ORDER BY cuentas)      AS mediana,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY cuentas)      AS p95,
       max(cuentas)                                               AS maximo
FROM por_cliente
GROUP BY tipo_cliente
ORDER BY tipo_cliente;

SELECT d.nombre AS departamento, count(*) AS clientes
FROM core.cliente c
JOIN ref.municipio m    ON m.municipio_codigo = c.municipio_codigo
JOIN ref.departamento d ON d.departamento_codigo = m.departamento_codigo
GROUP BY d.nombre ORDER BY clientes DESC LIMIT 10;

SELECT extract(year FROM fecha_vinculacion)::int AS anio, count(*) AS clientes_vinculados
FROM core.cliente GROUP BY 1 ORDER BY 1;
