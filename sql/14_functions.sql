-- =====================================================================
-- 14_functions.sql · Banco Andino Colombia
-- Operaciones seguras del negocio. Cada operación:
--   1. valida el permiso del usuario interno (RBAC de la aplicación, RN-28, RN-51);
--   2. valida precondiciones (estado, fondos, límites, monedas…);
--   3. bloquea las filas que modifica (SELECT … FOR UPDATE) para evitar
--      doble retiro, actualización perdida y doble procesamiento;
--   4. es atómica: es una sola sentencia SQL, así que todo o nada (RN-39);
--   5. queda auditada por los triggers de 16_triggers.sql (RN-52).
--
-- Todas son SECURITY DEFINER con search_path fijo: los roles de la
-- aplicación NO tienen permisos directos sobre las tablas, solo pueden
-- ejecutar estas funciones (mínimo privilegio, 17_roles_permissions.sql).
--
-- Errores del negocio (SQLSTATE propio, clase BA):
--   BA001 permiso denegado                  BA010 titularidad inválida
--   BA002 el estado de la cuenta no lo permite  BA011 transición o columna controlada
--   BA003 fondos insuficientes              BA012 cierre con saldo
--   BA004 límite diario de retiro excedido  BA013 aprobación de ajuste inválida
--   BA005 monto inválido                    BA014 contabilidad descuadrada o incoherente
--   BA006 transferencia inválida            BA015 clave de idempotencia reutilizada
--   BA007 registro inmutable                BA016 registro no encontrado
--   BA008 reverso inválido                  BA017 parámetro de producto o cliente inválido
--   BA009 el usuario es titular de la cuenta (RN-54)
--
-- Se ejecuta desde sql/run_all.sql (no abre ni cierra transacción).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 14.1 Utilidades
-- ---------------------------------------------------------------------

-- Fecha contable: día calendario en Colombia
CREATE FUNCTION fin.fn_fecha_contable(p_momento timestamptz DEFAULT clock_timestamp())
RETURNS date LANGUAGE sql STABLE PARALLEL SAFE
SET search_path = pg_catalog, pg_temp AS $$
  SELECT (p_momento AT TIME ZONE 'America/Bogota')::date
$$;
COMMENT ON FUNCTION fin.fn_fecha_contable(timestamptz) IS 'Día contable (hora de Colombia) de un momento dado.';

-- Exige un permiso de la aplicación y deja al usuario en la sesión para la auditoría
CREATE FUNCTION seg.fn_exigir_permiso(p_usuario_id bigint, p_permiso text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM seg.usuario u
    JOIN seg.usuario_rol ur ON ur.usuario_id = u.usuario_id
                           AND ur.vigente_desde <= clock_timestamp()
                           AND (ur.vigente_hasta IS NULL OR ur.vigente_hasta > clock_timestamp())
    JOIN seg.rol_permiso rp ON rp.rol_id = ur.rol_id
    JOIN seg.permiso p      ON p.permiso_id = rp.permiso_id
    WHERE u.usuario_id = p_usuario_id
      AND u.estado = 'ACTIVO'
      AND p.codigo = p_permiso
  ) THEN
    RAISE EXCEPTION 'El usuario % no tiene el permiso %', p_usuario_id, p_permiso
      USING ERRCODE = 'BA001';
  END IF;
  -- Quién opera: lo leen los triggers de auditoría (16_triggers.sql)
  PERFORM set_config('banco.usuario_id', p_usuario_id::text, true);
END $$;
COMMENT ON FUNCTION seg.fn_exigir_permiso(bigint, text) IS 'Valida que el usuario esté activo y tenga el permiso por un rol vigente (RN-28, RN-49, RN-51). Falla con BA001.';

-- Monto > 0 y con máximo 2 decimales (RN-30). numeric(18,2) redondearía en silencio.
CREATE FUNCTION fin.fn_validar_monto(p_monto numeric)
RETURNS void LANGUAGE plpgsql IMMUTABLE
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF p_monto IS NULL OR p_monto <= 0 OR p_monto <> round(p_monto, 2) OR p_monto >= 1e16 THEN
    RAISE EXCEPTION 'Monto inválido: % (debe ser mayor que 0 y tener máximo 2 decimales)', p_monto
      USING ERRCODE = 'BA005';
  END IF;
END $$;

-- RN-54: un usuario interno no opera cuentas de las que es titular
CREATE FUNCTION fin.fn_validar_no_titular(p_usuario_id bigint, p_cuenta_id bigint)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF p_cuenta_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM core.titularidad_cuenta t
    JOIN core.cliente c ON c.cliente_id = t.cliente_id
    JOIN seg.usuario u  ON u.tipo_documento = c.tipo_documento
                       AND u.numero_documento = c.numero_documento
    WHERE t.cuenta_id = p_cuenta_id
      AND t.vigente_hasta IS NULL
      AND u.usuario_id = p_usuario_id
  ) THEN
    RAISE EXCEPTION 'El usuario % es titular de la cuenta % y no puede operarla', p_usuario_id, p_cuenta_id
      USING ERRCODE = 'BA009';
  END IF;
END $$;

