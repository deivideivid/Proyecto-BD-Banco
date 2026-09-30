-- CT-3 · Sesión B: repite EXACTAMENTE la misma solicitud (misma clave K) al mismo tiempo,
-- como cuando el cliente pulsa dos veces el botón.
-- Esperado: devuelve el MISMO transaccion_id que la sesión A; solo queda un movimiento.
SELECT valor AS caj FROM public.ct_ctx WHERE clave = 'cajero' \gset
SELECT valor AS c4  FROM public.ct_ctx WHERE clave = 'c4' \gset
SELECT llave AS k   FROM public.ct_ctx WHERE clave = 'llave_ct3' \gset
SELECT fin.fn_consignar(:caj, :c4, 40000, :'k') AS consignacion_b;
