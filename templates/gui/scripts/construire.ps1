# Build {{nom}} for Windows distribution: dist\{{nom}}.exe (GUI application, icon assets\icone.ico).
#   powershell -ExecutionPolicy Bypass -File scripts\construire.ps1 [-Alexc path\to\alexc.exe]
param([string]$Alexc = "")
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($Alexc -eq "") {
    foreach ($name in 'alexc', 'alex') {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if ($c) { $Alexc = $c.Source; break }
    }
}
if ($Alexc -eq "") { Write-Error "alexc not found: add it to PATH or pass -Alexc path\to\alexc.exe"; exit 1 }
New-Item -ItemType Directory -Force (Join-Path $root 'dist') | Out-Null
& $Alexc build --native --windows --gui --icon (Join-Path $root 'assets\icone.ico') (Join-Path $root 'src\main.al') -o (Join-Path $root 'dist\{{nom}}.exe')
exit $LASTEXITCODE
