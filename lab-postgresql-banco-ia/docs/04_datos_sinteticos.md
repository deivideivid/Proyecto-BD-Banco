# G4 — Datos sintéticos

| Campo | Valor |
|---|---|
| Proyecto | Laboratorio de Ingeniería de Bases de Datos Relacionales Aumentada con IA — Banco Andino Colombia |
| Gate | **G4 — Generación de datos sintéticos** |
| Fecha | 2026-09-30 |
| Generadores | `src/generate_data.py` (lote 1) · `src/generate_transactions.py` (lote 2) · `requirements.txt` |
| Carga | `sql/load/carga_lote1.sql` · `sql/load/carga_lote2_transacciones.sql` |
| Perfil | `sql/load/perfil_datos_g4.sql` → [`evidence/g4_data_profile.csv`](../evidence/g4_data_profile.csv) |
| Evidencia | `evidence/g4_data_profile.csv` · `evidence/g4_reproducibilidad.txt` · `evidence/g4_lote1_validacion.txt` · `evidence/g4_lote2_validacion.txt` |
| Resultado | **G4 = PASS** (48/48 métricas del perfil; ver [sección 7](#7-verificación-del-gate-g4)) |

## 1. Qué se generó

| Lote | Contenido | Archivos |
|---|---|---|
| 1 | 33 departamentos · 51 municipios (DIVIPOLA) · 87 oficinas · 269 usuarios internos · **10.000 clientes** (8.500 naturales, 1.500 jurídicas) · **50.000 cuentas** · 51.551 titularidades · 112.145 eventos · 3.018 cambios de límite | `data/lote1/*.csv` (12 archivos, en el repositorio) |
| 2 | **1.000.000 de transacciones POSTED** (incluye 9.530 reversos y 4.255 ajustes aprobados) + 24.104 rechazadas + 74 pendientes · **2.000.000 de asientos** | `data/lote2/*.csv` (291 MB, **no se suben**: se generan en 30 s) |

Todos los datos son **100 % sintéticos**: nombres de Faker (`es_CO`), documentos en rangos inventados, correos del dominio reservado `example.com`.

## 2. Cómo se cumplen las reglas del Prompt 3

| # | Regla del laboratorio | Cómo la cumple el generador | Métrica del perfil |
|---|---|---|---|
| 1 | 0 PII real | Faker + documentos en rangos sintéticos + `@example.com` | 601–603 |
| 2 | Documentos, NIT y cuentas únicos | Muestreo sin reemplazo; NIT con dígito de verificación DIAN | 201–204 |
| 3 | Distribución geográfica ponderada | Municipios con peso según población aproximada | 701 (mayor departamento = 9,6 × el promedio) |
| 4 | Cuentas por cliente no uniformes | 1 cuenta base + 40.000 extra repartidas con pesos lognormales (empresas × 4) | 702 (mediana 3, máximo 300) |
| 5 | ≥ 24 meses con estacionalidad mes/día/hora | Ventana 2024-09-01 a 2026-08-31; pesos por quincena, fin de mes, diciembre, día de semana y hora | 405, 704–707 |
| 6 | Montos sesgados | Lognormal por tipo de operación; empresas × 6 | 708 (mediana 842.898 < promedio 1.775.276) |
| 7 | Transacción entre apertura y cierre | Cada movimiento se genera dentro de los tramos en que la cuenta está ACTIVA (o BLOQUEADA si es crédito) | 401 |
| 8 | Bloqueos respetados | Una cuenta BLOQUEADA recibe créditos pero no origina débitos (S1) | 402, 403 |
| 9 | Origen ≠ destino | El destino se elige excluyendo la cuenta origen y con la misma moneda | 504 |
| 10 | Sin saldo negativo sin sobregiro | Simulación cronológica con el saldo de cada momento | 503 |
| 11 | Ledger balanceado | 2 asientos por transacción (débito y crédito del mismo valor) | 501, 502 |
| 12 | Pocos casos extremos válidos | Sobregiros usados, retiros que agotan el límite diario, traslados antes del cierre, reversos rechazados | 801–804 |

## 3. Cómo funciona el generador del millón (lote 2)

1. **Lee el lote 1** y calcula, para cada cuenta, los tramos de tiempo en que puede recibir (ACTIVA o BLOQUEADA) u originar dinero (solo ACTIVA), a partir de sus eventos.
2. **Genera solicitudes** con fecha y hora realistas: operaciones de caja, transferencias, pagos de nómina en quincena, ajustes e intentos contra cuentas bloqueadas.
3. **Simula en orden cronológico**: cada solicitud se valida con el saldo, el estado y el límite diario **de ese momento**. Si no cumple, se descarta o se registra como REJECTED con su motivo.
4. **Programa reversos** de algunas operaciones días después (con las mismas reglas: un reverso contra cuenta bloqueada se rechaza, RN-43).
5. **Traslada el saldo** de las cuentas que se cierran justo antes del cierre, para que cierren en 0 (RN-20).
6. **Ajusta al objetivo exacto** de 1.000.000 POSTED quitando o agregando operaciones simples que no rompen ninguna regla.
7. Escribe los CSV y sus hashes.

## 4. Estrategia de carga masiva

| Aspecto | Decisión |
|---|---|
| Método | `\copy` (COPY desde el cliente) desde CSV; **no** 1.000.000 de `INSERT` individuales |
| Atomicidad | Cada lote en **una sola transacción**: si algo falla no queda nada a medias |
| Triggers | Se desactivan en las tablas que se cargan (`DISABLE TRIGGER USER`, solo el dueño) y se reactivan antes del `COMMIT` (decisión DC-07 de G3) |
| Saldos | Se calculan con un solo `UPDATE` desde los asientos (Σ créditos − Σ débitos) |
| Secuencias | `setval` al máximo ID cargado, para que la primera operación normal no choque |
| Después | `VACUUM ANALYZE` y validación en bloque: 20 controles (lote 1) y 24 controles (lote 2) |
| Tiempo medido | Lotes 1 + 2 ≈ **1 min 46 s** (PostgreSQL 16, local) |
| Tamaño final | **475 MB** con los dos lotes cargados |

## 5. Reproducibilidad

- Semilla única `SEED = 20260909` y un solo generador aleatorio por script; Faker con versión fija (`faker==40.39.0`).
- Dos ejecuciones completas producen **los 14 CSV con el mismo SHA-256** (`evidence/g4_reproducibilidad.txt`).
- El generador del millón usa solo la biblioteca estándar de Python y da el mismo resultado en Python 3.10, 3.11, 3.12 y 3.13.
- Huellas de control del lote 2: `asiento_contable` **1c68ae9b3d8ca2c0…** · `transaccion_financiera` **8fcf2ec17bc357e3…**

## 6. Supuestos de datos

| Supuesto | Razón |
|---|---|
| Los saldos parten de 0 al inicio de la ventana (2024-09-01); el histórico 2015–2024 no se simula | El laboratorio pide ≥ 24 meses de actividad; simular 10 años no agrega valor y multiplica el volumen. |
| Una cuenta que termina INACTIVA no tiene movimientos en los 180 días previos a su inactivación | Es lo que justifica inactivarla. |
| Las cuentas que se cierran trasladan su saldo antes del cierre | RN-20: una cuenta solo se cierra con saldo 0. |
| El volumen crece en el tiempo (más clientes y cuentas abiertas en la ventana) | Banco en crecimiento; evita una serie plana artificial. |
| USD ≈ COP / 4.000 solo para generar montos | No hay conversión entre monedas en el modelo (decisión de G1). |

## 7. Verificación del gate G4

| Criterio del laboratorio | Resultado | Evidencia |
|---|---|---|
| Conteos objetivo alcanzados (10K / 50K / 1M) | **Cumple** | Perfil 101–108 |
| 0 duplicados críticos | **Cumple** | Perfil 201–204 |
| 0 huérfanos | **Cumple** | Perfil 301–306 |
| 0 violaciones temporales críticas | **Cumple** | Perfil 401–406 |
| 0 violaciones financieras críticas | **Cumple** | Perfil 501–507 |
| Controles de distribución obligatorios (departamento, cuentas por cliente, transacciones por cuenta, hora, día/mes, montos, estados, ledger) | **Cumple** | Perfil 701–710 y 501 |
| Carga masiva documentada | **Cumple** | Sección 4 y scripts de `sql/load` |
| Hash de los CSV igual entre dos ejecuciones | **Cumple** | `g4_reproducibilidad.txt` |
| Evidencia mínima: `evidence/g4_data_profile.csv` + script reproducible | **Cumple** | 48/48 PASS |

**QUALITY GATE G4 = PASS**

## 8. Matriz IA: nuevas entradas de G4

Estas entradas también sirven para la defensa de G8 ("dónde la IA se equivocó").

| ID | Prompt | Recomendación o resultado de la IA | Decisión | Evidencia | Justificación |
|---|---|---|---|---|---|
| IA-22 | P-08 (3) | Generar "las primeras 10.000 cuentas" como un lote de 10.000 cuentas. | **Rechazar / corregir** | El equipo aclaró que eran 50.000 cuentas | La IA interpretó mal la instrucción; se regeneró con 50.000 (conteo 104). |
| IA-23 | P-08 (3) | Tomar de una búsqueda web los nombres de los municipios DIVIPOLA. | **Modificar** | Algunos nombres devueltos no correspondían al código | Se usaron solo códigos verificados (capitales y municipios confirmados en listados reales). |
| IA-24 | P-08 (3) | Primera versión del generador del millón. | **Modificar** | La validación encontró 482 movimientos en los 180 días previos a una inactivación y 0 rechazos por límite diario | Se corrigió el tramo de inactividad y se agregaron intentos que exceden el límite: 24/24 PASS. |
| IA-25 | P-08 (3) | Medir el tamaño de la base como 571 MB. | **Corregir** | La medición incluía tablas temporales de la validación | Tamaño real: 475 MB. Aun así se descarta el plan gratis de Supabase (IA-26). |
| IA-26 | P-08 (3) | Montar la base completa en Supabase gratis para compartirla. | **Rechazar** | Límite de 500 MB del plan gratis; con los índices de G7 se supera | Cada integrante carga la base local; los datos son idénticos por la semilla. |
| IA-27 | P-08 (3) | Saldos en 0 al inicio de la ventana de 24 meses. | **Aceptar** | Perfil 503: 0 saldos inválidos | Simplificación documentada (sección 6). |
