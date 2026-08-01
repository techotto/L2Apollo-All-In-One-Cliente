param(
    [ValidateSet("Guard","Install","ShowHwid","RevealBinHwid")]
    [string]$Action = "Guard",
    [string]$Key = "",
    [string]$Hwid = ""
)

$ErrorActionPreference = "Stop"
$ClientRoot = Split-Path $PSScriptRoot -Parent
$PakPath = Join-Path $PSScriptRoot "core.pak"
$PakKey  = "L2Apollo-ClientPack-v1"

function Unprotect-Payload([string]$B64, [string]$Key) {
    $raw = [Convert]::FromBase64String($B64)
    $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Key)
    $dec = New-Object byte[] $raw.Length
    for ($i = 0; $i -lt $raw.Length; $i++) {
        $dec[$i] = $raw[$i] -bxor $keyBytes[$i % $keyBytes.Length]
    }
    $ms = New-Object System.IO.MemoryStream(,$dec)
    $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $out = New-Object System.IO.MemoryStream
    $gz.CopyTo($out)
    $gz.Close()
    return [System.Text.Encoding]::UTF8.GetString($out.ToArray())
}

if (!(Test-Path $PakPath)) { throw "Pacote corrompido: core.pak ausente." }
$pak = Get-Content $PakPath -Raw -Encoding ASCII | ConvertFrom-Json

if ($Action -eq "Guard") {
    $code = Unprotect-Payload $pak.guard $PakKey
    $sb = [scriptblock]::Create($code)
    & $sb -BaseDir $ClientRoot
    exit
}

if ($Action -eq "ShowHwid") {
    $code = Unprotect-Payload $pak.install $PakKey
    $sb = [scriptblock]::Create($code)
    & $sb -ShowHwid
    exit
}

if ($Action -eq "RevealBinHwid") {
    $code = Unprotect-Payload $pak.install $PakKey
    $sb = [scriptblock]::Create($code)
    & $sb -RevealBinHwid -RootDir $ClientRoot
    exit
}

if ([string]::IsNullOrWhiteSpace($Key)) { throw "Informe a KEY." }
$code = Unprotect-Payload $pak.install $PakKey
$sb = [scriptblock]::Create($code)
& $sb -Key $Key -RootDir $ClientRoot -Hwid $Hwid -StartGuard
