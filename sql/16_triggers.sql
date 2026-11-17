-- =====================================================================
-- 16_triggers.sql · Banco Andino Colombia
-- Reglas que ni las columnas ni los CHECK pueden garantizar solos
-- (dependen de otras tablas, del tiempo o del estado).
--
-- Carga masiva (lotes 1 y 2): los scripts de sql/load desactivan estos
-- triggers con ALTER TABLE … DISABLE TRIGGER USER (solo el dueño de la
-- tabla puede hacerlo) y validan después con consultas de conjunto.
--
-- Se ejecuta desde sql/run_all.sql (no abre ni cierra transacción).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 16.1 Inmutabilidad (RN-40, RN-53) y no borrado (RN-09)
-- ---------------------------------------------------------------------

-- Transacciones: POSTED y REJECTED no cambian nunca. La única actualización
-- permitida es resolver un ajuste PENDING_APPROVAL (aprobar o rechazar).
CREATE FUNCTION fin.trg_transaccion_inmutable() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Las transacciones no se eliminan (transacción %)', OLD.transaccion_id USING ERRCODE = 'BA007';
  END IF;
  IF OLD.estado_codigo = 'PENDING_APPROVAL'
     AND NEW.estado_codigo IN ('POSTED', 'REJECTED')
     AND (NEW.tipo_codigo, NEW.cuenta_origen_id, NEW.cuenta_destino_id, NEW.monto, NEW.idempotency_key,
          NEW.hash_solicitud, NEW.transaccion_reversada_id, NEW.descripcion, NEW.fecha_solicitud, NEW.creado_por)
         IS NOT DISTINCT FROM
         (OLD.tipo_codigo, OLD.cuenta_origen_id, OLD.cuenta_destino_id, OLD.monto, OLD.idempotency_key,
          OLD.hash_solicitud, OLD.transaccion_reversada_id, OLD.descripcion, OLD.fecha_solicitud, OLD.creado_por)
  THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'La transacción % (%) es inmutable: los errores se corrigen con un reverso (RN-40, RN-41)',
    OLD.transaccion_id, OLD.estado_codigo USING ERRCODE = 'BA007';
END $$;

CREATE TRIGGER trg_transaccion_inmutable
  BEFORE UPDATE OR DELETE ON fin.transaccion_financiera
  FOR EACH ROW EXECUTE FUNCTION fin.trg_transaccion_inmutable();

-- Asientos y auditoría: nunca se modifican ni se borran
CREATE FUNCTION fin.trg_prohibir_cambios() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  RAISE EXCEPTION '% no permite % (registro inmutable)', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, TG_OP
    USING ERRCODE = 'BA007';
END $$;

CREATE TRIGGER trg_asiento_inmutable
  BEFORE UPDATE OR DELETE ON fin.asiento_contable
  FOR EACH ROW EXECUTE FUNCTION fin.trg_prohibir_cambios();
CREATE TRIGGER trg_auditoria_inmutable
  BEFORE UPDATE OR DELETE ON aud.log_auditoria
  FOR EACH ROW EXECUTE FUNCTION fin.trg_prohibir_cambios();            -- RN-53

-- TRUNCATE no dispara triggers de fila: se bloquea con triggers de sentencia
CREATE TRIGGER trg_transaccion_sin_truncate BEFORE TRUNCATE ON fin.transaccion_financiera
  FOR EACH STATEMENT EXECUTE FUNCTION fin.trg_prohibir_cambios();
CREATE TRIGGER trg_asiento_sin_truncate BEFORE TRUNCATE ON fin.asiento_contable
  FOR EACH STATEMENT EXECUTE FUNCTION fin.trg_prohibir_cambios();
CREATE TRIGGER trg_auditoria_sin_truncate BEFORE TRUNCATE ON aud.log_auditoria
  FOR EACH STATEMENT EXECUTE FUNCTION fin.trg_prohibir_cambios();

-- Clientes, cuentas, titularidades y eventos: se inactivan o se cierran, no se borran (RN-09)
CREATE FUNCTION core.trg_no_borrar() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'No se eliminan registros de % (se inactivan o se cierran, RN-09)', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME
    USING ERRCODE = 'BA007';
END $$;

