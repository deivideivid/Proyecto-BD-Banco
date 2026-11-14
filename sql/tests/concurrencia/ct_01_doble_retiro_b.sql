-- CT-1 · Sesión B: intenta retirar 80.000 de la misma cuenta al mismo tiempo.
-- Esperado: queda esperando el bloqueo de A y, cuando A confirma, falla con BA003
-- (fondos insuficientes). Sin SELECT … FOR UPDATE ambas pasarían (doble retiro).
SELECT valor AS caj FROM public.ct_ctx WHERE clave = 'cajero' \gset
SELECT valor AS c1  FROM public.ct_ctx WHERE clave = 'c1' \gset
\set VERBOSITY default
SELECT fin.fn_retirar(:caj, :c1, 80000, gen_random_uuid()) AS retiro_sesion_b;
