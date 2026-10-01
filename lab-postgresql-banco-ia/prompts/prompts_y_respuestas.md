# Registro de prompts y respuestas de IA

| Campo | Valor |
|---|---|
| Gates cubiertos | G0–G7 |
| Herramienta | Claude (Anthropic), en la aplicación de escritorio |
| Última actualización | 2026-09-30 |
| Matriz de decisiones | [Anexo C de la especificación](../docs/01_especificacion.md#anexo-c--matriz-de-decisiones-sobre-ia) (IA-01 a IA-11) y [sección 13 del modelo lógico](../docs/02_modelo_logico.md#13-matriz-ia-nuevas-entradas-de-g2) (IA-12 en adelante) |

## Reglas de uso aplicadas

- No se ingresaron datos personales reales, credenciales ni información confidencial.
- Se conservan los prompts completos y un resumen de las respuestas relevantes.
- Ninguna respuesta se incorporó sin revisión: los errores detectados y las decisiones tomadas se documentan en cada entrada.

## Índice

| ID | Fecha | Gate | Objetivo | Decisiones derivadas |
|---|---|---|---|---|
| [P-01](#p-01--plan-de-implementación-por-fases) | 2026-09-16 | G1 (preparación) | Analizar el documento del laboratorio y obtener un plan por fases con los 14 requisitos críticos. | IA-01, IA-02, IA-04, IA-10, IA-11 |
| [P-02](#p-02--revisión-del-alcance-de-la-respuesta) | 2026-09-16 | G1 (preparación) | Revisar si la respuesta anterior excedía lo solicitado. | IA-01 |
| [P-03](#p-03--resumen-para-el-equipo) | 2026-09-17 | G1 (preparación) | Obtener un resumen sencillo para socializar con el equipo. | — |
| [P-04](#p-04--entendimiento-del-negocio-y-reglas) | 2026-09-17 | G1 | Entender el negocio y proponer al menos 30 reglas verificables. | IA-03, IA-05 a IA-09 |
| [P-05](#p-05--selección-de-supuestos-y-documentación-de-g1) | 2026-09-17 | G1 | Seleccionar los 5 supuestos y documentar los puntos pendientes de G1. | IA-05 a IA-09 |
| [Prompt 1 del laboratorio](#prompt-1-del-laboratorio--analizar-el-caso) | 2026-09-17 | G1 | Correspondencia entre el Prompt 1 oficial y los resultados obtenidos. | — |
| [P-06](#p-06--prompt-2a-del-laboratorio--auditor-del-modelo) | 2026-09-29 | G2 | Auditar el modelo relacional implementado (Prompt 2A oficial). | IA-12 a IA-16 |
| [P-07](#p-07--prompt-2b-del-laboratorio--generar-sql-profesional) | 2026-09-30 | G3 | Construir la implementación completa y probarla (Prompt 2B oficial). | IA-17 a IA-21 |
| [P-08](#p-08--prompt-3-del-laboratorio--generar-10k50k1m) | 2026-09-17 a 2026-09-30 | G4 | Generar, cargar y perfilar los datos sintéticos (Prompt 3 oficial). | IA-22 a IA-27 |
| [P-09](#p-09--prompt-4-del-laboratorio--30-consultas) | 2026-09-30 | G5 | Proponer, escribir, validar y explicar las 30 consultas (basado en el Prompt 4). | IA-28 a IA-31 |
| [P-10](#p-10--prompt-5-del-laboratorio--auditor-de-calidad) | 2026-09-30 | G6 | Auditar la base sin corregirla, corregir los FAIL y probar que el gate detecta defectos (Prompt 5). | IA-32 a IA-36 |
| [P-11](#p-11--prompt-6-del-laboratorio--revisor-de-performance) | 2026-10-01 | G7 | Analizar 10 consultas con EXPLAIN antes y después, justificar índices y demostrar el RBAC (Prompt 6). | IA-37 a IA-44 |

---

## P-01 · Plan de implementación por fases

**Fecha:** 2026-09-16 · **Gate:** preparación de G1

<details>
<summary><strong>Prompt completo</strong></summary>

```text
Eres un ingeniero de bases de datos senior especializado en arquitectura OLTP bancaria y auditoría de calidad con PostgreSQL 16+. Tu rol es analizar exhaustivamente el proyecto de Banco Andino Colombia y estructurar un plan de implementación paso a paso que anticipe y resuelva los 14 requisitos críticos antes de que el estudiante comience a codificar.

---

**TAREA PRINCIPAL**

Analiza el documento de especificaciones "Laboratorio_PostgreSQL_Aumentado_con_IA (1).docx" y desglosa el proyecto de bases de datos bancario en una **hoja de ruta estructurada por fases**, integrando explícitamente estos 14 requisitos en cada sección:

1. **Seguridad** — Control de acceso basado en roles (RBAC), encriptación, auditoría
2. **Disponibilidad** — Estrategia de backup, recuperación, tiempo de inactividad permisible
3. **Tolerancia a Fallos** — Redundancia, conmutación por error, resiliencia
4. **Integridad Referencial** — Relaciones FK, cascadas, restricciones de negocio
5. **Optimización - Rendimiento** — Índices, particionamiento, EXPLAIN ANALYZE
6. **Concurrencia** — Prevención de lost update, niveles de aislamiento, locks
7. **Modelamiento** — Diagrama ER, relaciones, cardinalidades
8. **Normalización 3FN** — Descomposición, dependencias funcionales, eliminación de anomalías
9. **Datos (Calidad)** — Validación, restricciones CHECK, reglas de negocio, volumen (10.000 clientes, 50.000 cuentas, 1.000.000 transacciones)
10. **Consultas (Estructura)** — Queries complejas, vistas, procedimientos almacenados
11. **Observabilidad - Métricas** — Logging, monitoreo, alertas
12. **Marco Normativo - DAMA** — Gobernanza de datos, linaje, calidad
13. **Interoperabilidad** — Integración con otros sistemas, formatos de intercambio
14. **Mantenimiento Automático** — Vacío, ANALYZE, monitoreo de índices, limpieza de logs, archivado

---

**CONTEXTO DEL PROYECTO**

- **Caso:** Banco Andino Colombia (OLTP transaccional)
- **Alcance:** Clientes, cuentas (ahorro/corriente), productos, transacciones financieras, eventos administrativos, doble partida contable, seguridad (RBAC), auditoría
- **Restricciones técnicas obligatorias:**
  - `NUMERIC` para dinero (NO FLOAT)
  - `TIMESTAMPTZ` para fechas
  - Integridad referencial estricta
  - Inmutabilidad de transacciones contabilizadas
  - Concurrencia controlada sin lost update
  - Generación de datos con Python/Faker con semilla fija, respetando reglas de negocio
- **Metodología:** Quality Gates (G0-G8) con scripts numerados y validación mediante `EXPLAIN (ANALYZE, BUFFERS)`
- **IA como herramienta:** El estudiante debe mantener una Matriz de Decisiones documentando qué sugerencias de IA fueron aceptadas, modificadas o rechazadas

---

**ESTRUCTURA DE TU RESPUESTA**

Presenta el desglose en esta secuencia:

1. **Fase 0: Análisis de Especificaciones**
   - Resume los requisitos clave del documento
   - Identifica conflictos potenciales entre requisitos
   - Define el alcance exacto del modelo de datos

2. **Fase 1: Modelamiento (Requisitos 7, 8, 4)**
   - Diagrama ER conceptual
   - Tablas principales con atributos clave
   - Relaciones y cardinalidades
   - Dependencias funcionales y normalización a 3FN

3. **Fase 2: Seguridad e Integridad (Requisitos 1, 4, 9)**
   - Esquema de RBAC (roles, permisos, usuarios)
   - Restricciones CHECK y validaciones de dominio
   - Políticas de encriptación para datos sensibles
   - Auditoría de cambios

4. **Fase 3: Concurrencia y Transacciones (Requisitos 6, 3, 10)**
   - Niveles de aislamiento transaccional
   - Estrategia de locks y prevención de deadlock
   - Tolerancia a fallos: recuperación, rollback
   - Procedimientos almacenados para operaciones críticas

5. **Fase 4: Rendimiento y Optimización (Requisito 5)**
   - Estrategia de indexación (PK, FK, columnas de búsqueda frecuente)
   - Análisis de costos con EXPLAIN
   - Identificación de queries N+1 u otras ineficiencias
   - Particionamiento si aplica

6. **Fase 5: Disponibilidad y Observabilidad (Requisitos 2, 11, 13)**
   - Estrategia de backup (tipo, frecuencia, RPO/RTO)
   - Recuperación ante desastres
   - Métricas clave (latencia, throughput, errores)
   - Logging y alertas
   - Puntos de integración con otros sistemas

7. **Fase 6: Gobernanza y Mantenimiento (Requisitos 12, 14)**
   - Política DAMA: linaje de datos, propietarios, calidad
   - Tareas de mantenimiento automático: vacío, ANALYZE, monitoreo de índices
   - Limpieza de logs históricos
   - Archivado de datos antiguos
   - Calendarios y automatización con pg_cron o similar

8. **Fase 7: Generación de Datos (Requisito 9)**
   - Script Python/Faker con semilla fija
   - Reglas de negocio aplicadas (ej. no más de N cuentas por cliente, saldo mínimo)
   - Validación de volumen (10.000 clientes, 50.000 cuentas, 1.000.000 transacciones)

9. **Fase 8: Testing y Quality Gates**
   - Validaciones G0-G8
   - Scripts numerados reproducibles
   - Evidencia con EXPLAIN (ANALYZE, BUFFERS)
   - Matriz de Decisiones para sugerencias de IA

---

**INSTRUCCIONES CRÍTICAS**

- **Sé específico:** Incluye nombres de tablas, columnas, tipos de dato, restricciones exactas derivadas del documento
- **Anticipa problemas:** Señala dónde el diseño podría violar reglas de negocio, generar anomalías o fallar en concurrencia
- **Justifica decisiones:** Explica por qué cada requisito es importante para un banco (contexto de negocio)
- **Proporciona ejemplos concretos:** Para cada fase, da DDL inicial, restricciones, o queries de ejemplo (sin ejecutarlas, solo como referencia)
- **Estructura con profundidad progresiva:** Comienza abstracto (conceptos), luego desciende a detalles técnicos (DDL, índices, transacciones)

---

**NOTAS FINALES**

- Asume que el estudiante tiene conocimiento de PostgreSQL básico pero necesita guía en arquitectura compleja
- El output es un **plan de trabajo detallado**, no código ejecutable — el código lo escribirá el estudiante
- Enfatiza dónde la IA puede sugerir soluciones, pero el estudiante debe validar todas contra las reglas de negocio

* no estamos desarrollando nada aun, ESTAMOS EN FASE DE PLANEACIÓN Y DISEÑO
```

</details>

**Respuesta relevante (resumen):** plan de nueve fases publicado como página web y archivo Markdown. Incluía el análisis del documento, 16 conflictos entre requisitos, la estrategia supertipo/subtipos para clientes, un ERD preliminar, reglas de negocio, estrategias de concurrencia, rendimiento, respaldo, gobernanza y generación de datos, además de fragmentos de SQL de referencia.

**Errores o problemas detectados por el equipo:**

- Excedió el alcance solicitado: entregó código SQL casi funcional en una fase declarada de planeación y diseño.
- Adelantó entregables propios de gates posteriores (catálogo de consultas de G5, diseño del quality gate de G6).
- Profundizó en requisitos que no forman parte de la rúbrica del laboratorio.
- Redactó las reglas de negocio con notación de mecanismos de implementación, prematura para G1.

**Decisiones derivadas:** IA-01 (rechazar el código para esta fase), IA-02, IA-04, IA-10, IA-11.

---

## P-02 · Revisión del alcance de la respuesta

**Fecha:** 2026-09-16 · **Gate:** preparación de G1

**Prompt:**

```text
oye, me puedes explicar SIN HACER OTRO DOCUMENTO que hiciste aca, por que creo que te pedi hacer cosas muy basicas, no todo el trabajo
```

**Respuesta relevante (resumen):** la IA reconoció el exceso de alcance e identificó qué partes del plan correspondían a trabajo del estudiante (código, reglas de negocio, consultas y matriz de decisiones). Recomendó conservar únicamente el análisis del documento, el orden de trabajo y los riesgos anticipados.

**Decisión derivada:** IA-01.

---

## P-03 · Resumen para el equipo

**Fecha:** 2026-09-17 · **Gate:** preparación de G1

**Prompt:**

```text
Ok pero ahorita le voy a decir a mis compañeros de grupo sobre qué trata esto y que hace, me podrías hacer un resumen entendible y súper sencillo de todo lo que me mandaste porfa
```

**Respuesta relevante (resumen):** explicación en lenguaje sencillo del laboratorio, de los gates G0–G8, de las condiciones de reprobación técnica y de los primeros pasos. Se utilizó para socializar el proyecto con el equipo.

**Decisiones derivadas:** ninguna.

---

## P-04 · Entendimiento del negocio y reglas

**Fecha:** 2026-09-17 · **Gate:** G1

**Prompt:**

```text
Listo ya hicimos el G0 ahora, vamos a empezar a hacer el G1 y necesito que me ayudes a hacer lo siguiente, G1: entender el negocio y escribir mínimo 30 reglas (por ejemplo, "no se puede retirar más de lo que hay en la cuenta"). y explicame paso por paso que fue lo que hiciste, haces y harás
```

**Respuesta relevante (resumen):** descripción del método (lectura del caso, actores, entidades, separaciones obligatorias, formulación de reglas verificables), entendimiento del negocio, 40 reglas agrupadas por dominio con su forma de verificación y cinco supuestos para validar.

**Errores o problemas detectados por el equipo:**

- Varias reglas eran compuestas y evaluaban más de una condición a la vez.
- El máximo de 4 titulares no aplicaba de igual forma a todos los productos.

**Decisiones derivadas:** IA-03, IA-05 a IA-09.

---

## P-05 · Selección de supuestos y documentación de G1

**Fecha:** 2026-09-17 · **Gate:** G1

**Prompt:**

```text
You are a project documentation specialist helping finalize academic project deliverables for GitHub.

Your task: I need you to select the best solutions for 5 assumptions I previously discussed with you (choose the options that align with highest quality and strongest project viability), then help me resolve 7 specific points required to complete my G1 deliverable.

**What I need:**
1. For each of the 5 assumptions: state the assumption, explain why you're selecting this solution, and note how it strengthens the project
2. For the 7 G1 points: provide clear, actionable resolutions for each one
3. Format everything as markdown files (.md) organized for GitHub — either as a single comprehensive file or multiple files (whichever structure makes the most sense for clarity)
4. Use professional documentation language suitable for class submission
5. Include enough context and explanation that the documentation stands alone — instructors should understand the reasoning without needing to ask follow-up questions

**Output structure:**
- Start with a summary section explaining the 5 assumptions you've selected and the rationale
- Then address each of the 7 G1 points with solutions
- Ensure the files are ready to push directly to GitHub as project progress documentation

This is your deliverable for tomorrow's class, so make it complete and presentation-ready.
```

**Respuesta relevante (resumen):** selección justificada de los supuestos S1–S5, depuración de las reglas a 54 reglas atómicas, especificación del dominio, ERD conceptual, matriz de decisiones inicial y este registro de prompts.

**Decisiones derivadas:** IA-05 a IA-09 (confirmación de supuestos, con modificación del S3).

---

## Prompt 1 del laboratorio · Analizar el caso

El documento del laboratorio define el siguiente prompt para G1:

```text
Actúa como arquitecto de datos senior, DBA PostgreSQL y especialista en sistemas bancarios OLTP.
Diseña el dominio de una entidad ficticia "Banco Andino Colombia". NO generes todavía el SQL final.
Incluye: departamentos/municipios/oficinas; clientes persona natural y jurídica; productos; cuentas; titularidad N:M; eventos de cuenta; transacciones; doble partida; usuarios/roles/permisos; auditoría.
Condiciones:
- cliente ≠ usuario interno;
- eventos administrativos ≠ transacciones financieras;
- una cuenta puede tener varios titulares;
- toda transacción POSTED debe ser inmutable;
- correcciones por reverso/compensación;
- toda operación crítica debe poder auditarse;
- volumen objetivo: 10K clientes, 50K cuentas, 1M transacciones.
Entrega en este orden:
1) actores y procesos; 2) entidades y propósito; 3) atributos esenciales; 4) relaciones/cardinalidades; 5) catálogos/estados; 6) mínimo 30 reglas de negocio verificables; 7) riesgos de consistencia; 8) decisiones que requieren validación humana; 9) ERD Mermaid.
Finaliza con una autocrítica: qué está sobrediseñado, subdiseñado o ambiguo.
```

Las salidas exigidas por este prompt se obtuvieron en las sesiones P-01, P-04 y P-05 y, tras la revisión del equipo, quedaron consolidadas así:

| Salida exigida | Ubicación en la entrega |
|---|---|
| 1) Actores y procesos | [Especificación §2](../docs/01_especificacion.md#a2-actores-y-procesos) |
| 2) Entidades y propósito | [Especificación §3](../docs/01_especificacion.md#a3-entidades-y-propósito) |
| 3) Atributos esenciales | [Especificación §3](../docs/01_especificacion.md#a3-entidades-y-propósito) y [ERD](../docs/01_especificacion.md#anexo-b--diagrama-entidad-relación) |
| 4) Relaciones y cardinalidades | [Especificación §5](../docs/01_especificacion.md#a5-relaciones-y-cardinalidades) |
| 5) Catálogos y estados | [Especificación §6](../docs/01_especificacion.md#a6-catálogos-y-estados) |
| 6) Mínimo 30 reglas verificables | [Especificación §8](../docs/01_especificacion.md#a8-reglas-de-negocio-verificables) (54 reglas) |
| 7) Riesgos de consistencia | [Especificación §9](../docs/01_especificacion.md#a9-riesgos-de-consistencia) |
| 8) Decisiones que requieren validación humana | [Especificación §10](../docs/01_especificacion.md#a10-decisiones-que-requieren-validación-humana) |
| 9) ERD Mermaid | [Anexo B de la especificación](../docs/01_especificacion.md#anexo-b--diagrama-entidad-relación) y [`01_erd.png`](../docs/01_erd.png) |
| Autocrítica | [Especificación §11](../docs/01_especificacion.md#a11-autocrítica-del-diseño) |

---

## P-06 · Prompt 2A del laboratorio · Auditor del modelo

**Fecha:** 2026-09-29 · **Gate:** G2

**Prompt (texto oficial del laboratorio):**

```
Audita el modelo relacional propuesto para Banco Andino Colombia.
Evalúa 1FN, 2FN y 3FN; PK, FK y N:M; nulabilidad; unicidad; tipos; catálogos; trazabilidad; histórico; riesgos de anomalías INSERT/UPDATE/DELETE.
No rediseñes silenciosamente. Devuelve una tabla: hallazgo | severidad | evidencia | impacto | corrección propuesta.
Después entrega el modelo lógico corregido, indicando cada cambio realizado.
```

**Contexto entregado a la IA:** `sql/tablas_banco_andino.sql` (28 tablas) y la base cargada con los lotes 1 y 2 (10.000 clientes, 50.000 cuentas, 1.000.000 de transacciones POSTED), para verificar cada hallazgo contra datos reales.

**Respuesta relevante (resumen):** 12 hallazgos (1 alta, 6 media, 5 baja). El hallazgo alto (H-06) mostró que la clave primaria con vigencia de `titularidad_cuenta` permitía que el mismo cliente quedara dos veces vigente en una cuenta. Propuso 3 restricciones nuevas, identificó 8 redundancias que deben documentarse como excepciones a 3FN, y separó las reglas entre tablas que corresponden a funciones y triggers de G3. La tabla completa está en [`docs/02_modelo_logico.md`, sección 8](../docs/02_modelo_logico.md#8-auditoría-del-modelo-con-ia-prompt-2a).

**Revisión y verificación:**

- Ningún cambio se aplicó sin prueba: el DDL corregido se ejecutó desde cero, se recargaron los datos (lote 1 = 20/20 PASS, lote 2 = 24/24 PASS) y cada restricción nueva se probó con un caso que debe fallar.
- La propuesta de agregar la moneda a cada asiento (H-10) se **modificó**: sería una redundancia, porque la moneda depende de la cuenta.
- La propuesta de cambiar el CHECK de documentos del usuario por una FK compuesta (H-05) se **rechazó**: no mejora ninguna regla.

**Decisiones derivadas:** IA-12 a IA-16 (sección 13 del modelo lógico).

---

## P-07 · Prompt 2B del laboratorio · Generar SQL profesional

**Fecha:** 2026-09-30 · **Gate:** G3

**Prompt (texto oficial del laboratorio):**

```
Usa la especificación y el modelo lógico aprobados. Actúa como PostgreSQL Database Architect y Senior DBA.
Genera una implementación PostgreSQL profesional y reproducible.
Obligatorio: 3FN; PK/FK/UNIQUE/NOT NULL/CHECK; NUMERIC para dinero; TIMESTAMPTZ para eventos; convenciones snake_case; comentarios en objetos críticos; idempotency key; transacciones ACID; ledger de doble partida; inmutabilidad de POSTED; auditoría; RBAC; mínimo privilegio; índices justificados; manejo de concurrencia donde sea necesario.
Implementa operaciones seguras para: crear cliente/cuenta, activar, bloquear, desbloquear, consignar, retirar, transferir, reversar y cerrar cuenta. Cada operación debe validar precondiciones, ser atómica, auditar y manejar errores.
Evalúa SELECT ... FOR UPDATE y niveles de aislamiento para evitar doble retiro/lost update/doble procesamiento.
Organiza la salida en: 00_extensions.sql, 01_schemas.sql, ... 19_demo_queries.sql, 20_teardown.sql.
Antes de finalizar, audita tu propia salida y muestra: regla | PASS/FAIL | evidencia | corrección.
```

**Contexto entregado a la IA:** modelo aprobado en G2 (`docs/02_modelo_logico.md` y el DDL corregido), las 54 reglas de G1 y la base con los lotes 1 y 2 para probar compatibilidad.

**Respuesta relevante (resumen):** scripts numerados 00–20 y `run_all.sql`; 17 operaciones como funciones `SECURITY DEFINER` y 1 procedimiento; 32 triggers (inmutabilidad, doble partida diferida, reglas de cuenta y titularidad, auditoría); 5 roles de base de datos; 49 pruebas en `18_tests.sql` y 5 pruebas de concurrencia con dos sesiones. La autoauditoría está en [`docs/03_construccion.md`, sección 8](../docs/03_construccion.md#8-autoauditoría-formato-del-prompt-2b-regla--passfail--evidencia--corrección).

**Revisión y verificación:**

- `run_all.sql` se ejecutó dos veces seguidas en una base nueva: 49/49 PASS las dos veces.
- Se cargaron los lotes con los triggers activos en el modelo: 20/20 y 24/24 PASS. Las 49 pruebas también pasan sobre la base con el millón de transacciones.
- Se detectaron y corrigieron dos problemas de la primera versión: la prueba de `TRUNCATE` (verificaciones diferidas pendientes) y una vista lenta sobre 1.000.000 de filas (de 3 min 25 s a 4 s).
- Se **rechazó** crear índices en G3 (se justifican en G7) y se **modificó** la auditoría durante la carga masiva.

**Decisiones derivadas:** IA-17 a IA-21 ([sección 11 de la construcción](../docs/03_construccion.md#11-matriz-ia-nuevas-entradas-de-g3)).

---

## P-08 · Prompt 3 del laboratorio · Generar 10K/50K/1M

**Fecha:** 2026-09-17 (generadores y cargas) y 2026-09-30 (perfil de G4) · **Gate:** G4

**Prompt (texto oficial del laboratorio):**

```
Actúa como Senior Data Engineer especializado en datos sintéticos financieros y PostgreSQL.
Crea un generador reproducible con SEED=20260909 para poblar el esquema aprobado con:
- 10.000 clientes (aprox. 85% naturales, 15% jurídicas);
- 50.000 cuentas;
- 1.000.000 transacciones financieras + ledger asociado;
- usuarios internos en cantidad razonable.
Reglas: 1) 0 PII real; 2) documentos/NIT/cuentas únicos; 3) distribución geográfica ponderada, no uniforme; 4) cuentas por cliente no uniformes; 5) actividad temporal ≥24 meses con estacionalidad por mes/día/hora; 6) montos con distribución sesgada; 7) transacción posterior a apertura y anterior al cierre; 8) bloqueos respetados; 9) origen ≠ destino; 10) sin saldo negativo cuando no hay sobregiro; 11) ledger balanceado; 12) pequeña cantidad de casos extremos válidos.
Implementa preferiblemente Python + Faker + psycopg o CSV + PostgreSQL COPY. Evita 1M INSERT individuales.
Entrega: generate_data.py, requirements.txt, README, configuración, estrategia de carga y validación posterior con tabla métrica | esperado | obtenido | PASS/FAIL.
```

**Respuesta relevante (resumen):** dos generadores (`generate_data.py` para clientes y cuentas; `generate_transactions.py` para el millón con simulación cronológica), carga con `\copy` en una transacción por lote, 20 + 24 controles de carga y un perfil de 48 métricas que produce `evidence/g4_data_profile.csv`.

**Errores de la IA detectados por el equipo o por las validaciones:**

- Interpretó "las primeras 10.000 cuentas" como un lote de 10.000; eran 50.000 (IA-22).
- Una búsqueda web devolvió nombres de municipios que no correspondían a su código DIVIPOLA (IA-23).
- La primera versión del generador del millón dejó 482 movimientos en el periodo previo a una inactivación y ningún rechazo por límite diario; lo detectaron las validaciones (IA-24).
- Reportó el tamaño de la base como 571 MB; incluía tablas temporales. El real es 475 MB (IA-25).

**Decisiones derivadas:** IA-22 a IA-27 ([sección 8 del documento de datos](../docs/04_datos_sinteticos.md#8-matriz-ia-nuevas-entradas-de-g4)).

---

## P-09 · Prompt 4 del laboratorio · 30 consultas

**Fecha:** 2026-09-30 · **Gate:** G5

**Prompt oficial del laboratorio (modo tutor):**

```
Actúa como tutor SQL PostgreSQL. A partir del esquema Banco Andino, propón 30 problemas: 10 básicos, 10 intermedios y 10 avanzados.
Para cada problema entrega: objetivo de negocio, tablas necesarias, conceptos SQL evaluados y criterio para validar el resultado. NO entregues la solución inicialmente.
Cuando reciba la consulta del estudiante, evalúala por: corrección, legibilidad, eficiencia, robustez ante NULL/duplicados y semántica de negocio. Da pistas antes de mostrar una solución alternativa.
```

**Cómo se usó (transparencia):** el equipo pidió a la IA los 30 problemas **con su solución**, sus resultados sobre el millón de transacciones y una explicación en lenguaje sencillo de cada uno, en lugar del modo tutor paso a paso. Para cumplir el criterio de G5 ("el estudiante puede explicar el resultado de cada una"), `evidence/g5_results.md` incluye la sección **"Cómo explicarla"** en cada consulta, y el equipo se reparte las 30 para practicarlas en pgAdmin 4. El texto oficial del Prompt 4 se puede usar después en modo tutor para repasar.

**Respuesta relevante (resumen):** `sql/19_demo_queries.sql` con 30 consultas (objetivo, tablas, conceptos y criterio de validación en cada una) y 7 validaciones cruzadas; `evidence/g5_results.md` con el resultado real, el tiempo y la explicación de cada consulta.

**Errores detectados al ejecutar sobre los datos reales:**

- I06 tardó 2 min 39 s por una subconsulta correlacionada que recalculaba un promedio 50.000 veces (IA-28).
- A07 comparaba con el límite actual y mostraba días "al 180 %" que en realidad cumplían RN-37 (IA-29).
- VC1 sumaba pesos y dólares en la misma validación (IA-30).

**Decisiones derivadas:** IA-28 a IA-31 ([`evidence/g5_results.md`](../evidence/g5_results.md#matriz-ia-nuevas-entradas-de-g5)).

---

## P-10 · Prompt 5 del laboratorio · Auditor de calidad

**Fecha:** 2026-09-30 · **Gate:** G6

**Prompt oficial del laboratorio:**

```
Actúa como Senior Data Quality Engineer, PostgreSQL DBA y Data Auditor. Audita la base sin corregirla primero.
Genera SQL ejecutable para evaluar: completitud, unicidad, integridad referencial, validez, consistencia geográfica, consistencia temporal, consistencia financiera, reconciliación de saldos, reglas de negocio, distribuciones, diseño y auditoría.
Para cada test devuelve: test_id | categoría | regla | tabla | esperado | obtenido | severidad | PASS/WARNING/FAIL | detalle.
Quality gates críticos: 0 duplicados de documento/NIT/cuenta/idempotencia; 0 huérfanos; 0 transacciones imposibles por estado/fecha; Σ débito = Σ crédito para 100% de POSTED; diferencias de saldo = 0 salvo regla documentada.
Calcula scores solo desde pruebas ejecutadas: Data Quality, Database Design, Integrity, Auditability y Overall. Si falla cualquier regla crítica financiera o referencial, QUALITY_GATE=FAIL.
No corrijas silenciosamente: primero evidencia el fallo, luego recomienda.
```

**Cómo se usó:** se pidió además (1) corregir los FAIL encontrados y repetir el gate, conservando el antes y el después, y (2) demostrar que el gate sí detecta errores metiendo defectos en una copia de la base.

**Respuesta relevante (resumen):** `sql/quality_gate.sql` con 76 pruebas en las 12 categorías y puntajes por dimensión; `sql/load/registrar_cargas_en_auditoria.sql` para corregir A04; `sql/tests/quality_gate_defectos.sql` con 7 defectos inyectados (7/7 detectados); `evidence/g6_quality_before_after.md` con el antes (98,3, 1 FAIL ALTA) y el después (99,6, 0 FAIL).

**Errores o vacíos de la IA detectados:**

- La carga con triggers desactivados que la misma IA propuso en G3 (DC-07) dejó 3,2 millones de filas sin rastro en la auditoría; lo destapó la prueba A04 (IA-32).
- La primera versión de la prueba de defectos habría sobrescrito la evidencia real con los resultados de la copia dañada (IA-36).

**Decisiones derivadas:** IA-32 a IA-36 ([`evidence/g6_quality_before_after.md`](../evidence/g6_quality_before_after.md#9-matriz-ia-nuevas-entradas-de-g6)).

---

## P-11 · Prompt 6 del laboratorio · Revisor de performance

**Fecha:** 2026-10-01 · **Gate:** G7

**Prompt oficial del laboratorio:**

```
Analiza estos planes EXPLAIN (ANALYZE, BUFFERS). No recomiendes índices de forma automática.
Para cada consulta identifica cuello de botella, causa probable, selectividad, columnas de join/filtro/orden, índice candidato si aplica, costo de escritura/almacenamiento del índice y riesgo de sobreindexación.
Devuelve comparación before/after y clasifica la mejora como: no concluyente, menor, relevante o crítica. Señala cuando la mejor decisión sea NO crear índice.
```

**Cómo se usó:**

- Antes de usar el prompt, se pidió a la IA elegir 10 consultas representativas. Se incluyeron las que ejecutan por dentro las funciones del banco (límite diario de `fn_retirar`, trigger de eventos, procedimiento de inactivación) y no solo las más lentas de G5.
- Se pidió medir también el costo de escritura con operaciones reales y con la carga masiva.
- Para la seguridad (paso 6 y 7 de la fase), se pidió un script que probara permisos con un usuario de cada rol sin dejar cambios.

**Respuesta relevante (resumen):**

- `sql/perf/g7_workload.sql` (workload medible antes y después) y 6 índices en `sql/12_indexes.sql`, cada uno con su consulta.
- `sql/15_procedures.sql` con el procedimiento de inactivación reescrito.
- `sql/tests/g7_rbac_demo.sql` con 23 pruebas de acceso.
- `evidence/g7_explain.md` y `evidence/g7_security.md`.

**Errores o vacíos de la IA detectados por las mediciones:**

- En G5 propuso como candidatas a índice las 5 consultas más lentas. Son reportes que leen casi toda la tabla; los cuellos de botella reales estaban en las operaciones: un retiro tardaba 95 ms por recorrer el millón de transacciones (IA-37).
- El índice del extracto hizo que el reporte A06/W10 pasara de 1,3 s a 2,8 s, aunque el costo estimado bajó. Sus tres primeras propuestas para corregirlo (índice cubriente, más `work_mem`, reescritura) no mejoraron nada (IA-39, IA-40).

**Decisiones derivadas:** IA-37 a IA-42 ([`evidence/g7_explain.md`](../evidence/g7_explain.md#9-matriz-ia-nuevas-entradas-de-g7-rendimiento)) e IA-43 a IA-44 ([`evidence/g7_security.md`](../evidence/g7_security.md#6-matriz-ia-nuevas-entradas-de-g7-seguridad)).