CREATE TRIGGER trg_cliente_no_borrar          BEFORE DELETE ON core.cliente            FOR EACH ROW EXECUTE FUNCTION core.trg_no_borrar();
CREATE TRIGGER trg_persona_natural_no_borrar  BEFORE DELETE ON core.persona_natural    FOR EACH ROW EXECUTE FUNCTION core.trg_no_borrar();
CREATE TRIGGER trg_persona_juridica_no_borrar BEFORE DELETE ON core.persona_juridica   FOR EACH ROW EXECUTE FUNCTION core.trg_no_borrar();
CREATE TRIGGER trg_cuenta_no_borrar           BEFORE DELETE ON core.cuenta             FOR EACH ROW EXECUTE FUNCTION core.trg_no_borrar();
CREATE TRIGGER trg_titularidad_no_borrar      BEFORE DELETE ON core.titularidad_cuenta FOR EACH ROW EXECUTE FUNCTION core.trg_no_borrar();
CREATE TRIGGER trg_evento_no_borrar           BEFORE DELETE ON core.evento_cuenta      FOR EACH ROW EXECUTE FUNCTION core.trg_no_borrar();
CREATE TRIGGER trg_cambio_limite_no_borrar    BEFORE DELETE ON core.cambio_limite      FOR EACH ROW EXECUTE FUNCTION core.trg_no_borrar();

-- ---------------------------------------------------------------------
-- 16.2 Doble partida (RN-45 a RN-47) y coherencia del asiento (G2, H-03)
-- ---------------------------------------------------------------------

-- Cada línea: la transacción debe estar POSTED; las cuentas de depósito llevan
-- cuenta de cliente y deben coincidir con el producto de esa cuenta.
CREATE FUNCTION fin.trg_asiento_coherente() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_estado text; v_deposito boolean; v_cc_producto text;
BEGIN
  SELECT estado_codigo INTO v_estado FROM fin.transaccion_financiera WHERE transaccion_id = NEW.transaccion_id;
  IF v_estado IS DISTINCT FROM 'POSTED' THEN
    RAISE EXCEPTION 'Solo las transacciones POSTED tienen asientos (transacción %, estado %)', NEW.transaccion_id, v_estado
      USING ERRCODE = 'BA014';   -- RN-45
  END IF;
  SELECT es_deposito_cliente INTO v_deposito FROM ref.cuenta_contable WHERE cuenta_contable_codigo = NEW.cuenta_contable_codigo;
  IF v_deposito IS DISTINCT FROM (NEW.cuenta_id IS NOT NULL) THEN
    RAISE EXCEPTION 'La cuenta contable % % cuenta de cliente', NEW.cuenta_contable_codigo,
      CASE WHEN v_deposito THEN 'exige' ELSE 'no admite' END USING ERRCODE = 'BA014';
  END IF;
  IF NEW.cuenta_id IS NOT NULL THEN
    SELECT p.cuenta_contable_codigo INTO v_cc_producto
    FROM core.cuenta c JOIN core.producto p ON p.producto_codigo = c.producto_codigo
    WHERE c.cuenta_id = NEW.cuenta_id;
    IF v_cc_producto IS DISTINCT FROM NEW.cuenta_contable_codigo THEN
      RAISE EXCEPTION 'La cuenta % pertenece a %, no a %', NEW.cuenta_id, v_cc_producto, NEW.cuenta_contable_codigo
        USING ERRCODE = 'BA014';
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_asiento_coherente
  BEFORE INSERT ON fin.asiento_contable
  FOR EACH ROW EXECUTE FUNCTION fin.trg_asiento_coherente();

-- Al confirmar (COMMIT): toda transacción POSTED tiene débito y crédito y cuadra.
-- Es diferido porque la transacción se inserta antes que sus líneas.
CREATE FUNCTION fin.trg_transaccion_cuadrada() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_debitos numeric; v_creditos numeric; v_estado text;
BEGIN
  SELECT estado_codigo INTO v_estado FROM fin.transaccion_financiera WHERE transaccion_id = NEW.transaccion_id;
  IF v_estado IS DISTINCT FROM 'POSTED' THEN
    RETURN NULL;
  END IF;
  SELECT coalesce(sum(valor) FILTER (WHERE naturaleza = 'D'), 0),
         coalesce(sum(valor) FILTER (WHERE naturaleza = 'C'), 0)
  INTO v_debitos, v_creditos
  FROM fin.asiento_contable WHERE transaccion_id = NEW.transaccion_id;
  IF v_debitos = 0 OR v_creditos = 0 OR v_debitos <> v_creditos THEN
    RAISE EXCEPTION 'Transacción % descuadrada: débitos %, créditos % (RN-46, RN-47)', NEW.transaccion_id, v_debitos, v_creditos
      USING ERRCODE = 'BA014';
  END IF;
  RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER trg_transaccion_cuadrada
  AFTER INSERT OR UPDATE OF estado_codigo ON fin.transaccion_financiera
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW WHEN (NEW.estado_codigo = 'POSTED')
  EXECUTE FUNCTION fin.trg_transaccion_cuadrada();

