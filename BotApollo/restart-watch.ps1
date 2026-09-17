# Reinicia o Robo - L2 Apollo enquanto o exit code != 0 (Sair limpo = 0).
# - Ignora stubs WindowsApps (Microsoft Store)
# - Aspas no path (pastas com espaco tipo "Otto Tech" / "L2 Valakas")
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
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
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

    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pyLauncher -and ([string]$pyLauncher.Source) -notmatch 'WindowsApps') {
        return $pyLauncher.Source
    }
    return $null
}

$py = Resolve-PythonExe
if (-not $py) {
    Write-Log "ERRO: Python nao encontrado (evite o stub WindowsApps)."
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "Python nao encontrado.`nInstale o Python e marque Add to PATH.`n(Nao use o atalho da Microsoft Store.)",
            "Robo - L2 Apollo",
            "OK",
            "Error"
        ) | Out-Null
    } catch { }
    exit 1
}

$main = Join-Path $dir "main.py"
if (-not (Test-Path -LiteralPath $main)) {
    Write-Log "ERRO: main.py ausente em $dir"
    exit 1
}

Write-Log "Python=$py"
Write-Log "Main=$main"

# Start-Process ArgumentList: path com espaco PRECISA ir entre aspas numa string unica.
if ([IO.Path]::GetFileNameWithoutExtension($py) -ieq "py") {
    $argLine = "-3 `"$main`""
} else {
    $argLine = "`"$main`""
}

while ($true) {
    Write-Log "Iniciando args=$argLine"
    $p = Start-Process -FilePath $py -ArgumentList $argLine -WorkingDirectory $dir -Wait -PassThru -WindowStyle Hidden
    if ($null -eq $p) {
        Write-Log "Start-Process retornou null — retry em 3s"
        Start-Sleep -Seconds 3
        continue
    }
    Write-Log ("Saiu com codigo {0}" -f $p.ExitCode)
    if ($p.ExitCode -eq 0) {
        exit 0
    }
    Start-Sleep -Seconds 3
}
