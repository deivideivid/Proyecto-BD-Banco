# Despliegue del aplicativo

**Encargado:** Jerónimo Soto. · **Comparación hecha el 12/11/2026.** Los planes gratis cambian
seguido, así que volvemos a mirar los límites el día que creemos las cuentas.

Aquí decidimos dónde publicar el aplicativo para que el profesor y cualquiera del grupo lo
pueda abrir, también desde el celular. La primera idea era Replit, pero antes de decidir
comparamos 11 opciones, todas con la misma pregunta: **¿nos deja correr nuestro SQL tal cual,
con la base completa, gratis y rápido?**

## En corto

| | Base de datos | Servidor Python | Costo | Tarjeta |
|---|---|---|---|---|
| **Propuesta** | **Neon Free** (1 GB, no vence) | **Render Free** (no vence) | $0 | No |
| Plan B (si no cabe en 1 GB) | Azure for Students (32 GB, 12 meses) | Render Free | $0 con correo de la universidad | No |
| Plan C (si todo falla) | Base reducida en Neon o Supabase | Render Free | $0 | No |

## Lo que tenemos que tener en cuenta

- **Cuánto pesa la base de verdad.** Sin los índices de G7 son **475 MB**. Con los índices
  creados después de cargar, **560 MB**. Si la montamos con la reconstrucción de un paso (G8),
  que es como la montaríamos en la nube, `run_all.sql` crea los índices **antes** de cargar y
  quedan en 116 MB en vez de 86 MB (`evidence/g7_explain.md`). Eso da **unos 590–600 MB**. El
  689 MB de `evidence/g8_reconstruccion.txt` es mayor porque se midió dentro de la misma sesión
  de la carga, con sus tablas temporales. Lo confirmamos en la nube con
  [`medir_nube.sql`](medir_nube.sql).
- **El esquema `bi` (B2) se suma.** Para que todo quepa en 1 GB, el modelo estrella tiene que
  quedar **por debajo de 250–300 MB**: hechos angostos (claves y montos), el hecho de saldos
  **mensual** y no diario (50.000 cuentas × 365 días serían 18 millones de filas) y las
  dimensiones pequeñas o como vistas.
- **El aplicativo tiene un servidor en Python** que se conecta a PostgreSQL. No es una página
  suelta: el lugar donde lo publiquemos tiene que correr Python y llegar a la base.
- **Los datos son 100 % sintéticos**, así que no hay problema de privacidad si se publica.
- **Nunca subimos contraseñas** al repositorio: van como variables de entorno del servicio.

## Qué le pide nuestro SQL a un proveedor

Revisamos los scripts 00–20, las cargas, G6, G7 y G8. La buena noticia es que **no necesitan
superusuario ni extensiones**: en G3 lo escribimos pensando en eso. Solo encontramos un
detalle de PostgreSQL 16 que sí nos afecta en la nube.

