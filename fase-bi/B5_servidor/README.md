# B5 · Servidor del aplicativo y permisos

En este gate hicimos el servidor en Python (FastAPI) con el inicio de sesión, los 5 perfiles y
todas las operaciones del banco contra la base. El servidor no inventa reglas: llama a las mismas
funciones seguras que probamos en G3 y G7 (`sql/14_functions.sql`), y la base vuelve a revisar
cada permiso. Las pantallas de cada perfil van en B6.

- `sql/b5_01_esquema_app.sql` - esquema `app` (accesos con contraseña bcrypt y bitácora de
  ingresos), usuario técnico del canal digital, funciones del Cliente, accesos de demostración y
  el usuario `app_servidor`.
- `sql/b5_02_pruebas_bd.sql` - 30 pruebas de permisos directamente en la base.
- `ejecutar_b5.bat` - corre los dos scripts y al final pide la contraseña nueva de `app_servidor`.
- `pruebas/probar_perfiles.py` y `probar_b5.bat` - 104 pruebas contra el servidor prendido, perfil
  por perfil.
- `matriz_permisos.md` - qué puede hacer cada perfil y quién lo frena si intenta otra cosa.
- El código del servidor está en `fase-bi/aplicativo/servidor/`.

## Cómo quedó armado

**Dos controles, uno detrás del otro.** El servidor deja pasar a cada perfil solo a sus rutas
(si no, responde 403). Y aunque el servidor se equivocara, la base también lo frena:

- El servidor entra con **un solo usuario, `app_servidor`, que no tiene ningún permiso propio**.
  En cada petición abre una transacción y se pone el rol del perfil que inició sesión
  (`SET LOCAL ROLE banco_cajero`, `banco_supervisor`...). Lo creamos con `INHERIT FALSE`: puede
  ponerse esos roles, pero sin ponérselos no puede leer ni una tabla. Así cumplimos lo que pidió
  Jerónimo para el despliegue: conectarnos con un usuario que solo tenga los grupos `banco_*`.
- Dentro de cada función del banco, `seg.fn_exigir_permiso` revisa además el permiso del empleado
  (RN-28, RN-51). Por eso un supervisor que use la cuenta de un cajero tampoco puede reversar.

**Inicio de sesión.** La base del banco no guarda contraseñas (desde G3), así que creamos
`app.acceso` con el hash bcrypt de cada acceso. El servidor nunca lee esa tabla: usa funciones
(`app.fn_acceso_buscar`, `app.fn_sesion`). Con 5 contraseñas malas seguidas el acceso se bloquea
15 minutos, y el mensaje es el mismo si el usuario no existe, para no delatar quién tiene acceso.
La sesión va en una cookie firmada y en cada petición le preguntamos a la base si el acceso sigue
vigente: cuando el administrador le quita el rol a alguien, esa persona queda por fuera al
instante (lo probamos). Si nadie usa la sesión en 30 minutos, se cierra.

**El Cliente.** Las funciones del banco piden siempre un empleado (RN-10), así que creamos el
usuario técnico `canal.digital` con un rol nuevo que solo tiene `TX_TRANSFERIR`. El cliente usa
las funciones `app.fn_cliente_*`, que en la base revisan que la cuenta sea suya antes de llamar a
`fin.fn_transferir`. El rol del cliente en la base (`banco_cliente_app`) no puede leer ninguna
tabla: solo esas funciones.

**Errores en lenguaje sencillo.** Cada código de la base se vuelve un mensaje para la persona
(por ejemplo, BA003 → "Fondos insuficientes", 42501 → "La base de datos no permite esta operación a
su perfil"). Cuando el banco rechaza una consignación, retiro o transferencia por estado, fondos
o límite, el servidor deja el rechazo registrado con su motivo (RN-45), como en los datos de G4.

**Otras protecciones.** Cada operación lleva una clave única (idempotencia, RN-38): si llega dos
veces, no se cobra dos veces. Las operaciones exigen una cabecera propia del aplicativo (contra
CSRF) y las páginas van con cabeceras de seguridad (CSP, sin marcos). El cajero y el supervisor
solo operan cuentas de su oficina. Los montos viajan como texto para no perder centavos.

## Cómo correrlo en el computador de Juan Diego

1. Doble clic en `ejecutar_b5.bat`. Pide la contraseña de `postgres`, corre los scripts (debe
   terminar en **B5 PERMISOS EN LA BASE = PASS**) y al final pide dos veces la contraseña nueva de
   `app_servidor`. Esa contraseña no queda en ningún archivo.
2. Doble clic en `fase-bi/aplicativo/iniciar_local.bat` y escribir la contraseña de
   `app_servidor`. La primera vez instala dos librerías nuevas y genera las contraseñas de los 5
   accesos de demostración: las muestra una vez y quedan en
   `fase-bi/aplicativo/accesos_demo.local.txt`, que no se sube a GitHub.
3. Con el aplicativo prendido, doble clic en `probar_b5.bat`. Debe terminar en
   **B5 PERFILES = PASS**.

| Acceso | Perfil | Quién es en la base |
|---|---|---|
| `demo.cliente` | Cliente | Un cliente persona natural con varias cuentas en pesos |
| `demo.cajero` | Cajero | Un cajero de la Oficina Bogotá, D.C. Centro |
| `demo.supervisor` | Supervisor | El supervisor de esa misma oficina |
| `demo.auditor` | Auditor de datos | Un auditor |
| `demo.admin` | Administrador | Un administrador de seguridad |

## Cuándo damos B5 por cerrado

Cada perfil solo puede hacer lo suyo, y lo probamos con intentos que deben fallar.

## Resultado

Lo probamos primero en una copia de la base (creada con `CREATE DATABASE ... TEMPLATE`):

- **En la base:** 30 de 30 pruebas en PASS. Cada rol intentó lo que no le toca y la base lo negó
  (por ejemplo: el cajero no reversa, el auditor no consigna, el administrador no ve cuentas ni se
  asigna roles a sí mismo, el cliente no puede leer tablas ni mover dinero de una cuenta ajena).
- **Contra el servidor:** 104 de 104 en PASS. La matriz de 5 perfiles × 7 secciones dio 200 donde
  toca y 403 donde no. Además hicimos operaciones de verdad (consignar, retirar, transferir,
  registrar un cliente, abrir, activar, bloquear, desbloquear, reversar, cerrar, ajustes con
  aprobación de otro) y al final el auditor confirmó que la contabilidad sigue cuadrada.

## Lo que nos pasó

- **El supervisor no podía ver los ajustes pendientes.** Las consultas buscaban el login del
  empleado en `seg.usuario`, y desde G3 el cajero y el supervisor no pueden leer el esquema `seg`.
  Lo dejamos así (está bien que no lo vean) y quitamos ese dato de las consultas.
- **La transferencia del cliente fallaba al confirmar, no al hacerla.** La revisión de que la
  transacción cuadre (`trg_transaccion_cuadrada`) está diferida hasta el COMMIT, y ahí corría con
  el rol del cliente, que no puede leer `fin.transaccion_financiera`. Nuestra prueba en la base no
  lo vio porque deshacía todo antes del COMMIT. Lo arreglamos en dos partes: la función del cliente
  corre esa revisión dentro de ella (`SET CONSTRAINTS ALL IMMEDIATE`), y la prueba de la base ahora
  también fuerza esas revisiones con el rol de cada prueba. Comprobamos que con la función vieja la
  prueba sí falla.

## Lo que queda para B6

Las pantallas de cada perfil (por ahora hay un ingreso y un panel provisional), y que el
administrador pueda darles acceso al aplicativo a los empleados nuevos que crea.
