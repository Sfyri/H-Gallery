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
