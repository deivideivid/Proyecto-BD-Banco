-- =====================================================================
-- 10_audit.sql · Banco Andino Colombia
-- Registro de auditoría (RN-52, RN-53).
-- Se ejecuta desde sql/run_all.sql (no abre ni cierra transacción).
-- =====================================================================

-- =====================================================================
-- 10. AUDITORÍA
-- =====================================================================

CREATE TABLE aud.log_auditoria (
  auditoria_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ocurrido_en      timestamptz  NOT NULL DEFAULT clock_timestamp(),
  usuario_id       bigint       REFERENCES seg.usuario (usuario_id),
  usuario_bd       text         NOT NULL DEFAULT session_user,
  esquema          varchar(63)  NOT NULL,
  tabla            varchar(63)  NOT NULL,
  registro         jsonb        NOT NULL,
  operacion        varchar(8)   NOT NULL CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
  valores_antes    jsonb,
  valores_despues  jsonb,
  CONSTRAINT ck_auditoria_imagenes CHECK (
       (operacion = 'INSERT' AND valores_antes IS NULL     AND valores_despues IS NOT NULL)
    OR (operacion = 'UPDATE' AND valores_antes IS NOT NULL AND valores_despues IS NOT NULL)
    OR (operacion = 'DELETE' AND valores_antes IS NOT NULL AND valores_despues IS NULL)
  )
);
COMMENT ON TABLE aud.log_auditoria IS 'Quién, qué, cuándo, sobre qué registro y valores antes/después de operaciones críticas (RN-52). Solo inserción (RN-53, se protege en G3).';
COMMENT ON COLUMN aud.log_auditoria.registro IS 'Clave primaria del registro afectado, por ejemplo {"cuenta_id": 125}.';
