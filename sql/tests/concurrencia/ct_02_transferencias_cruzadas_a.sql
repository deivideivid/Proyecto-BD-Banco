-- CT-2 · Sesión A: transfiere 100.000 de c2 a c3 y mantiene la transacción abierta.
\if :{?espera} \else \set espera 10 \endif
SELECT valor AS caj FROM public.ct_ctx WHERE clave = 'cajero' \gset
SELECT valor AS c2  FROM public.ct_ctx WHERE clave = 'c2' \gset
SELECT valor AS c3  FROM public.ct_ctx WHERE clave = 'c3' \gset
BEGIN;
SELECT fin.fn_transferir(:caj, :c2, :c3, 100000, gen_random_uuid()) AS transferencia_a;
\echo 'Sesión A: transferencia c2 → c3 hecha, esperando antes del COMMIT (ejecute ya la sesión B)...'
SELECT pg_sleep(:espera);
COMMIT;
\echo 'Sesión A: COMMIT'
