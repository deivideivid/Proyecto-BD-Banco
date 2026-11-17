# B8 · Planilla de la evaluación del grupo

Cada uno llena su parte (y la de tareas comunes) mientras prueba. En **¿Salió bien?** ponemos *Sí*,
*No* o *A medias*; en **Dónde**, *Celular* o *Computador*; la **gravedad** solo cuando algo falla
(*Alta*, *Media* o *Baja*, como dice la [guía](guia_evaluacion.md)). Si es más fácil, cada uno le
manda a Juan Diego sus respuestas por mensaje con el número de la tarea y él las pasa aquí.

**Fecha de la evaluación:** 17/11/2026 (cada uno por su cuenta)  ·  **Enlace:** https://banco-andino.onrender.com

## Tareas comunes (todos)

| Tarea | Juan Diego | David | Jerónimo | Adrián | Miguel |
|---|---|---|---|---|---|
| C1 Entrar desde el celular | Sí · celular |  |  | Sí · celular | Sí · celular |
| C2 Menú y secciones | Sí · celular |  |  | Sin evidencia | Sí · celular |
| C3 Equipo y Tecnologías | Sí · celular |  |  | Sin evidencia | Sí · celular |
| C4 Salir y botón Atrás | Sí · computador |  |  | Sí · computador (pidió entrar de nuevo) | Sí · celular |

## Cajero · David González

| Tarea | ¿Salió bien? | Dónde | Qué pasó / comentario | Gravedad |
|---|---|---|---|---|
| 1 Buscar cliente y ver ficha | Sí | Celular | Buscó la 20000000080 y abrió su ficha con las cuentas |  |
| 2 Pasar número de cuenta al cliente | Sí | Celular | Mandó al grupo: "Adrián, tu cuenta destino es 20000000080" |  |
| 3 Consignar $50.000 | Sí | Celular | Transacción 1024198, nuevo saldo 14.643.197,00 ([captura](capturas/b8_cajero_consignacion.jpg)) |  |
| 4 Retirar $20.000 | Sí | Celular | Transacción 1024199, nuevo saldo 14.623.197,00 |  |
| 5 Retirar más del saldo (debe negar) | Sí, lo negó | Celular | "Fondos insuficientes. (quedó registrado el rechazo n.º 1024200)" ([captura](capturas/b8_cajero_retiro_rechazado.jpg)) |  |
| 6 Transferir $10.000 | Sí | Celular | De la 20000000080 a la 10000000408, transacción 1024201 |  |
| 7 Crear cliente inventado y abrir cuenta | Sí | Celular | Registró "Cliente Prueba Bocho" (CC 1122334455, inventada) y confirmó la apertura de una cuenta de ahorros |  |
| 8 Bloquear una cuenta | No se hizo |  | Decidimos cerrar sin esta tarea |  |
| 9 Registrar un ajuste | Sí | Celular | Ajuste 1024203 a favor por $15.000, quedó PENDING_APPROVAL ([captura](capturas/b8_cajero_ajuste_pendiente.jpg)) |  |
| 10 Abrir estadisticas.html (debe negar) | No se hizo |  | Decidimos cerrar sin esta tarea |  |

## Supervisor · Jerónimo Soto

| Tarea | ¿Salió bien? | Dónde | Qué pasó / comentario | Gravedad |
|---|---|---|---|---|
| 1 Aprobar el ajuste | Sí (según la bitácora) | Computador | No mandó captura, pero en la bitácora Miguel encontró que `aarango` actualizó el ajuste 1024203 a las 11:59, o sea que sí lo atendió ([captura](capturas/b8_auditor_bitacora_supervisor.jpg)) |  |
| 2 Reversar la consignación | Sí | Computador | Consignó $30.000 en la 10000000148 (1024206) y la reversó con el motivo "cancelación de prueba" (reverso 1024207, [captura](capturas/b8_supervisor_reverso_hecho.jpg)) |  |
| 3 Desbloquear la cuenta | Sí | Computador | Bloqueó la 10000000148 con un motivo y la desbloqueó ([captura](capturas/b8_supervisor_desbloqueo.jpg)) |  |
| 4 Cambiar límite diario | Sí | Computador | Límite de la 10000000148 de $3.000.000 a $2.000.000 |  |
| 5 Estadísticas de su oficina y filtros | Sí | Computador | Solo Oficina Bogotá, D.C. Centro; probó el filtro de producto (Ahorros), el de mes y las 4 pestañas; en Control y calidad, 6 de 6 en PASS y puntaje 99,6 ([captura](capturas/b8_supervisor_estadisticas_oficina.jpg)) |  |
| 6 Reversar otra vez (debe negar) | Sí, lo negó | Computador | "Esta transacción ya fue reversada." y el botón queda desactivado ([captura](capturas/b8_supervisor_ya_reversada.jpg)) |  |

