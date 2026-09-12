# L2Apollo - atualizacao forcada do pacote cliente
# Preserva: config\ + keys.txt/token.txt/helper.live/hwid.local
# Sobrescreve: .enc, DLL, exe, runtime, bats, etc.
$ErrorActionPreference = "Continue"
$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location -LiteralPath $Root

function Write-Step([string]$msg) { Write-Host ""; Write-Host $msg -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Info([string]$msg) { Write-Host "  $msg" -ForegroundColor Gray }
function Write-Warn([string]$msg) { Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)  { Write-Host "  [ERRO] $msg" -ForegroundColor Red }

$encName = $null
Get-ChildItem -LiteralPath $Root -Filter "*.enc" -File -ErrorAction SilentlyContinue |
  Select-Object -First 1 | ForEach-Object { $encName = $_.Name }
if (-not $encName) { $encName = "L2Apollo-All-In-One.enc" }

$trackedHot = @(
  $encName,
  "L2ApolloPanel.dll",
  "L2Apollo.exe",
  "L2ApolloPanel.exe",
  "atualizar.bat",
  "atualizar-core.ps1",
  "runtime\core.pak",
  "runtime\boot.ps1"
) | ForEach-Object { Join-Path $Root $_ }

$knownKill = @(
  "L2ApolloPanel", "L2Apollo",
  "Adrenaline", "l2", "AB", "Manager", "AdrenalineBotUpdater"
)

# --- Restart Manager: quem trava arquivo ---
$rmType = @"
using System;
using System.Runtime.InteropServices;
public static class L2Rm {
  [StructLayout(LayoutKind.Sequential)]
  public struct RM_UNIQUE_PROCESS {
    public int dwProcessId;
    public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
  }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct RM_PROCESS_INFO {
    public RM_UNIQUE_PROCESS Process;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string strAppName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string strServiceShortName;
    public uint ApplicationType;
    public uint AppStatus;
    public uint TSSessionId;
    [MarshalAs(UnmanagedType.Bool)] public bool bRestartable;
  }
  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
  public static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);
  [DllImport("rstrtmgr.dll")]
  public static extern int RmEndSession(uint pSessionHandle);
  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
  public static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames,
    uint nApplications, IntPtr rgApplications, uint nServices, string[] rgsServiceNames);
  [DllImport("rstrtmgr.dll")]
  public static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded,
    ref uint pnProcInfo, [In, Out] RM_PROCESS_INFO[] rgAffectedApps, out uint lpdwRebootReasons);
}
"@
try { Add-Type -TypeDefinition $rmType -ErrorAction Stop } catch { }

function Get-LockingPids([string[]]$paths) {
  $set = New-Object "System.Collections.Generic.HashSet[int]"
  $exist = @($paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
  if ($exist.Count -eq 0) { return @() }
  if (-not ("L2Rm" -as [type])) { return @() }

  $session = [uint32]0
  $key = [guid]::NewGuid().ToString()
  $rc = [L2Rm]::RmStartSession([ref]$session, 0, $key)
  if ($rc -ne 0) { return @() }
  try {
    $rc = [L2Rm]::RmRegisterResources($session, [uint32]$exist.Count, [string[]]$exist, 0, [IntPtr]::Zero, 0, $null)
    if ($rc -ne 0) { return @() }
    $needed = [uint32]0
    $count = [uint32]0
    $reboot = [uint32]0
    $rc = [L2Rm]::RmGetList($session, [ref]$needed, [ref]$count, $null, [ref]$reboot)
    if ($needed -eq 0) { return @() }
    $arr = New-Object L2Rm+RM_PROCESS_INFO[] $needed
    $count = $needed
    $rc = [L2Rm]::RmGetList($session, [ref]$needed, [ref]$count, $arr, [ref]$reboot)
    if ($rc -ne 0) { return @() }
    for ($i = 0; $i -lt $count; $i++) {
      $id = [int]$arr[$i].Process.dwProcessId
      if ($id -gt 4) { [void]$set.Add($id) }
    }
  } finally {
    [void][L2Rm]::RmEndSession($session)
  }
  return @($set)
}

function Stop-PidSafe([int]$procId, [string]$why) {
  if ($procId -le 4) { return $false }
  try {
    $p = Get-Process -Id $procId -ErrorAction Stop
    $name = $p.ProcessName
    if ($name -match '^(explorer|csrss|winlogon|services|lsass|System)$') {
      Write-Warn "Nao vou matar processo do sistema: $name (PID $procId)"
      return $false
    }
    Write-Host "  -> matando $name (PID $procId) [$why]" -ForegroundColor Yellow
    Stop-Process -Id $procId -Force -ErrorAction Stop
    return $true
  } catch {
    Write-Warn "Nao consegui matar PID $procId : $($_.Exception.Message)"
    return $false
  }
}

function Restore-ClientLocal {
  param($Root, $cfg, $cfgDef, $cfgBak, $licBak, $encName)
  Write-Step "[6/6] Restaurando sua config\ e licenca..."
  if (-not (Test-Path -LiteralPath $cfg)) { New-Item -ItemType Directory -Path $cfg -Force | Out-Null }
  if (Test-Path -LiteralPath $cfgBak) {
    Copy-Item -LiteralPath (Join-Path $cfgBak "*") -Destination $cfg -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "config\ restaurada (seus INIs)"
  } else {
    Write-Info "(sem backup de config)"
  }
  foreach ($f in @("keys.txt", "token.txt", "helper.live", "hwid.local")) {
    $src = Join-Path $licBak $f
    if (Test-Path -LiteralPath $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $Root $f) -Force
    }
  }
  if (Test-Path -LiteralPath $cfgDef) {
    Get-ChildItem -LiteralPath $cfgDef -Filter "*.ini" -File | ForEach-Object {
      $dest = Join-Path $cfg $_.Name
      if (-not (Test-Path -LiteralPath $dest)) {
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
        Write-Info ("+ " + $_.Name + " (novo, veio do default)")
      }
    }
  }
  Remove-Item -LiteralPath $cfgBak -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $licBak -Recurse -Force -ErrorAction SilentlyContinue
  $encOld = Join-Path $Root ($encName + ".old")
  if (Test-Path -LiteralPath $encOld) {
    Remove-Item -LiteralPath $encOld -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "============================================================"
Write-Host "  L2 APOLLO - Atualizar (forcado)"
Write-Host "============================================================"
Write-Host "  Pasta: $Root"

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
  Write-Err "Git nao encontrado no PATH. Instale Git for Windows."
  exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $Root ".git"))) {
  Write-Err "Esta pasta nao e um repositorio Git."
  Write-Info "Clone: git clone https://github.com/techotto/L2Apollo-All-In-One-Cliente.git"
  exit 1
}

