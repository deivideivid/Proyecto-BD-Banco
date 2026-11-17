<#
 Banco Andino | B7 Despliegue. Lo usan los tres .bat de esta carpeta, uno por paso:

   b7_1_montar_base.bat       Monta la base completa en Neon: G0 a G8 (con el millón de
                              transacciones) y encima B2, B4, B5 y B6. Tarda 20-40 minutos.
   b7_2_clave_y_accesos.bat   Pone la contraseña de app_servidor, mide cuánto ocupa la base,
                              crea las contraseñas de los accesos de demostración de la nube y
                              deja copiada la DATABASE_URL que va en Render.
   b7_3_probar_nube.bat       Corre las pruebas de los 5 perfiles contra el enlace de Render.

 Las cadenas de conexión y las contraseñas se piden en la ventana sin mostrarse y no quedan en
 ningún archivo. Lo que sale en pantalla se guarda en despliegue\salidas\ (sin contraseñas).
#>
param([Parameter(Mandatory = $true)][ValidateSet("1", "2", "3", "4")][string]$Paso)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:PGCLIENTENCODING = "UTF8"
$raiz = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $raiz

$carpetaSalidas = Join-Path $PSScriptRoot "salidas"
New-Item -ItemType Directory -Force -Path $carpetaSalidas | Out-Null
$nombres = @{ "1" = "salida_b7_1_montaje.txt"; "2" = "salida_b7_2_clave_y_medida.txt"; "3" = "salida_b7_3_pruebas_nube.txt"; "4" = "salida_b7_4_diagnostico_accesos.txt" }
$rutaSalida = Join-Path $carpetaSalidas $nombres[$Paso]
("Banco Andino - B7 paso " + $Paso + " - " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " - equipo " + $env:COMPUTERNAME) |
    Out-File -FilePath $rutaSalida -Encoding utf8

function Log([string]$texto) {
    Write-Host $texto
    Add-Content -Path $rutaSalida -Value $texto -Encoding utf8
}
function Terminar([bool]$ok) {
    Remove-Item Env:\PGPASSWORD, Env:\DATABASE_URL, Env:\ACCESOS_ARCHIVO -ErrorAction SilentlyContinue
    Log ""
    if ($ok) { Log "RESULTADO: OK" } else { Log "RESULTADO: HUBO UN ERROR - revise el mensaje FALLO." }
    Log ("Salida guardada en: " + $rutaSalida)
    if ($ok) { exit 0 } else { exit 1 }
}
function LeerSecreto([string]$pregunta) {
    $seguro = Read-Host $pregunta -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro)
    $texto = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    return $texto.Trim()
}
function LeerCadenaNeon {
    for ($i = 1; $i -le 3; $i++) {
        $url = LeerSecreto "Pegue la cadena de conexion DIRECTA de Neon (usuario neondb_owner, base banco_andino_lab). No se muestra"
        if ($url -notmatch '^postgres(ql)?://') { Write-Host "Esa no parece una cadena de Neon: debe empezar con postgresql://"; continue }
        if ($url -match '-pooler') { Write-Host "Esa es la cadena con -pooler. En Neon apague 'Connection pooling' y copie la directa."; continue }
        if ($url -notmatch '/banco_andino_lab(\?|$)') { Write-Host "La cadena no apunta a la base banco_andino_lab. En Neon, en 'Database', escoja banco_andino_lab."; continue }
        return $url
    }
    Log "FALLO: no recibimos una cadena directa de Neon a banco_andino_lab."
    Terminar $false
}

# psql (en este computador no está en el PATH, por eso lo buscamos)
$psql = $null
$cmd = Get-Command psql -ErrorAction SilentlyContinue
if ($cmd) { $psql = $cmd.Source } else {
    $candidato = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
        Sort-Object { [int](($_.Directory.Parent.Name) -replace '\D', '') } -Descending | Select-Object -First 1
    if ($candidato) { $psql = $candidato.FullName }
}
$venvPy = Join-Path $raiz "fase-bi\aplicativo\.venv\Scripts\python.exe"

