# Sobe UMA instancia do Robo - L2 Apollo (mata a anterior).
# Usa o mesmo Python do cmd (PATH do Windows / alias).
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

function Refresh-ProcessPath {
    # Explorer/PS as vezes nao ve o PATH do usuario igual ao cmd interativo
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($machine) { $parts += $machine }
    if ($user) { $parts += $user }
    if ($env:Path) { $parts += $env:Path }
    $env:Path = ($parts -join ";")
}

function Resolve-PythonExe {
    Refresh-ProcessPath

    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($name in @("pythonw", "python", "py")) {
        try {
            foreach ($line in @(& where.exe $name 2>$null)) {
                $t = [string]$line.Trim()
                if ($t) { [void]$hits.Add($t) }
            }
        } catch { }
    }

    Write-Log ("where hits: " + (($hits | Select-Object -Unique) -join " | "))

    # 1) Instalacao real (fora WindowsApps)
    foreach ($h in ($hits | Select-Object -Unique)) {
        if ($h -match 'WindowsApps') { continue }
        if (Test-Path -LiteralPath $h) { return $h }
    }

    # 2) Alias Microsoft Store / unico no PATH — no cmd o cliente usa isso e abre 3.x
    foreach ($h in ($hits | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $h) { return $h }
    }

    # 3) Nome puro (Start-Process resolve no PATH, igual digitar python no cmd)
    foreach ($name in @("pythonw", "python", "py")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $name }
    }

    # 4) Pastas tipicas
    $guess = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python313\pythonw.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python313\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\pythonw.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python314\pythonw.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python314\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Python\bin\pythonw.exe"),
        (Join-Path $env:LOCALAPPDATA "Python\bin\python.exe")
    )
    foreach ($g in $guess) {
        if (Test-Path -LiteralPath $g) { return $g }
    }

    Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA "Programs\Python") -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            foreach ($exe in @("pythonw.exe", "python.exe")) {
                $c = Join-Path $_.FullName $exe
                if (Test-Path -LiteralPath $c) { return $c }
            }
        }

    return $null
}

function Stop-PreviousBotApollo([string]$mainPath) {
    $myPid = $PID
    $mainLeaf = [IO.Path]::GetFileName($mainPath)

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $myPid -and
            $_.Name -match '^(powershell|pwsh)\.exe$' -and
            $_.CommandLine -and
            ($_.CommandLine -match 'restart-watch\.ps1|start-bot\.ps1')
        } |
        ForEach-Object {
            Write-Log ("Matando watch PID={0}" -f $_.ProcessId)
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^pythonw?\.exe$' -and
            $_.CommandLine -and
            (
                ($_.CommandLine -like ("*{0}*" -f $mainPath)) -or
                (($_.CommandLine -like ("*{0}*" -f $mainLeaf)) -and ($_.CommandLine -like '*BotApollo*'))
            )
        } |
        ForEach-Object {
            Write-Log ("Matando Robo PID={0}" -f $_.ProcessId)
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    $pidFile = Join-Path $logDir "robo.pid"
    if (Test-Path -LiteralPath $pidFile) {
        try {
            $old = [int]((Get-Content -LiteralPath $pidFile -Raw).Trim())
            if ($old -gt 0) { Stop-Process -Id $old -Force -ErrorAction SilentlyContinue }
        } catch { }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Milliseconds 400
}

$py = Resolve-PythonExe
$main = Join-Path $dir "main.py"

if (-not $py) {
    Write-Log "ERRO: Python nao encontrado apos refresh PATH"
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "Python nao encontrado no PATH.`nNo cmd, teste: python --version`nInstale o Python e marque Add to PATH.",
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

# py launcher precisa -3; path com espaco entre aspas
if ($py -eq "py" -or ([IO.Path]::GetFileNameWithoutExtension([string]$py) -ieq "py")) {
    $argLine = "-3 `"$main`""
} else {
    $argLine = "`"$main`""
}

Write-Log "Start args=$argLine"
$p = Start-Process -FilePath $py -ArgumentList $argLine -WorkingDirectory $dir -PassThru -WindowStyle Hidden
if ($null -eq $p) {
    Write-Log "ERRO: Start-Process falhou com FilePath=$py — tentando via cmd"
    # Ultimo recurso: mesmo jeito que o cliente testa no cmd
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c","python `"$main`"" -WorkingDirectory $dir -PassThru -WindowStyle Hidden
}
if ($null -eq $p) {
    Write-Log "ERRO: Start-Process falhou de vez"
    exit 1
}
Write-Log ("OK PID={0}" -f $p.Id)
exit 0
