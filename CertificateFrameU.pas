unit CertificateFrameU;

{
  Configurations > Certificate: what the certificate needs that neither the data file nor the other sheets
  hold (CertificateU.TCertInputs): the owner, the instrument, the procedure, the technician, remarks, the room's
  temperature and humidity, the previous calibration's date, the notes, the standards used besides the meters
  (the meters are shown above them in grey, as their own sheets have them),
  the comments and the form's footer. The measured values, the calibration date, the certificate number, the
  due date and the meters' lines are not typed: they are worked out.

  The sheet is a draft: Save checks it and writes the "certificate" section of the configuration file, Reload
  goes back to what is saved, Defaults shows the workbook's text (not saved until Save).

  Preview and Export PDF first save the sheet and bring the data file's certificate up to date with it
  (CertificateU.TCertificateData.Refresh), then print that certificate (CertificatePdfU.GenerateCertificate):
  Preview into a temporary file shown by CertViewFormU, which has Print; Export PDF into a file of your choice.
  UI only.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Math, System.IOUtils, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Grids, Vcl.ComCtrls, AppConfigU,
  CertificateU, FlukeMetersU;

type
  TCertificateFrame = class(TFrame)
    OwnerLbl: TLabel;
    OwnerNameLbl: TLabel;
    OwnerNameEdit: TEdit;
    OwnerAddr1Lbl: TLabel;
    OwnerAddr1Edit: TEdit;
    OwnerAddr2Lbl: TLabel;
    OwnerAddr2Edit: TEdit;
    InstrumentLbl: TLabel;
    MfrLbl: TLabel;
    MfrEdit: TEdit;
    DescLbl: TLabel;
    DescEdit: TEdit;
    ModelLbl: TLabel;
    ModelEdit: TEdit;
    SerialLbl: TLabel;
    SerialEdit: TEdit;
    InfoTitleLbl: TLabel;
    Proc1Lbl: TLabel;
    Proc1Edit: TEdit;
    Proc2Lbl: TLabel;
    Proc2Edit: TEdit;
    TechLbl: TLabel;
    TechEdit: TEdit;
    RemarksLbl: TLabel;
    RemarksEdit: TEdit;
    CondLbl: TLabel;
    TempLbl: TLabel;
    TempEdit: TEdit;
    HumLbl: TLabel;
    HumEdit: TEdit;
    PrevLbl: TLabel;
    PrevPick: TDateTimePicker;
    FormNoLbl: TLabel;
    FormNoEdit: TEdit;
    RevLbl: TLabel;
    RevEdit: TEdit;
    RevDateLbl: TLabel;
    RevDateEdit: TEdit;
    NotesLbl: TLabel;
    NotesEdit: TEdit;
    StdLbl: TLabel;
    StdGrid: TStringGrid;
    CommentsLbl: TLabel;
    CommentsMemo: TMemo;
    InfoLbl: TLabel;
    DefaultsBtn: TButton;
    ReloadBtn: TButton;
    PreviewBtn: TButton;
    ExportBtn: TButton;
    SaveBtn: TButton;
    procedure StdGridDrawCell(Sender: TObject; ACol, ARow: LongInt; Rect: TRect; State: TGridDrawState);
    procedure StdGridSelectCell(Sender: TObject; ACol, ARow: LongInt; var CanSelect: Boolean);
    procedure DefaultsBtnClick(Sender: TObject);
    procedure ReloadBtnClick(Sender: TObject);
    procedure SaveBtnClick(Sender: TObject);
    procedure PreviewBtnClick(Sender: TObject);
    procedure ExportBtnClick(Sender: TObject);

  private
    { the comment for the box as the file has it: not a field of the sheet, carried from load to save }
    RecordComments: String;
    {
      the grid's first rows are the meters of the Fluke sheets (each unit with a serial number), shown so that
      all the standards are in one place: grey, not selectable, not read back. They are edited on their sheets
    }
    MeterRows: Integer;

    procedure ShowInputs(const I: TCertInputs);
    { the sheet into I; False, with the reason shown, when a cell does not read }
    function ReadInputs(out I: TCertInputs): Boolean;
    procedure Reload;
    { saves the sheet, then brings the data file's certificate up to date; False, with the reason shown }
    function Prepare(out Cert: TCertificate): Boolean;
    procedure ShowGaps(const Cert: TCertificate; const Done: String);
    procedure Say(const Text: String; const Bad: Boolean = False);

  public
    constructor Create(AOwner: TComponent); override;
    { the configuration file changed behind the sheet (a Read of the board saved the standards): what is saved, again }
    procedure ReloadSheet;
  end;

implementation

{$R *.dfm}

uses
  CertificatePdfU, CertViewFormU;

const
  { columns }
  C_SERIAL = 0;
  C_MFR = 1;
  C_MODEL = 2;
  C_DUE = 3;
  { rows the grid always offers; blank ones are no standard }
  STD_ROWS = 5;

{ a certificate number as a file name }
function FileNameOf(const Number: String): String;
begin
  Result := Trim(Number);
  for var Ch in TPath.GetInvalidFileNameChars do Result := Result.Replace(Ch, '_');
  if Result = '' then Result := 'certificate';
end;

constructor TCertificateFrame.Create(AOwner: TComponent);
begin
  inherited;
  StdGrid.Cells[C_SERIAL, 0] := 'Serial #';
  StdGrid.Cells[C_MFR, 0] := 'Mfr.';
  StdGrid.Cells[C_MODEL, 0] := 'Model';
  StdGrid.Cells[C_DUE, 0] := 'Cal. Due (yyyy-mm-dd)';
  Reload;
end;

procedure TCertificateFrame.ReloadSheet;
begin
  Reload;
end;

procedure TCertificateFrame.Say(const Text: String; const Bad: Boolean);
begin
  InfoLbl.Caption := Text;
  if Bad then InfoLbl.Font.Color := clRed else InfoLbl.Font.Color := clWindowText;
end;

procedure TCertificateFrame.Reload;
var
  Inputs: TCertInputs;
  Why: String;
begin
  var FromFile := TCertInputs.Load(Inputs, Why);
  ShowInputs(Inputs);
  if FromFile then Say(TAppConfig.FileName)
  else if Why <> '' then Say(Why + ' :: defaults shown', True)
  else Say('Nothing saved yet :: the workbook''s text shown, Save writes ' + TAppConfig.FileName);
end;

procedure TCertificateFrame.ShowInputs(const I: TCertInputs);
begin
  OwnerNameEdit.Text := I.OwnerName;
  OwnerAddr1Edit.Text := I.OwnerAddress1;
  OwnerAddr2Edit.Text := I.OwnerAddress2;
  MfrEdit.Text := I.Manufacturer;
  DescEdit.Text := I.Description;
  ModelEdit.Text := I.Model;
  SerialEdit.Text := I.Serial;
  Proc1Edit.Text := I.Procedure1;
  Proc2Edit.Text := I.Procedure2;
  TechEdit.Text := I.Technician;
  RemarksEdit.Text := I.Remarks;
  TempEdit.Text := I.Temp;
  HumEdit.Text := I.Humidity;
  { no date = unticked, showing today for when it is ticked }
  if I.PrevCalDate = 0 then PrevPick.Date := Date else PrevPick.Date := I.PrevCalDate;
  PrevPick.Checked := I.PrevCalDate <> 0;
  FormNoEdit.Text := I.FormNo;
  RevEdit.Text := I.Rev;
  RevDateEdit.Text := I.RevDate;
  NotesEdit.Text := I.Notes;
  CommentsMemo.Text := I.Comments;
  RecordComments := I.RecordComments;

  { the meters as their sheets have them saved }
  var Units: TArray<TCertStandard>;
  var Meters := TFlukeMeters.Create;
  try
    var Ignore: String;
    Meters.Load(Ignore);
    for var Model := Low(TFlukeModel) to High(TFlukeModel) do
      for var U := 0 to FLUKE_UNITS -1 do
        if Meters.Meters[Model].Units[U].Serial <> '' then
        begin
          var S: TCertStandard;
          S.Serial := Meters.Meters[Model].Units[U].Serial;
          S.Mfr := 'Fluke';
          S.Model := FLUKE_MODEL_NAME[Model];
          S.Due := Meters.Meters[Model].Units[U].Due;
          Units := Units + [S];
        end;
  finally
    Meters.Free;
  end;
  MeterRows := 0;      { while the rows are filled, any of them may be selected }
  var Shown := Units + I.Standards;
  StdGrid.RowCount := Length(Units) + Max(Length(I.Standards) +1, STD_ROWS) +1;
  for var Row := 1 to StdGrid.RowCount -1 do StdGrid.Rows[Row].Clear;
  for var N := 0 to High(Shown) do
  begin
    StdGrid.Cells[C_SERIAL, N +1] := Shown[N].Serial;
    StdGrid.Cells[C_MFR, N +1] := Shown[N].Mfr;
    StdGrid.Cells[C_MODEL, N +1] := Shown[N].Model;
    StdGrid.Cells[C_DUE, N +1] := CfgDate(Shown[N].Due);
  end;
  StdGrid.Row := Length(Units) +1;
  StdGrid.Col := 0;
  MeterRows := Length(Units);
  StdGrid.Invalidate;
end;

function TCertificateFrame.ReadInputs(out I: TCertInputs): Boolean;
var
  S: TCertStandard;
begin
  Result := False;
  I := Default(TCertInputs);
  I.OwnerName := Trim(OwnerNameEdit.Text);
  I.OwnerAddress1 := Trim(OwnerAddr1Edit.Text);
  I.OwnerAddress2 := Trim(OwnerAddr2Edit.Text);
  I.Manufacturer := Trim(MfrEdit.Text);
  I.Description := Trim(DescEdit.Text);
  I.Model := Trim(ModelEdit.Text);
  I.Serial := Trim(SerialEdit.Text);
  I.Procedure1 := Trim(Proc1Edit.Text);
  I.Procedure2 := Trim(Proc2Edit.Text);
  I.Technician := Trim(TechEdit.Text);
  I.Remarks := Trim(RemarksEdit.Text);
  I.Temp := Trim(TempEdit.Text);
  I.Humidity := Trim(HumEdit.Text);
  if PrevPick.Checked then I.PrevCalDate := Trunc(PrevPick.Date);
  I.FormNo := Trim(FormNoEdit.Text);
  I.Rev := Trim(RevEdit.Text);
  I.RevDate := Trim(RevDateEdit.Text);
  I.Notes := Trim(NotesEdit.Text);
  { the memo wraps for the eye only: the comment is one paragraph }
  var Typed: String := CommentsMemo.Text;
  I.Comments := Trim(Typed.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' '));
  I.RecordComments := RecordComments;

  { the meters' rows are not the sheet's: they are left to their own sheets }
  for var Row := MeterRows +1 to StdGrid.RowCount -1 do
  begin
    if Trim(StdGrid.Rows[Row].Text) = '' then Continue;
    S.Serial := Trim(StdGrid.Cells[C_SERIAL, Row]);
    S.Mfr := Trim(StdGrid.Cells[C_MFR, Row]);
    S.Model := Trim(StdGrid.Cells[C_MODEL, Row]);
    if not CfgTryDate(StdGrid.Cells[C_DUE, Row], S.Due) then
    begin
      Say(Format('Standards row %d: "%s" is not a date as yyyy-mm-dd', [Row, StdGrid.Cells[C_DUE, Row]]), True);
      Exit;
    end;
    I.Standards := I.Standards + [S];
  end;
  Result := True;
end;

{ alternating bands of clWindow and clInactiveBorder (the Record tab's look); a due date that is not one shows red }
procedure TCertificateFrame.StdGridDrawCell(Sender: TObject; ACol, ARow: LongInt; Rect: TRect; State: TGridDrawState);
var
  D: TDate;
begin
  if (ARow < 1) or (gdSelected in State) then Exit;

  var Text := StdGrid.Cells[ACol, ARow];
  if ARow mod 2 <> 0 then StdGrid.Canvas.Brush.Color := clInactiveBorder
  else StdGrid.Canvas.Brush.Color := clWindow;
  { a meter's row: grey, it is the Fluke sheet's }
  if ARow <= MeterRows then StdGrid.Canvas.Font.Color := clGrayText
  else if (ACol = C_DUE) and not CfgTryDate(Text, D) then StdGrid.Canvas.Font.Color := clRed
  else StdGrid.Canvas.Font.Color := clWindowText;
  StdGrid.Canvas.FillRect(Rect);
  var Box := Rect;
  InflateRect(Box, -4, 0);
  DrawText(StdGrid.Canvas.Handle, PChar(Text), Length(Text), Box, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

{ the meters' rows cannot be entered, so they cannot be typed in }
procedure TCertificateFrame.StdGridSelectCell(Sender: TObject; ACol, ARow: LongInt; var CanSelect: Boolean);
begin
  CanSelect := ARow > MeterRows;
end;

procedure TCertificateFrame.DefaultsBtnClick(Sender: TObject);
begin
  ShowInputs(TCertInputs.Defaults);
  Say('The workbook''s text shown :: not saved yet');
end;

procedure TCertificateFrame.ReloadBtnClick(Sender: TObject);
begin
  Reload;
end;

procedure TCertificateFrame.SaveBtnClick(Sender: TObject);
var
  Inputs: TCertInputs;
  Why: String;
begin
  if not ReadInputs(Inputs) then Exit;
  if not Inputs.Save(Why) then
  begin
    Say(Why, True);
    Exit;
  end;
  ShowInputs(Inputs);
  Say('Saved :: ' + TAppConfig.FileName);
end;

function TCertificateFrame.Prepare(out Cert: TCertificate): Boolean;
var
  Inputs: TCertInputs;
  Why: String;
begin
  Result := False;
  Cert := Default(TCertificate);
  if not ReadInputs(Inputs) then Exit;
  if not Inputs.Save(Why) then
  begin
    Say(Why, True);
    Exit;
  end;
  Result := TCertificateData.Refresh(Cert, Why);
  if not Result then Say('Certificate: ' + Why, True);
end;

{ what was done, or, when a shunt has no value, why (the first of them) }
procedure TCertificateFrame.ShowGaps(const Cert: TCertificate; const Done: String);
begin
  if Length(Cert.Gaps) = 0 then Say(Done)
  else if Length(Cert.Gaps) = 1 then Say(Cert.Gaps[0], True)
  else Say(Format('%s  (and %d more without a value)', [Cert.Gaps[0], Length(Cert.Gaps) -1]), True);
end;

procedure TCertificateFrame.PreviewBtnClick(Sender: TObject);
var
  Cert: TCertificate;
  Why: String;
begin
  if not Prepare(Cert) then Exit;

  var Folder := TPath.Combine(TPath.GetTempPath, 'AutoCalv2');
  var Pdf := TPath.Combine(Folder, 'certificate-preview.pdf');
  Screen.Cursor := crHourGlass;
  try
    try
      ForceDirectories(Folder);
    except
      on E: Exception do
      begin
        Say(E.Message, True);
        Exit;
      end;
    end;
    { from the data file's certificate member, as written just now }
    if not GenerateCertificate(Pdf, Why) then
    begin
      Say('Certificate: ' + Why, True);
      Exit;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  TCertViewForm.Preview(Self, Pdf, FileNameOf(Cert.Number));
  ShowGaps(Cert, 'Previewed :: ' + ExtractFileName(TAppData.FileName) + ' holds this certificate');
end;

procedure TCertificateFrame.ExportBtnClick(Sender: TObject);
var
  Cert: TCertificate;
  Why: String;
begin
  if not Prepare(Cert) then Exit;

  var Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title := 'Export certificate';
    Dlg.Filter := 'PDF (*.pdf)|*.pdf';
    Dlg.DefaultExt := 'pdf';
    Dlg.FileName := FileNameOf(Cert.Number) + '.pdf';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt, ofPathMustExist];
    if not Dlg.Execute then Exit;

    Screen.Cursor := crHourGlass;
    try
      if not GenerateCertificate(Dlg.FileName, Why) then
      begin
        Say('Certificate: ' + Why, True);
        Exit;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
    ShowGaps(Cert, 'Exported :: ' + Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

end.
