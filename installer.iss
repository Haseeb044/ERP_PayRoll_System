[Setup]
AppName=Rider Payroll ERP
AppVersion=1.0.0
DefaultDirName={commonpf}\RiderPayrollERP
DefaultGroupName=Rider Payroll ERP
OutputDir=E:\Final YearProject\rider_payroll_erp\dist
OutputBaseFilename=RiderPayrollERP_Setup_v1.0.0
Compression=lzma
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "E:\Final YearProject\rider_payroll_erp\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Rider Payroll ERP"; Filename: "{app}\rider_payroll_erp.exe"
Name: "{commondesktop}\Rider Payroll ERP"; Filename: "{app}\rider_payroll_erp.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\rider_payroll_erp.exe"; Description: "Launch Rider Payroll ERP"; Flags: nowait postinstall skipifsilent