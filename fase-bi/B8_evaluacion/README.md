# B8 · Pruebas y evaluación del grupo

En B8 probamos el aplicativo publicado (https://banco-andino.onrender.com) de dos formas:

1. **Pruebas automáticas contra la nube:** ya las corrimos al cerrar B7. Dieron 110 de 110 en PASS
   con los 5 perfiles (`B5_servidor/salidas/salida_pruebas_perfiles_nube.txt`). Si en esta
   evaluación cambiamos algo, las volvemos a correr con `despliegue/b7_3_probar_nube.bat`.
2. **Evaluación del grupo (human in the loop):** cada uno de nosotros toma un perfil y lo usa en el
   celular y en el computador, siguiendo [`guia_evaluacion.md`](guia_evaluacion.md), y anota lo
   que encuentra en [`planilla_evaluacion.md`](planilla_evaluacion.md).

**Damos B8 por cerrado cuando:** las pruebas automáticas siguen en PASS, la planilla queda llena
por los cinco y cada hallazgo de gravedad Alta o Media quedó corregido (o explicado por qué no).

## Estado

| Parte | Estado |
|---|---|
| Pruebas automáticas contra la nube | 110/110 PASS (16/11/2026) |
| Guía y planilla | Listas |
| Evaluación del grupo | Juan Diego (Administrador) lista; faltan David, Jerónimo, Adrián y Miguel |
| Correcciones | 2 hallazgos corregidos (mensaje de RN-50 y vista de celular). Después de corregir: 50/50 en la revisión de pantallas y 110/110 en las pruebas de perfiles |

Cambiamos la forma de evaluar: en vez de una llamada con todos, cada uno prueba su perfil cuando
puede y le manda sus respuestas a Juan Diego. Para que no dependiéramos tanto unos de otros, el
supervisor hace su propia consignación y la reversa, y bloquea y desbloquea él mismo; solo el
ajuste (cajero → supervisor) y la cuenta destino del cliente (cajero → cliente) siguen encadenados.
