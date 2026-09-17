# Sobe UMA instancia do Robo - L2 Apollo (mata a anterior).
# Chamado pelo start.bat. Reinicio em crash fica no main.py.
$ErrorActionPreference = "Continue"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $dir

$logDir = Join-Path $dir "logs"
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$log = Join-Path $logDir "start.log"

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    try { Add-Content -LiteralPath $log -Value $line -Encoding UTF8 } catch { }
}

function Resolve-PythonExe {
    $Prefer = @(
        (Join-Path $env:LOCALAPPDATA "Python\bin\pythonw.exe"),
        (Join-Path $env:LOCALAPPDATA "Python\bin\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python314\pythonw.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python313\pythonw.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\pythonw.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\pythonw.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python310\pythonw.exe")
    )
    foreach ($p in $Prefer) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    foreach ($name in @("pythonw", "python")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $src = [string]$cmd.Source
        if ($src -match 'WindowsApps') { continue }
        if ($src -and (Test-Path -LiteralPath $src)) { return $src }
    }
    return $null
}

function Stop-PreviousBotApollo([string]$mainPath) {
    $myPid = $PID
    $mainLeaf = [IO.Path]::GetFileName($mainPath)
    $dirNorm = $dir.TrimEnd('\')

    # Qualquer watch antigo desta pasta
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $myPid -and
            $_.Name -match '^(powershell|pwsh)\.exe$' -and
            $_.CommandLine -and
            ($_.CommandLine -match 'restart-watch\.ps1|start-bot\.ps1') -and
            ($_.CommandLine -like ("*{0}*" -f [IO.Path]::GetFileName($dirNorm)))
        } |
        ForEach-Object {
            Write-Log ("Matando watch PID={0}" -f $_.ProcessId)
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    # python desta pasta / main.py
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^pythonw?\.exe$' -and
            $_.CommandLine -and
            (
                ($_.CommandLine -like ("*{0}*" -f $mainPath)) -or
                (
                    ($_.CommandLine -like ("*{0}*" -f $mainLeaf)) -and
                    ($_.CommandLine -like '*BotApollo*')
                )
            )
        } |
        ForEach-Object {
            Write-Log ("Matando Robo PID={0}" -f $_.ProcessId)
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    # PID file
    $pidFile = Join-Path $logDir "robo.pid"
    if (Test-Path -LiteralPath $pidFile) {
        try {
            $old = [int]((Get-Content -LiteralPath $pidFile -Raw).Trim())
            if ($old -gt 0) {
                Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
            }
        } catch { }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Milliseconds 500
}

$py = Resolve-PythonExe
$main = Join-Path $dir "main.py"

if (-not $py) {
    Write-Log "ERRO: Python nao encontrado"
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "Python nao encontrado.`nInstale o Python (Add to PATH).`nNao use o stub da Microsoft Store.",
            "Robo - L2 Apollo", "OK", "Error"
        ) | Out-Null
    } catch { }
    exit 1
}
if (-not (Test-Path -LiteralPath $main)) {
    Write-Log "ERRO: main.py ausente"
    exit 1
}

Write-Log "Kill anteriores..."
Stop-PreviousBotApollo -mainPath $main

Write-Log "Python=$py"
Write-Log "Main=$main"
Write-Log "Start-Process (sem Wait)..."

# Path com espaco: ArgumentList como STRING com aspas
$argLine = "`"$main`""
if ([IO.Path]::GetFileNameWithoutExtension($py) -ieq "py") {
    $argLine = "-3 `"$main`""
}

$p = Start-Process -FilePath $py -ArgumentList $argLine -WorkingDirectory $dir -PassThru -WindowStyle Hidden
if ($null -eq $p) {
    Write-Log "ERRO: Start-Process falhou"
    exit 1
}
Write-Log ("OK PID={0}" -f $p.Id)
exit 0
