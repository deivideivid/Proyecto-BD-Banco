# Banco Andino Colombia · Laboratorio PostgreSQL aumentado con IA

Base de datos OLTP de un banco ficticio en **PostgreSQL 16 o superior** (el equipo usa 18.6), construida por quality gates (G0–G8).
Todos los datos son **100 % sintéticos**: no hay información de personas reales.

## Estructura

```
lab-postgresql-banco-ia/
├── docs/        Especificación (G1), modelo lógico (G2), construcción (G3), datos (G4), diagramas ER y decisiones
├── prompts/     Registro de prompts y respuestas de la IA
├── sql/         Scripts numerados 00–20, run_all.sql, cargas (sql/load) y pruebas de concurrencia (sql/tests)
├── src/         Generadores de datos sintéticos (Python)
├── data/lote1/  CSV del lote 1 (clientes, cuentas, eventos)
├── data/lote2/  CSV del lote 2 (NO se sube: se genera localmente)
└── evidence/    Evidencia de cada gate
```

## Volumen de datos

| Lote | Contenido | Controles |
|---|---|---|
| 1 | 10.000 clientes · 50.000 cuentas · titularidades · eventos | 20/20 PASS |
| 2 | 1.000.000 transacciones POSTED (+ rechazadas y pendientes) · 2.000.000 asientos | 24/24 PASS |

La base completa pesa cerca de **475 MB**, muy cerca del límite de 500 MB del plan gratis de Supabase (y lo superará con los índices de G7), así que se trabaja en **PostgreSQL local**.

## Cómo montar la base (Windows)

Requisitos: PostgreSQL 16 o superior (incluye `psql`) y Python 3.10 a 3.13.
Todos los comandos se ejecutan **desde la carpeta `lab-postgresql-banco-ia`**, porque las rutas de carga son relativas.

```powershell
cd lab-postgresql-banco-ia

# 1. Generar el lote 2 (unos 30 s; no necesita instalar nada)
python src/generate_transactions.py
#    Huellas esperadas: asiento_contable 1c68ae9b3d8ca2c0 · transaccion_financiera 8fcf2ec17bc357e3

# 2. Crear la base y el modelo completo (tablas, funciones, triggers, roles) + 49 pruebas
psql -U postgres -c "CREATE DATABASE banco_andino_lab"
psql -U postgres -d banco_andino_lab -f sql/run_all.sql
#    Debe terminar con: G3 PRUEBAS = PASS (49 PASS, 0 FAIL)

# 3. Cargar los datos (al final cada script muestra sus controles: todos deben decir PASS)
psql -U postgres -d banco_andino_lab -f sql/load/carga_lote1.sql
psql -U postgres -d banco_andino_lab -f sql/load/carga_lote2_transacciones.sql

# 4. Perfil de datos de G4 (48 métricas; guarda evidence/g4_data_profile.csv)
psql -U postgres -d banco_andino_lab -f sql/load/perfil_datos_g4.sql

# 5. Las 30 consultas de G5 (unos 10 s)
psql -U postgres -d banco_andino_lab -f sql/19_demo_queries.sql
```

> Si PowerShell dice que `psql` no se reconoce, use **SQL Shell (psql)**: `\cd 'C:/ruta/a/lab-postgresql-banco-ia'`, `\c banco_andino_lab` y luego `\i sql/run_all.sql`, `\i sql/load/carga_lote1.sql`, etc. O agregue `C:\Program Files\PostgreSQL\18\bin` al PATH de Windows.

El lote 1 ya viene en `data/lote1`. Si se quiere regenerar: `pip install -r requirements.txt` y `python src/generate_data.py`.
Ambos generadores usan la semilla `20260909`, así que producen exactamente los mismos datos en cualquier computador.

> pgAdmin 4 sirve para consultar, pero **no ejecuta `\copy` ni `\ir`**: `run_all.sql` y las cargas se ejecutan con `psql` (SQL Shell).
>
> ⚠️ `run_all.sql` **borra y recrea** el modelo: después hay que volver a cargar los lotes.

## Estado por gates

- [x] **G0** Entorno: PostgreSQL 18.6 + Python 3.13 → `evidence/g0_environment.txt`
- [x] **G1** Negocio: 54 reglas, supuestos S1–S5 (adoptados por el equipo, no consultados con el docente), diagrama ER, matriz IA → `docs/01_especificacion.md`
- [x] **G2** Modelo lógico: 3FN con 8 excepciones justificadas, ERD final de 28 tablas, 13 decisiones → `docs/02_modelo_logico.md`, `docs/02_erd.png`
- [x] **G3** Construcción: scripts 00–20, 17 operaciones seguras, 32 triggers, 5 roles, 49 pruebas + 5 de concurrencia → `docs/03_construccion.md`, `evidence/g3_tests.txt`
- [x] **G4** Datos sintéticos: 10K clientes · 50K cuentas · 1M transacciones, reproducibles, perfil de 48 métricas → `docs/04_datos_sinteticos.md`, `evidence/g4_data_profile.csv`
- [x] **G5** Consultas: 30 (10 básicas, 10 intermedias, 10 avanzadas) + 7 validaciones cruzadas → `sql/19_demo_queries.sql`, `evidence/g5_results.md`
- [ ] **G6** Quality gate de datos
- [ ] **G7** Rendimiento y seguridad
- [ ] **G8** Informe y defensa

## Reglas del repositorio

- Nunca subir contraseñas, cadenas de conexión ni archivos `.env`.
- No subir los CSV del lote 2 (ya están en `.gitignore`).
- Hacer **Pull** antes de empezar a trabajar y **commit** al cerrar cada gate.
