# Matriz de decisiones de IA (consolidada)

| Campo | Valor |
|---|---|
| Proyecto | Laboratorio de Ingeniería de Bases de Datos Relacionales Aumentada con IA — Banco Andino Colombia |
| Gate | **G8 — Cierre, evidencia y defensa** |
| Fecha | 2026-10-01 |
| Contenido | Las 46 decisiones (IA-01 a IA-46) tomadas sobre recomendaciones de la IA en G1–G7, con su evidencia |
| Prompts | Texto de cada prompt y respuesta en [`prompts/prompts_y_respuestas.md`](../prompts/prompts_y_respuestas.md) (P-01 a P-12) |

Regla de trabajo del laboratorio: **IA propone → el equipo revisa → PostgreSQL ejecuta → las pruebas miden → el quality gate decide.** Ninguna recomendación se aceptó solo porque la IA la dio; cada decisión tiene una evidencia que se puede volver a ejecutar.

## 1. Resumen

| Gate | Aceptar | Modificar | Rechazar | Corregir | Aplazar | Total |
|---|---|---|---|---|---|---|
| G1 | 7 | 3 | 1 | 0 | 0 | 11 |
| G2 | 3 | 1 | 1 | 0 | 0 | 5 |
| G3 | 2 | 2 | 1 | 0 | 0 | 5 |
| G4 | 1 | 2 | 2 | 1 | 0 | 6 |
| G5 | 0 | 1 | 2 | 1 | 0 | 4 |
| G6 | 2 | 1 | 0 | 1 | 1 | 5 |
| G7 | 4 | 1 | 3 | 2 | 0 | 10 |
| **Total** | **19** | **11** | **10** | **5** | **1** | **46** |

Qué significa cada decisión:

- **Aceptar:** se adoptó tal cual porque la evidencia la respaldó.
- **Modificar:** la idea servía, pero el equipo la cambió.
- **Rechazar:** no se adoptó.
- **Corregir:** la IA cometió un error que las pruebas o la revisión del equipo detectaron.
- **Aplazar:** se dejó para el gate donde se podía medir.

En total, **27 de 46 recomendaciones (59 %) no se aceptaron tal cual**: se modificaron, se rechazaron o se corrigieron.

## 2. Dónde la IA se equivocó o fue mejorada (para la defensa)

| # | Error o mejora | Cómo se detectó | Qué se hizo | Decisión |
|---|---|---|---|---|
| 1 | El generador del millón dejó 482 movimientos en los 180 días previos a una inactivación y ningún rechazo por límite diario | Validación del lote 2 (24 controles) | Se corrigió el cálculo de los tramos de inactividad y se agregaron intentos que exceden el límite: 24/24 PASS | IA-24 |
| 2 | Carga masiva con los triggers apagados: 3,2 millones de filas sin rastro en la auditoría | Quality gate de G6, prueba A04 = FAIL | Cada carga deja su registro en `aud.log_auditoria`: A04 = PASS | IA-32 |
| 3 | Propuso indexar las 5 consultas más lentas (reportes que leen casi toda la tabla) | `EXPLAIN (ANALYZE, BUFFERS)` de G7 | Los cuellos de botella reales eran las operaciones: retiro de 198,9 a 2,4 ms con un solo índice | IA-37 |
| 4 | El índice del extracto hizo más lento un reporte (A06/W10), aunque el costo estimado bajó | Comparación antes/después en G7 | Se documentó la regresión y se mitigó solo en ese reporte | IA-39 a IA-41 |
| 5 | Comparaba los retiros con el límite **actual** y no con el vigente ese día (A07) | Resultado imposible: días "al 180 %" | Se reconstruye el límite vigente desde los eventos | IA-29 |
| 6 | Subconsulta correlacionada que tardaba 2 min 39 s (I06) | Tiempo medido en G5 | Reescrita con una CTE: milisegundos | IA-28 |
| 7 | Validación cruzada que sumaba pesos y dólares (VC1) | Revisión del resultado | Se filtra una sola moneda | IA-30 |
| 8 | Máximo fijo de 4 titulares para todos los productos | Revisión del negocio (nómina y empresarial) | Máximo por producto (RN-16) | IA-07 |
| 9 | Interpretó "las primeras 10.000 cuentas" como el total | Conteo 104 del perfil | Se regeneró con 50.000 | IA-22 |
| 10 | Scripts sin UTF-8: tildes dañadas en Windows; EXPLAIN de PostgreSQL 18 con filas decimales | Ejecución en el PC del equipo | Se forzó UTF-8 y se redondean las filas; probado en PostgreSQL 16 y 18 | IA-45, IA-46 |