-- También si alguien agrega líneas después a una transacción ya contabilizada
CREATE CONSTRAINT TRIGGER trg_asiento_cuadrado
  AFTER INSERT ON fin.asiento_contable
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION fin.trg_transaccion_cuadrada();

-- ---------------------------------------------------------------------
-- 16.3 Clientes: exactamente un subtipo (RN-02)
-- ---------------------------------------------------------------------
CREATE FUNCTION core.trg_cliente_un_subtipo() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_natural boolean; v_juridica boolean;
BEGIN
  v_natural  := EXISTS (SELECT 1 FROM core.persona_natural  WHERE cliente_id = NEW.cliente_id);
  v_juridica := EXISTS (SELECT 1 FROM core.persona_juridica WHERE cliente_id = NEW.cliente_id);
  IF v_natural = v_juridica THEN
    RAISE EXCEPTION 'El cliente % debe tener exactamente un subtipo (natural o jurídica)', NEW.cliente_id
      USING ERRCODE = 'BA017';
  END IF;
  RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER trg_cliente_un_subtipo
  AFTER INSERT ON core.cliente
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION core.trg_cliente_un_subtipo();

-- ---------------------------------------------------------------------
-- 16.4 Cuentas: columnas controladas (RN-17, RN-22, RN-25, RN-27)
-- ---------------------------------------------------------------------
-- estado_cuenta, fecha_cierre y limite_retiro_diario solo cambian a través de
-- un evento (trigger de evento_cuenta / cambio_limite): pg_trigger_depth() > 1.
CREATE FUNCTION core.trg_cuenta_reglas() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_permite_sobregiro boolean;
BEGIN
  SELECT permite_sobregiro INTO v_permite_sobregiro FROM core.producto WHERE producto_codigo = NEW.producto_codigo;
  IF NEW.cupo_sobregiro > 0 AND NOT v_permite_sobregiro THEN
    RAISE EXCEPTION 'El producto % no permite cupo de sobregiro (RN-17)', NEW.producto_codigo USING ERRCODE = 'BA017';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.estado_cuenta <> 'CREADA' OR NEW.saldo_contable <> 0 OR NEW.saldo_retenido <> 0 THEN
      RAISE EXCEPTION 'Una cuenta nueva nace en estado CREADA y con saldo 0' USING ERRCODE = 'BA011';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.moneda_codigo <> OLD.moneda_codigo THEN
    RAISE EXCEPTION 'La moneda de una cuenta no cambia (RN-22)' USING ERRCODE = 'BA017';
  END IF;
  IF NEW.producto_codigo <> OLD.producto_codigo OR NEW.numero_cuenta <> OLD.numero_cuenta
     OR NEW.fecha_apertura <> OLD.fecha_apertura THEN
    RAISE EXCEPTION 'El producto, el número y la fecha de apertura de una cuenta no cambian' USING ERRCODE = 'BA017';
  END IF;
  IF (NEW.estado_cuenta, NEW.fecha_cierre, NEW.limite_retiro_diario)
       IS DISTINCT FROM (OLD.estado_cuenta, OLD.fecha_cierre, OLD.limite_retiro_diario)
     AND pg_trigger_depth() < 2 THEN
    RAISE EXCEPTION 'Estado, fecha de cierre y límite solo cambian registrando un evento de cuenta (RN-25, RN-27)'
      USING ERRCODE = 'BA011';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_cuenta_reglas
  BEFORE INSERT OR UPDATE ON core.cuenta
  FOR EACH ROW EXECUTE FUNCTION core.trg_cuenta_reglas();