| Lo que usamos | Dónde | ¿Funciona en la nube? |
|---|---|---|
| PostgreSQL 16 o superior | `00_extensions.sql` lo verifica | Sí. Neon, Render, Azure, Aiven y Supabase ofrecen 16 o más (Render llega a la 18, igual que la nuestra) |
| Ninguna extensión (`gen_random_uuid` y `sha256` son nativas) | 00 | Sí, en todos |
| `CREATE ROLE` de los 5 grupos `banco_*` | 17 | Sí donde el usuario tiene `CREATEROLE`: Neon, Supabase, Azure y Aiven. En Railway o en una máquina propia somos superusuario. En la documentación de Render no lo encontramos confirmado |
| `SET LOCAL ROLE` en las pruebas | `18_tests.sql`, `g7_rbac_demo.sql`, `g8_demo_defensa.sql` | **Falla si no lo ajustamos.** Desde PostgreSQL 16, quien crea un rol sin ser superusuario no puede "ponerse" ese rol, y sale *permission denied to set role*. Lo resolvemos con [`preparar_nube.sql`](preparar_nube.sql), que activa `createrole_self_grant = 'set'` |
| Funciones `SECURITY DEFINER` | 14, 15, 16 | Sí |
| `DISABLE TRIGGER USER` en las cargas | `carga_lote1.sql`, `carga_lote2_transacciones.sql` | Sí, porque solo pide ser dueño de la tabla (no usamos `DISABLE TRIGGER ALL`, que sí pide superusuario) |
| `\copy` desde los CSV | cargas | Sí: `\copy` lee los archivos en nuestro computador y los envía por la conexión |
| Fechas y horas | CSV con `-05:00` y `AT TIME ZONE 'America/Bogota'` explícito | Sí. No dependen de la zona horaria del servidor, que en la nube suele ser UTC. Igual dejamos la base en hora de Colombia para el aplicativo |
| `CREATE DATABASE … TEMPLATE` | `tests/quality_gate_defectos.sql` | Puede fallar en la nube. Esa prueba la seguimos corriendo en local |
| Pruebas de concurrencia | `tests/concurrencia/` | Necesitan dos consolas a la vez. También las dejamos en local |

## Comparación

Las marcamos así: ✅ sirve, 🟡 sirve con condiciones, ❌ no sirve para nosotros.

| Opción | Tipo | ¿Tarjeta? | Espacio de la base | ¿Cabe la base completa (~600 MB + `bi`)? | ¿Se apaga o vence? | Veredicto |
|---|---|---|---|---|---|---|
| **Neon Free** (base) | Gratis permanente | No | 1 GB por proyecto | Sí, con unos 300–400 MB de margen para `bi` | La base se duerme a los 5 min sin uso y despierta sola. No vence | ✅ **Para la base** |
| **Render Free** (servidor) | Gratis permanente | No | (no aplica) | (no aplica) | Se duerme a los 15 min sin visitas y tarda cerca de 1 min en despertar. 750 h al mes | ✅ **Para el servidor** |
| Azure for Students | Prueba de 12 meses + USD 100 | No (pide correo de la universidad) | 32 GB | Sí, de sobra | 750 h al mes de un servidor B1MS, que alcanza para tenerlo prendido todo el mes. Se acaba a los 12 meses | 🟡 Plan B |
| Render Postgres Free | Gratis pero **vence** | No | 1 GB | Sí, justo | **Vence a los 30 días**; después hay 14 días de gracia y **la borra**. Sin copias de seguridad | 🟡 Solo si la creamos menos de 30 días antes de la sustentación |
| Aiven Free | Gratis permanente | No | 1 GB de disco | Justo (no confirmamos si lo mide igual que Neon) | Se apaga por inactividad (avisan por correo) y hay que prenderla a mano. Máximo 20 conexiones | 🟡 Respaldo de Neon |
| Supabase Free | Gratis permanente | No | 500 MB | **No** (ya lo vimos en G4, IA-26) | Se pausa a los 7 días sin uso | ❌ Solo para la base reducida |
| Railway | Prueba de USD 5, una sola vez | No | 0,5 GB en el plan gratis | **No**. El plan Hobby (USD 5 al mes) da 5 GB | La prueba se acaba (30 días o al gastar los USD 5) | ❌ No es gratis |
| Replit Starter (la primera idea) | Gratis con límites | No | Según terceros, ~1 GiB para la base publicada (no lo confirmamos) | Justo y sin confirmar | **La app publicada se apaga a los 30 días** (hay que volver a publicarla) y lleva el sello "Made with Replit". Lo demás va por créditos | ❌ Límites poco claros |
| Koyeb | Gratis con límites | Según fuentes de 2026, ahora sí | 1 GB | Sí | La base gratis solo da **5 horas de uso** | ❌ |
| Oracle Cloud Always Free | Gratis permanente (una máquina virtual) | **Sí**, para verificar | 200 GB de disco | Sí, de sobra | Las cuentas inactivas se pueden reclamar y no siempre hay capacidad | 🟡 Solo si alguien sabe administrar Linux |
| Google Cloud / AWS | Prueba con créditos | **Sí** | De sobra | Sí | Al acabar la prueba empiezan a cobrar | ❌ Por la tarjeta |

