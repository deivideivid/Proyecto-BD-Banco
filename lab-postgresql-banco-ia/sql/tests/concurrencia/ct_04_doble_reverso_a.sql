-- CT-4 · Sesión A: un supervisor reversa la consignación inicial de c4 y espera.
\if :{?espera} \else \set espera 10 \endif
SELECT valor AS sup FROM public.ct_ctx WHERE clave = 'super' \gset
SELECT valor AS tx  FROM public.ct_ctx WHERE clave = 'tx_a_reversar' \gset
SELECT llave AS k   FROM public.ct_ctx WHERE clave = 'llave_ct4_a' \gset
BEGIN;
SELECT fin.fn_reversar(:sup, :tx, :'k', 'CT-4 sesión A') AS reverso_a;
\echo 'Sesión A: reverso hecho, esperando antes del COMMIT (ejecute ya la sesión B)...'
SELECT pg_sleep(:espera);
COMMIT;
\echo 'Sesión A: COMMIT'
