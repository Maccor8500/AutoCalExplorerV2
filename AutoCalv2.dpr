program AutoCalv2;



{$R *.dres}

uses
  Vcl.Forms,
  CommonsU in '..\..\..\..\Delphi\MacCommonCode\Julius\CommonsU.pas',
  AutoCalProtocolU in '..\..\..\..\Delphi\MacCommonCode\Julius\AutoCalProtocolU.pas',
  AutoCalBoardU in 'AutoCalBoardU.pas',
  SystemInfoImportU in 'SystemInfoImportU.pas',
  AvrFlasherU in 'AvrFlasherU.pas',
  ConfettiU in 'ConfettiU.pas',
  MaccorTesterU in 'MaccorTesterU.pas',
  MeterBenchU in 'MeterBenchU.pas',
  AppConfigU in 'AppConfigU.pas',
  OhmLabsU in 'OhmLabsU.pas',
  OhmLabsFrameU in 'OhmLabsFrameU.pas' {OhmLabsFrame: TFrame},
  FlukeMetersU in 'FlukeMetersU.pas',
  CalDataU in 'CalDataU.pas',
  MeterSheetU in 'MeterSheetU.pas',
  CertificateU in 'CertificateU.pas',
  RecordSummaryU in 'RecordSummaryU.pas',
  CertificatePdfU in 'CertificatePdfU.pas',
  CertificateFrameU in 'CertificateFrameU.pas' {CertificateFrame: TFrame},
  CertViewFormU in 'CertViewFormU.pas' {CertViewForm},
  FlukeFrameU in 'FlukeFrameU.pas' {FlukeFrame: TFrame},
  ControlsFrameU in 'ControlsFrameU.pas' {ControlsFrame: TFrame},
  CalibrationFrameU in 'CalibrationFrameU.pas' {CalibrationFrame: TFrame},
  FirmwareFrameU in 'FirmwareFrameU.pas' {FirmwareFrame: TFrame},
  RecordFrameU in 'RecordFrameU.pas' {RecordFrame: TFrame},
  MainU in 'MainU.pas' {MainForm},
  Vcl.Themes,
  Vcl.Styles,
  ShuntCfgFormU in 'ShuntCfgFormU.pas' {ShuntCfgForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