## Pros y contras de las que sí sirven

### 1. Neon Free (base) + Render Free (servidor): la que proponemos

**Pros**
- **$0 y sin tarjeta**, y ninguno de los dos vence: Neon aclara que su plan gratis es
  permanente y no una prueba. El enlace sigue vivo después de la sustentación.
- **La base completa cabe** (1 GB por proyecto) y no tenemos que hacer muestra.
- **Corremos nuestros mismos scripts** (`g8_reconstruir_todo.sql`) sin cambiarlos, solo con
  `preparar_nube.sql` antes. Si al terminar `git status` no muestra cambios en
  `evidence/g4_data_profile.csv`, la base de la nube quedó idéntica a la local, igual que en G8.
- La base se duerme cuando nadie la usa y **despierta sola** con la primera consulta (en
  Aiven y Supabase toca prenderla a mano).
- Si nos pasamos de 1 GB, Neon **no borra nada**: solo fallan las escrituras que agranden la
  base, hasta que liberemos espacio.
- **Render publica desde GitHub**: cada push a la rama `fase-bi` vuelve a desplegar solo.
- Los dos tienen región en el este de EE. UU. (Virginia), que es lo más cercano a Colombia.
- Power BI Desktop también se puede conectar a Neon con el rol de solo lectura de B2, así los
  5 trabajamos sobre la misma base (lo probamos en B3).

**Contras**
- **El servidor tarda cerca de 1 minuto en despertar** si nadie lo abrió en los últimos 15
  minutos. Lo manejamos abriéndolo antes de la sustentación.
- **1 GB es justo** con el esquema `bi`: B2 tiene que ser liviano (ver arriba).
- Neon da 100 horas-CU al mes por proyecto (unas 400 horas con la base al mínimo). Sobra para
  demos, pero **no podemos tener la base despierta todo el día**: si ponemos algo a "tocar"
  el servidor para que no se duerma, tiene que ser una ruta que no consulte la base.
- 5 GB de transferencia al mes en Neon. Cada vez que Power BI importa el millón de
  transacciones gasta del orden de 100 MB.
- Render puede reiniciar el servidor gratis en cualquier momento y su disco se borra en cada
  reinicio. El aplicativo no puede guardar archivos ahí: todo va a la base o al repositorio.
- Son dos cuentas y dos paneles, en vez de uno.

### 2. Azure for Students (base) + Render Free (servidor): plan B

**Pros:** 32 GB (nunca nos preocupamos por el tamaño), PostgreSQL administrado de verdad, sin
tarjeta y USD 100 de crédito. 750 horas al mes alcanzan para dejarlo prendido todo el mes.

**Contras:** pide el **correo de la universidad** y que seamos estudiantes de tiempo completo.
El portal de Azure es más enredado: hay que escoger justo el tamaño **B1MS** (otro tamaño gasta
el crédito), abrir el firewall para que Render llegue a la base y vigilar el crédito. Se acaba a
los 12 meses.

### 3. Todo en Render (Postgres Free + servidor Free)

**Pros:** lo más rápido de montar, todo en un solo panel, y trae PostgreSQL 18 como el nuestro.

**Contras:** la base **vence a los 30 días** y a los 14 días siguientes **la borran sin copia
de seguridad**. Solo nos serviría si la creamos menos de 30 días antes de la sustentación y no
nos importa que después desaparezca. Además, Render solo permite una base gratis activa por workspace.

### 4. Replit (la primera idea)

**Pros:** editor en el navegador donde los 5 podemos trabajar a la vez, y la base y el
servidor quedan en el mismo sitio.

