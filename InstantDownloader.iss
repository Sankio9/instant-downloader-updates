#define MyAppName "Instant Downloader"
#define MyAppVersion "1.8.0-rc.7"
[Setup]
AppId={{C1F0AA1C-B0C0-4556-9BA2-31C4D185A8D1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Instant Downloader
AppPublisherURL=https://github.com/Sankio9/instant-downloader-updates
DefaultDirName={localappdata}\Programs\Instant Downloader
DefaultGroupName=Instant Downloader
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputDir=dist
OutputBaseFilename=Instant_Downloader_Setup_v1.8_RC7_x64
SetupLogging=yes
CloseApplications=yes
RestartApplications=no
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
[Files]
Source: "package\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "config.json,.auth\*,node_modules\*,_temp\*,_cache\*,_browsers\*,_jobs\*,*.part"
Source: "Bootstrap_Runtime.ps1"; DestDir: "{app}"; Flags: ignoreversion
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce
[Icons]
Name: "{autodesktop}\Instant Downloader"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Instant_Downloader.ps1"""; WorkingDir: "{app}"; Tasks: desktopicon
Name: "{group}\Instant Downloader"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Instant_Downloader.ps1"""; WorkingDir: "{app}"
[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Instant_Downloader.ps1"""; Description: "Launch Instant Downloader"; WorkingDir: "{app}"; Flags: postinstall nowait skipifsilent unchecked
[Code]
var DataPage: TInputDirWizardPage;
function IsSmokeMode(): Boolean;
begin
  Result := Pos('/CI_SKIP_RUNTIME=1', Uppercase(GetCmdTail)) > 0;
end;
procedure InitializeWizard();
begin
  DataPage := CreateInputDirPage(wpSelectDir,
    'Course and temporary storage',
    'Choose where Instant Downloader keeps its files',
    'The application, temporary/browser data and downloaded courses use separate folders. Choose any disk for each.', False, '');
  DataPage.Add('Temporary data (Node cache / Playwright browsers)');
  DataPage.Add('Downloaded courses and lesson index');
  DataPage.Values[0] := ExpandConstant('{localappdata}\InstantDownloader\TEMP');
  DataPage.Values[1] := ExpandConstant('{userdocs}\Instant Archive');
end;
function NormalizedPath(Value: string): string;
begin
  Result := Lowercase(RemoveBackslashUnlessRoot(Trim(Value)));
end;
function NextButtonClick(CurPageID: Integer): Boolean;
var App, Temp, Archive: string;
begin
  Result := True;
  if CurPageID = DataPage.ID then
  begin
    App := NormalizedPath(WizardDirValue());
    Temp := NormalizedPath(DataPage.Values[0]);
    Archive := NormalizedPath(DataPage.Values[1]);
    if (Temp = '') or (Archive = '') then
    begin
      MsgBox('Please select both folders.', mbError, MB_OK);
      Result := False; Exit;
    end;
    if (Temp = Archive) or (Temp = App) or (Archive = App) then
    begin
      MsgBox('Application, temporary and archive folders must be different.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;
procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer; Cmd, Temp, Archive, App: string;
begin
  if CurStep = ssPostInstall then
  begin
    App := ExpandConstant('{app}');
    Temp := DataPage.Values[0];
    Archive := DataPage.Values[1];
    WizardForm.StatusLabel.Caption := 'Configuring Node.js, Chromium and FFmpeg. This may take several minutes...';
    Cmd := '-NoProfile -ExecutionPolicy Bypass -File "' + App + '\Bootstrap_Runtime.ps1" -AppRoot "' + App + '" -TempRoot "' + Temp + '" -ArchiveRoot "' + Archive + '"';
    if IsSmokeMode() then Cmd := Cmd + ' -SmokeOnly';
    if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Cmd, App, SW_HIDE, ewWaitUntilTerminated, Code) then
      RaiseException('Could not launch runtime setup. See setup.log.');
    if Code <> 0 then
      RaiseException('Runtime setup failed (exit code ' + IntToStr(Code) + '). See ' + App + '\setup.log. You may safely rerun the installer.');
    WizardForm.StatusLabel.Caption := 'Instant Downloader is ready.';
  end;
end;