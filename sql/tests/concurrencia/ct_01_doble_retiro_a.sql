-- CT-1 · Sesión A: retira 80.000 de c1 (saldo 100.000) y mantiene la transacción abierta.
\if :{?espera} \else \set espera 10 \endif
SELECT valor AS caj FROM public.ct_ctx WHERE clave = 'cajero' \gset
SELECT valor AS c1  FROM public.ct_ctx WHERE clave = 'c1' \gset
BEGIN;
SELECT fin.fn_retirar(:caj, :c1, 80000, gen_random_uuid()) AS retiro_sesion_a;
\echo 'Sesión A: retiro hecho, esperando antes del COMMIT (ejecute ya la sesión B)...'
SELECT pg_sleep(:espera);
COMMIT;
\echo 'Sesión A: COMMIT'