**Contras:** en el plan gratis la app publicada **se apaga a los 30 días** y lleva el sello de
Replit. El tamaño de la base publicada no está claro en su documentación (terceros hablan de
~1 GiB) y el uso se cobra con créditos. Si nos quedamos cortos, el plan Core cuesta USD 20 al
mes. Para lo que necesitamos, Neon + Render nos da lo mismo sin esa incertidumbre.

### 5. Base reducida (muestra): plan C

Si nada de lo anterior funciona, publicamos con 1 de cada 10 transacciones (unos 60–100 MB),
que cabe hasta en Supabase. El problema es que los conteos y el quality gate ya no darían igual
que en local, y en la sustentación tendríamos que explicar dos bases distintas.

## Lo que proponemos

**Neon Free para la base completa + Render Free para el servidor en Python.** Es la única
combinación que es gratis de forma permanente, no pide tarjeta, deja correr nuestro SQL sin
cambiarlo y aguanta el millón de transacciones. Si después de crear el esquema `bi`,
`medir_nube.sql` dice "NO CABE", pasamos la base a Azure for Students y el servidor se queda en
Render.

## Cómo lo montaríamos (Neon + Render)

### Base en Neon (unos 30 min, la mayoría esperando la carga)

1. Entramos a neon.com con GitHub (no pide tarjeta) y creamos el proyecto `banco-andino`, con
   la versión de PostgreSQL más nueva que ofrezca (mínimo 16) y la región **AWS US East (N.
   Virginia)**.
2. En *Databases* creamos la base **`banco_andino_lab`**, con el mismo nombre que en local,
   para que los scripts y el README sigan sirviendo tal cual.
3. En *Connect* copiamos la cadena **directa**, la que **no** tiene `-pooler` en el host. Los
   scripts usan tablas temporales, `SET` y `\copy`, y eso no funciona bien a través del pooler.
4. En PowerShell, desde la raíz del repositorio (en este computador `psql` no estaba en el
   PATH, por eso la primera línea):

   ```powershell
   $env:Path += ";C:\Program Files\PostgreSQL\18\bin"
   python src/generate_transactions.py                 # lote 2: no está en el repo
   $NEON = Read-Host "Cadena directa de Neon"           # así la contraseña no queda en el historial
   psql -d $NEON -f fase-bi/despliegue/preparar_nube.sql -f sql/g8_reconstruir_todo.sql
   psql -d $NEON -f fase-bi/despliegue/medir_nube.sql
   git status                                          # evidence/g4_data_profile.csv sin cambios = base idéntica
   ```

   Los dos `-f` van en el mismo `psql` a propósito, para que el ajuste de `SET ROLE` aplique a
   la reconstrucción. El lote 2 son 291 MB de CSV que se suben desde nuestro computador, así que
   conviene hacerlo con buen internet, ojalá por cable. Esperamos **G8 RECONSTRUCCIÓN = PASS**.
5. Si `medir_nube.sql` dice "CABE JUSTO", podemos recuperar unos 30 MB reconstruyendo los
   índices que se crearon antes de la carga:
   `REINDEX TABLE fin.transaccion_financiera; REINDEX TABLE fin.asiento_contable;`

### Servidor en Render (unos 10 min, cuando exista el servidor de B5)

1. Entramos a render.com con GitHub → *New* → *Web Service* y conectamos el repositorio. Lo
   tiene que autorizar quien administra `deivideivid/Proyecto-BD-Banco` en GitHub (David), o
   David nos da permiso de administrador.
2. Rama `fase-bi`, carpeta raíz la del aplicativo, entorno Python, tipo de instancia **Free**
   y región **Virginia (US East)**.
3. En *Environment* ponemos `DATABASE_URL` con la cadena del **usuario del aplicativo** (no
   la del dueño de Neon) y `sslmode=require`. Para el aplicativo sí podemos usar la cadena con
   `-pooler`.

