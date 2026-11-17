# B7 · Paso a paso del despliegue (Neon + Render)

**Encargado:** David González (Jerónimo estuvo ausente). La comparación de proveedores y el porqué
de Neon + Render están en [`DESPLIEGUE.md`](DESPLIEGUE.md).

Lo montamos desde el computador de Juan Diego, porque ahí están PostgreSQL 18 (trae `psql`), los
CSV del lote 2 (no van en GitHub), el entorno de Python del aplicativo y el repositorio en la rama
`fase-bi`. Conviene hacerlo con internet por cable: el paso 1 sube unos 300 MB.

Antes de B7 probamos toda la cadena en un PostgreSQL 16 nuevo con un dueño **sin superusuario**
(como en Neon). G8, B2, B4, B5 y B6 dieron PASS, la base quedó idéntica a la local
(`evidence/` sin cambios) y las 110 pruebas de perfiles pasaron. La base ocupó **784 MB de 1 GB**
(76,5 %, "CABE JUSTO"). También probamos que, si la base se duerme y corta las conexiones, el
aplicativo se vuelve a conectar solo.

**Reglas que no rompemos:** las cadenas de conexión y las contraseñas solo se pegan en las
ventanas de los `.bat` (no se muestran) o en Render. Nunca van al repositorio, a WhatsApp ni al
chat del grupo. Los archivos `*.local.txt` no se suben (están en `.gitignore`).

## 0. Antes de empezar

1. En GitHub Desktop, con la rama `fase-bi`, hacemos *Fetch origin* y *Pull* para tener todo.
   El último commit tiene que incluir esta carpeta con los `b7_*.bat`, porque Render publica lo
   que está en GitHub.
2. Si en el computador nunca se ha arrancado el aplicativo, abrimos una vez
   `fase-bi\aplicativo\iniciar_local.bat` para que cree su entorno de Python, y lo cerramos.

## 1. Cuenta y base en Neon (unos 10 min)

1. Entramos a **neon.com** → *Sign up* → **Continue with GitHub** con la cuenta de David. No pide
   tarjeta.
2. Creamos el proyecto:
   - *Project name:* `banco-andino`
   - *Postgres version:* la más nueva que ofrezca (mínimo 16)
   - *Cloud provider:* **AWS** · *Region:* **US East (N. Virginia)**
3. En el panel del proyecto vamos a **Databases** → **New database**:
   - *Name:* `banco_andino_lab` (igual que en local)
   - *Owner:* `neondb_owner`
4. Arriba, botón **Connect**:
   - *Branch:* `main` · *Database:* **`banco_andino_lab`** · *Role:* `neondb_owner`
   - **Connection pooling: apagado** (la dirección no debe tener `-pooler`)
   - *Show password* y **Copy snippet**. La cadena se ve así (sin espacios):
     `postgresql://neondb_owner:npg_…@ep-…us-east-1.aws.neon.tech/banco_andino_lab?sslmode=require…`

## 2. Montar la base (20-40 min, casi todo esperando)

1. Doble clic en `fase-bi\despliegue\b7_1_montar_base.bat`.
2. Pide la cadena: clic derecho en la ventana para pegarla (no se ve nada, es normal) y Enter.
3. Esperamos sin cerrar la ventana. Al final tiene que decir:
   - `G8 RECONSTRUCCIÓN = PASS`
   - `B2 MODELO ESTRELLA = PASS`, `B4 ESTADÍSTICAS = PASS`, `B5 PERMISOS EN LA BASE = PASS` y
     `B6 ACCESOS = PASS`
   - `RESULTADO: OK`
4. En GitHub Desktop, en *Changes*, **no** debe aparecer `evidence/g4_data_profile.csv`: eso
   prueba que la base de la nube quedó igual a la local. Sí aparece
   `despliegue/salidas/salida_b7_1_montaje.txt`, que es la evidencia.

Si algo sale con `FALLO`, paramos y revisamos `salida_b7_1_montaje.txt` antes de seguir.

## 3. Contraseña de app_servidor, tamaño y accesos (5 min)

1. Doble clic en `fase-bi\despliegue\b7_2_clave_y_accesos.bat` y pegamos otra vez la cadena de
   Neon.
2. Inventamos la contraseña de `app_servidor` (el usuario con el que entra el aplicativo):
   **20 o más caracteres, solo letras y números**. La escribimos dos veces. Neon no acepta el
   `\password` de psql (pide la contraseña en texto y la cifra él mismo), así que el `.bat` la
   manda con `ALTER ROLE` por la conexión cifrada; lo encontramos en el primer intento.
