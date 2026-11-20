#define AppVersion "1.2.0"
#ifdef TestRoot
  #define InstallDir TestRoot + "\app"
  #define StartupDir TestRoot + "\startup"
  #define ProgramsDir TestRoot + "\programs"
#else
  #define InstallDir "{localappdata}\WaterBuddy"
  #define StartupDir "{userstartup}"
  #define ProgramsDir "{userprograms}"
#endif
[Setup]
#ifdef TestRoot
AppId=WaterBuddy.InstallerTest
Uninstallable=yes
CreateUninstallRegKey=no
OutputBaseFilename=WaterBuddy-TestSetup
#else
AppId=WaterBuddy.Desktop
OutputBaseFilename=Water-Buddy-Setup
AppMutex=Local\ThanniWaterReminderV1

#endif
AppName=Water Buddy
AppVersion={#AppVersion}
AppPublisher=Water Buddy
AppPublisherURL=https://water-buddy-reminder.vercel.app/
DefaultDirName={#InstallDir}
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
MinVersion=10.0
WizardStyle=modern
WizardSizePercent=110
Compression=lzma2
SolidCompression=yes
OutputDir=..\artifacts
UninstallDisplayName=Water Buddy
CloseApplications=no
RestartApplications=no
SetupLogging=yes
InfoBeforeFile=setup-info.txt

[Files]
Source: "..\app\WaterReminder.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\Dashboard.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\Buddy.xaml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\Dashboard.xaml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\mascot-sprites.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\mascot-sad.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "setup-info.txt"; DestDir: "{app}"; DestName: "Readme.txt"; Flags: ignoreversion

[Icons]
Name: "{#StartupDir}\Thanni Water Reminder"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\WaterReminder.ps1"" -Background"; WorkingDir: "{app}"; Comment: "Water Buddy starts at Windows sign-in"; Flags: runminimized
Name: "{#ProgramsDir}\Water Buddy"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\WaterReminder.ps1"" -ShowDashboard"; WorkingDir: "{app}"; Flags: runminimized
Name: "{#ProgramsDir}\Uninstall Water Buddy"; Filename: "{uninstallexe}"; WorkingDir: "{app}"

[Run]
#ifndef TestRoot
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\WaterReminder.ps1"" -Preview"; WorkingDir: "{app}"; Flags: nowait runhidden skipifsilent
#endif

[Messages]
FinishedLabel=Water Buddy is installed.%n%nAutomatic startup is enabled for your Windows account. Your buddy will remind you every hour from 7 AM to 4 PM while your PC is awake.%n%nYou can close your browser. Your drink history stays on this PC.

[Code]
function InitializeUninstall(): Boolean;
begin
  Result := True;
#ifndef TestRoot
  if CheckForMutexes('Local\ThanniWaterReminderV1') then
  begin
    MsgBox('Water Buddy is running. Choose Exit from its tray menu, then run Uninstall again.', mbInformation, MB_OK);
    Result := False;
  end;
#endif
end;