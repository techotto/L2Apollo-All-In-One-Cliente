# Reinicia o Robo - L2 Apollo enquanto o exit code != 0 (Sair limpo = 0).
$ErrorActionPreference = "Continue"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $dir

$py = $null
foreach ($name in @("pythonw", "python")) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) {
        $py = $cmd.Source
        break
    }
}
if (-not $py) {
    exit 1
}

$main = Join-Path $dir "main.py"
while ($true) {
    $p = Start-Process -FilePath $py -ArgumentList @($main) -WorkingDirectory $dir -Wait -PassThru -WindowStyle Hidden
    if ($null -eq $p) {
        Start-Sleep -Seconds 3
        continue
    }
    if ($p.ExitCode -eq 0) {
        exit 0
    }
    Start-Sleep -Seconds 3
}