### Lo que el servidor de B5 tiene que cumplir para poder publicarlo

- Leer la conexión de `os.environ["DATABASE_URL"]`, nunca escrita en el código.
- Escuchar en `0.0.0.0` y en el puerto que Render le da en la variable `PORT`.
- Tener su `requirements.txt` con el comando de arranque claro (por ejemplo `gunicorn` para
  Flask o `uvicorn` para FastAPI).
- Conectarse con usuarios `LOGIN` que solo tengan los grupos `banco_*`, nunca con el dueño de
  la base. Esos usuarios los creamos a mano en Neon, con contraseñas fuertes que no van al
  repositorio.
- Una ruta `/salud` que **no** consulte la base, para despertar el servidor sin gastar horas de
  Neon.

### El día de la sustentación

- 5 minutos antes abrimos el enlace (Render tarda ~1 min) y entramos a una pantalla que
  consulte la base, para despertar también a Neon.
- Tenemos de respaldo la base local de Juan Diego y el aplicativo corriendo en local, por si
  falla el internet del salón.

## Qué tenemos que decidir

- [ ] Dónde va el servidor del aplicativo. **Propuesta:** Render Free.
- [ ] Dónde va la base (completa o reducida). **Propuesta:** completa en Neon Free; si no cabe
      con `bi`, Azure for Students.
- [ ] Si el enlace tiene que quedar encendido todo el tiempo o solo el día de la sustentación.
      **Propuesta:** queda publicado siempre, se duerme solo y lo despertamos antes de mostrarlo.
- [ ] Quién tiene las credenciales del servicio. **Propuesta:** Jerónimo crea las cuentas y
      guarda las cadenas. Al grupo le pasa por mensaje privado solo la del rol de solo lectura
      para Power BI. Nunca van al repositorio ni al chat del grupo.

## Lo que decidimos

(Pendiente: lo aprobamos en grupo con esta comparación.)

## Fuentes (consultadas el 12/11/2026)

- Neon: [límites del plan Free](https://neon.com/faqs/free-plan-limits-and-quotas) y [precios](https://neon.com/pricing).
- Render: [servicios gratis](https://render.com/docs/free) y [crear y conectar Postgres](https://render.com/docs/postgresql-creating-connecting).
- Supabase: [precios](https://supabase.com/pricing) y [límite de 0,5 GB por proyecto](https://supabase.com/changelog/33121-relaxing-database-size-limit-on-free-plan-0-5-gb-database-size-per-project).
- Aiven: [PostgreSQL gratis](https://aiven.io/free-postgresql-database).
- Azure: [Azure for Students](https://azure.microsoft.com/en-us/free/students) y [PostgreSQL con la cuenta gratis](https://learn.microsoft.com/en-ie/azure/postgresql/flexible-server/how-to-deploy-on-azure-free-account).
- Koyeb: [preguntas de precios](https://www.koyeb.com/docs/faqs/pricing).
- Railway (fuentes de terceros): [Render vs Railway](https://encore.dev/articles/render-vs-railway), [precios de Railway 2026](https://temps.sh/blog/railway-pricing-2026).
- Replit (fuentes de terceros): [¿Replit es gratis?](https://rationalgo.ai/resources/app-builder/pricing-guides/is-replit-free-starter-plan), [precios de Replit](https://bilt.me/blog/replit-pricing).
- Oracle (fuentes de terceros): [cambios del plan Always Free en 2026](https://terminalbytes.com/oracle-cloud-free-tier-changes-2026).
- PostgreSQL 16 y `SET ROLE`: [Percona sobre `CREATEROLE` en PG 16](https://www.percona.com/blog/exploring-the-improved-createrole-attribute-for-user-management-in-postgresql-16/) y [lista pgsql-general](https://www.postgresql.org/message-id/CAFCRh-_-fuE8vSvP1vyqKXFGihfj9RmUB9z1wmEFtbkYTXNHTQ%40mail.gmail.com).