-- ---------------------------------------------------------------------
-- 16.5 Eventos: orden del ciclo de vida y estado vigente (RN-23 a RN-25)
-- ---------------------------------------------------------------------
CREATE FUNCTION core.trg_evento_validar() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_estado text; v_ultimo timestamptz; v_hay_eventos boolean;
BEGIN
  SELECT estado_cuenta INTO v_estado FROM core.cuenta WHERE cuenta_id = NEW.cuenta_id FOR UPDATE;
  SELECT max(ocurrido_en), count(*) > 0 INTO v_ultimo, v_hay_eventos
  FROM core.evento_cuenta WHERE cuenta_id = NEW.cuenta_id;

  IF NEW.tipo_evento = 'CREACION' THEN
    IF v_hay_eventos THEN
      RAISE EXCEPTION 'La cuenta % ya tiene evento de creación (RN-23)', NEW.cuenta_id USING ERRCODE = 'BA011';
    END IF;
  ELSIF NOT v_hay_eventos THEN
    RAISE EXCEPTION 'El primer evento de una cuenta debe ser CREACION (RN-23)' USING ERRCODE = 'BA011';
  ELSIF NEW.estado_anterior IS DISTINCT FROM v_estado THEN
    RAISE EXCEPTION 'El evento dice que la cuenta estaba % pero está % (RN-25)', NEW.estado_anterior, v_estado
      USING ERRCODE = 'BA011';
  ELSIF NEW.ocurrido_en < v_ultimo THEN
    RAISE EXCEPTION 'Un evento no puede ser anterior al último evento de la cuenta' USING ERRCODE = 'BA011';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION core.trg_evento_aplicar() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NEW.tipo_evento <> 'CREACION' THEN
    UPDATE core.cuenta
    SET estado_cuenta = NEW.estado_nuevo,
        fecha_cierre  = CASE WHEN NEW.tipo_evento = 'CIERRE' THEN NEW.ocurrido_en ELSE fecha_cierre END
    WHERE cuenta_id = NEW.cuenta_id
      AND (estado_cuenta <> NEW.estado_nuevo OR NEW.tipo_evento = 'CIERRE');
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_evento_validar
  BEFORE INSERT ON core.evento_cuenta
  FOR EACH ROW EXECUTE FUNCTION core.trg_evento_validar();
CREATE TRIGGER trg_evento_aplicar
  AFTER INSERT ON core.evento_cuenta
  FOR EACH ROW EXECUTE FUNCTION core.trg_evento_aplicar();
CREATE TRIGGER trg_evento_inmutable
  BEFORE UPDATE ON core.evento_cuenta
  FOR EACH ROW EXECUTE FUNCTION fin.trg_prohibir_cambios();

-- Cambio de límite: el valor anterior debe ser el vigente; actualiza la cuenta (RN-27)
CREATE FUNCTION core.trg_cambio_limite_aplicar() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_cuenta bigint; v_actual numeric;
BEGIN
  SELECT e.cuenta_id INTO v_cuenta FROM core.evento_cuenta e WHERE e.evento_id = NEW.evento_id;
  SELECT limite_retiro_diario INTO v_actual FROM core.cuenta WHERE cuenta_id = v_cuenta FOR UPDATE;
  IF v_actual <> NEW.valor_anterior THEN
    RAISE EXCEPTION 'El límite vigente es %, no % (RN-27)', v_actual, NEW.valor_anterior USING ERRCODE = 'BA011';
  END IF;
  UPDATE core.cuenta SET limite_retiro_diario = NEW.valor_nuevo WHERE cuenta_id = v_cuenta;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_cambio_limite_aplicar
  AFTER INSERT ON core.cambio_limite
  FOR EACH ROW EXECUTE FUNCTION core.trg_cambio_limite_aplicar();
CREATE TRIGGER trg_cambio_limite_inmutable
  BEFORE UPDATE ON core.cambio_limite
  FOR EACH ROW EXECUTE FUNCTION fin.trg_prohibir_cambios();

-- ---------------------------------------------------------------------
-- 16.6 Titularidad: edad, tipo de cliente y máximo por producto
--      (RN-08, RN-14, RN-15, RN-16; supuestos S2, S3, S4)
-- ---------------------------------------------------------------------
CREATE FUNCTION core.trg_titularidad_reglas() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  c core.cuenta%ROWTYPE; p core.producto%ROWTYPE;
  v_tipo_cliente text; v_nacimiento date; v_vigentes int;
