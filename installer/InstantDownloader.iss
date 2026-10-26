#define MyAppName "Instant Downloader"
#define MyAppVersion "1.8.0-rc.7"
[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Instant Downloader
AppPublisherURL=https://github.com/Sankio9/instant-downloader-updates
VersionInfoVersion=1.8.0.7
VersionInfoDescription=Instant Downloader Windows installer - PC2 validation build
DefaultDirName={localappdata}\InstantDownloaderInstallerCache
CreateAppDir=no
Uninstallable=no
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
WizardStyle=modern
OutputDir=output
OutputBaseFilename=Instant_Downloader_Setup_v1.8_RC7_PC2
Compression=lzma2
SolidCompression=yes
ShowLanguageDialog=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\payload\*"; DestDir: "{tmp}\InstantDownloaderPayload"; Flags: ignoreversion

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -ExecutionPolicy Bypass -File ""{tmp}\InstantDownloaderPayload\Install_Instant_Downloader.ps1"""; Flags: waituntilterminated runasoriginaluser skipifsilent; Description: "Install Instant Downloader and dependencies"; StatusMsg: "Opening Instant Downloader setup..."