3. Sale la medida de la base. Esperamos `CABE CON MARGEN` o `CABE JUSTO`. Si dice `NO CABE`,
   paramos: toca el plan B (Azure for Students).
4. Con esa contraseña el aplicativo prueba que entra a Neon y crea las contraseñas de los 5
   accesos de demostración. Se muestran una sola vez y
   quedan en `fase-bi\aplicativo\accesos_demo_nube.local.txt` (no va a GitHub).
5. Al final deja **copiada en el portapapeles** la `DATABASE_URL` para Render. Pasamos de una vez
   al punto 4 sin copiar nada más.

## 4. Servidor en Render (unos 10 min)

1. Entramos a **render.com** → *Get Started* → **GitHub** con la cuenta de David.
2. **+ New** → **Web Service** → *Git Provider: GitHub*. Si pide instalar la app de Render en
   GitHub, le damos acceso solo al repositorio `Proyecto-BD-Banco`. Lo escogemos de la lista.
3. Llenamos así:

   | Campo | Valor |
   |---|---|
   | *Name* | `banco-andino` (de aquí sale el enlace) |
   | *Language* | `Python 3` |
   | *Branch* | **`fase-bi`** |
   | *Region* | **Virginia (US East)** |
   | *Root Directory* | vacío |
   | *Build Command* | `pip install -r fase-bi/aplicativo/requirements.txt` |
   | *Start Command* | `cd fase-bi/aplicativo && uvicorn servidor.main:app --host 0.0.0.0 --port $PORT` |
   | *Instance Type* | **Free** |

4. En **Environment Variables** agregamos tres:

   | Nombre | Valor |
   |---|---|
   | `DATABASE_URL` | Ctrl + V (lo que dejó copiado el paso 3) |
   | `APP_SECRET` | botón **Generate** |
   | `APP_HTTPS` | `1` |

   Después copiamos cualquier otra cosa para sacar la cadena del portapapeles.
5. En **Advanced** → *Health Check Path:* `/salud`. *Auto-Deploy:* **On Commit**.
6. **Deploy Web Service**. En *Logs* esperamos `Build successful`, `Application startup complete`
   y `Your service is live`. La primera vez tarda unos minutos.
7. Arriba sale el enlace, del tipo `https://banco-andino.onrender.com`. Lo abrimos, entramos con un
   acceso de `accesos_demo_nube.local.txt` y revisamos Estadísticas.

## 5. Pruebas contra la nube (unos 5 min)

1. Doble clic en `fase-bi\despliegue\b7_3_probar_nube.bat` y pegamos el enlace de Render.
2. Despierta el servidor y corre las pruebas de los 5 perfiles. Esperamos
   `Pruebas: 110 · PASS: 110` y `B5 PERFILES = PASS`. Quedan en
   `B5_servidor\salidas\salida_pruebas_perfiles_nube.txt`.
3. Abrimos el enlace desde el celular de alguien del grupo.

## 6. Evidencia y cierre de B7

- Capturas sin contraseñas ni cadenas: el proyecto en Neon, el servicio *Live* en Render, el
  aplicativo en el computador y en el celular.
- Las salidas de `despliegue/salidas/` y la de las pruebas en la nube.
- Commit en `fase-bi`. Los `*.local.txt` no deben aparecer en *Changes*.

## Si algo falla

| Lo que pasa | Lo que hacemos |
|---|---|
| El `.bat` dice que la cadena tiene `-pooler` o no apunta a `banco_andino_lab` | En *Connect* de Neon apagamos *Connection pooling* y escogemos la base `banco_andino_lab` |
| `faltan estos archivos: data\lote2…` | Corremos `python src\generate_transactions.py` desde la raíz del repositorio (genera los CSV idénticos) |
| El paso 1 se cae a la mitad (se fue el internet) | Guardamos la salida y la revisamos antes de volver a correrlo |
| Render: `Could not open requirements file` | Revisamos que *Root Directory* esté vacío y el *Build Command* tal cual |
| Render: `password authentication failed` | La `DATABASE_URL` quedó mal: corremos otra vez el paso 3 y pegamos la nueva en Render (*Environment* → *Save, rebuild and deploy*) |
| El enlace tarda casi un minuto | Es normal: Render se duerme a los 15 min sin visitas. Antes de la sustentación lo abrimos 5 min antes |
| En la página sale "Usuario o contraseña incorrectos" con los accesos de prueba | Revisamos que sea `accesos_demo_nube.local.txt` (el de la nube) y no `accesos_demo.local.txt` (el de la base local): se parecen mucho y nos pasó. `b7_4_diagnostico_accesos.bat` muestra si las contraseñas del archivo coinciden con la base y los últimos intentos de ingreso, sin mostrar contraseñas |