# =====================================================================================
if ($Paso -eq "1") {
    if (-not $psql) { Log "FALLO: no se encontro psql (viene con PostgreSQL)."; Terminar $false }
    $faltan = @("data\lote1\cliente.csv", "data\lote2\transaccion_financiera.csv", "data\lote2\asiento_contable.csv",
                "evidence\g6_quality_results.csv") | Where-Object { -not (Test-Path $_) }
    if ($faltan) {
        Log ("FALLO: faltan estos archivos: " + ($faltan -join ", "))
        Log "Los CSV del lote 2 no van en GitHub. Se generan identicos con:  python src\generate_transactions.py"
        Terminar $false
    }
    $url = LeerCadenaNeon
    # Cada tanda va en su propia conexion, como en local (los scripts de pruebas usan tablas
    # temporales con el mismo nombre). G0-G8 va junto con preparar_nube.sql, como lo pide
    # DESPLIEGUE.md, y a cada tanda de la fase BI le ponemos createrole_self_grant = 'set' para que
    # el dueno de Neon pueda "ponerse" los roles nuevos que crean B2 y B5 (en la nube no somos
    # superusuario).
    $tandas = @(
        @("fase-bi\despliegue\preparar_nube.sql", "sql\g8_reconstruir_todo.sql"),
        @("fase-bi\B2_modelo_estrella\sql\b2_01_esquema_bi.sql"),
        @("fase-bi\B2_modelo_estrella\sql\b2_02_cargar_bi.sql"),
        @("fase-bi\B2_modelo_estrella\sql\b2_03_rol_powerbi.sql"),
        @("fase-bi\B2_modelo_estrella\sql\b2_04_validar_bi.sql"),
        @("fase-bi\B2_modelo_estrella\sql\b2_05_kpi_referencia.sql"),
        @("fase-bi\B4_tableros_app\sql\b4_01_funciones_estadisticas.sql"),
        @("fase-bi\B4_tableros_app\sql\b4_02_validar_estadisticas.sql"),
        @("fase-bi\B5_servidor\sql\b5_01_esquema_app.sql"),
        @("fase-bi\B5_servidor\sql\b5_02_pruebas_bd.sql"),
        @("fase-bi\B6_interfaces\sql\b6_01_accesos_admin.sql")
    )
    Log ""
    Log "Montando la base en Neon. Sube unos 300 MB de CSV: no cierre esta ventana ni apague el computador."
    foreach ($tanda in $tandas) {
        Log ""
        Log ("===== " + ($tanda -join " + ") + " =====")
        $argumentos = @("-X", "-v", "ON_ERROR_STOP=1", "-d", $url, "-c", "SET createrole_self_grant = 'set'")
        foreach ($s in $tanda) { $argumentos += @("-f", $s) }
        & $psql @argumentos 2>&1 | ForEach-Object { Log ([string]$_) }
        if ($LASTEXITCODE -ne 0) { Log ("FALLO en " + ($tanda -join " + ") + " (se detiene aqui)."); Terminar $false }
    }
    Log ""
    Log "Revise arriba: G8 RECONSTRUCCION = PASS, B2, B4, B5 en PASS y B6 ACCESOS = PASS."
    Log "Despues: git status no debe mostrar cambios en evidence\g4_data_profile.csv (base identica a la local)."
    Terminar $true
}

