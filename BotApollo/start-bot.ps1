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
    # 1) where.exe = mesma resolucao do cmd (python no PATH do Windows)
    foreach ($name in @("pythonw", "python", "py")) {
        try {
            $lines = & where.exe $name 2>$null
        } catch {
            $lines = $null
        }
        if (-not $lines) { continue }
        foreach ($line in @($lines)) {
            $src = [string]$line.Trim()
            if (-not $src) { continue }
            if ($src -match 'WindowsApps') { continue }
            if (Test-Path -LiteralPath $src) { return $src }
        }
    }

    # 2) Get-Command (pode achar fora do where)
    foreach ($name in @("pythonw", "python", "py")) {
        $all = @(Get-Command $name -All -ErrorAction SilentlyContinue)
        foreach ($cmd in $all) {
            $src = [string]$cmd.Source
            if (-not $src -or ($src -match 'WindowsApps')) { continue }
            if (Test-Path -LiteralPath $src) { return $src }
        }
    }

    # 3) Pastas tipicas de instalacao
    $roots = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python"),
        (Join-Path $env:LOCALAPPDATA "Python"),
        (Join-Path ${env:ProgramFiles} "Python*"),
        (Join-Path ${env:ProgramFiles(x86)} "Python*")
    )
    foreach ($rootPat in $roots) {
        if (-not $rootPat) { continue }
        $dirs = @()
        try { $dirs = @(Get-Item -Path $rootPat -ErrorAction SilentlyContinue) } catch { }
        foreach ($d in $dirs) {
            foreach ($exe in @("pythonw.exe", "python.exe")) {
                $candidate = Join-Path $d.FullName $exe
                if (Test-Path -LiteralPath $candidate) { return $candidate }
                $candidate2 = Join-Path $d.FullName (Join-Path "bin" $exe)
                if (Test-Path -LiteralPath $candidate2) { return $candidate2 }
            }
        }
        # Python3xx subdirs
        if (Test-Path -LiteralPath (Split-Path $rootPat -Parent)) {
            Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA "Programs\Python") -Directory -ErrorAction SilentlyContinue |
                ForEach-Object {
                    foreach ($exe in @("pythonw.exe", "python.exe")) {
                        $c = Join-Path $_.FullName $exe
                        if (Test-Path -LiteralPath $c) { return $c }
                    }
                }
        }
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