BEGIN
  IF NEW.vigente_hasta IS NOT NULL THEN
    RETURN NEW;    -- cerrar una titularidad no requiere validar reglas de apertura
  END IF;
  SELECT * INTO c FROM core.cuenta WHERE cuenta_id = NEW.cuenta_id FOR UPDATE;   -- serializa altas concurrentes
  SELECT * INTO p FROM core.producto WHERE producto_codigo = c.producto_codigo;
  SELECT tipo_cliente INTO v_tipo_cliente FROM core.cliente WHERE cliente_id = NEW.cliente_id;

  IF c.estado_cuenta = 'CERRADA' THEN
    RAISE EXCEPTION 'No se agregan titulares a una cuenta cerrada' USING ERRCODE = 'BA010';
  END IF;
  IF p.tipo_cliente_permitido IS NOT NULL AND p.tipo_cliente_permitido <> v_tipo_cliente THEN
    RAISE EXCEPTION 'El producto % solo admite clientes %, no % (RN-14, RN-15)', p.producto_codigo, p.tipo_cliente_permitido, v_tipo_cliente
      USING ERRCODE = 'BA010';
  END IF;
  IF v_tipo_cliente = 'NATURAL' THEN
    SELECT fecha_nacimiento INTO v_nacimiento FROM core.persona_natural WHERE cliente_id = NEW.cliente_id;
    IF (c.fecha_apertura AT TIME ZONE 'America/Bogota')::date < v_nacimiento + INTERVAL '18 years' THEN
      RAISE EXCEPTION 'El titular debe tener 18 años cumplidos a la fecha de apertura (RN-08)' USING ERRCODE = 'BA010';
    END IF;
  END IF;
  SELECT count(*) INTO v_vigentes FROM core.titularidad_cuenta
  WHERE cuenta_id = NEW.cuenta_id AND vigente_hasta IS NULL
    AND NOT (cliente_id = NEW.cliente_id AND vigente_desde = NEW.vigente_desde);
  IF v_vigentes + 1 > p.max_titulares THEN
    RAISE EXCEPTION 'El producto % admite máximo % titular(es) (RN-16)', p.producto_codigo, p.max_titulares
      USING ERRCODE = 'BA010';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_titularidad_reglas
  BEFORE INSERT OR UPDATE ON core.titularidad_cuenta
  FOR EACH ROW EXECUTE FUNCTION core.trg_titularidad_reglas();

-- ---------------------------------------------------------------------
-- 16.7 Auditoría (RN-52)
-- ---------------------------------------------------------------------
-- Guarda quién (usuario interno de la operación y usuario de base de datos),
-- cuándo, qué tabla, qué registro y los valores antes / después.
-- Argumentos del trigger: nombres de las columnas de la clave primaria.
CREATE FUNCTION aud.trg_auditar() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_fila jsonb := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  v_registro jsonb := '{}'::jsonb;
  v_col text;
BEGIN
  FOREACH v_col IN ARRAY TG_ARGV LOOP
    v_registro := v_registro || jsonb_build_object(v_col, v_fila -> v_col);
  END LOOP;
  INSERT INTO aud.log_auditoria (usuario_id, usuario_bd, esquema, tabla, registro, operacion, valores_antes, valores_despues)
  VALUES (nullif(current_setting('banco.usuario_id', true), '')::bigint,
          session_user, TG_TABLE_SCHEMA, TG_TABLE_NAME, v_registro, TG_OP,
          CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
          CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END);
  RETURN NULL;
END $$;
COMMENT ON FUNCTION aud.trg_auditar() IS 'Registro de auditoría genérico (RN-52). Toma el usuario interno de la variable de sesión banco.usuario_id que fijan las operaciones.';

CREATE TRIGGER trg_auditar_cliente            AFTER INSERT OR UPDATE OR DELETE ON core.cliente            FOR EACH ROW EXECUTE FUNCTION aud.trg_auditar('cliente_id');
CREATE TRIGGER trg_auditar_cuenta             AFTER INSERT OR UPDATE OR DELETE ON core.cuenta             FOR EACH ROW EXECUTE FUNCTION aud.trg_auditar('cuenta_id');
CREATE TRIGGER trg_auditar_titularidad        AFTER INSERT OR UPDATE OR DELETE ON core.titularidad_cuenta FOR EACH ROW EXECUTE FUNCTION aud.trg_auditar('cuenta_id', 'cliente_id', 'vigente_desde');
CREATE TRIGGER trg_auditar_evento_cuenta      AFTER INSERT ON core.evento_cuenta                          FOR EACH ROW EXECUTE FUNCTION aud.trg_auditar('evento_id');
CREATE TRIGGER trg_auditar_transaccion        AFTER INSERT OR UPDATE OR DELETE ON fin.transaccion_financiera FOR EACH ROW EXECUTE FUNCTION aud.trg_auditar('transaccion_id');
CREATE TRIGGER trg_auditar_usuario            AFTER INSERT OR UPDATE OR DELETE ON seg.usuario             FOR EACH ROW EXECUTE FUNCTION aud.trg_auditar('usuario_id');
CREATE TRIGGER trg_auditar_usuario_rol        AFTER INSERT OR UPDATE OR DELETE ON seg.usuario_rol         FOR EACH ROW EXECUTE FUNCTION aud.trg_auditar('usuario_id', 'rol_id', 'vigente_desde');
CREATE TRIGGER trg_auditar_rol_permiso        AFTER INSERT OR UPDATE OR DELETE ON seg.rol_permiso         FOR EACH ROW EXECUTE FUNCTION aud.trg_auditar('rol_id', 'permiso_id');