# =====================================================================================
if ($Paso -eq "2") {
    if (-not $psql) { Log "FALLO: no se encontro psql."; Terminar $false }
    if (-not (Test-Path $venvPy)) {
        Log "FALLO: falta el entorno de Python del aplicativo. Arranque una vez fase-bi\aplicativo\iniciar_local.bat y vuelva a intentar."
        Terminar $false
    }
    $url = LeerCadenaNeon
    $servidorNeon = ([Uri]$url).Host

    Log ""
    Log "== 1) Contrasena de app_servidor (el usuario con el que entra el aplicativo)"
    Write-Host "Invente una contrasena de 20 o mas caracteres, SOLO letras y numeros (sin simbolos)."
    Write-Host "No se muestra. Guardela donde guarda sus contrasenas: va en Render."
    # Neon no acepta \password de psql (manda la contrasena ya cifrada): pide el texto y la cifra
    # el mismo Neon. Por eso la mandamos con ALTER ROLE por la conexion cifrada (sslmode=require),
    # por la entrada de psql y no como argumento, y solo letras y numeros (no hay comillas que romper).
    $clave = $null
    for ($i = 1; $i -le 3; $i++) {
        $c1 = LeerSecreto "Contrasena nueva para app_servidor"
        $c2 = LeerSecreto "Escribala otra vez"
        if ($c1 -cne $c2) { Write-Host "No coinciden. Otra vez."; continue }
        if ($c1 -notmatch '^[A-Za-z0-9]{20,}$') { Write-Host "Tiene que tener 20 o mas caracteres y solo letras y numeros. Otra vez."; continue }
        $clave = $c1; break
    }
    $c1 = $null; $c2 = $null
    if (-not $clave) { Log "FALLO: no recibimos una contrasena valida para app_servidor."; Terminar $false }
    ("ALTER ROLE app_servidor PASSWORD '" + $clave + "';") | & $psql -X -q -v ON_ERROR_STOP=1 -d $url -f -
    if ($LASTEXITCODE -ne 0) { Log "FALLO al poner la contrasena de app_servidor."; Terminar $false }
    Log "Contrasena de app_servidor puesta."

    Log ""
    Log "== 2) Cuanto ocupa la base (limite de Neon Free: 1 GB)"
    & $psql -X -d $url -f "fase-bi\despliegue\medir_nube.sql" 2>&1 | ForEach-Object { Log ([string]$_) }
    if ($LASTEXITCODE -ne 0) { Log "FALLO al medir la base."; Terminar $false }

    Log ""
    Log "== 3) El aplicativo entra con app_servidor y crea los accesos de demostracion de la nube"
    $env:DATABASE_URL = "host=$servidorNeon port=5432 dbname=banco_andino_lab user=app_servidor sslmode=require"
    $env:PGPASSWORD = $clave
    Push-Location (Join-Path $raiz "fase-bi\aplicativo")
    & $venvPy -m servidor.probar_conexion
    if ($LASTEXITCODE -ne 0) { Pop-Location; Log "FALLO: el aplicativo no pudo entrar a Neon con app_servidor."; Terminar $false }
    if ($clave -notmatch '^[A-Za-z0-9]+$') {
        Write-Host "OJO: la contrasena tiene simbolos. Funciona aqui, pero en la DATABASE_URL de Render puede fallar."
    }
    $env:ACCESOS_ARCHIVO = "accesos_demo_nube.local.txt"
    & $venvPy -m servidor.crear_accesos
    $okAccesos = ($LASTEXITCODE -eq 0)
    Pop-Location
    if (-not $okAccesos) { Log "FALLO al crear los accesos de demostracion."; Terminar $false }
    Log "Accesos de demostracion de la nube: en fase-bi\aplicativo\accesos_demo_nube.local.txt (no va a GitHub)."

    $paraRender = "postgresql://app_servidor:" + [Uri]::EscapeDataString($clave) + "@" + $servidorNeon + "/banco_andino_lab?sslmode=require"
    Set-Clipboard -Value $paraRender
    $clave = $null; $paraRender = $null
    Log ""
    Log "== 4) Para Render"
    Log "Quedo COPIADA en el portapapeles la DATABASE_URL para Render (con app_servidor, no con neondb_owner)."
    Log ("Tiene esta forma: postgresql://app_servidor:<contrasena>@" + $servidorNeon + "/banco_andino_lab?sslmode=require")
    Log "Peguela en Render > Environment > DATABASE_URL y despues copie cualquier otra cosa para borrarla del portapapeles."
    Terminar $true
}

# =====================================================================================
if ($Paso -eq "3") {
    if (-not (Test-Path $venvPy)) { Log "FALLO: falta el entorno de Python del aplicativo (iniciar_local.bat una vez)."; Terminar $false }
    $enlace = (Read-Host "Pegue el enlace de Render (por ejemplo https://banco-andino.onrender.com)").Trim().TrimEnd("/")
    if ($enlace -notmatch '^https://') { Log "FALLO: el enlace debe empezar con https://"; Terminar $false }
    Log ("Servidor: " + $enlace)
    Log "Despertando el servidor (si estaba dormido tarda cerca de 1 minuto)..."
    $despierto = $false
    for ($i = 1; $i -le 12; $i++) {
        try {
            $r = Invoke-RestMethod -Uri ($enlace + "/salud") -TimeoutSec 20
            if ($r.estado -eq "ok") { $despierto = $true; break }
        } catch { Start-Sleep -Seconds 5 }
    }
    if (-not $despierto) { Log "FALLO: el servidor no respondio /salud en 2 minutos. Revise los Logs en Render."; Terminar $false }
    Log "Servidor despierto. Corremos las pruebas de los 5 perfiles (hacen operaciones pequenas reales, 'Prueba B5')."
    $env:PYTHONIOENCODING = "utf-8"
    & $venvPy "fase-bi\B5_servidor\pruebas\probar_perfiles.py" $enlace 2>&1 | ForEach-Object { Log ([string]$_) }
    $ok = ($LASTEXITCODE -eq 0)
    Log "El detalle queda en fase-bi\B5_servidor\salidas\salida_pruebas_perfiles_nube.txt"
    Terminar $ok
}

# =====================================================================================
if ($Paso -eq "4") {
    # Diagnostico de los accesos de demostracion en Neon (solo lee; no muestra contrasenas).
    if (-not (Test-Path $venvPy)) { Log "FALLO: falta el entorno de Python del aplicativo (iniciar_local.bat una vez)."; Terminar $false }
    $url = LeerCadenaNeon
    $env:DATABASE_URL = $url
    $env:PYTHONIOENCODING = "utf-8"
    & $venvPy "fase-bi\despliegue\diagnostico_accesos.py" 2>&1 | ForEach-Object { Log ([string]$_) }
    Terminar ($LASTEXITCODE -eq 0)
}
