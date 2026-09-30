-- CT-2 · Sesión B: al mismo tiempo transfiere 50.000 en sentido contrario (c3 → c2).
-- Esperado: espera a A y luego termina bien. No hay interbloqueo (deadlock) porque
-- ambas funciones bloquean las cuentas en el mismo orden (menor cuenta_id primero).
SELECT valor AS caj FROM public.ct_ctx WHERE clave = 'cajero' \gset
SELECT valor AS c2  FROM public.ct_ctx WHERE clave = 'c2' \gset
SELECT valor AS c3  FROM public.ct_ctx WHERE clave = 'c3' \gset
SELECT fin.fn_transferir(:caj, :c3, :c2, 50000, gen_random_uuid()) AS transferencia_b;