$before = (& git -C $Root rev-parse --short HEAD 2>$null)
$encBefore = Get-Item -LiteralPath (Join-Path $Root $encName) -ErrorAction SilentlyContinue
Write-Info ("Commit atual: " + $(if ($before) { $before } else { "?" }))
if ($encBefore) {
  Write-Info ("$encName : {0:N0} bytes  {1}" -f $encBefore.Length, $encBefore.LastWriteTime.ToString("dd/MM/yyyy HH:mm:ss"))
} else {
  Write-Warn "$encName ainda nao existe nesta pasta"
}

Write-Step "[1/6] Salvando config\ e licenca..."
$cfg = Join-Path $Root "config"
$cfgDef = Join-Path $Root "config.default"
$cfgBak = Join-Path $env:TEMP ("l2apollo-config-bak-" + [guid]::NewGuid().ToString("N"))
$licBak = Join-Path $env:TEMP ("l2apollo-lic-bak-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $cfgBak -Force | Out-Null
New-Item -ItemType Directory -Path $licBak -Force | Out-Null
if (Test-Path -LiteralPath $cfg) {
  Copy-Item -LiteralPath (Join-Path $cfg "*") -Destination $cfgBak -Recurse -Force -ErrorAction SilentlyContinue
  Write-Ok "config\ salva em backup temporario"
} else {
  Write-Info "(ainda nao tinha config\)"
}
foreach ($f in @("keys.txt", "token.txt", "helper.live", "hwid.local")) {
  $src = Join-Path $Root $f
  if (Test-Path -LiteralPath $src) {
    Copy-Item -LiteralPath $src -Destination (Join-Path $licBak $f) -Force
  }
}
Write-Ok "licenca (keys/token/helper/hwid) preservada"

$script:UpdateOk = $false
try {
  Write-Step "[2/6] Detectando processos que travam .enc / DLL / exe..."
  $killed = 0
  $lockerPids = @(Get-LockingPids $trackedHot)
  if ($lockerPids.Count -eq 0) {
    Write-Info "Nenhum processo detectado via Restart Manager (ou arquivos livres)."
  } else {
    Write-Warn ("Encontrei {0} processo(s) usando arquivos do pacote:" -f $lockerPids.Count)
    foreach ($lockerId in $lockerPids) {
      $pn = "?"
      try { $pn = (Get-Process -Id $lockerId -ErrorAction SilentlyContinue).ProcessName } catch {}
      Write-Host "     - PID $lockerId  $pn" -ForegroundColor Yellow
    }
    foreach ($lockerId in $lockerPids) {
      if (Stop-PidSafe $lockerId "arquivo em uso") { $killed++ }
    }
  }

  Write-Info "Tambem encerrando processos conhecidos (painel / Adrenaline)..."
  foreach ($name in $knownKill) {
    Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
      if (Stop-PidSafe $_.Id "lista conhecida") { $killed++ }
    }
  }
  Start-Sleep -Seconds 1
  Write-Ok ("Processos encerrados nesta rodada: $killed")

  $encPath = Join-Path $Root $encName
  if (Test-Path -LiteralPath $encPath) {
    try {
      $fs = [System.IO.File]::Open($encPath, "Open", "ReadWrite", "None")
      $fs.Close()
    } catch {
      Write-Warn "$encName ainda parece travado - tentando renomear para .old"
      try {
        $old = $encPath + ".old"
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue }
        Rename-Item -LiteralPath $encPath -NewName ($encName + ".old") -Force -ErrorAction Stop
        Write-Ok "renomeado para $encName.old (sera substituido pelo GitHub)"
      } catch {
        Write-Err "Nao consegui liberar $encName. Feche o Adrenaline manualmente e rode de novo."
        Write-Err $_.Exception.Message
      }
    }
  }

  Write-Step "[3/6] Baixando do GitHub..."
  & git -C $Root fetch --prune origin
  if ($LASTEXITCODE -ne 0) { throw "git fetch falhou (rede / git)." }
  Write-Ok "fetch OK"

  $remote = (& git -C $Root rev-parse --short origin/main 2>$null)
  if (-not $remote) { throw "origin/main nao encontrado apos fetch." }
  Write-Info "GitHub main: $remote"

  Write-Step "[4/6] Forcando pasta = GitHub (sem merge / sem pull)..."
  & git -C $Root merge --abort 2>$null | Out-Null
  & git -C $Root rebase --abort 2>$null | Out-Null
  & git -C $Root cherry-pick --abort 2>$null | Out-Null
  & git -C $Root am --abort 2>$null | Out-Null
  & git -C $Root reset --hard HEAD 2>$null | Out-Null
  & git -C $Root clean -fd 2>$null | Out-Null

  & git -C $Root checkout -B main origin/main
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "checkout -B falhou; tentando reset --hard origin/main"
    & git -C $Root reset --hard origin/main
  }
  if ($LASTEXITCODE -ne 0) { throw "Falha ao aplicar update (arquivo ainda em uso?). Feche Adrenaline e rode de novo." }
  & git -C $Root reset --hard origin/main
  if ($LASTEXITCODE -ne 0) { throw "reset final falhou." }
  & git -C $Root clean -fd 2>$null | Out-Null
  Write-Ok "reset OK"

  Write-Step "[5/6] Verificando se atualizou de verdade..."
  $after = (& git -C $Root rev-parse --short HEAD 2>$null)
  $afterFull = (& git -C $Root rev-parse HEAD 2>$null)
  $remoteFull = (& git -C $Root rev-parse origin/main 2>$null)
  $encAfter = Get-Item -LiteralPath (Join-Path $Root $encName) -ErrorAction SilentlyContinue
  $dllAfter = Get-Item -LiteralPath (Join-Path $Root "L2ApolloPanel.dll") -ErrorAction SilentlyContinue

  $ok = $true
  if (-not $afterFull -or -not $remoteFull -or ($afterFull -ne $remoteFull)) {
    Write-Err "HEAD != origin/main  (local=$after  remote=$remote)"
    $ok = $false
  } else {
    Write-Ok "Commit local = GitHub ($after)"
  }

  if ($encAfter) {
    Write-Ok ("$encName : {0:N0} bytes  {1}" -f $encAfter.Length, $encAfter.LastWriteTime.ToString("dd/MM/yyyy HH:mm:ss"))
    if ($encBefore -and $before -ne $after -and $encBefore.Length -eq $encAfter.Length -and $encBefore.LastWriteTime -eq $encAfter.LastWriteTime) {
      Write-Warn "Tamanho/data do .enc iguais ao anterior - pode ter ficado travado."
      Write-Warn "Feche o Adrenaline e rode de novo."
      $ok = $false
    }
  } else {
    Write-Err "$encName NAO encontrado apos update"
    $ok = $false
  }

  if ($dllAfter) {
    Write-Ok ("L2ApolloPanel.dll : {0:N0} bytes  {1}" -f $dllAfter.Length, $dllAfter.LastWriteTime.ToString("dd/MM/yyyy HH:mm:ss"))
  } else {
    Write-Warn "L2ApolloPanel.dll nao encontrado"
  }

  if ($before -and $after -and ($before -eq $after)) {
    Write-Info "Ja estava no commit mais recente ($after) - nada novo no GitHub."
  } elseif ($before -and $after) {
    Write-Ok "Atualizou: $before  ->  $after"
  }

  $script:UpdateOk = $ok
} catch {
  Write-Err $_.Exception.Message
  $script:UpdateOk = $false
} finally {
  Restore-ClientLocal -Root $Root -cfg $cfg -cfgDef $cfgDef -cfgBak $cfgBak -licBak $licBak -encName $encName
}

Write-Host ""
Write-Host "============================================================"
if ($script:UpdateOk) {
  Write-Host "  SUCESSO - pacote igual ao GitHub." -ForegroundColor Green
  Write-Host "  Seus INIs em config\ foram mantidos." -ForegroundColor Green
  Write-Host ""
  Write-Host "  Agora: abra o .enc de novo no Adrenaline (F9)." -ForegroundColor White
  Write-Host "============================================================"
  exit 0
} else {
  Write-Host "  FALHOU / INCOMPLETO - veja os [ERRO]/[!] acima." -ForegroundColor Red
  Write-Host "  Dica: feche o Adrenaline e rode atualizar.bat de novo." -ForegroundColor Yellow
  Write-Host "============================================================"
  exit 1
}
