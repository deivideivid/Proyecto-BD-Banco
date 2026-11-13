<#
 Banco Andino | Arranca el aplicativo en este computador (por ahora, la sección Estadísticas).

 La primera vez crea un entorno de Python en la carpeta .venv e instala lo de requirements.txt
 (necesita internet). Pide la contraseña del usuario de solo lectura (powerbi_lector, el mismo de
 Power BI); no la guarda en ningún archivo. Después abre http://localhost:8000 en el navegador.
 Para apagarlo: Ctrl + C en esta ventana.
#>
param(
    [int]$Puerto = 8000,
    [string]$PgHost = "localhost",
    [int]$PgPort = 5432,
    [string]$Base = "banco_andino_lab",
    [string]$Usuario = "powerbi_lector"
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location $PSScriptRoot

# 1. Python
$py = $null
foreach ($c in @("py", "python")) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $py = $c; break }
}
if (-not $py) { Write-Host "No encontramos Python. Instálelo desde python.org (3.11 o más nuevo) y vuelva a intentar."; exit 1 }

# 2. Entorno propio del aplicativo (solo la primera vez)
$venvPy = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) {
    Write-Host "Creando el entorno de Python del aplicativo (solo la primera vez)..."
    if ($py -eq "py") { & py -3 -m venv .venv } else { & python -m venv .venv }
}
Write-Host "Revisando las librerías..."
& $venvPy -m pip install --quiet --disable-pip-version-check -r requirements.txt
if ($LASTEXITCODE -ne 0) { Write-Host "No se pudieron instalar las librerías (revise la conexión a internet)."; exit 1 }

# 3. Conexión a la base (la contraseña queda solo en la memoria de esta ventana).
#    La probamos antes de arrancar: si PostgreSQL no la acepta, la volvemos a pedir.
$env:DATABASE_URL = "host=$PgHost port=$PgPort dbname=$Base user=$Usuario"
$conecto = $false
for ($intento = 1; $intento -le 3; $intento++) {
    $seguro = Read-Host ("Contraseña de PostgreSQL para '" + $Usuario + "' (la misma de Power BI)") -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro)
    $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    & $venvPy -m servidor.probar_conexion
    $codigo = $LASTEXITCODE
    if ($codigo -eq 0) { $conecto = $true; break }
    if ($codigo -eq 1) { break }   # la base no responde: no sirve volver a pedir la contraseña
    Write-Host ("Intento " + $intento + " de 3.")
}
if (-not $conecto) {
    Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "No arrancamos el aplicativo porque no pudo entrar a la base."
    Write-Host ("Si no recuerda la contraseña de '" + $Usuario + "', en pgAdmin (como postgres) puede ponerle una nueva:")
    Write-Host ("    ALTER ROLE " + $Usuario + " PASSWORD 'la_nueva';")
    Write-Host "Después hay que ponerle esa misma en Power BI."
    exit 1
}

# 4. Buscar un puerto libre: si quedó otra copia del aplicativo abierta, no chocamos con ella
$inicial = $Puerto
while (Get-NetTCPConnection -LocalPort $Puerto -State Listen -ErrorAction SilentlyContinue) {
    $Puerto++
    if ($Puerto -gt $inicial + 20) { Write-Host "No encontramos un puerto libre entre $inicial y $Puerto."; exit 1 }
}
if ($Puerto -ne $inicial) {
    Write-Host ""
    Write-Host "Ojo: el puerto $inicial ya lo está usando otro programa (seguramente otra ventana del aplicativo"
    Write-Host "que quedó abierta). Ciérrela para no confundirse. Esta vez usamos el puerto $Puerto."
}

# 5. Abrir el navegador cuando el servidor ya esté arriba, y arrancar
$url = "http://localhost:$Puerto"
Start-Process cmd -ArgumentList "/c", "timeout /t 6 >nul & start `"`" $url" -WindowStyle Hidden
Write-Host ""
Write-Host "Aplicativo en $url  (Ctrl + C para apagarlo)"
Write-Host "La primera vez las estadísticas tardan unos segundos mientras la base las calcula."
& $venvPy -m uvicorn servidor.main:app --host 127.0.0.1 --port $Puerto
Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
