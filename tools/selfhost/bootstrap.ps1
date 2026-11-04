# Amorçage de la chaîne ALEX pure sous Windows x64 (pendant de bootstrap.sh, docs/SELFHOST.md), SANS compilateur
# C++ ni autre binaire que la graine :
#   0. graine versionnée : bootstrap/alexvm.exe (VM écrite en ALEX, exécutable Windows) et bootstrap/alexc.albc
#      (compilateur écrit en ALEX, bytecode, commun à Linux et à Windows) ;
#   1. la graine compile le compilateur en natif Windows                 -> build/alexc-stage1.exe
#   2. build/alexc-stage1.exe se recompile                                -> build/alexc.exe
#   3. build/alexc.exe construit la VM                                    -> build/alexvm.exe
#   4. contrôle : build/alexc.exe se recompile à l'identique (point fixe), la VM reconstruite est identique ;
#      stage1 == stage2 et VM == graine si la graine est à jour ;
#      (alexc.exe et alexvm.exe portent le logo d'ALEX : runtime/alex/windows/alex.ico)
#   5. le SDK (stdlib, runtime, templates, VM) est embarqué dans build/alexc.exe (alexc bundle) : copié seul
#      n'importe où, il compile et exécute sans dossier stdlib ni runtime à côté (commands.bundle).
#
#   powershell -ExecutionPolicy Bypass -File tools/selfhost/bootstrap.ps1          (make pure-windows)
#   powershell -ExecutionPolicy Bypass -File tools/selfhost/bootstrap.ps1 -Seed    régénère TOUTE la graine depuis
#       build/alexc.exe : alexc.albc, alexvm (Linux) et alexvm.exe (Windows), pour que les deux amorçages partent
#       du même compilateur.
param([switch]$Seed)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Repo = (Get-Location).Path
New-Item -ItemType Directory -Force build | Out-Null

# Exécute un outil de la chaîne (sortie standard écartée) ; arrêt au premier code de sortie non nul.
function Invoke-Step([string]$exe, [string[]]$argv) {
    & $exe @argv > $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ÉCHEC ($LASTEXITCODE) : $exe $($argv -join ' ')"
        exit 1
    }
}

function Test-Same([string]$a, [string]$b) {
    (Test-Path $a) -and (Test-Path $b) -and ((Get-FileHash $a).Hash -eq (Get-FileHash $b).Hash)
}

function Show-Size([string[]]$files) {
    foreach ($f in $files) { Write-Host ("     {0} : {1} octets" -f $f, (Get-Item $f).Length) }
}

if ($Seed) {
    if (-not (Test-Path build/alexc.exe)) { Write-Host "build/alexc.exe requis (amorçage préalable)"; exit 1 }
    New-Item -ItemType Directory -Force bootstrap | Out-Null
    Invoke-Step build/alexc.exe @('build', 'src/alexc.al', '-o', 'bootstrap/alexc.albc')
    Invoke-Step build/alexc.exe @('vm', '-o', 'bootstrap/alexvm')
    Invoke-Step build/alexc.exe @('vm', '--windows', '-o', 'bootstrap/alexvm.exe')
    Show-Size @('bootstrap/alexc.albc', 'bootstrap/alexvm', 'bootstrap/alexvm.exe')
    exit 0
}

if (-not ((Test-Path bootstrap/alexvm.exe) -and (Test-Path bootstrap/alexc.albc))) {
    Write-Host "graine absente : bootstrap/alexvm.exe, bootstrap/alexc.albc"
    exit 1
}
$t0 = Get-Date
$W = Join-Path ([IO.Path]::GetTempPath()) ("alex-bootstrap-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $W | Out-Null
try {
    # chemin de la chaîne d'outils embarqué dans les exécutables dynamiques (ALEX_EXE) : alexc, à tous les étages
    $env:ALEX_EXE = Join-Path $Repo 'build\alexc.exe'
    Write-Host "1/5 graine (VM ALEX + compilateur en bytecode) -> build/alexc-stage1.exe"
    $env:ALEX_QUIET_RUN = '1'
    Invoke-Step bootstrap/alexvm.exe @('bootstrap/alexc.albc', 'native', '--dynamic', '--windows', '--icon', 'runtime/alex/windows/alex.ico', 'src/alexc.al', '-o', 'build/alexc-stage1.exe')
    Remove-Item Env:ALEX_QUIET_RUN
    Write-Host "2/5 build/alexc-stage1.exe -> build/alexc.exe"
    # ALEX_EXE (embarqué dans les exécutables) doit désigner un fichier existant à chaque étage
    if (-not (Test-Path build/alexc.exe)) { Copy-Item build/alexc-stage1.exe build/alexc.exe }
    Invoke-Step build/alexc-stage1.exe @('native', '--dynamic', '--windows', '--icon', 'runtime/alex/windows/alex.ico', 'src/alexc.al', '-o', 'build/alexc.exe')
    Write-Host "3/5 build/alexc.exe -> build/alexvm.exe"
    Invoke-Step build/alexc.exe @('vm', '--windows', '-o', 'build/alexvm.exe')
    Write-Host "4/5 point fixe"
    Invoke-Step build/alexc.exe @('native', '--dynamic', '--windows', '--icon', 'runtime/alex/windows/alex.ico', 'src/alexc.al', '-o', "$W\alexc-stage3.exe")
    Invoke-Step build/alexc.exe @('vm', '--windows', '-o', "$W\alexvm2.exe")
    $ok = 0
    if (Test-Same build/alexc.exe "$W\alexc-stage3.exe") { Write-Host "OK   point fixe du compilateur : stage2 == stage3" }
    else { Write-Host "ÉCHEC point fixe du compilateur"; $ok = 1 }
    if ((Test-Same build/alexc-stage1.exe build/alexc.exe) -and (Test-Same build/alexvm.exe bootstrap/alexvm.exe)) {
        Write-Host "OK   graine à jour : stage1 == stage2, VM == graine"
    } else {
        Write-Host "     graine plus ancienne que les sources (stage1 != stage2 ou VM != graine) : tools/selfhost/bootstrap.ps1 -Seed"
    }
    if (Test-Same build/alexvm.exe "$W\alexvm2.exe") { Write-Host "OK   VM reconstruite identique" }
    else { Write-Host "ÉCHEC VM non reproductible"; $ok = 1 }
    # build/alexc.exe ne peut se réécrire pendant qu'il tourne (Windows verrouille l'exécutable) : stage1 empaquette.
    Write-Host "5/5 SDK embarqué -> build/alexc.exe (portable)"
    Invoke-Step build/alexc-stage1.exe @('bundle', '--exe', 'build/alexc.exe', '--vm', 'build/alexvm.exe', '-o', 'build/alexc.exe')
    Show-Size @('build/alexc.exe', 'build/alexvm.exe')
    Write-Host ("     {0} s, aucun compilateur C++ utilisé" -f [int]((Get-Date) - $t0).TotalSeconds)
    exit $ok
} finally {
    Remove-Item -Recurse -Force $W -ErrorAction SilentlyContinue
}
