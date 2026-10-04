# =============================================================================
# L2Apollo - Setup da maquina do cliente
# =============================================================================
# Instala Git + Python (winget) e clona o pacote cliente.
#
# Uso:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-maquina.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-maquina.ps1 -Dest "D:\L2Apollo"
# Ou: dois cliques em setup-maquina.bat (como Administrador)
# =============================================================================

param(
    [string]$Dest = "",
    [string]$RepoUrl = "https://github.com/techotto/L2Apollo-All-In-One-Cliente.git",
    [string]$FolderName = "L2Apollo-All-In-One-Cliente",
    [switch]$SkipGit,
    [switch]$SkipPython,
    [switch]$SkipClone,
    [switch]$SkipPip
)

$ErrorActionPreference = "Stop"
$exitCode = 0

function Write-Step([string]$Msg) {
    Write-Host ""
    Write-Host ("==> " + $Msg) -ForegroundColor Cyan
}

function Write-Ok([string]$Msg) {
    Write-Host ("[OK] " + $Msg) -ForegroundColor Green
}

function Write-Info([string]$Msg) {
    Write-Host ("     " + $Msg) -ForegroundColor Gray
}

function Write-Warn([string]$Msg) {
    Write-Host ("[!] " + $Msg) -ForegroundColor Yellow
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-PathEnv {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = ($machine + ";" + $user)
}

function Test-Cmd([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Ensure-Winget {
    if (Test-Cmd "winget") {
        return $true
    }
    Write-Warn "winget nao encontrado. Instale o 'Instalador de App' na Microsoft Store."
    return $false
}

function Install-WithWinget([string]$Id, [string]$DisplayName) {
    if (-not (Ensure-Winget)) {
        throw "winget indisponivel. Instale o Instalador de App (Microsoft Store) e rode de novo."
    }
    Write-Info ("winget install " + $Id + " ...")
    # Out-Host: NAO deixa o texto do winget virar retorno da funcao (bug do PowerShell)
    & winget install -e --id $Id --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-Host
    $code = $LASTEXITCODE
    # 0 = ok | -1978335189 = ja instalado
    if (($code -eq 0) -or ($code -eq -1978335189)) {
        Write-Ok ($DisplayName + " instalado (ou ja estava).")
        return
    }
    throw ("winget falhou ao instalar " + $DisplayName + " (exit=" + $code + ").")
}

function Ensure-Git {
    Refresh-PathEnv
    if (Test-Cmd "git") {
        $v = (& git --version 2>$null | Out-String).Trim()
        Write-Ok ("Git ja instalado: " + $v)
        return
    }
    Write-Step "Instalando Git..."
    Install-WithWinget "Git.Git" "Git"
    Refresh-PathEnv
    if (-not (Test-Cmd "git")) {
        throw "Git instalado, mas nao esta no PATH. Feche o terminal e abra de novo (ou reinicie o PC)."
    }
    $v = (& git --version 2>$null | Out-String).Trim()
    Write-Ok $v
}

function Find-PythonExe {
    foreach ($name in @("py", "python", "python3")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $cmd) {
            continue
        }
        try {
            $out = & $cmd.Source --version 2>&1 | Out-String
            if ($out -match "Python\s+3\.") {
                return [string]$cmd.Source
            }
        }
        catch {
            # stub da Store ou falha - tenta proximo
        }
    }

    # Fallback: caminhos tipicos do instalador oficial (apos winget, PATH ainda frio)
    $local = [Environment]::GetFolderPath("LocalApplicationData")
    $candidates = @(
        (Join-Path $local "Programs\Python\Launcher\py.exe"),
        (Join-Path $local "Programs\Python\Python313\python.exe"),
        (Join-Path $local "Programs\Python\Python312\python.exe"),
        (Join-Path $local "Programs\Python\Python311\python.exe")
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) {
            try {
                $out = & $p --version 2>&1 | Out-String
                if ($out -match "Python\s+3\.") {
                    return [string]$p
                }
            }
            catch { }
        }
    }
    return $null
}

function Ensure-Python {
    Refresh-PathEnv
    $py = Find-PythonExe
    if ($py) {
        $v = (& $py --version 2>&1 | Out-String).Trim()
        Write-Ok ("Python ja instalado: " + $v + " (" + $py + ")")
        return [string]$py
    }

    Write-Step "Instalando Python 3 (winget)..."
    if (-not (Ensure-Winget)) {
        throw "winget indisponivel para instalar Python."
    }

    $candidates = @(
        "Python.Python.3.13",
        "Python.Python.3.12",
        "Python.Python.3.11"
    )
    $installed = $false
    foreach ($id in $candidates) {
        Write-Info ("Tentando " + $id + " ...")
        & winget install -e --id $id --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-Host
        if (($LASTEXITCODE -eq 0) -or ($LASTEXITCODE -eq -1978335189)) {
            $installed = $true
            break
        }
        Write-Warn ("Nao instalou " + $id + " (exit=" + $LASTEXITCODE + ") - tentando proxima...")
    }
    if (-not $installed) {
        throw "Nao foi possivel instalar Python via winget."
    }

    Refresh-PathEnv
    Start-Sleep -Seconds 2
    Refresh-PathEnv
    $py = Find-PythonExe
    if (-not $py) {
        throw "Python instalado, mas nao esta no PATH. Feche o terminal e abra de novo (ou reinicie o PC)."
    }
    $v = (& $py --version 2>&1 | Out-String).Trim()
    Write-Ok $v
    return [string]$py
}

function Resolve-DestFolder {
    if (-not [string]::IsNullOrWhiteSpace($Dest)) {
        return [System.IO.Path]::GetFullPath($Dest)
    }
    $docs = [Environment]::GetFolderPath("MyDocuments")
    if ([string]::IsNullOrWhiteSpace($docs)) {
        $docs = $env:USERPROFILE
    }
    return (Join-Path $docs $FolderName)
}

function Ensure-Clone([string]$Target) {
    Write-Step "Clonando repositorio do cliente..."
    Write-Info ("URL:  " + $RepoUrl)
    Write-Info ("Pasta: " + $Target)

    $gitDir = Join-Path $Target ".git"
    if (Test-Path -LiteralPath $gitDir) {
        Write-Ok "Pasta ja e um clone git - atualizando (fetch + reset hard main)..."
        & git -C $Target fetch --prune origin
        if ($LASTEXITCODE -ne 0) {
            throw "git fetch falhou."
        }
        & git -C $Target checkout -B main origin/main
        & git -C $Target reset --hard origin/main
        Write-Ok "Clone atualizado."
        return
    }

    if (Test-Path -LiteralPath $Target) {
        $items = @(Get-ChildItem -LiteralPath $Target -Force -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) {
            throw ("Pasta destino ja existe e nao esta vazia: " + $Target + " | Apague ou use -Dest com outro caminho.")
        }
    }
    else {
        $parent = Split-Path -Parent $Target
        if ($parent -and (-not (Test-Path -LiteralPath $parent))) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
    }

    & git clone --depth 1 $RepoUrl $Target
    if (($LASTEXITCODE -ne 0) -or (-not (Test-Path -LiteralPath (Join-Path $Target ".git")))) {
        throw "git clone falhou."
    }
    Write-Ok "Clone concluido."
}

function Ensure-PipDeps([string]$Target, [string]$PythonExe) {
    $req = Join-Path $Target "BotApollo\requirements.txt"
    if (-not (Test-Path -LiteralPath $req)) {
        Write-Warn "BotApollo\requirements.txt nao encontrado - pulando pip."
        return
    }
    Write-Step "Instalando dependencias Python do BotApollo..."
    & $PythonExe -m pip install --upgrade pip
    & $PythonExe -m pip install -r $req
    if ($LASTEXITCODE -ne 0) {
        throw "pip install falhou."
    }
    Write-Ok "Dependencias do BotApollo ok."
}

try {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  L2Apollo - Setup da maquina (Git + Python + clone)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    if (-not (Test-IsAdmin)) {
        Write-Warn "Nao esta como Administrador. winget pode pedir UAC / falhar."
        Write-Info "Prefira: botao direito no setup-maquina.bat -> Executar como administrador."
    }

    $target = Resolve-DestFolder
    $pythonExe = $null

    if (-not $SkipGit) {
        Ensure-Git | Out-Null
    }
    if (-not $SkipPython) {
        $pythonExe = [string](Ensure-Python | Select-Object -Last 1)
    }
    else {
        $pythonExe = Find-PythonExe
    }
    if (-not $SkipClone) {
        Ensure-Clone $target | Out-Null
    }
    if ((-not $SkipPip) -and $pythonExe -and (Test-Path -LiteralPath $target)) {
        Write-Info ("Usando Python: " + $pythonExe)
        Ensure-PipDeps $target $pythonExe | Out-Null
    }

    if (Test-Path -LiteralPath $target) {
        [System.IO.File]::WriteAllText("C:\Users\Public\l2apollo.path", $target, [System.Text.Encoding]::ASCII)
        Write-Ok "Pasta do pacote gravada em C:\Users\Public\l2apollo.path"
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  PRONTO" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Info ("Pasta do cliente: " + $target)
    Write-Info "Proximos passos:"
    Write-Info "  1) Abra o .enc desta pasta no Adrenaline (F9)"
    Write-Info "  2) No painel, preencha o CADASTRO"
    Write-Info "  3) Aguarde o suporte liberar"
    Write-Host ""
}
catch {
    $exitCode = 1
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "  ERRO" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
}

Write-Host "Pressione Enter para fechar..." -ForegroundColor Yellow
try {
    [void](Read-Host)
}
catch {
    Start-Sleep -Seconds 8
}
exit $exitCode
