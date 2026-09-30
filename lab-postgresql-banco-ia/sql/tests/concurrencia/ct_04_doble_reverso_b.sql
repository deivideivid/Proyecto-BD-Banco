-- CT-4 · Sesión B: otro supervisor intenta reversar la MISMA transacción al mismo tiempo.
-- Esperado: espera a A y luego falla con BA008 (ya fue reversada, RN-42).
SELECT valor AS sup FROM public.ct_ctx WHERE clave = 'super' \gset
SELECT valor AS tx  FROM public.ct_ctx WHERE clave = 'tx_a_reversar' \gset
SELECT llave AS k   FROM public.ct_ctx WHERE clave = 'llave_ct4_b' \gset
\set VERBOSITY default
SELECT fin.fn_reversar(:sup, :tx, :'k', 'CT-4 sesión B') AS reverso_b;
