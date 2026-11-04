<#
.SYNOPSIS
    Installe (ou désinstalle) ALEX sous Windows et l'inscrit dans le PATH.

.DESCRIPTION
    À lancer depuis le dossier décompressé de l'archive (bin\alex.exe, lib\alex\...), ou via install.cmd.
      - copie ALEX dans « %LOCALAPPDATA%\Programs\ALEX » (utilisateur) ou « %ProgramFiles%\ALEX » (-AllUsers) ;
      - ajoute <dossier>\bin au PATH (utilisateur ou système), sans doublon, et prévient les applications ouvertes ;
      - crée les raccourcis du menu Démarrer, l'association des fichiers .al (option) ;
      - inscrit ALEX dans « Applications installées » (désinstallation propre, mise à jour en place).

.PARAMETER AllUsers     Installe pour tous les utilisateurs (droits d'administrateur : l'élévation est demandée).
.PARAMETER InstallDir   Dossier d'installation personnalisé.
.PARAMETER NoPath       N'ajoute pas ALEX au PATH.
.PARAMETER Associate    Associe les fichiers .al à ALEX (exécuter). ALEX Studio, l'IDE, a son propre installeur.
.PARAMETER NoShortcuts  Ne crée pas de raccourcis dans le menu Démarrer.
.PARAMETER Uninstall    Désinstalle ALEX (retire aussi l'entrée du PATH).
.PARAMETER Quiet        Aucune interaction ni pause finale.
#>
[CmdletBinding()]
param(
    [switch]$AllUsers,
    [string]$InstallDir,
    [switch]$NoPath,
    [switch]$Associate,
    [switch]$NoShortcuts,
    [switch]$Uninstall,
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$AppKey = 'ALEX'
$AppName = 'ALEX'

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Relance le script avec élévation (UAC) en conservant les paramètres.
function Restart-Elevated {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) { if ($kv.Value.IsPresent) { $argList += "-$($kv.Key)" } }
        else { $argList += "-$($kv.Key)"; $argList += ('"{0}"' -f $kv.Value) }
    }
    $proc = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $argList -Verb RunAs -Wait -PassThru
    exit $proc.ExitCode
}

