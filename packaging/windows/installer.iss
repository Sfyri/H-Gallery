#preproc ispp
#include "version.iss"

#define MyAppName "H-Gallery"
#define MyAppPublisher "Sfyri"
#define MyAppURL "https://github.com/Sfyri/H-Gallery"
#define MyAppExeName "H-Gallery.exe"
#ifndef SourceDir
  #define SourceDir "..\..\dist\windows\H-Gallery"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist\installer"
#endif

[Setup]
AppId={{79548A0B-920B-4409-8F08-7432B1508059}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
VersionInfoVersion={#MyAppVersionInfo}
DefaultDirName={localappdata}\Programs\H-Gallery
DefaultGroupName=H-Gallery
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=H-Gallery-Setup-{#MyAppVersion}
SetupIconFile=assets\h-gallery.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ChangesAssociations=no
ChangesEnvironment=no

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Crea un collegamento sul desktop"; GroupDescription: "Collegamenti aggiuntivi:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "configure-firewall.ps1"; DestDir: "{app}\tools"; DestName: "configure-firewall.ps1"; Flags: ignoreversion

[Icons]
Name: "{group}\H-Gallery"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Configura gallerie"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--configure"
Name: "{group}\Arresta H-Gallery"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--stop"
Name: "{autodesktop}\H-Gallery"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Avvia H-Gallery"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\{#MyAppExeName}"; Parameters: "--stop"; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "StopHGallery"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  ExistingExe: String;
begin
  Result := '';
  ExistingExe := ExpandConstant('{app}\{#MyAppExeName}');
  if FileExists(ExistingExe) then
    Exec(ExistingExe, '--stop', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function RunFirewallAction(Action: String): Boolean;
var
  ResultCode: Integer;
  PowerShellPath: String;
  ScriptPath: String;
  Params: String;
begin
  Result := False;
  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  ScriptPath := ExpandConstant('{app}\tools\configure-firewall.ps1');

  if not FileExists(PowerShellPath) then
  begin
    Log('M8.9: Windows PowerShell non trovato: ' + PowerShellPath);
    Exit;
  end;

  if not FileExists(ScriptPath) then
  begin
    Log('M8.9: helper firewall non trovato: ' + ScriptPath);
    Exit;
  end;

  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ScriptPath + '" -Action ' + Action;

  Log('M8.9: esecuzione helper firewall, azione=' + Action);
  if not ShellExec(
    'runas',
    PowerShellPath,
    Params,
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
  begin
    Log('M8.9: avvio helper firewall non riuscito. Codice=' + IntToStr(ResultCode));
    Exit;
  end;

  if ResultCode <> 0 then
  begin
    Log('M8.9: helper firewall terminato con codice=' + IntToStr(ResultCode));
    Exit;
  end;

  Log('M8.9: helper firewall completato correttamente.');
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if not RunFirewallAction('Install') then
    begin
      if not WizardSilent then
        MsgBox(
          'H-Gallery è stato installato, ma Windows Firewall non è stato configurato.' + #13#10 + #13#10 +
          'La sincronizzazione Android potrebbe non riuscire finché non vengono autorizzate le porte locali di H-Gallery.' + #13#10 +
          'Puoi reinstallare H-Gallery in seguito per riprovare la configurazione.',
          mbInformation,
          MB_OK
        );
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    if not RunFirewallAction('Remove') then
    begin
      if not UninstallSilent then
        MsgBox(
          'Non è stato possibile rimuovere automaticamente le regole Windows Firewall di H-Gallery.' + #13#10 +
          'La disinstallazione continuerà normalmente.',
          mbInformation,
          MB_OK
        );
    end;
  end;
end;
