; Installeur Windows d'ALEX (Inno Setup 6).  Produit  alex-<version>-windows-<arch>-setup.exe
;   iscc /DAppVersion=1.0.0-beta.7 /DStageDir=C:\...\stage /DOutDir=C:\...\dist alex.iss
; (en pratique : make installer-windows). Le dossier « stage » a la disposition de l'archive :
;   bin\alex.exe  lib\alex\{stdlib,templates}  share\...  alex.ico  LISEZMOI.txt
; ALEX Studio, l'IDE, a son propre installeur (projet séparé).
; Le dossier bin est ajouté AUTOMATIQUEMENT au PATH (utilisateur par défaut, système si « tous les utilisateurs »)
; et retiré à la désinstallation.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef NumericVersion
  #define NumericVersion "0.0.0.0"
#endif
#ifndef StageDir
  #define StageDir "stage"
#endif
#ifndef OutDir
  #define OutDir "."
#endif
#ifndef ArchTag
  #define ArchTag "x86_64"
#endif

#define ProductName "ALEX"
#define FilePrefix "alex"

[Setup]
AppId={{6C1D0E52-5A0B-4E64-9B7A-A1E4C0A1E7A1}
AppName={#ProductName}
AppVersion={#AppVersion}
AppVerName={#ProductName} {#AppVersion}
AppPublisher=ALEX
VersionInfoVersion={#NumericVersion}
VersionInfoProductName=ALEX
VersionInfoDescription=Installation du langage ALEX
DefaultDirName={autopf}\{#ProductName}
DefaultGroupName={#ProductName}
UninstallDisplayIcon={app}\alex.ico
UninstallDisplayName={#ProductName} {#AppVersion}
SetupIconFile={#StageDir}\alex.ico
OutputDir={#OutDir}
OutputBaseFilename={#FilePrefix}-{#AppVersion}-windows-{#ArchTag}-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Utilisateur courant par défaut (pas d'UAC) ; la boîte de dialogue propose « tous les utilisateurs ».
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
ChangesEnvironment=yes
ChangesAssociations=yes
DisableProgramGroupPage=yes
#if ArchTag == "x86_64"
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
CloseApplications=yes
RestartApplications=no
ShowLanguageDialog=auto

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
french.AddToPath=Ajouter ALEX au PATH (commande « alex » disponible dans tous les terminaux)
english.AddToPath=Add ALEX to the PATH (the "alex" command is available in every terminal)
french.AssocAl=Associer les fichiers .al à ALEX (exécuter)
english.AssocAl=Associate .al files with ALEX (run)
french.OpenTerminal=Invite de commandes ALEX
english.OpenTerminal=ALEX command prompt
french.Docs=Documentation ALEX
english.Docs=ALEX documentation
french.PathNote=Ouvrez un nouveau terminal pour que la commande « alex » soit reconnue.
english.PathNote=Open a new terminal for the "alex" command to be recognised.

[Tasks]
Name: "addtopath"; Description: "{cm:AddToPath}"; GroupDescription: "PATH :"
Name: "assoc"; Description: "{cm:AssocAl}"; GroupDescription: "Fichiers :"; Flags: unchecked

[Files]
; Remplacement complet à la mise à jour : l'ancienne bibliothèque standard est supprimée avant la copie.
Source: "{#StageDir}\bin\*"; DestDir: "{app}\bin"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StageDir}\lib\*"; DestDir: "{app}\lib"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StageDir}\share\*"; DestDir: "{app}\share"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StageDir}\alex.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageDir}\LISEZMOI.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageDir}\VERSION.txt"; DestDir: "{app}"; Flags: ignoreversion

[InstallDelete]
Type: filesandordirs; Name: "{app}\lib"
Type: filesandordirs; Name: "{app}\share"

[Icons]
Name: "{autoprograms}\{#ProductName}\{cm:OpenTerminal}"; Filename: "{cmd}"; Parameters: "/k """"{app}\bin\alexc.exe"" --version"""; IconFilename: "{app}\alex.ico"; WorkingDir: "{userdocs}"
Name: "{autoprograms}\{#ProductName}\{cm:Docs}"; Filename: "{app}\share\doc\alex"
Name: "{autoprograms}\{#ProductName}\{cm:UninstallProgram,ALEX}"; Filename: "{uninstallexe}"

[Registry]
Root: HKA; Subkey: "Software\Classes\.al"; ValueType: string; ValueData: "ALEX.Source"; Flags: uninsdeletevalue uninsdeletekeyifempty; Tasks: assoc
Root: HKA; Subkey: "Software\Classes\ALEX.Source"; ValueType: string; ValueData: "Programme ALEX"; Flags: uninsdeletekey; Tasks: assoc
Root: HKA; Subkey: "Software\Classes\ALEX.Source\DefaultIcon"; ValueType: string; ValueData: "{app}\alex.ico"; Tasks: assoc
Root: HKA; Subkey: "Software\Classes\ALEX.Source\shell"; ValueType: string; ValueData: "run"; Tasks: assoc
Root: HKA; Subkey: "Software\Classes\ALEX.Source\shell\run"; ValueType: string; ValueData: "Exécuter avec ALEX"; Tasks: assoc
Root: HKA; Subkey: "Software\Classes\ALEX.Source\shell\run\command"; ValueType: string; ValueData: """{cmd}"" /k """"{app}\bin\alexc.exe"" run ""%1"""""; Tasks: assoc

[Code]
const
  UserEnvKey = 'Environment';
  MachineEnvKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

function EnvRoot: Integer;
begin
  if IsAdminInstallMode then Result := HKEY_LOCAL_MACHINE else Result := HKEY_CURRENT_USER;
end;

function EnvSubKey: String;
begin
  if IsAdminInstallMode then Result := MachineEnvKey else Result := UserEnvKey;
end;

// Normalise un élément du PATH pour la comparaison (minuscules, sans guillemets ni « \ » final).
function Norm(S: String): String;
begin
  S := Trim(S);
  if (Length(S) >= 2) and (S[1] = '"') and (S[Length(S)] = '"') then S := Copy(S, 2, Length(S) - 2);
  S := Lowercase(ExpandConstant(S));
  while (Length(S) > 3) and ((S[Length(S)] = '\') or (S[Length(S)] = '/')) do Delete(S, Length(S), 1);
  Result := S;
end;

// Éléments du PATH (valeur brute, %VAR% non développés) ; Remove=True : retire Dir et renvoie le nouveau PATH.
function PathHas(Path, Dir: String): Boolean;
var
  P, Item: String;
  I: Integer;
begin
  Result := False;
  P := Path;
  while P <> '' do
  begin
    I := Pos(';', P);
    if I = 0 then begin Item := P; P := ''; end
    else begin Item := Copy(P, 1, I - 1); P := Copy(P, I + 1, Length(P)); end;
    if (Trim(Item) <> '') and (Norm(Item) = Norm(Dir)) then begin Result := True; Exit; end;
  end;
end;

function PathWithout(Path, Dir: String): String;
var
  P, Item: String;
  I: Integer;
begin
  Result := '';
  P := Path;
  while P <> '' do
  begin
    I := Pos(';', P);
    if I = 0 then begin Item := P; P := ''; end
    else begin Item := Copy(P, 1, I - 1); P := Copy(P, I + 1, Length(P)); end;
    if (Trim(Item) <> '') and (Norm(Item) <> Norm(Dir)) then
    begin
      if Result <> '' then Result := Result + ';';
      Result := Result + Item;
    end;
  end;
end;

procedure AddToPath(Dir: String);
var
  Path: String;
begin
  if not RegQueryStringValue(EnvRoot, EnvSubKey, 'Path', Path) then Path := '';
  if PathHas(Path, Dir) then Exit;
  if Path <> '' then Path := Dir + ';' + Path else Path := Dir;   // en tête : cet alex.exe est prioritaire
  RegWriteExpandStringValue(EnvRoot, EnvSubKey, 'Path', Path);
end;

procedure RemoveFromPath(Dir: String);
var
  Path: String;
begin
  if not RegQueryStringValue(EnvRoot, EnvSubKey, 'Path', Path) then Exit;
  if PathHas(Path, Dir) then
    RegWriteExpandStringValue(EnvRoot, EnvSubKey, 'Path', PathWithout(Path, Dir));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('addtopath') then
    AddToPath(ExpandConstant('{app}\bin'));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // Dans tous les cas : si ALEX avait été ajouté au PATH, l'entrée est retirée (sans effet sinon).
  if CurUninstallStep = usPostUninstall then
    RemoveFromPath(ExpandConstant('{app}\bin'));
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
    if WizardIsTaskSelected('addtopath') then
      WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10#13#10 + CustomMessage('PathNote');
end;
