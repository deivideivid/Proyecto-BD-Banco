# Registro de prompts y respuestas de IA

| Campo | Valor |
|---|---|
| Gates cubiertos | G0–G1 |
| Herramienta | Claude (Anthropic), en la aplicación de escritorio |
| Última actualización | 2026-09-17 |
| Matriz de decisiones | [`../docs/matriz_decisiones_ia.md`](../docs/matriz_decisiones_ia.md) |

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
| 1) Actores y procesos | [Especificación §2](../docs/01_especificacion.md#2-actores-y-procesos) |
| 2) Entidades y propósito | [Especificación §3](../docs/01_especificacion.md#3-entidades-y-propósito) |
| 3) Atributos esenciales | [Especificación §3](../docs/01_especificacion.md#3-entidades-y-propósito) y [ERD](../docs/01_erd.md) |
| 4) Relaciones y cardinalidades | [Especificación §5](../docs/01_especificacion.md#5-relaciones-y-cardinalidades) |
| 5) Catálogos y estados | [Especificación §6](../docs/01_especificacion.md#6-catálogos-y-estados) |
| 6) Mínimo 30 reglas verificables | [Especificación §8](../docs/01_especificacion.md#8-reglas-de-negocio-verificables) (54 reglas) |
| 7) Riesgos de consistencia | [Especificación §9](../docs/01_especificacion.md#9-riesgos-de-consistencia) |
| 8) Decisiones que requieren validación humana | [Especificación §10](../docs/01_especificacion.md#10-decisiones-que-requieren-validación-humana) |
| 9) ERD Mermaid | [01_erd.md](../docs/01_erd.md) |
| Autocrítica | [Especificación §11](../docs/01_especificacion.md#11-autocrítica-del-diseño) |
