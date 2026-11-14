-- =====================================================================
-- g8_erd_desde_catalogo.sql · Banco Andino Colombia · G8
-- Genera el ERD final (Mermaid) LEYENDO EL CATÁLOGO de PostgreSQL, es decir,
-- desde el modelo realmente implementado y no desde un dibujo. Así el ERD
-- coincide por construcción con el DDL ejecutado.
--   Entidades: las 28 tablas de ref, seg, core, fin y aud con sus columnas
--              (PK, FK, UK) · Relaciones: las 42 claves foráneas.
--   Cardinalidad: lado padre || si la FK es NOT NULL, |o si admite NULL;
--                 lado hijo o| si la FK también es única (1:1), o{ si no (1:N).
-- Uso (desde la carpeta lab-postgresql-banco-ia):
--   psql -U postgres -d banco_andino_lab -f sql/tests/g8_erd_desde_catalogo.sql
--   → docs/erd_final.mmd (se ve en https://mermaid.live o en GitHub)
-- =====================================================================
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';
\set QUIET on

SET client_min_messages = warning;
DROP TABLE IF EXISTS pg_temp.erd;
CREATE TEMP TABLE erd AS
WITH tablas AS (
  SELECT c.oid, n.nspname || '_' || c.relname AS ent, n.nspname || '.' || c.relname AS nombre
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'r' AND n.nspname IN ('ref', 'seg', 'core', 'fin', 'aud')
),
cols AS (
  SELECT t.ent, a.attnum,
         CASE ty.typname WHEN 'int8' THEN 'bigint' WHEN 'int4' THEN 'integer' WHEN 'int2' THEN 'smallint'
                         WHEN 'bpchar' THEN 'char' WHEN 'bool' THEN 'boolean' ELSE ty.typname END AS tipo,
         a.attname,
         EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = t.oid AND k.contype = 'p' AND a.attnum = ANY (k.conkey)) AS es_pk,
         EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = t.oid AND k.contype = 'f' AND a.attnum = ANY (k.conkey)) AS es_fk,
         EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = t.oid AND k.contype = 'u' AND k.conkey = ARRAY[a.attnum]) AS es_uk
  FROM tablas t
  JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum > 0 AND NOT a.attisdropped
  JOIN pg_type ty ON ty.oid = a.atttypid
),
lineas AS (
  SELECT 0 AS grupo, ''::text AS ent, 0 AS orden, 'erDiagram' AS linea
  UNION ALL
  SELECT 1, t.ent, -1, '  ' || t.ent || '["' || t.nombre || '"] {' FROM tablas t
  UNION ALL
  SELECT 1, c.ent, c.attnum,
         '    ' || c.tipo || ' ' || c.attname ||
         coalesce(' ' || nullif(concat_ws(', ', CASE WHEN c.es_pk THEN 'PK' END, CASE WHEN c.es_fk THEN 'FK' END,
                                               CASE WHEN c.es_uk AND NOT c.es_pk THEN 'UK' END), ''), '')
  FROM cols c
  UNION ALL
  SELECT 1, t.ent, 100000, '  }' FROM tablas t
  UNION ALL
  SELECT 2, h.ent, row_number() OVER (PARTITION BY h.ent ORDER BY cols_txt)::int,
         '  ' || p.ent || ' ' ||
         CASE WHEN nulas THEN '|o' ELSE '||' END || '--' || CASE WHEN unica THEN 'o|' ELSE 'o{' END ||
         ' ' || h.ent || ' : "' || cols_txt || '"'
  FROM (
    SELECT k.conrelid, k.confrelid,
           (SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM unnest(k.conkey) WITH ORDINALITY x(n, i)
            JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = x.n) AS cols_txt,
           EXISTS (SELECT 1 FROM unnest(k.conkey) x(n) JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = x.n
                   WHERE NOT a.attnotnull) AS nulas,
           EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = k.conrelid AND i.indisunique AND i.indpred IS NULL
                     AND (i.indkey::int2[])[0:i.indnkeyatts - 1] <@ k.conkey) AS unica
    FROM pg_constraint k
    WHERE k.contype = 'f' AND k.connamespace::regnamespace::text IN ('ref', 'seg', 'core', 'fin', 'aud')
  ) f
  JOIN tablas h ON h.oid = f.conrelid
  JOIN tablas p ON p.oid = f.confrelid
)
SELECT row_number() OVER (ORDER BY grupo, ent, orden) AS n, linea FROM lineas;

\copy (SELECT linea FROM erd ORDER BY n) TO 'docs/erd_final.mmd'
SELECT (SELECT count(*) FROM erd WHERE linea LIKE '%["%"] {') AS entidades,
       (SELECT count(*) FROM erd WHERE linea LIKE '% : "%"') AS relaciones;
\echo 'ERD generado en docs/erd_final.mmd'
