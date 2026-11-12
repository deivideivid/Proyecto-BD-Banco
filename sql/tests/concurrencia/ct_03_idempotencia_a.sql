-- CT-3 · Sesión A: consigna 40.000 en c4 con la clave de idempotencia K y espera.
\if :{?espera} \else \set espera 10 \endif
SELECT valor AS caj FROM public.ct_ctx WHERE clave = 'cajero' \gset
SELECT valor AS c4  FROM public.ct_ctx WHERE clave = 'c4' \gset
SELECT llave AS k   FROM public.ct_ctx WHERE clave = 'llave_ct3' \gset
BEGIN;
SELECT fin.fn_consignar(:caj, :c4, 40000, :'k') AS consignacion_a;
\echo 'Sesión A: consignación con clave K hecha, esperando antes del COMMIT (ejecute ya la sesión B)...'
SELECT pg_sleep(:espera);
COMMIT;
\echo 'Sesión A: COMMIT'