## Cliente · Adrián Daniel Argotte

| Tarea | ¿Salió bien? | Dónde | Qué pasó / comentario | Gravedad |
|---|---|---|---|---|
| 1 Ver saldos | Sí | Celular | Vio sus 5 cuentas con el saldo de cada una |  |
| 2 Movimientos por fechas | Sin evidencia |  | No mandó captura de esta tarea |  |
| 3 Transferir $10.000 | Sí | Celular | De la 10000000012 a la 20000000080, descripción "Toma"; transacción 1024202, nuevo saldo 7.266.416,28 ([captura](capturas/b8_cliente_transferencia_exitosa.jpg)) |  |
| 4 Transferir más del saldo (debe negar) | Sí, lo negó | Computador | "Fondos insuficientes. (quedó registrado el rechazo n.º 1024205)" ([captura](capturas/b8_cliente_fondos_insuficientes.jpg)) |  |
| 5 Cuenta que no existe (debe negar) | Sí, lo negó | Computador | Pero el mensaje era "No encontramos el registro.", que no dice qué falló ([captura](capturas/b8_cliente_cuenta_inexistente_antes.jpg)) |  |
| 6 Mis estadísticas | Sí | Computador | Entradas y salidas de los últimos 12 meses con movimiento y la gráfica por mes ([captura](capturas/b8_cliente_mis_estadisticas.jpg)) |  |

## Auditor de datos · Miguel Andrés Pava

| Tarea | ¿Salió bien? | Dónde | Qué pasó / comentario | Gravedad |
|---|---|---|---|---|
| 1 Calidad: 76 pruebas | Sí | Celular | Puntaje general 99,6; 74 PASS, 2 WARNING (Database Design y Data Quality) y 0 FAIL; las que no pasaron salen primero ([captura](capturas/b8_auditor_calidad_celular.jpg)) |  |
| 2 Cuadres en 0 | Sí | Computador | Los tres controles en 0; con "Volver a revisar" siguen en 0 |  |
| 3 Bitácora: consignación, reverso y ajuste | Sí | Computador | Cajero `fcardenas`: 1024198, 1024199, 1024200, 1024201 y 1024203 ([captura](capturas/b8_auditor_bitacora_cajero.jpg)); supervisor `aarango`: 1024206, su reverso 1024207 y el UPDATE del ajuste 1024203; administrador `aperez`: el usuario 272 (prueba.b8), su rol y los cambios ([captura](capturas/b8_auditor_bitacora_admin_ids.jpg)) |  |
| 4 Ingresos: intento fallido | Sí | Computador | Aparecen ingresos exitosos y fallidos ([captura](capturas/b8_auditor_ingresos.jpg)) |  |
| 5 Estadísticas de control | Sí | Celular | Se entiende todo y se ve muy bien en el celular |  |
| 6 Abrir caja.html (debe negar) | Sí, lo negó | Computador | Lo devolvió a su sección de auditor; no lo dejó operar |  |

## Administrador · Juan Diego Ortiz

| Tarea | ¿Salió bien? | Dónde | Qué pasó / comentario | Gravedad |
|---|---|---|---|---|
| 1 Crear usuario de prueba | Sí | Computador | Se creó `prueba.b8` y salió "Usuario creado" |  |
| 2 Asignar rol CAJERO | Sí | Computador | Salió "rol asignado" y apareció CAJERO en la fila |  |
| 3 Dar acceso y entrar con él | Sí | Computador | Salió la contraseña temporal y entramos como cajero en una ventana de incógnito |  |
| 4 Quitar acceso: la sesión deja de servir | Sí | Computador | Al recargar la ventana de incógnito nos sacó a Ingresar |  |
| 5 Revocar rol y desactivar | Sí | Computador | Quedó "Sin rol" e INACTIVO |  |
| 6 Darse rol o acceso a sí mismo (debe negar) | Sí, lo negó | Computador | Mensaje: "Los datos no cumplen una regla del banco." |  |
| 7 Estadísticas de todo el banco | Sí | Celular | Todo el banco (1.000.000 de transacciones) y los filtros funcionaron |  |

## Preguntas generales (cada uno)

