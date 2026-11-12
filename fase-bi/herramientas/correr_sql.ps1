<#
 Banco Andino | Corre una lista de scripts SQL en la base banco_andino_lab y guarda todo lo que salga.
 Lo usan los archivos .bat de cada gate de la fase BI (por ejemplo B2_modelo_estrella\ejecutar_b2.bat).

 Uso (desde la raiz del repositorio):
   powershell -ExecutionPolicy Bypass -File fase-bi\herramientas\correr_sql.ps1 `
     -Scripts "fase-bi/B2_modelo_estrella/sql/b2_01_esquema_bi.sql" -Salida "fase-bi/B2_modelo_estrella/salidas/salida_b2.txt"

 La contrasena se pide una sola vez y no se guarda. Si un script falla, se detiene ahi.
#>
param(
    [Parameter(Mandatory = $true)][string[]]$Scripts,
    [Parameter(Mandatory = $true)][string]$Salida,
    [string]$Titulo = "Banco Andino",
    [string]$PgUser = "postgres",
    [string]$PgHost = "localhost",
    [int]$PgPort = 5432,
    [string]$Base = "banco_andino_lab"
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:PGCLIENTENCODING = "UTF8"

$raiz = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $raiz
$rutaSalida = Join-Path $raiz $Salida
New-Item -ItemType Directory -Force -Path (Split-Path $rutaSalida -Parent) | Out-Null
($Titulo + " - " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " - equipo " + $env:COMPUTERNAME) | Out-File -FilePath $rutaSalida -Encoding utf8

function Log([string]$texto) {
    Write-Host $texto
    Add-Content -Path $rutaSalida -Value $texto -Encoding utf8
}

# Buscar psql
$psql = $null
$cmd = Get-Command psql -ErrorAction SilentlyContinue
if ($cmd) { $psql = $cmd.Source } else {
    $candidato = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
        Sort-Object { [int](($_.Directory.Parent.Name) -replace '\D', '') } -Descending | Select-Object -First 1
    if ($candidato) { $psql = $candidato.FullName }
}
if (-not $psql) { Log "FALLO: no se encontro psql."; exit 1 }

$seguro = Read-Host ("Contrasena de PostgreSQL para el usuario '" + $PgUser + "'") -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro)
$env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

$con = @("-X", "-h", $PgHost, "-p", [string]$PgPort, "-U", $PgUser, "-d", $Base, "-v", "ON_ERROR_STOP=1")
# Con "powershell -File" la lista llega como un solo texto separado por comas: se separa aqui.
$lista = @($Scripts | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
$todoBien = $true
foreach ($archivo in $lista) {
    Log ""
    Log ("===== " + $archivo + " =====")
    if (-not (Test-Path $archivo)) { Log ("FALLO: no existe " + $archivo); $todoBien = $false; break }
    & $psql @con -f $archivo 2>&1 | ForEach-Object { Log ([string]$_) }
    if ($LASTEXITCODE -ne 0) {
        Log ("FALLO en " + $archivo + " (se detiene aqui)")
        $todoBien = $false
        break
    }
}
Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue

Log ""
if ($todoBien) { Log "RESULTADO: OK - todos los scripts corrieron sin errores." }
else { Log "RESULTADO: HUBO UN ERROR - revise el mensaje FALLO." }
Log ("Salida guardada en: " + $rutaSalida)