-- Bloquea una o dos cuentas SIEMPRE en orden de cuenta_id: evita interbloqueos
-- cuando dos transferencias cruzadas (A→B y B→A) llegan al mismo tiempo.
CREATE FUNCTION core.fn_bloquear_cuentas(p_cuenta_a bigint, p_cuenta_b bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_esperadas int := num_nonnulls(p_cuenta_a, p_cuenta_b);
  v_bloqueadas int;
BEGIN
  SELECT count(*) INTO v_bloqueadas
  FROM (
    SELECT cuenta_id FROM core.cuenta
    WHERE cuenta_id IN (p_cuenta_a, p_cuenta_b)
    ORDER BY cuenta_id
    FOR UPDATE
  ) x;
  IF v_bloqueadas < v_esperadas THEN
    RAISE EXCEPTION 'Cuenta no encontrada (%, %)', p_cuenta_a, p_cuenta_b USING ERRCODE = 'BA016';
  END IF;
END $$;

-- Valida que una cuenta (ya bloqueada) pueda originar un débito: ACTIVA + fondos (RN-31, RN-34)
CREATE FUNCTION fin.fn_validar_debito(p_cuenta_id bigint, p_monto numeric)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  c core.cuenta%ROWTYPE;
BEGIN
  SELECT * INTO c FROM core.cuenta WHERE cuenta_id = p_cuenta_id;
  IF c.estado_cuenta <> 'ACTIVA' THEN
    RAISE EXCEPTION 'La cuenta % está % y no puede originar débitos', c.numero_cuenta, c.estado_cuenta
      USING ERRCODE = 'BA002';
  END IF;
  IF c.saldo_disponible + c.cupo_sobregiro < p_monto THEN
    RAISE EXCEPTION 'Fondos insuficientes en la cuenta %: disponible % + cupo %, solicitado %',
      c.numero_cuenta, c.saldo_disponible, c.cupo_sobregiro, p_monto USING ERRCODE = 'BA003';
  END IF;
END $$;

-- Valida que una cuenta pueda recibir un crédito: ACTIVA o BLOQUEADA (RN-35, supuesto S1)
CREATE FUNCTION fin.fn_validar_credito(p_cuenta_id bigint)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_estado text; v_numero text;
BEGIN
  SELECT estado_cuenta, numero_cuenta INTO v_estado, v_numero FROM core.cuenta WHERE cuenta_id = p_cuenta_id;
  IF v_estado NOT IN ('ACTIVA', 'BLOQUEADA') THEN
    RAISE EXCEPTION 'La cuenta % está % y no puede recibir créditos', v_numero, v_estado
      USING ERRCODE = 'BA002';
  END IF;
END $$;

-- Cuenta contable de depósitos según el producto de la cuenta
CREATE FUNCTION fin.fn_cuenta_contable(p_cuenta_id bigint)
RETURNS varchar LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
  SELECT p.cuenta_contable_codigo
  FROM core.cuenta c JOIN core.producto p ON p.producto_codigo = c.producto_codigo
  WHERE c.cuenta_id = p_cuenta_id
$$;

-- Idempotencia (RN-38): si la clave ya existe devuelve la transacción; si la
-- clave existe con otra solicitud (hash distinto) falla con BA015.
CREATE FUNCTION fin.fn_buscar_idempotencia(p_key uuid, p_hash bytea)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_id bigint; v_hash bytea;
BEGIN
  IF p_key IS NULL THEN
    RAISE EXCEPTION 'La clave de idempotencia es obligatoria' USING ERRCODE = 'BA015';
  END IF;
  SELECT transaccion_id, hash_solicitud INTO v_id, v_hash
  FROM fin.transaccion_financiera WHERE idempotency_key = p_key;
  IF FOUND AND v_hash IS DISTINCT FROM p_hash THEN
    RAISE EXCEPTION 'La clave % ya se usó para otra solicitud', p_key USING ERRCODE = 'BA015';
  END IF;
  RETURN v_id;   -- NULL si la clave es nueva
END $$;

-- Aplica al saldo de las cuentas lo que dicen los asientos de una transacción.
-- El saldo SIEMPRE se deriva del ledger (desnormalización D-01, RN-48).
CREATE FUNCTION fin.fn_aplicar_saldos(p_transaccion_id bigint)
RETURNS void LANGUAGE sql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
  UPDATE core.cuenta c
  SET saldo_contable = c.saldo_contable + x.delta
  FROM (
    SELECT cuenta_id, sum(CASE naturaleza WHEN 'C' THEN valor ELSE -valor END) AS delta
    FROM fin.asiento_contable
    WHERE transaccion_id = p_transaccion_id AND cuenta_id IS NOT NULL
    GROUP BY cuenta_id
  ) x
  WHERE c.cuenta_id = x.cuenta_id
$$;

-- Registra una transacción POSTED de dos líneas y aplica saldos. Uso interno.
-- Devuelve NULL si otra sesión ya registró la misma clave (idempotencia concurrente).
CREATE FUNCTION fin.fn_contabilizar(
  p_usuario_id bigint, p_tipo text, p_origen bigint, p_destino bigint, p_monto numeric,
  p_key uuid, p_hash bytea, p_descripcion text,
  p_cc_debito text, p_cuenta_debito bigint, p_cc_credito text, p_cuenta_credito bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_id bigint;
  v_ahora timestamptz := clock_timestamp();
BEGIN
  INSERT INTO fin.transaccion_financiera
    (tipo_codigo, estado_codigo, cuenta_origen_id, cuenta_destino_id, monto, idempotency_key,
     hash_solicitud, descripcion, fecha_solicitud, fecha_contabilizacion, fecha_contable, creado_por)
  VALUES
    (p_tipo, 'POSTED', p_origen, p_destino, p_monto, p_key,
     p_hash, p_descripcion, v_ahora, v_ahora, fin.fn_fecha_contable(v_ahora), p_usuario_id)
  ON CONFLICT (idempotency_key) DO NOTHING
  RETURNING transaccion_id INTO v_id;

  IF v_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Las dos líneas en una sola sentencia (RN-46, RN-47)
  INSERT INTO fin.asiento_contable (transaccion_id, linea, cuenta_contable_codigo, cuenta_id, naturaleza, valor, registrado_en)
  VALUES (v_id, 1, p_cc_debito,  p_cuenta_debito,  'D', p_monto, v_ahora),
         (v_id, 2, p_cc_credito, p_cuenta_credito, 'C', p_monto, v_ahora);

  PERFORM fin.fn_aplicar_saldos(v_id);
  RETURN v_id;
END $$;

-- ---------------------------------------------------------------------
-- 14.2 Clientes
-- ---------------------------------------------------------------------

CREATE FUNCTION core.fn_crear_cliente_natural(
  p_usuario_id bigint, p_tipo_documento text, p_numero_documento text,
  p_nombres text, p_apellidos text, p_fecha_nacimiento date, p_municipio_codigo text,
  p_email text DEFAULT NULL, p_telefono text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_id bigint;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'CLI_CREAR');
  INSERT INTO core.cliente (tipo_cliente, tipo_documento, numero_documento, municipio_codigo,
                            fecha_vinculacion, email, telefono)
  VALUES ('NATURAL', p_tipo_documento, p_numero_documento, p_municipio_codigo,
          fin.fn_fecha_contable(), p_email, p_telefono)
  RETURNING cliente_id INTO v_id;
  INSERT INTO core.persona_natural (cliente_id, nombres, apellidos, fecha_nacimiento)
  VALUES (v_id, p_nombres, p_apellidos, p_fecha_nacimiento);
  RETURN v_id;
END $$;
COMMENT ON FUNCTION core.fn_crear_cliente_natural(bigint, text, text, text, text, date, text, text, text) IS 'Crea el cliente y su subtipo persona natural en una sola operación (RN-01 a RN-03). Permiso CLI_CREAR.';

CREATE FUNCTION core.fn_crear_cliente_juridico(
  p_usuario_id bigint, p_nit text, p_razon_social text, p_fecha_constitucion date,
  p_actividad_economica text, p_municipio_codigo text,
  p_email text DEFAULT NULL, p_telefono text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_id bigint;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'CLI_CREAR');
  INSERT INTO core.cliente (tipo_cliente, tipo_documento, numero_documento, digito_verificacion,
                            municipio_codigo, fecha_vinculacion, email, telefono)
  VALUES ('JURIDICA', 'NIT', p_nit, ref.fn_dv_nit(p_nit),
          p_municipio_codigo, fin.fn_fecha_contable(), p_email, p_telefono)
  RETURNING cliente_id INTO v_id;
  INSERT INTO core.persona_juridica (cliente_id, razon_social, fecha_constitucion, actividad_economica)
  VALUES (v_id, p_razon_social, p_fecha_constitucion, p_actividad_economica);
  RETURN v_id;
END $$;
COMMENT ON FUNCTION core.fn_crear_cliente_juridico(bigint, text, text, date, text, text, text, text) IS 'Crea el cliente y su subtipo persona jurídica; calcula el dígito de verificación del NIT (RN-04). Permiso CLI_CREAR.';

-- ---------------------------------------------------------------------
-- 14.3 Cuentas y ciclo de vida
-- ---------------------------------------------------------------------

-- Registra un evento de cuenta. El trigger de 16_triggers.sql valida el estado
-- anterior y actualiza la cuenta (RN-23 a RN-25). Uso interno.
CREATE FUNCTION core.fn_registrar_evento(
  p_usuario_id bigint, p_cuenta_id bigint, p_tipo_evento text, p_estado_nuevo text, p_motivo text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_actual text; v_numero text; v_id bigint;
BEGIN
  PERFORM core.fn_bloquear_cuentas(p_cuenta_id);
  SELECT estado_cuenta, numero_cuenta INTO v_actual, v_numero FROM core.cuenta WHERE cuenta_id = p_cuenta_id;
  IF NOT EXISTS (SELECT 1 FROM ref.transicion_estado_cuenta
                 WHERE tipo_evento = p_tipo_evento AND estado_anterior = v_actual AND estado_nuevo = p_estado_nuevo) THEN
    RAISE EXCEPTION 'Transición no permitida para la cuenta %: % de % a %', v_numero, p_tipo_evento, v_actual, p_estado_nuevo
      USING ERRCODE = 'BA011';
  END IF;
  INSERT INTO core.evento_cuenta (cuenta_id, tipo_evento, estado_anterior, estado_nuevo, motivo, ocurrido_en, registrado_por)
  VALUES (p_cuenta_id, p_tipo_evento, v_actual, p_estado_nuevo, p_motivo, clock_timestamp(), p_usuario_id)
  RETURNING evento_id INTO v_id;
  RETURN v_id;
END $$;

CREATE FUNCTION core.fn_abrir_cuenta(
  p_usuario_id bigint, p_cliente_id bigint, p_producto_codigo text, p_moneda_codigo text,
  p_oficina_id integer, p_limite_retiro_diario numeric, p_cupo_sobregiro numeric DEFAULT 0)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_id bigint; v_prefijo text; v_estado_cliente text;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'CTA_ABRIR');

  SELECT estado_cliente INTO v_estado_cliente FROM core.cliente WHERE cliente_id = p_cliente_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El cliente % no existe', p_cliente_id USING ERRCODE = 'BA016';
  END IF;
  IF v_estado_cliente <> 'ACTIVO' THEN
    RAISE EXCEPTION 'El cliente % está % y no puede abrir cuentas', p_cliente_id, v_estado_cliente USING ERRCODE = 'BA017';
  END IF;

  v_prefijo := CASE p_producto_codigo
                 WHEN 'AHORROS' THEN '10' WHEN 'CORRIENTE' THEN '20'
                 WHEN 'NOMINA' THEN '30' WHEN 'EMPRESARIAL' THEN '40' END;
  IF v_prefijo IS NULL THEN
    RAISE EXCEPTION 'Producto no válido: %', p_producto_codigo USING ERRCODE = 'BA017';
  END IF;
  PERFORM fin.fn_validar_monto(p_limite_retiro_diario);

  v_id := nextval(pg_get_serial_sequence('core.cuenta', 'cuenta_id'));
  INSERT INTO core.cuenta (cuenta_id, numero_cuenta, producto_codigo, moneda_codigo, oficina_id,
                           estado_cuenta, fecha_apertura, cupo_sobregiro, limite_retiro_diario)
  VALUES (v_id, v_prefijo || lpad(v_id::text, 9, '0'), p_producto_codigo, p_moneda_codigo, p_oficina_id,
          'CREADA', clock_timestamp(), coalesce(p_cupo_sobregiro, 0), p_limite_retiro_diario);

  INSERT INTO core.evento_cuenta (cuenta_id, tipo_evento, estado_anterior, estado_nuevo, ocurrido_en, registrado_por)
  VALUES (v_id, 'CREACION', NULL, 'CREADA', clock_timestamp(), p_usuario_id);

  -- El trigger de titularidad valida RN-08, RN-14, RN-15 y RN-16
  INSERT INTO core.titularidad_cuenta (cuenta_id, cliente_id, vigente_desde, rol_titular)
  VALUES (v_id, p_cliente_id, clock_timestamp(), 'PRINCIPAL');
  RETURN v_id;
END $$;
COMMENT ON FUNCTION core.fn_abrir_cuenta(bigint, bigint, text, text, integer, numeric, numeric) IS 'Abre una cuenta en estado CREADA con su titular principal y el evento CREACION (RN-11 a RN-17, RN-23). Permiso CTA_ABRIR.';

CREATE FUNCTION core.fn_agregar_titular(p_usuario_id bigint, p_cuenta_id bigint, p_cliente_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'CTA_ABRIR');
  PERFORM core.fn_bloquear_cuentas(p_cuenta_id);
  INSERT INTO core.titularidad_cuenta (cuenta_id, cliente_id, vigente_desde, rol_titular)
  VALUES (p_cuenta_id, p_cliente_id, clock_timestamp(), 'COTITULAR');
END $$;
COMMENT ON FUNCTION core.fn_agregar_titular(bigint, bigint, bigint) IS 'Agrega un cotitular; el trigger valida edad, tipo de cliente y máximo del producto (RN-08, RN-14 a RN-16).';

CREATE FUNCTION core.fn_activar_cuenta(p_usuario_id bigint, p_cuenta_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'CTA_ACTIVAR');
  RETURN core.fn_registrar_evento(p_usuario_id, p_cuenta_id, 'ACTIVACION', 'ACTIVA');
END $$;

CREATE FUNCTION core.fn_bloquear_cuenta(p_usuario_id bigint, p_cuenta_id bigint, p_motivo text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'CTA_BLOQUEAR');
  RETURN core.fn_registrar_evento(p_usuario_id, p_cuenta_id, 'BLOQUEO', 'BLOQUEADA', p_motivo);  -- RN-29
END $$;

CREATE FUNCTION core.fn_desbloquear_cuenta(p_usuario_id bigint, p_cuenta_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'CTA_DESBLOQUEAR');   -- solo SUPERVISOR (RN-28)
  RETURN core.fn_registrar_evento(p_usuario_id, p_cuenta_id, 'DESBLOQUEO', 'ACTIVA');
END $$;

CREATE FUNCTION core.fn_cambiar_limite(p_usuario_id bigint, p_cuenta_id bigint, p_nuevo_limite numeric)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_evento bigint; v_actual numeric;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'CTA_CAMBIAR_LIMITE');   -- solo SUPERVISOR (RN-28)
  PERFORM fin.fn_validar_monto(p_nuevo_limite);
  v_evento := core.fn_registrar_evento(p_usuario_id, p_cuenta_id, 'CAMBIO_LIMITE', 'ACTIVA');
  SELECT limite_retiro_diario INTO v_actual FROM core.cuenta WHERE cuenta_id = p_cuenta_id;
  -- El trigger de cambio_limite actualiza la cuenta (RN-27)
  INSERT INTO core.cambio_limite (evento_id, valor_anterior, valor_nuevo)
  VALUES (v_evento, v_actual, p_nuevo_limite);
  RETURN v_evento;
END $$;

CREATE FUNCTION core.fn_cerrar_cuenta(p_usuario_id bigint, p_cuenta_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  c core.cuenta%ROWTYPE; v_evento bigint;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'CTA_CERRAR');   -- solo SUPERVISOR (RN-28)
  PERFORM core.fn_bloquear_cuentas(p_cuenta_id);
  SELECT * INTO c FROM core.cuenta WHERE cuenta_id = p_cuenta_id;
  IF c.saldo_contable <> 0 OR c.saldo_retenido <> 0 THEN
    RAISE EXCEPTION 'La cuenta % tiene saldo % (retenido %) y no se puede cerrar', c.numero_cuenta, c.saldo_contable, c.saldo_retenido
      USING ERRCODE = 'BA012';   -- RN-20
  END IF;
  v_evento := core.fn_registrar_evento(p_usuario_id, p_cuenta_id, 'CIERRE', 'CERRADA');
  -- Cierra las titularidades vigentes y deja INACTIVO al cliente que ya no tenga cuentas
  UPDATE core.titularidad_cuenta SET vigente_hasta = clock_timestamp()
  WHERE cuenta_id = p_cuenta_id AND vigente_hasta IS NULL;
  UPDATE core.cliente cl SET estado_cliente = 'INACTIVO'
  WHERE cl.estado_cliente = 'ACTIVO'
    AND cl.cliente_id IN (SELECT cliente_id FROM core.titularidad_cuenta WHERE cuenta_id = p_cuenta_id)
    AND NOT EXISTS (SELECT 1 FROM core.titularidad_cuenta t
                    WHERE t.cliente_id = cl.cliente_id AND t.vigente_hasta IS NULL);
  RETURN v_evento;
END $$;
COMMENT ON FUNCTION core.fn_cerrar_cuenta(bigint, bigint) IS 'Cierra una cuenta con saldo 0 (RN-20), termina sus titularidades e inactiva al cliente sin cuentas vigentes. Permiso CTA_CERRAR.';

-- ---------------------------------------------------------------------
-- 14.4 Operaciones de dinero
-- ---------------------------------------------------------------------

CREATE FUNCTION fin.fn_consignar(
  p_usuario_id bigint, p_cuenta_id bigint, p_monto numeric, p_idempotency_key uuid, p_descripcion text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_hash bytea := sha256(convert_to(concat_ws('|', 'CONSIGNACION', p_cuenta_id, p_monto), 'UTF8'));
  v_id bigint;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'TX_CONSIGNAR');
  PERFORM fin.fn_validar_monto(p_monto);
  v_id := fin.fn_buscar_idempotencia(p_idempotency_key, v_hash);
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;          -- solicitud repetida (RN-38)

  PERFORM fin.fn_validar_no_titular(p_usuario_id, p_cuenta_id);
  PERFORM core.fn_bloquear_cuentas(p_cuenta_id);
  PERFORM fin.fn_validar_credito(p_cuenta_id);           -- ACTIVA o BLOQUEADA (RN-35, S1)

  v_id := fin.fn_contabilizar(p_usuario_id, 'CONSIGNACION', NULL, p_cuenta_id, p_monto,
                              p_idempotency_key, v_hash, p_descripcion,
                              'ACT_CAJA', NULL, fin.fn_cuenta_contable(p_cuenta_id), p_cuenta_id);
  RETURN coalesce(v_id, fin.fn_buscar_idempotencia(p_idempotency_key, v_hash));
END $$;
COMMENT ON FUNCTION fin.fn_consignar(bigint, bigint, numeric, uuid, text) IS 'Consignación en caja: D ACT_CAJA / C depósito del cliente. Idempotente (RN-38). Permiso TX_CONSIGNAR.';

CREATE FUNCTION fin.fn_retirar(
  p_usuario_id bigint, p_cuenta_id bigint, p_monto numeric, p_idempotency_key uuid, p_descripcion text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_hash bytea := sha256(convert_to(concat_ws('|', 'RETIRO', p_cuenta_id, p_monto), 'UTF8'));
  v_id bigint; v_hoy date := fin.fn_fecha_contable(); v_retirado numeric; v_limite numeric;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'TX_RETIRAR');
  PERFORM fin.fn_validar_monto(p_monto);
  v_id := fin.fn_buscar_idempotencia(p_idempotency_key, v_hash);
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  PERFORM fin.fn_validar_no_titular(p_usuario_id, p_cuenta_id);
  PERFORM core.fn_bloquear_cuentas(p_cuenta_id);        -- FOR UPDATE: evita el doble retiro
  PERFORM fin.fn_validar_debito(p_cuenta_id, p_monto);  -- ACTIVA + fondos (RN-31, RN-34)

  -- Límite diario (RN-37): suma de retiros POSTED del día + este retiro
  SELECT limite_retiro_diario INTO v_limite FROM core.cuenta WHERE cuenta_id = p_cuenta_id;
  SELECT coalesce(sum(monto), 0) INTO v_retirado
  FROM fin.transaccion_financiera
  WHERE cuenta_origen_id = p_cuenta_id AND tipo_codigo = 'RETIRO'
    AND estado_codigo = 'POSTED' AND fecha_contable = v_hoy;
  IF v_retirado + p_monto > v_limite THEN
    RAISE EXCEPTION 'Excede el límite diario de retiro: retirado hoy %, solicitado %, límite %', v_retirado, p_monto, v_limite
      USING ERRCODE = 'BA004';
  END IF;

  v_id := fin.fn_contabilizar(p_usuario_id, 'RETIRO', p_cuenta_id, NULL, p_monto,
                              p_idempotency_key, v_hash, p_descripcion,
                              fin.fn_cuenta_contable(p_cuenta_id), p_cuenta_id, 'ACT_CAJA', NULL);
  RETURN coalesce(v_id, fin.fn_buscar_idempotencia(p_idempotency_key, v_hash));
END $$;
COMMENT ON FUNCTION fin.fn_retirar(bigint, bigint, numeric, uuid, text) IS 'Retiro en caja: D depósito / C ACT_CAJA. Valida estado, fondos y límite diario con la cuenta bloqueada (RN-31, RN-34, RN-37). Permiso TX_RETIRAR.';

CREATE FUNCTION fin.fn_transferir(
  p_usuario_id bigint, p_cuenta_origen_id bigint, p_cuenta_destino_id bigint, p_monto numeric,
  p_idempotency_key uuid, p_descripcion text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_hash bytea := sha256(convert_to(concat_ws('|', 'TRANSFERENCIA', p_cuenta_origen_id, p_cuenta_destino_id, p_monto), 'UTF8'));
  v_id bigint; v_mon_o text; v_mon_d text;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'TX_TRANSFERIR');
  PERFORM fin.fn_validar_monto(p_monto);
  IF p_cuenta_origen_id IS NOT DISTINCT FROM p_cuenta_destino_id THEN
    RAISE EXCEPTION 'La cuenta origen y la cuenta destino deben ser distintas' USING ERRCODE = 'BA006';   -- RN-32
  END IF;
  v_id := fin.fn_buscar_idempotencia(p_idempotency_key, v_hash);
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  PERFORM fin.fn_validar_no_titular(p_usuario_id, p_cuenta_origen_id);
  PERFORM fin.fn_validar_no_titular(p_usuario_id, p_cuenta_destino_id);
  PERFORM core.fn_bloquear_cuentas(p_cuenta_origen_id, p_cuenta_destino_id);   -- en orden: sin interbloqueos

  SELECT moneda_codigo INTO v_mon_o FROM core.cuenta WHERE cuenta_id = p_cuenta_origen_id;
  SELECT moneda_codigo INTO v_mon_d FROM core.cuenta WHERE cuenta_id = p_cuenta_destino_id;
  IF v_mon_o <> v_mon_d THEN
    RAISE EXCEPTION 'No se puede transferir entre monedas distintas (% → %)', v_mon_o, v_mon_d USING ERRCODE = 'BA006';   -- RN-33
  END IF;
  PERFORM fin.fn_validar_debito(p_cuenta_origen_id, p_monto);   -- RN-31, RN-34
  PERFORM fin.fn_validar_credito(p_cuenta_destino_id);          -- RN-35

  v_id := fin.fn_contabilizar(p_usuario_id, 'TRANSFERENCIA', p_cuenta_origen_id, p_cuenta_destino_id, p_monto,
                              p_idempotency_key, v_hash, p_descripcion,
                              fin.fn_cuenta_contable(p_cuenta_origen_id), p_cuenta_origen_id,
                              fin.fn_cuenta_contable(p_cuenta_destino_id), p_cuenta_destino_id);
  RETURN coalesce(v_id, fin.fn_buscar_idempotencia(p_idempotency_key, v_hash));
END $$;
COMMENT ON FUNCTION fin.fn_transferir(bigint, bigint, bigint, numeric, uuid, text) IS 'Transferencia atómica: débito en origen y crédito en destino en la misma transacción (RN-32, RN-33, RN-39). Permiso TX_TRANSFERIR.';

CREATE FUNCTION fin.fn_reversar(
  p_usuario_id bigint, p_transaccion_id bigint, p_idempotency_key uuid, p_motivo text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  o fin.transaccion_financiera%ROWTYPE;
  v_hash bytea := sha256(convert_to(concat_ws('|', 'REVERSO', p_transaccion_id), 'UTF8'));
  v_id bigint; v_ahora timestamptz;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'TX_REVERSAR');   -- CAJERO no reversa (RN-51)
  v_id := fin.fn_buscar_idempotencia(p_idempotency_key, v_hash);
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  -- Bloquea la original: dos reversos simultáneos de la misma transacción se ordenan
  SELECT * INTO o FROM fin.transaccion_financiera WHERE transaccion_id = p_transaccion_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La transacción % no existe', p_transaccion_id USING ERRCODE = 'BA016';
  END IF;
  IF o.estado_codigo <> 'POSTED' OR o.tipo_codigo = 'REVERSO' THEN
    RAISE EXCEPTION 'Solo se reversan transacciones POSTED que no sean reversos (tipo %, estado %)', o.tipo_codigo, o.estado_codigo
      USING ERRCODE = 'BA008';   -- RN-42
  END IF;
  IF EXISTS (SELECT 1 FROM fin.transaccion_financiera WHERE transaccion_reversada_id = p_transaccion_id) THEN
    RAISE EXCEPTION 'La transacción % ya fue reversada', p_transaccion_id USING ERRCODE = 'BA008';   -- RN-42
  END IF;

  -- Cuentas invertidas (RN-41) y mismas reglas que cualquier transacción (RN-43)
  PERFORM fin.fn_validar_no_titular(p_usuario_id, o.cuenta_origen_id);
  PERFORM fin.fn_validar_no_titular(p_usuario_id, o.cuenta_destino_id);
  PERFORM core.fn_bloquear_cuentas(coalesce(o.cuenta_origen_id, o.cuenta_destino_id),
                                   CASE WHEN o.cuenta_origen_id IS NOT NULL THEN o.cuenta_destino_id END);
  IF o.cuenta_destino_id IS NOT NULL THEN
    PERFORM fin.fn_validar_debito(o.cuenta_destino_id, o.monto);    -- la que recibió ahora devuelve
  END IF;
  IF o.cuenta_origen_id IS NOT NULL THEN
    PERFORM fin.fn_validar_credito(o.cuenta_origen_id);
  END IF;

  v_ahora := clock_timestamp();
  INSERT INTO fin.transaccion_financiera
    (tipo_codigo, estado_codigo, cuenta_origen_id, cuenta_destino_id, monto, idempotency_key, hash_solicitud,
     transaccion_reversada_id, descripcion, fecha_solicitud, fecha_contabilizacion, fecha_contable, creado_por)
  VALUES
    ('REVERSO', 'POSTED', o.cuenta_destino_id, o.cuenta_origen_id, o.monto, p_idempotency_key, v_hash,
     o.transaccion_id, coalesce(p_motivo, 'Reverso de la transacción ' || o.transaccion_id),
     v_ahora, v_ahora, fin.fn_fecha_contable(v_ahora), p_usuario_id)
  ON CONFLICT (idempotency_key) DO NOTHING
  RETURNING transaccion_id INTO v_id;
  IF v_id IS NULL THEN
    RETURN fin.fn_buscar_idempotencia(p_idempotency_key, v_hash);
  END IF;

  -- Asientos espejo: mismas cuentas contables con la naturaleza invertida
  INSERT INTO fin.asiento_contable (transaccion_id, linea, cuenta_contable_codigo, cuenta_id, naturaleza, valor, registrado_en)
  SELECT v_id, row_number() OVER (ORDER BY a.linea DESC), a.cuenta_contable_codigo, a.cuenta_id,
         CASE a.naturaleza WHEN 'D' THEN 'C' ELSE 'D' END, a.valor, v_ahora
  FROM fin.asiento_contable a
  WHERE a.transaccion_id = o.transaccion_id;

  PERFORM fin.fn_aplicar_saldos(v_id);
  RETURN v_id;
END $$;
COMMENT ON FUNCTION fin.fn_reversar(bigint, bigint, uuid, text) IS 'Reverso: nueva transacción por el mismo monto, cuentas invertidas y asientos espejo; la original no se modifica (RN-40 a RN-43). Permiso TX_REVERSAR.';

-- Ajustes con maker-checker (RN-44)
CREATE FUNCTION fin.fn_crear_ajuste(
  p_usuario_id bigint, p_cuenta_id bigint, p_monto numeric, p_sentido char,
  p_idempotency_key uuid, p_descripcion text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_hash bytea := sha256(convert_to(concat_ws('|', 'AJUSTE', p_cuenta_id, p_monto, p_sentido), 'UTF8'));
  v_id bigint;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'TX_AJUSTE_CREAR');
  PERFORM fin.fn_validar_monto(p_monto);
  IF p_sentido NOT IN ('C', 'D') THEN
    RAISE EXCEPTION 'Sentido del ajuste inválido: % (C = a favor, D = en contra)', p_sentido USING ERRCODE = 'BA017';
  END IF;
  v_id := fin.fn_buscar_idempotencia(p_idempotency_key, v_hash);
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  PERFORM fin.fn_validar_no_titular(p_usuario_id, p_cuenta_id);
  IF NOT EXISTS (SELECT 1 FROM core.cuenta WHERE cuenta_id = p_cuenta_id) THEN
    RAISE EXCEPTION 'Cuenta no encontrada: %', p_cuenta_id USING ERRCODE = 'BA016';
  END IF;

  INSERT INTO fin.transaccion_financiera
    (tipo_codigo, estado_codigo, cuenta_origen_id, cuenta_destino_id, monto, idempotency_key, hash_solicitud,
     descripcion, fecha_solicitud, creado_por)
  VALUES
    ('AJUSTE', 'PENDING_APPROVAL',
     CASE WHEN p_sentido = 'D' THEN p_cuenta_id END, CASE WHEN p_sentido = 'C' THEN p_cuenta_id END,
     p_monto, p_idempotency_key, v_hash, p_descripcion, clock_timestamp(), p_usuario_id)
  ON CONFLICT (idempotency_key) DO NOTHING
  RETURNING transaccion_id INTO v_id;
  RETURN coalesce(v_id, fin.fn_buscar_idempotencia(p_idempotency_key, v_hash));
END $$;
COMMENT ON FUNCTION fin.fn_crear_ajuste(bigint, bigint, numeric, char, uuid, text) IS 'Crea un ajuste PENDING_APPROVAL sin efecto en saldos. Permiso TX_AJUSTE_CREAR.';

CREATE FUNCTION fin.fn_aprobar_ajuste(p_usuario_id bigint, p_transaccion_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  t fin.transaccion_financiera%ROWTYPE; v_cuenta bigint; v_cc text; v_ahora timestamptz;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'TX_AJUSTE_APROBAR');   -- CAJERO no aprueba (RN-51)
  SELECT * INTO t FROM fin.transaccion_financiera WHERE transaccion_id = p_transaccion_id FOR UPDATE;
  IF NOT FOUND OR t.tipo_codigo <> 'AJUSTE' OR t.estado_codigo <> 'PENDING_APPROVAL' THEN
    RAISE EXCEPTION 'La transacción % no es un ajuste pendiente de aprobación', p_transaccion_id USING ERRCODE = 'BA013';
  END IF;
  IF t.creado_por = p_usuario_id THEN
    RAISE EXCEPTION 'Quien crea un ajuste no puede aprobarlo (RN-44)' USING ERRCODE = 'BA013';
  END IF;

  v_cuenta := coalesce(t.cuenta_destino_id, t.cuenta_origen_id);
  PERFORM fin.fn_validar_no_titular(p_usuario_id, v_cuenta);
  PERFORM core.fn_bloquear_cuentas(v_cuenta);
  IF t.cuenta_origen_id IS NOT NULL THEN
    PERFORM fin.fn_validar_debito(v_cuenta, t.monto);
  ELSE
    PERFORM fin.fn_validar_credito(v_cuenta);
  END IF;

  v_ahora := clock_timestamp();
  UPDATE fin.transaccion_financiera
  SET estado_codigo = 'POSTED', aprobado_por = p_usuario_id,
      fecha_contabilizacion = v_ahora, fecha_contable = fin.fn_fecha_contable(v_ahora)
  WHERE transaccion_id = p_transaccion_id;

  v_cc := fin.fn_cuenta_contable(v_cuenta);
  IF t.cuenta_destino_id IS NOT NULL THEN   -- a favor del cliente
    INSERT INTO fin.asiento_contable (transaccion_id, linea, cuenta_contable_codigo, cuenta_id, naturaleza, valor, registrado_en)
    VALUES (p_transaccion_id, 1, 'PAS_AJUSTES_PENDIENTES', NULL, 'D', t.monto, v_ahora),
           (p_transaccion_id, 2, v_cc, v_cuenta, 'C', t.monto, v_ahora);
  ELSE                                       -- en contra del cliente
    INSERT INTO fin.asiento_contable (transaccion_id, linea, cuenta_contable_codigo, cuenta_id, naturaleza, valor, registrado_en)
    VALUES (p_transaccion_id, 1, v_cc, v_cuenta, 'D', t.monto, v_ahora),
           (p_transaccion_id, 2, 'PAS_AJUSTES_PENDIENTES', NULL, 'C', t.monto, v_ahora);
  END IF;
  PERFORM fin.fn_aplicar_saldos(p_transaccion_id);
  RETURN p_transaccion_id;
END $$;
COMMENT ON FUNCTION fin.fn_aprobar_ajuste(bigint, bigint) IS 'Aprueba un ajuste: aprobador distinto del creador (RN-44), mismas reglas de estado y fondos, genera asientos y aplica saldos. Permiso TX_AJUSTE_APROBAR.';

CREATE FUNCTION fin.fn_rechazar_ajuste(p_usuario_id bigint, p_transaccion_id bigint, p_motivo text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  t fin.transaccion_financiera%ROWTYPE;
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'TX_AJUSTE_APROBAR');
  SELECT * INTO t FROM fin.transaccion_financiera WHERE transaccion_id = p_transaccion_id FOR UPDATE;
  IF NOT FOUND OR t.tipo_codigo <> 'AJUSTE' OR t.estado_codigo <> 'PENDING_APPROVAL' THEN
    RAISE EXCEPTION 'La transacción % no es un ajuste pendiente de aprobación', p_transaccion_id USING ERRCODE = 'BA013';
  END IF;
  UPDATE fin.transaccion_financiera
  SET estado_codigo = 'REJECTED', motivo_rechazo = coalesce(p_motivo, 'Rechazado por el supervisor')
  WHERE transaccion_id = p_transaccion_id;
  RETURN p_transaccion_id;
END $$;

-- Registro de solicitudes rechazadas (RN-45). Las funciones anteriores fallan con
-- error y no dejan rastro (la transacción se deshace); el canal que recibió la
-- solicitud llama a esta función en una transacción aparte para registrar el rechazo.
CREATE FUNCTION fin.fn_registrar_rechazo(
  p_usuario_id bigint, p_tipo text, p_cuenta_origen_id bigint, p_cuenta_destino_id bigint,
  p_monto numeric, p_idempotency_key uuid, p_motivo text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_permiso text := CASE p_tipo WHEN 'CONSIGNACION' THEN 'TX_CONSIGNAR' WHEN 'RETIRO' THEN 'TX_RETIRAR'
                                WHEN 'TRANSFERENCIA' THEN 'TX_TRANSFERIR' WHEN 'DEBITO' THEN 'TX_DEBITAR'
                                WHEN 'CREDITO' THEN 'TX_ACREDITAR' END;
  v_id bigint;
BEGIN
  IF v_permiso IS NULL THEN
    RAISE EXCEPTION 'Tipo de transacción no válido para registrar rechazo: %', p_tipo USING ERRCODE = 'BA017';
  END IF;
  PERFORM seg.fn_exigir_permiso(p_usuario_id, v_permiso);
  IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
    RAISE EXCEPTION 'El rechazo exige un motivo (RN-45)' USING ERRCODE = 'BA017';
  END IF;
  INSERT INTO fin.transaccion_financiera
    (tipo_codigo, estado_codigo, cuenta_origen_id, cuenta_destino_id, monto, idempotency_key,
     fecha_solicitud, creado_por, motivo_rechazo)
  VALUES
    (p_tipo, 'REJECTED', p_cuenta_origen_id, p_cuenta_destino_id, p_monto, p_idempotency_key,
     clock_timestamp(), p_usuario_id, p_motivo)
  RETURNING transaccion_id INTO v_id;
  RETURN v_id;
END $$;
COMMENT ON FUNCTION fin.fn_registrar_rechazo(bigint, text, bigint, bigint, numeric, uuid, text) IS 'Registra una solicitud rechazada con su motivo, sin asientos ni efecto en saldos (RN-45).';