| Pregunta | Juan Diego | David | Jerónimo | Adrián | Miguel |
|---|---|---|---|---|---|
| Facilidad de uso (1 a 5) | 5 |  |  | No las mandó | 5 |
| Apariencia (1 a 5) | 5 |  |  | No las mandó | 5 |
| ¿Se usa cómodo en el celular? (1 a 5) | 4 |  |  | No las mandó | 5 |
| Lo que más nos gustó | Que el sitio es interactivo y flexible con el usuario, y muy atractivo visualmente |  |  | No las mandó | Que la bitácora deja ver con claridad quién hizo cada cosa y cuándo, que los cuadres se revisan en segundos y que el auditor no puede operar aunque cambie el enlace |
| Lo que confundió o cambiaríamos | Ajustaría un poco la versión de celular; la de computador está perfecta |  |  | No las mandó | En la bitácora: ver el nombre del usuario y no solo su número, y en los UPDATE qué campo cambió (antes y después) |
| ¿Algún mensaje de error que no se entendió? | Ninguno |  |  | No las mandó | Ninguno |

## Lo que encontramos y qué hicimos

| # | Quién lo encontró | Perfil y tarea | Gravedad | Qué pasaba | Qué cambiamos | ¿Quedó resuelto? |
|---|---|---|---|---|---|---|
| 1 | Juan Diego | Administrador, tarea 6 | Baja | Al intentar asignarse un rol, la base lo frena (bien), pero el aviso decía "Los datos no cumplen una regla del banco.", que no explica por qué ([captura](capturas/b8_admin_rol_a_si_mismo_antes.jpg)) | El servidor reconoce la regla RN-50 por el nombre de la restricción y ahora dice "No puede asignarse roles a sí mismo: otro administrador debe hacerlo." | Sí |
| 2 | Juan Diego | Celular, en general | Media | En el celular las listas largas eran muy largas (Usuarios y roles medía unas 23.000 px con los 100 empleados), las filas de las tablas no se distinguían bien entre sí y algunos textos de la barra de abajo se partían en dos líneas | Cada fila es ahora una tarjeta propia con su título; las listas muestran de a 10 con un botón "Mostrar 10 más"; los botones ocupan el ancho y miden al menos 44 px; los campos usan letra de 16 px para que el teléfono no haga zoom; la barra de abajo usa nombres cortos. Usuarios y roles pasó a unos 3.600 px ([después](capturas/b8_celular_admin_usuarios_despues.png), [antes](../B6_interfaces/capturas/celular_admin_usuarios.png)) | Sí |
| 3 | David (revisión de sus capturas) | Cajero, movimientos de la cuenta | Baja | En "Últimos movimientos" del cajero y en el detalle del supervisor, el estado salía con el código en inglés (POSTED, PENDING_APPROVAL, REJECTED) y el tipo en mayúsculas ([captura](capturas/b8_cajero_movimientos_estados_en_ingles.jpg)) | Ahora salen en español: Aplicada, Pendiente de aprobación, Rechazada; y el tipo como Transferencia, Ajuste, Retiro… (los colores siguen saliendo del código) | Sí |
| 4 | Jerónimo | Supervisor, Reversar | Baja | Al buscar una transacción que todavía se puede reversar, salía la palabra "null" encima del botón Reversar ([captura](capturas/b8_supervisor_reversar_null_antes.jpg)) | La pantalla armaba el detalle con un espacio vacío que el navegador escribía como "null"; ahora lo quitamos antes de mostrarlo. También el tipo de la transacción sale en español en la confirmación del reverso | Sí |
| 5 | Miguel | Auditor, Bitácora | Baja (sugerencia) | En la columna Registro salía solo el número ("usuario_id 272"), sin el nombre, y no se podía confirmar a simple vista que fuera `prueba.b8` ([captura](capturas/b8_auditor_bitacora_admin_ids.jpg)) | El registro ahora muestra el login del usuario, el código del rol y el número de la cuenta (por ejemplo "usuario prueba.b8 (n.º 272) · rol CAJERO") | Sí |
| 6 | Miguel | Auditor, Bitácora | Baja (sugerencia) | En los UPDATE no se veía qué campo cambió: la modificación del rol mostraba lo mismo que la asignación | Agregamos la columna Cambios con cada campo, el valor anterior y el nuevo. Así se ve que la "modificación del rol" era la revocación (`vigente_hasta: vacío → fecha`) y la del usuario, la desactivación (`estado: ACTIVO → INACTIVO`) | Sí |
| 7 | Adrián | Cliente, Transferir a una cuenta que no existe | Baja | La transferencia se negó bien, pero el mensaje decía "No encontramos el registro.", sin decir que lo que no existe es la cuenta destino ([captura](capturas/b8_cliente_cuenta_inexistente_antes.jpg)) | Ahora dice "No existe una cuenta del Banco Andino con ese número. Revise la cuenta destino." (en caja ya decía "No existe la cuenta de destino.") | Sí |