## 3. Matriz completa

| ID | Gate | Prompt | Recomendación o resultado de la IA | Decisión | Evidencia | Justificación | Fuente |
|---|---|---|---|---|---|---|---|
| IA-01 | G1 | P-01 | Entregar, en la fase de planeación, código SQL casi completo: función de transferencia, triggers de inmutabilidad y partida doble, auditoría y script de quality gate. | **Rechazar** (para G1) | Regla central del laboratorio (sección 1: "No se acepta código porque la IA lo dijo") y criterio pedagógico (sección 17). | El código se construirá y validará por el equipo en G3. Del plan solo se conservan como referencia los riesgos identificados. | [01_especificacion.md](../docs/01_especificacion.md) |
| IA-02 | G1 | P-01 | Redactar 42 reglas de negocio con notación técnica de mecanismos de implementación (constraint, trigger, función, prueba de calidad). | **Modificar** | Criterio de G1: "≥30 reglas verificables"; en G1 aún no existe modelo lógico ni DDL. | En P-04 las reglas se reescribieron en lenguaje de negocio, con una prueba de verificación y un resultado esperado binario. El mecanismo de implementación se decide en G2–G3. | [01_especificacion.md](../docs/01_especificacion.md) |
| IA-03 | G1 | P-04 | Lista de 40 reglas, varias de ellas compuestas (evaluaban más de una condición). | **Modificar** | Revisión del equipo: las reglas propuestas sobre municipio/oficina, cierre de cuenta, doble partida, roles y auditoría combinaban 2 o 3 condiciones en una sola. | Se dividieron en reglas atómicas para que cada prueba falle por una sola razón. Resultado: 54 reglas (RN-01 a RN-54). | [01_especificacion.md](../docs/01_especificacion.md) |
| IA-04 | G1 | P-01 | Modelar clientes con supertipo `cliente` y subtipos 1:1 `persona_natural` y `persona_juridica`, en lugar de tabla única o `INHERITS`. | **Aceptar** | Documentación de PostgreSQL: en tablas con `INHERITS` las restricciones `UNIQUE` y las claves foráneas no se propagan a las tablas hijas. Análisis de alternativas en el Anexo A, sección A.4. | Garantiza documento único (RN-01), evita nulos y permite reglas por tipo de cliente. | [01_especificacion.md](../docs/01_especificacion.md) |
| IA-05 | G1 | P-04, P-05 | S1: una cuenta bloqueada recibe créditos pero no origina débitos. | **Aceptar** | Análisis de negocio en la [sección 1, S1](#s1--cuenta-bloqueada). | Protege los fondos sin rechazar pagos entrantes de terceros; produce reglas verificables (RN-34, RN-35, RN-43). | [01_especificacion.md](../docs/01_especificacion.md) |
| IA-06 | G1 | P-04, P-05 | S2: edad mínima de 18 años para ser titular. | **Aceptar** | Mayoría de edad en Colombia a los 18 años; la titularidad de menores exige representante legal, entidad no incluida en el alcance. | Regla simple y verificable contra la fecha de nacimiento (RN-08) sin agregar entidades. | [01_especificacion.md](../docs/01_especificacion.md) |
| IA-07 | G1 | P-04, P-05 | S3: máximo fijo de 4 titulares por cuenta. | **Modificar** | Revisión del equipo: un máximo único no aplica a nómina (cuenta de un empleado) ni a la cuenta empresarial (titular: la empresa). | El máximo se definió como parámetro del producto: AHORROS 4, CORRIENTE 4, NOMINA 1, EMPRESARIAL 1 (RN-16). | [01_especificacion.md](../docs/01_especificacion.md) |
| IA-08 | G1 | P-04, P-05 | S4: cuenta empresarial como producto adicional. | **Aceptar** | Comparación con alternativas (CDT, ahorro programado) en la [sección 1, S4](#s4--producto-adicional). | Reutiliza el modelo de cuenta, incorpora a las personas jurídicas y soporta la distribución de 50.000 cuentas. | [01_especificacion.md](../docs/01_especificacion.md) |
| IA-09 | G1 | P-04, P-05 | S5: el volumen de 1.000.000 corresponde a transacciones `POSTED`, incluidos reversos y ajustes aprobados; las rechazadas son adicionales. | **Aceptar** | Documento del laboratorio: el reverso es un tipo de transacción financiera y el volumen se exige "con ledger asociado"; las rechazadas no generan ledger. | Conteo inequívoco y verificable con una sola consulta en G4. | [01_especificacion.md](../docs/01_especificacion.md) |
| IA-10 | G1 | P-01 | Evitar el tipo `money` y `FLOAT` para importes; usar `NUMERIC`. | **Aceptar** | Contrato de calidad del laboratorio ("0 FLOAT/REAL para dinero"). Prueba en PostgreSQL 16: `SELECT '1234.56'::money;` devuelve un texto con formato dependiente de la configuración regional (`lc_monetary`). | Precisión exacta en cálculos monetarios y resultados independientes de la configuración del servidor. | [01_especificacion.md](../docs/01_especificacion.md) |
| IA-11 | G1 | P-01 | Mantener el promedio de 5 cuentas por cliente concentrando la mayor cantidad de cuentas en personas jurídicas. | **Aceptar** | Cálculo: 50.000 cuentas ÷ 10.000 clientes = 5; el control de distribución del laboratorio exige "pocos clientes con muchas cuentas". | Evita una distribución uniforme artificial y resulta coherente con el uso empresarial. Se implementará en G4. | [01_especificacion.md](../docs/01_especificacion.md) |
| IA-12 | G2 | P-06 (2A) | Índice único parcial para impedir titular duplicado vigente (H-06). | **Aceptar** | Prueba negativa en la sección 9; recarga 20/20 y 24/24 PASS | Cierra un hueco real de la PK con vigencia. | [02_modelo_logico.md](../docs/02_modelo_logico.md) |
| IA-13 | G2 | P-06 (2A) | CHECK: fechas contables solo en POSTED; aprobador solo en AJUSTE (H-07, H-08). | **Aceptar** | Pruebas negativas en la sección 9 | Refuerza RN-44 y RN-45 sin costo. | [02_modelo_logico.md](../docs/02_modelo_logico.md) |
| IA-14 | G2 | P-06 (2A) | Agregar `moneda_codigo` a cada asiento (H-10). | **Modificar** | Análisis de dependencias: la moneda depende de la cuenta | Guardarla sería redundante; se deriva de la cuenta y los reportes agrupan por moneda. | [02_modelo_logico.md](../docs/02_modelo_logico.md) |
| IA-15 | G2 | P-06 (2A) | Reemplazar el CHECK de documentos de usuario por FK compuesta (H-05). | **Rechazar** | Catálogo de documentos estable (5 valores) | El cambio no mejora ninguna regla; se revisa si el catálogo crece. | [02_modelo_logico.md](../docs/02_modelo_logico.md) |
| IA-16 | G2 | P-06 (2A) | Mantener saldo, estado y límite en la cuenta como caché con reconciliación (H-01, H-02). | **Aceptar** | RN-48 = 0 diferencias en 2.000.000 de asientos | Necesario para OLTP; controlado y probado. | [02_modelo_logico.md](../docs/02_modelo_logico.md) |
| IA-17 | G3 | P-07 (2B) | Operaciones como funciones `SECURITY DEFINER` con `search_path` fijo y sin permisos directos a tablas. | **Aceptar** | T42 a T45 | Mínimo privilegio verificable. | [03_construccion.md](../docs/03_construccion.md) |
| IA-18 | G3 | P-07 (2B) | `SELECT … FOR UPDATE` en orden de `cuenta_id` y aislamiento `READ COMMITTED`. | **Aceptar** | CT-1 a CT-4 | Evita doble retiro e interbloqueos. | [03_construccion.md](../docs/03_construccion.md) |
| IA-19 | G3 | P-07 (2B) | Crear en G3 índices para todas las claves foráneas. | **Rechazar** (por ahora) | Criterio de G7: "un índice sin consulta que lo justifique" | Se crean en G7 con `EXPLAIN` antes y después. | [03_construccion.md](../docs/03_construccion.md) |
| IA-20 | G3 | P-07 (2B) | Auditar con trigger cada inserción también durante la carga masiva. | **Modificar** | Carga de 3.000.000 de filas | Los triggers se desactivan en la carga (solo el dueño puede) y se valida en bloque. | [03_construccion.md](../docs/03_construccion.md) |
| IA-21 | G3 | P-07 (2B) | Vista de estado por eventos con `LATERAL` por cuenta. | **Modificar** | Prueba sobre 1.000.000: 3 min 25 s → 4 s | Reescrita con `DISTINCT ON`. | [03_construccion.md](../docs/03_construccion.md) |
| IA-22 | G4 | P-08 (3) | Generar "las primeras 10.000 cuentas" como un lote de 10.000 cuentas. | **Rechazar / corregir** | El equipo aclaró que eran 50.000 cuentas | La IA interpretó mal la instrucción; se regeneró con 50.000 (conteo 104). | [04_datos_sinteticos.md](../docs/04_datos_sinteticos.md) |
| IA-23 | G4 | P-08 (3) | Tomar de una búsqueda web los nombres de los municipios DIVIPOLA. | **Modificar** | Algunos nombres devueltos no correspondían al código | Se usaron solo códigos verificados (capitales y municipios confirmados en listados reales). | [04_datos_sinteticos.md](../docs/04_datos_sinteticos.md) |
| IA-24 | G4 | P-08 (3) | Primera versión del generador del millón. | **Modificar** | La validación encontró 482 movimientos en los 180 días previos a una inactivación y 0 rechazos por límite diario | Se corrigió el tramo de inactividad y se agregaron intentos que exceden el límite: 24/24 PASS. | [04_datos_sinteticos.md](../docs/04_datos_sinteticos.md) |
| IA-25 | G4 | P-08 (3) | Medir el tamaño de la base como 571 MB. | **Corregir** | La medición incluía tablas temporales de la validación | Tamaño real: 475 MB. Aun así se descarta el plan gratis de Supabase (IA-26). | [04_datos_sinteticos.md](../docs/04_datos_sinteticos.md) |
| IA-26 | G4 | P-08 (3) | Montar la base completa en Supabase gratis para compartirla. | **Rechazar** | Límite de 500 MB del plan gratis; con los índices de G7 se supera | Cada integrante carga la base local; los datos son idénticos por la semilla. | [04_datos_sinteticos.md](../docs/04_datos_sinteticos.md) |
| IA-27 | G4 | P-08 (3) | Saldos en 0 al inicio de la ventana de 24 meses. | **Aceptar** | Perfil 503: 0 saldos inválidos | Simplificación documentada (sección 6). | [04_datos_sinteticos.md](../docs/04_datos_sinteticos.md) |
| IA-28 | G5 | P-09 (4) | Subconsulta correlacionada que calcula el promedio del producto dentro del `WHERE` (I06). | **Modificar** | 2 min 39 s en la primera ejecución | Se precalcula el promedio en una CTE y la subconsulta solo lo consulta: milisegundos. | [g5_results.md](../evidence/g5_results.md) |
| IA-29 | G5 | P-09 (4) | Comparar los retiros del día con el límite actual de la cuenta (A07). | **Rechazar / corregir** | Días "al 180 %" que no violaban RN-37 | Se compara con el límite vigente ese día, reconstruido desde los eventos. | [g5_results.md](../evidence/g5_results.md) |
| IA-30 | G5 | P-09 (4) | Validación cruzada del saldo AHORROS sumando pesos y dólares (VC1). | **Corregir** | El ledger no separa moneda por cuenta contable | Se filtra COP en los dos caminos (decisión DM-09 de G2). | [g5_results.md](../evidence/g5_results.md) |
| IA-31 | G5 | P-09 (4) | Crear índices ya para acelerar I02, I09 y A06. | **Rechazar** (por ahora) | Tiempos medidos arriba | Se hace en G7 con `EXPLAIN` antes y después, como exige el laboratorio. | [g5_results.md](../evidence/g5_results.md) |
| IA-32 | G6 | P-07 (2B) / P-10 (5) | En G3 la IA propuso cargar con los triggers desactivados (DC-07) sin advertir que así las cargas no quedaban auditadas. | **Modificar** | A04 = FAIL (7 tablas sin rastro) | Se mantiene la carga rápida, pero ahora cada carga deja su registro en `aud.log_auditoria`: A04 = PASS. | [g6_quality_before_after.md](../evidence/g6_quality_before_after.md) |
| IA-33 | G6 | P-10 (5) | Umbral de 5 % para clientes sin correo. | **Aceptar como WARNING** | C04 = 7,1 % | Campo opcional; no se inventan correos. Se recomienda actualización de datos. | [g6_quality_before_after.md](../evidence/g6_quality_before_after.md) |
| IA-34 | G6 | P-10 (5) | Prueba de FK sin índice (34 casos). | **Aplazar a G7** | DS05 = WARNING | Solo se crean índices con una consulta que los justifique en `EXPLAIN`; evita sobreindexar. | [g6_quality_before_after.md](../evidence/g6_quality_before_after.md) |
| IA-35 | G6 | P-10 (5) | Validar el gate metiendo defectos en una copia de la base. | **Aceptar** | 7/7 defectos detectados; QUALITY_GATE = FAIL en la copia | Demuestra que las pruebas sí detectan errores. | [g6_quality_before_after.md](../evidence/g6_quality_before_after.md) |
| IA-36 | G6 | P-10 (5) | Primera versión de la prueba de defectos: corría el gate tal cual y sobrescribía `evidence/g6_quality_results.csv` con los resultados de la copia dañada. | **Corregir** | Revisión del equipo antes de ejecutar | Se agregó la variable `qg_sin_csv`; la prueba de defectos guarda su propio archivo (`g6_defectos_results.csv`). | [g6_quality_before_after.md](../evidence/g6_quality_before_after.md) |
| IA-37 | G7 | P-09 (4) / P-11 (6) | En G5 la IA marcó como candidatas a índice las 5 consultas más lentas (A06, A02, A10, A09, I07). | **Rechazar** | Secciones 5 y 7 | Son reportes que leen casi todo; los cuellos de botella reales estaban en las operaciones (W01, W06). | [g7_explain.md](../evidence/g7_explain.md) |
| IA-38 | G7 | P-11 (6) | Índice `asiento_contable (cuenta_id, registrado_en)`. | **Modificar** | IX-3: 39 MB | Se hizo parcial (`cuenta_id IS NOT NULL`): excluye el 36 % de las líneas que ninguna consulta por cuenta usa. | [g7_explain.md](../evidence/g7_explain.md) |
| IA-39 | G7 | P-11 (6) | Índice cubriente `INCLUDE (naturaleza, valor)` para corregir la regresión de W10. | **Rechazar** | 60 MB; W10 en 2,8 s | No resolvió la regresión y aumentó el tamaño un 54 %. | [g7_explain.md](../evidence/g7_explain.md) |
| IA-40 | G7 | P-11 (6) | Subir `work_mem` o reescribir W10 con `GROUP BY`. | **Rechazar** | 1,55 s y 1,9 s | Ninguna mejora; el cuello es el cálculo numérico. | [g7_explain.md](../evidence/g7_explain.md) |
| IA-41 | G7 | P-11 (6) | Desactivar el index scan solo en la transacción del reporte W10. | **Aceptar** | W10S: 1,43 s | Mitigación con alcance limitado; IX-3 se mantiene para la operación diaria. | [g7_explain.md](../evidence/g7_explain.md) |
| IA-42 | G7 | P-11 (6) | Reescribir W09 y el procedimiento de inactivación con `registrado_en`. | **Aceptar** | 428,7 → 74,3 ms; OP3 22,7 → 1,1 s; mismas 12.365 cuentas | Equivalencia verificada en los 2.000.000 de asientos. | [g7_explain.md](../evidence/g7_explain.md) |
| IA-43 | G7 | P-11 | Demostrar el RBAC con usuarios `NOLOGIN` y `SET ROLE`, deshaciendo cada acción permitida. | **Aceptar** | 23/23 PASS; la base no cambia | Prueba real de permisos sin contraseñas en el repositorio ni datos modificados. | [g7_security.md](../evidence/g7_security.md) |
| IA-44 | G7 | P-11 | Incluir una prueba de que el rol de base de datos no basta (S13). | **Aceptar** | S13 = DENEGADO (app, BA001) | Demuestra el segundo nivel (permisos del empleado), que es el que exige RN-51. | [g7_security.md](../evidence/g7_security.md) |
| IA-45 | G7 | P-11 (6) | Scripts de G7 sin `SET client_encoding = 'UTF8'`. En SQL Shell de Windows las tildes del CSV quedaron dañadas ("OperaciÃ³n"). | **Corregir** | `g7_explain_antes.csv` generado en el PC del equipo | Se forzó UTF-8 en 7 scripts y se reparó el CSV. La misma causa había dañado las tildes de los catálogos creados con `run_all.sql` en G3; se corrige reconstruyendo la base en G8. | [g7_explain.md](../evidence/g7_explain.md) |
| IA-46 | G7 | P-11 (6) | El script de medición suponía que EXPLAIN devuelve filas enteras; PostgreSQL 18 devuelve "1.00". | **Corregir** | Error en el PC del equipo (PostgreSQL 18.6) | Se redondea el valor; probado en PostgreSQL 16 y 18. | [g7_explain.md](../evidence/g7_explain.md) |
