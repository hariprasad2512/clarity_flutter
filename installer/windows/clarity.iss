; Clarity for Windows — Inno Setup wizard script.
;
; Built on GitHub Actions (windows-latest):
;   flutter build windows --release
;   iscc installer/windows/clarity.iss /DAppVersion=1.1.3
;
; Produces a classic setup wizard: Welcome > License > Directory >
; Start Menu > Install > Launch checkbox > Finish, plus uninstaller.
;
; Source layout expected (Flutter default):
;   build\windows\x64\runner\Release\Clarity.exe + flutter dlls + data\

#define MyAppName "Clarity"
#define MyAppExeName "Clarity.exe"
#ifndef AppVersion
  #define AppVersion "1.1.3"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
#define MyAppPublisher "Clarity"
#define MyAppURL "https://github.com/anomalyco/clarity_flutter"

[Setup]
AppId={{8E2B4B6A-1C3A-4E5F-9A7B-A1B2C3D4E5F6}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppVerName={#MyAppName} {#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
LicenseFile=..\..\LICENSE
; Wizard branding: green check mark.
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutputDir}
OutputBaseFilename=Clarity-{#AppVersion}-windows-setup
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter release bundle: exe + flutter_windows.dll + plugins + data\flutter_assets.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; OAuth return path: com.harry.Clarity://oauth-callback (mirrors the macOS
; Info.plist CFBundleURLTypes entry). Without this the browser sign-in flow
; can't route back to the app. HKCU = per-user, no elevation needed.
Root: HKCU; Subkey: "Software\Classes\com.harry.Clarity"; ValueType: string; ValueName: ""; ValueData: "URL:Clarity OAuth"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\com.harry.Clarity"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\com.harry.Clarity\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCU; Subkey: "Software\Classes\com.harry.Clarity\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
