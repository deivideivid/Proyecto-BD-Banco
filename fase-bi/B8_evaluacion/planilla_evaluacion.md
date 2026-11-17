# B8 · Planilla de la evaluación del grupo

Cada uno llena su parte (y la de tareas comunes) mientras prueba. En **¿Salió bien?** ponemos *Sí*,
*No* o *A medias*; en **Dónde**, *Celular* o *Computador*; la **gravedad** solo cuando algo falla
(*Alta*, *Media* o *Baja*, como dice la [guía](guia_evaluacion.md)). Si es más fácil, cada uno le
manda a Juan Diego sus respuestas por mensaje con el número de la tarea y él las pasa aquí.

**Fecha de la evaluación:** 17/11/2026 (cada uno por su cuenta)  ·  **Enlace:** https://banco-andino.onrender.com

## Tareas comunes (todos)

| Tarea | Juan Diego | David | Jerónimo | Adrián | Miguel |
|---|---|---|---|---|---|
| C1 Entrar desde el celular | Sí · celular |  |  |  |  |
| C2 Menú y secciones | Sí · celular |  |  |  |  |
| C3 Equipo y Tecnologías | Sí · celular |  |  |  |  |
| C4 Salir y botón Atrás | Sí · computador |  |  |  |  |

## Cajero · David González

| Tarea | ¿Salió bien? | Dónde | Qué pasó / comentario | Gravedad |
|---|---|---|---|---|
| 1 Buscar cliente y ver ficha |  |  |  |  |
| 2 Pasar número de cuenta al cliente |  |  |  |  |
| 3 Consignar $50.000 |  |  |  |  |
| 4 Retirar $20.000 |  |  |  |  |
| 5 Retirar más del saldo (debe negar) |  |  |  |  |
| 6 Transferir $10.000 |  |  |  |  |
| 7 Crear cliente inventado y abrir cuenta |  |  |  |  |
| 8 Bloquear una cuenta |  |  |  |  |
| 9 Registrar un ajuste |  |  |  |  |
| 10 Abrir estadisticas.html (debe negar) |  |  |  |  |

## Supervisor · Jerónimo Soto

| Tarea | ¿Salió bien? | Dónde | Qué pasó / comentario | Gravedad |
|---|---|---|---|---|
| 1 Aprobar el ajuste |  |  |  |  |
| 2 Reversar la consignación |  |  |  |  |
| 3 Desbloquear la cuenta |  |  |  |  |
| 4 Cambiar límite diario |  |  |  |  |
| 5 Estadísticas de su oficina y filtros |  |  |  |  |
| 6 Reversar otra vez (debe negar) |  |  |  |  |

## Cliente · Adrián Daniel Argotte

| Tarea | ¿Salió bien? | Dónde | Qué pasó / comentario | Gravedad |
|---|---|---|---|---|
| 1 Ver saldos |  |  |  |  |
| 2 Movimientos por fechas |  |  |  |  |
| 3 Transferir $10.000 |  |  |  |  |
| 4 Transferir más del saldo (debe negar) |  |  |  |  |
| 5 Cuenta que no existe (debe negar) |  |  |  |  |
| 6 Mis estadísticas |  |  |  |  |

## Auditor de datos · Miguel Andrés Pava

| Tarea | ¿Salió bien? | Dónde | Qué pasó / comentario | Gravedad |
|---|---|---|---|---|
| 1 Calidad: 76 pruebas |  |  |  |  |
| 2 Cuadres en 0 |  |  |  |  |
| 3 Bitácora: consignación, reverso y ajuste |  |  |  |  |
| 4 Ingresos: intento fallido |  |  |  |  |
| 5 Estadísticas de control |  |  |  |  |
| 6 Abrir caja.html (debe negar) |  |  |  |  |

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
| Facilidad de uso (1 a 5) | 5 |  |  |  |  |
| Apariencia (1 a 5) | 5 |  |  |  |  |
| ¿Se usa cómodo en el celular? (1 a 5) | 4 |  |  |  |  |
| Lo que más nos gustó | Que el sitio es interactivo y flexible con el usuario, y muy atractivo visualmente |  |  |  |  |
| Lo que confundió o cambiaríamos | Ajustaría un poco la versión de celular; la de computador está perfecta |  |  |  |  |
| ¿Algún mensaje de error que no se entendió? | Ninguno |  |  |  |  |

## Lo que encontramos y qué hicimos

| # | Quién lo encontró | Perfil y tarea | Gravedad | Qué pasaba | Qué cambiamos | ¿Quedó resuelto? |
|---|---|---|---|---|---|---|
| 1 | Juan Diego | Administrador, tarea 6 | Baja | Al intentar asignarse un rol, la base lo frena (bien), pero el aviso decía "Los datos no cumplen una regla del banco.", que no explica por qué ([captura](capturas/b8_admin_rol_a_si_mismo_antes.jpg)) | El servidor reconoce la regla RN-50 por el nombre de la restricción y ahora dice "No puede asignarse roles a sí mismo: otro administrador debe hacerlo." | Sí |
| 2 | Juan Diego | Celular, en general | Media | En el celular las listas largas eran muy largas (Usuarios y roles medía unas 23.000 px con los 100 empleados), las filas de las tablas no se distinguían bien entre sí y algunos textos de la barra de abajo se partían en dos líneas | Cada fila es ahora una tarjeta propia con su título; las listas muestran de a 10 con un botón "Mostrar 10 más"; los botones ocupan el ancho y miden al menos 44 px; los campos usan letra de 16 px para que el teléfono no haga zoom; la barra de abajo usa nombres cortos. Usuarios y roles pasó a unos 3.600 px ([después](capturas/b8_celular_admin_usuarios_despues.png), [antes](../B6_interfaces/capturas/celular_admin_usuarios.png)) | Sí |
