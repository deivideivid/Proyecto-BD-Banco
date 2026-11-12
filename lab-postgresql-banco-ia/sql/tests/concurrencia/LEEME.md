# Pruebas de concurrencia (G3)

Con estas pruebas demostramos que las operaciones no fallan cuando **dos personas actúan al mismo tiempo**:
doble retiro, transferencias cruzadas, doble clic (misma clave de idempotencia) y doble reverso.

Necesitan **dos sesiones** y datos confirmados, por eso las corrimos en una base de pruebas aparte.

## Cómo preparamos la base (una vez)

Desde la carpeta `lab-postgresql-banco-ia`, en PowerShell:

```powershell
psql -U postgres -c "CREATE DATABASE banco_andino_ct"
psql -U postgres -d banco_andino_ct -f sql/run_all.sql
psql -U postgres -d banco_andino_ct -f sql/tests/concurrencia/ct_00_preparar.sql
```

## Cómo corrimos cada prueba (dos ventanas)

Para CT-1 a CT-4 abrimos dos ventanas: en la primera corrimos el archivo `_a` y, **antes de 10 segundos**, en la segunda el archivo `_b`.

| Prueba | Ventana 1 | Ventana 2 | Qué pasó en la ventana 2 |
|---|---|---|---|
| CT-1 | `ct_01_doble_retiro_a.sql` | `ct_01_doble_retiro_b.sql` | Espera y luego **BA003 Fondos insuficientes** |
| CT-2 | `ct_02_transferencias_cruzadas_a.sql` | `ct_02_transferencias_cruzadas_b.sql` | Espera y luego **termina bien** (sin deadlock) |
| CT-3 | `ct_03_idempotencia_a.sql` | `ct_03_idempotencia_b.sql` | Espera y devuelve **el mismo número** de transacción que A |
| CT-4 | `ct_04_doble_reverso_a.sql` | `ct_04_doble_reverso_b.sql` | Espera y luego **BA008 ya fue reversada** |

Así lo hicimos con CT-1 (cada línea en una ventana distinta):

```powershell
psql -U postgres -d banco_andino_ct -f sql/tests/concurrencia/ct_01_doble_retiro_a.sql
psql -U postgres -d banco_andino_ct -f sql/tests/concurrencia/ct_01_doble_retiro_b.sql
```

## Cómo lo verificamos

```powershell
psql -U postgres -d banco_andino_ct -f sql/tests/concurrencia/ct_99_verificar.sql
```

Todas las filas nos dieron **PASS**. El resultado quedó guardado en `evidence/g3_tests.txt`.

**Por qué funciona:** cada operación bloquea las filas de las cuentas con `SELECT … FOR UPDATE`
(siempre en orden de `cuenta_id`, así dos transferencias cruzadas no se bloquean mutuamente),
la clave de idempotencia es `UNIQUE` y el reverso bloquea la transacción original.
Usamos el nivel de aislamiento por defecto (`READ COMMITTED`): con los bloqueos de fila es suficiente
y evita los reintentos que exigiría `SERIALIZABLE`.