# --- PATH : lecture/écriture de la valeur BRUTE (REG_EXPAND_SZ conservé, %VAR% non développés) -------------------
function Get-EnvKey([bool]$machine, [bool]$write) {
    if ($machine) {
        return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $write)
    }
    return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $write)
}
function Get-RawPath([bool]$machine) {
    $k = Get-EnvKey $machine $false
    try {
        $v = $k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $v) { return '' }
        return [string]$v
    } finally { $k.Close() }
}
function Set-RawPath([bool]$machine, [string]$value) {
    $k = Get-EnvKey $machine $true
    try { $k.SetValue('Path', $value, [Microsoft.Win32.RegistryValueKind]::ExpandString) } finally { $k.Close() }
}
function Normalize-Dir([string]$d) {
    return ([Environment]::ExpandEnvironmentVariables($d.Trim().Trim('"'))).TrimEnd('\', '/').ToLowerInvariant()
}
function Add-ToPath([bool]$machine, [string]$dir) {
    $raw = Get-RawPath $machine
    $want = Normalize-Dir $dir
    $parts = @($raw -split ';' | Where-Object { $_.Trim() -ne '' })
    if ($parts | Where-Object { (Normalize-Dir $_) -eq $want }) { return $false }
    Set-RawPath $machine ((@($dir) + $parts) -join ';')   # en tête : ce alex.exe est prioritaire
    return $true
}
function Remove-FromPath([bool]$machine, [string]$dir) {
    $raw = Get-RawPath $machine
    $want = Normalize-Dir $dir
    $parts = @($raw -split ';' | Where-Object { $_.Trim() -ne '' })
    $kept = @($parts | Where-Object { (Normalize-Dir $_) -ne $want })
    if ($kept.Count -eq $parts.Count) { return $false }
    Set-RawPath $machine ($kept -join ';')
    return $true
}
# Prévient l'Explorateur et les nouveaux terminaux que l'environnement a changé (WM_SETTINGCHANGE).
function Send-EnvChange {
    try {
        if (-not ('Alex.NativeMethods' -as [type])) {
            Add-Type -Namespace Alex -Name NativeMethods -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true, CharSet=System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
        }
        $r = [UIntPtr]::Zero
        [void][Alex.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$r)
    } catch { Write-Verbose "diffusion WM_SETTINGCHANGE impossible : $_" }
}

function New-Shortcut([string]$path, [string]$target, [string]$arguments, [string]$icon, [string]$desc, [string]$workDir) {
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($path)
    $lnk.TargetPath = $target
    $lnk.Arguments = $arguments
    $lnk.IconLocation = $icon
    $lnk.Description = $desc
    if ($workDir) { $lnk.WorkingDirectory = $workDir }
    $lnk.Save()
}

function Wait-Key {
    if (-not $Quiet -and $Host.Name -eq 'ConsoleHost') {
        Write-Host ''
        Write-Host 'Appuyez sur une touche pour fermer...'
        [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
}

try {
    if ($AllUsers -and -not (Test-Admin)) { Restart-Elevated }
    $machine = [bool]$AllUsers
    $hive = if ($machine) { 'HKLM:' } else { 'HKCU:' }
    $uninstKey = "$hive\Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppKey"
    $classes = "$hive\Software\Classes"
    $startMenu = if ($machine) { Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\$AppName" }
                 else { Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$AppName" }

    # ------------------------------------------------------------------ désinstallation
    if ($Uninstall) {
        $dir = $InstallDir
        if (-not $dir -and (Test-Path $uninstKey)) { $dir = (Get-ItemProperty $uninstKey).InstallLocation }
        if (-not $dir) { $dir = if ($machine) { Join-Path $env:ProgramFiles $AppName } else { Join-Path $env:LOCALAPPDATA "Programs\$AppName" } }
        Write-Host "Désinstallation de $AppName ($dir)"
        $changed = Remove-FromPath $machine (Join-Path $dir 'bin')
        if ($changed) { Write-Host '  PATH : entrée retirée' }
        if (Test-Path $startMenu) { Remove-Item $startMenu -Recurse -Force }
        foreach ($k in @("$classes\.al", "$classes\ALEX.Source")) { if (Test-Path $k) { Remove-Item $k -Recurse -Force } }
        if (Test-Path $uninstKey) { Remove-Item $uninstKey -Recurse -Force }
        Send-EnvChange
        # Le script en cours d'exécution se trouve dans le dossier à supprimer : suppression différée.
        if (Test-Path $dir) {
            $cmd = "ping 127.0.0.1 -n 3 >nul & rmdir /s /q `"$dir`""
            Start-Process -FilePath "$env:ComSpec" -ArgumentList "/c $cmd" -WindowStyle Hidden
        }
        Write-Host "$AppName a été désinstallé. Les terminaux déjà ouverts conservent l'ancien PATH."
        Wait-Key
        exit 0
    }

    # ------------------------------------------------------------------ installation
    $src = Split-Path -Parent $PSCommandPath
    $exe = Join-Path $src 'bin\alex.exe'
    if (-not (Test-Path $exe)) { throw "bin\alex.exe introuvable à côté de install.ps1 ($src). Décompressez toute l'archive avant d'installer." }
    if (-not $InstallDir) {
        $InstallDir = if ($machine) { Join-Path $env:ProgramFiles $AppName } else { Join-Path $env:LOCALAPPDATA "Programs\$AppName" }
    }
    $InstallDir = [IO.Path]::GetFullPath($InstallDir)
    $binDir = Join-Path $InstallDir 'bin'
    $version = (Get-Content (Join-Path $src 'VERSION.txt') -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $version) { $version = (& $exe version --short 2>$null) }
    if (-not $version) { $version = 'inconnue' }

    Write-Host "Installation de $AppName $version"
    Write-Host "  dossier : $InstallDir ($(if ($machine) { 'tous les utilisateurs' } else { 'utilisateur courant' }))"

    # Garde-fous : jamais d'installation sur la racine d'un lecteur ni sur le dossier source lui-même.
    if ($InstallDir.TrimEnd('\') -eq [IO.Path]::GetPathRoot($InstallDir).TrimEnd('\')) { throw "dossier d'installation refusé : $InstallDir" }
    if ($InstallDir.TrimEnd('\') -ieq $src.TrimEnd('\')) { throw "le dossier d'installation ne peut pas être le dossier de l'archive" }

    # Mise à jour en place : l'ancien contenu (bibliothèque, caches) est remplacé en entier.
    foreach ($sub in @('bin', 'lib', 'share')) {
        $p = Join-Path $InstallDir $sub
        if (Test-Path $p) { Remove-Item $p -Recurse -Force }
    }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    foreach ($item in @('bin', 'lib', 'share', 'alex.ico', 'LISEZMOI.txt', 'VERSION.txt')) {
        $s = Join-Path $src $item
        if (Test-Path $s) { Copy-Item $s -Destination $InstallDir -Recurse -Force }
    }
    # Le désinstalleur : copie de ce script dans le dossier d'installation.
    $setupDir = Join-Path $InstallDir 'setup'
    New-Item -ItemType Directory -Force -Path $setupDir | Out-Null
    Copy-Item $PSCommandPath (Join-Path $setupDir 'install.ps1') -Force

    # PATH
    if (-not $NoPath) {
        if (Add-ToPath $machine $binDir) { Write-Host "  PATH : $binDir ajouté ($(if ($machine) { 'système' } else { 'utilisateur' }))" }
        else { Write-Host '  PATH : déjà présent' }
        $env:Path = "$binDir;$env:Path"        # session courante
        Send-EnvChange
    }

    # Raccourcis
    $icon = Join-Path $InstallDir 'alex.ico'
    if (-not $NoShortcuts) {
        New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
        $alexExe = Join-Path $binDir 'alex.exe'
        New-Shortcut (Join-Path $startMenu 'Invite de commandes ALEX.lnk') $env:ComSpec "/k `"`"$alexExe`" --version`"" $icon 'Terminal avec ALEX' $env:USERPROFILE
        $doc = Join-Path $InstallDir 'share\doc\alex'
        if (Test-Path $doc) { New-Shortcut (Join-Path $startMenu 'Documentation ALEX.lnk') $doc '' $icon 'Guides et référence' $null }
        New-Shortcut (Join-Path $startMenu 'Désinstaller ALEX.lnk') (Get-Process -Id $PID).Path `
            "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $setupDir 'install.ps1')`" -Uninstall$(if ($machine) { ' -AllUsers' })" $icon "Désinstalle $AppName" $null
    }

    # Association .al
    if ($Associate) {
 $alexExe = Join-Path $binDir 'alex.exe'
        New-Item -Force -Path "$classes\.al" -Value 'ALEX.Source' | Out-Null
        New-Item -Force -Path "$classes\ALEX.Source" -Value 'Programme ALEX' | Out-Null
        New-Item -Force -Path "$classes\ALEX.Source\DefaultIcon" -Value "`"$icon`"" | Out-Null
        New-Item -Force -Path "$classes\ALEX.Source\shell" -Value 'run' | Out-Null
        New-Item -Force -Path "$classes\ALEX.Source\shell\run\command" -Value "`"$env:ComSpec`" /k `"`"$alexExe`" run `"%1`"`"" | Out-Null
        New-Item -Force -Path "$classes\ALEX.Source\shell\run" -Value 'Exécuter avec ALEX' | Out-Null
        Write-Host '  association : .al'
    }

    # Applications installées
    New-Item -Force -Path $uninstKey | Out-Null
    $psExe = (Get-Process -Id $PID).Path
    $uninstCmd = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $setupDir 'install.ps1')`" -Uninstall$(if ($machine) { ' -AllUsers' })"
    $props = @{
        DisplayName = "$AppName $version"; DisplayVersion = "$version"; Publisher = 'ALEX'
        InstallLocation = $InstallDir; DisplayIcon = $icon
        UninstallString = $uninstCmd; QuietUninstallString = "$uninstCmd -Quiet"
        URLInfoAbout = 'https://github.com/'; InstallDate = (Get-Date -Format 'yyyyMMdd')
    }
    foreach ($kv in $props.GetEnumerator()) { New-ItemProperty -Path $uninstKey -Name $kv.Key -Value $kv.Value -PropertyType String -Force | Out-Null }
    New-ItemProperty -Path $uninstKey -Name 'NoModify' -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $uninstKey -Name 'NoRepair' -Value 1 -PropertyType DWord -Force | Out-Null
    $kb = [int]((Get-ChildItem $InstallDir -Recurse -File | Measure-Object Length -Sum).Sum / 1KB)
    New-ItemProperty -Path $uninstKey -Name 'EstimatedSize' -Value $kb -PropertyType DWord -Force | Out-Null

    Write-Host ''
    Write-Host "$AppName $version est installé."
    if (-not $NoPath) {
        Write-Host 'Ouvrez un NOUVEAU terminal puis tapez :  alexc --version'
    }
    Wait-Key
    exit 0
} catch {
    Write-Host "Erreur : $($_.Exception.Message)" -ForegroundColor Red
    Wait-Key
    exit 1
}
