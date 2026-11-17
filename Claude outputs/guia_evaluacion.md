# B8 · Guía de la evaluación del grupo (human in the loop)

Cada uno de nosotros usa el aplicativo publicado como lo usaría una persona del banco, con un
perfil, y anota en [`planilla_evaluacion.md`](planilla_evaluacion.md) lo que salió bien, lo que
falló y lo que confundió. Las pruebas automáticas ya pasaron (110 de 110 contra la nube y 50
revisiones de pantallas), así que aquí buscamos lo que una máquina no ve: si se entiende, si los
mensajes son claros, si en el celular se usa cómodo y si algo se siente raro.

**Enlace:** https://banco-andino.onrender.com. Si nadie lo ha abierto en los últimos 15 minutos,
la primera carga tarda cerca de un minuto.

## Quién prueba qué

| Integrante | Perfil | Usuario |
|---|---|---|
| David González | Cajero | `demo.cajero` |
| Jerónimo Soto | Supervisor | `demo.supervisor` (si no puede, lo toma Juan Diego al final) |
| Adrián Daniel Argotte | Cliente | `demo.cliente` |
| Miguel Andrés Pava | Auditor de datos | `demo.auditor` |
| Juan Diego Ortiz | Administrador | `demo.admin` |

Juan Diego le pasa a cada uno **solo su** contraseña, por mensaje privado, del archivo
`accesos_demo_nube.local.txt` (el de la nube, no el de la base local). No la compartimos en el
grupo.

## Reglas

- Cada uno prueba **en el celular y en el computador**: la mitad de las tareas en cada uno.
- Los datos son ficticios. Si un formulario pide cédula, nombres o teléfono, **inventamos** datos;
  nunca ponemos los nuestros ni los de otra persona.
- Montos pequeños (entre $10.000 y $100.000) para no descuadrar las cifras de Estadísticas.
- Varias tareas se encadenan entre perfiles (el cajero crea algo que el supervisor aprueba y el
  auditor ve en la bitácora). Por eso hacemos la evaluación **al mismo tiempo**, en una llamada, y
  nos pasamos los números que haga falta.
- Si algo falla, anotamos qué hicimos, qué esperábamos y qué salió (mejor con captura), y
  seguimos con la siguiente tarea.
- Gravedad: **Alta** = no deja hacer la tarea o muestra algo que no debería; **Media** = se puede
  hacer pero cuesta o el mensaje confunde; **Baja** = detalle de apariencia o de texto.

## Orden sugerido (unos 40 minutos)

1. Todos entran y hacen las tareas comunes (C1 a C4).
2. Cajero: tareas 1 a 9. Avisa en la llamada el número de la consignación (tarea 3), la cuenta
   bloqueada (tarea 8) y que registró el ajuste (tarea 9).
3. Supervisor y cliente trabajan con lo que pasó el cajero; el administrador hace lo suyo.
4. Al final, el auditor busca en la bitácora lo que hicimos todos.
5. Cada uno llena las preguntas generales de la planilla.

## Tareas comunes (todos)

- **C1.** Entrar con su usuario desde el celular. ¿Se entiende la pantalla de ingreso?
- **C2.** Abrir el menú (hamburguesa en el celular) y recorrer sus secciones.
- **C3.** Abrir **Equipo** y la hoja de vida de dos compañeros. Abrir **Tecnologías**.
- **C4.** Salir. Con el botón *Atrás* del navegador, revisar que ya no se ven datos.

## Cajero (`demo.cajero`)

1. Buscar un cliente por apellido y abrir su ficha y sus cuentas.
2. Pasarle al cliente (Adrián) por la llamada un número de cuenta de 11 dígitos para su tarea 4.
3. Consignar $50.000 en una cuenta. Anotar el número de la transacción y pasárselo al supervisor.
4. Retirar $20.000 de la misma cuenta.
5. Intentar retirar más de lo que tiene la cuenta: debe negarlo con un mensaje claro.
6. Transferir $10.000 entre dos cuentas.
7. Crear un cliente persona natural **con datos inventados** y abrirle una cuenta.
8. Bloquear una cuenta y pasarle el número al supervisor para que la desbloquee.
9. Registrar un ajuste pequeño y avisarle al supervisor que quedó pendiente.
10. Escribir `estadisticas.html` en la barra del navegador: no debe dejarlo ver.

## Supervisor (`demo.supervisor`)

1. **Pendientes:** aprobar el ajuste que registró el cajero.
2. **Reversar:** buscar la consignación del cajero por su número y reversarla con un motivo.
3. Desde **Caja**, buscar la cuenta que bloqueó el cajero y desbloquearla.
4. Cambiarle el límite diario de retiro a una cuenta.
5. **Estadísticas:** revisar que solo ve su oficina y probar los filtros (mes y producto).
6. Intentar reversar la misma transacción otra vez: debe negarlo.

## Cliente (`demo.cliente`)

1. **Mis cuentas:** ver los saldos. ¿Se entienden?
2. **Movimientos:** consultar los de una cuenta en un rango de fechas.
3. **Transferir** $10.000 a la cuenta que le pasó el cajero. Revisar la confirmación y el
   comprobante.
4. Intentar transferir más de lo que tiene: debe negarlo con un mensaje claro.
5. Transferir a un número que no existe (por ejemplo `00000000000`): debe decir que no existe.
6. **Mis estadísticas:** ¿se entiende lo que muestra?

## Auditor de datos (`demo.auditor`)

1. **Calidad:** revisar las 76 pruebas del quality gate.
2. **Cuadres:** comprobar que la contabilidad sigue cuadrada después de lo que hicimos.
3. **Bitácora:** encontrar la consignación, el reverso y el ajuste que hicimos hoy.
4. **Ingresos:** encontrar algún intento fallido de entrada.
5. **Estadísticas de control:** ¿se entiende?
6. Escribir `caja.html` en la barra del navegador: no debe dejarlo operar.

## Administrador (`demo.admin`)

1. **Usuarios:** crear un usuario interno de prueba (login inventado, por ejemplo `prueba.b8`).
2. Asignarle el rol CAJERO.
3. **Accesos:** darle acceso al aplicativo. Con la contraseña temporal que sale, entrar con ese
   usuario en una ventana de incógnito o en el celular.
4. Quitarle el acceso y comprobar que esa sesión deja de servir.
5. Revocarle el rol y desactivar el usuario.
6. Intentar darse un rol o un acceso a sí mismo: debe negarlo.
7. **Estadísticas:** ver todo el banco y probar los filtros.
