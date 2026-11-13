unit FlukeFrameU;

{
  Configurations > Fluke 8508A / Fluke 8588A: one sheet per meter type, the same frame opened for each (Open).

    Digits of resolution    what the meters of this type are set to while connected
    Meter 1, Meter 2        the pair's serial numbers and calibration due dates (a date is given when its box
                            is ticked; one that has passed shows "Overdue" in red)
    DC voltage accuracy     per range: ppm of reading, ppm of range and the calibration uncertainty in volts
                            (the workbook's meter sheet, columns H, I and M); a blank row is no range

  The sheet is a draft: Save checks it and writes this type into the "meters" section of the configuration
  file, Reload goes back to what is saved, Defaults shows the workbook's figures (not saved until Save).
  UI only: the figures are FlukeMetersU's.

  Two of these live on one form, so the main form creates them without an owner, names them apart and only
  then takes them over; the pickers are therefore left ticked in the dfm and set once the frame has its parent.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Math, Vcl.Graphics, Vcl.Controls,
  Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Grids, Vcl.ComCtrls, Vcl.Samples.Spin, AppConfigU, FlukeMetersU;

type
  TFlukeFrame = class(TFrame)
    TitleLbl: TLabel;
    DigitsLbl: TLabel;
    DigitsSpin: TSpinEdit;
    DigitsNoteLbl: TLabel;
    MetersLbl: TLabel;
    Serial1Lbl: TLabel;
    Serial1Edit: TEdit;
    Due1Lbl: TLabel;
    Due1Pick: TDateTimePicker;
    Serial2Lbl: TLabel;
    Serial2Edit: TEdit;
    Due2Lbl: TLabel;
    Due2Pick: TDateTimePicker;
    SpecLbl: TLabel;
    SpecGrid: TStringGrid;
    HintLbl: TLabel;
    InfoLbl: TLabel;
    DefaultsBtn: TButton;
    ReloadBtn: TButton;
    SaveBtn: TButton;
    ScpiBox: TCheckBox;
    procedure ScpiBoxClick(Sender: TObject);
    procedure DigitsSpinChange(Sender: TObject);
    procedure DuePickChange(Sender: TObject);
    procedure SpecGridDrawCell(Sender: TObject; ACol, ARow: LongInt; Rect: TRect; State: TGridDrawState);
    procedure DefaultsBtnClick(Sender: TObject);
    procedure ReloadBtnClick(Sender: TObject);
    procedure SaveBtnClick(Sender: TObject);

  private
    Model: TFlukeModel;
    Opened: Boolean;
    Loading: Boolean;                         { the sheet is being filled: the controls' changes are not the user's }
    SerialEdits: array [0..FLUKE_UNITS -1] of TEdit;
    DuePicks: array [0..FLUKE_UNITS -1] of TDateTimePicker;
    DueLbls: array [0..FLUKE_UNITS -1] of TLabel;

    procedure ShowMeter(const Meter: TFlukeMeter);
    procedure ShowDigitsNote;
    { 'Cal. due', or a red 'Overdue' for a meter whose ticked due date has passed }
    procedure ShowDue(const Index: Integer);
    { the sheet into Meter; False, with the reason shown, when a cell does not read }
    function ReadMeter(out Meter: TFlukeMeter): Boolean;
    procedure Reload;
    procedure Say(const Text: String; const Bad: Boolean = False);

  public
    Meters: TFlukeMeters;                     { what is saved (or the defaults until something is) }

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { once, after the frame has its parent: the type this sheet is for }
    procedure Open(const AModel: TFlukeModel);
    { the configuration file changed behind the sheet (a Read of the board saved the meters' lines): what is saved, again }
    procedure ReloadSheet;
  end;

implementation

{$R *.dfm}

const
  { columns }
  C_RANGE = 0;
  C_PPM_READING = 1;
  C_PPM_RANGE = 2;
  C_CAL_UNC = 3;
  { rows the grid always offers; blank ones are no range }
  SPEC_ROWS = 5;

constructor TFlukeFrame.Create(AOwner: TComponent);
begin
  inherited;
  Meters := TFlukeMeters.Create;
  Meters.Seed;
  SerialEdits[0] := Serial1Edit;
  SerialEdits[1] := Serial2Edit;
  DuePicks[0] := Due1Pick;
  DuePicks[1] := Due2Pick;
  DueLbls[0] := Due1Lbl;
  DueLbls[1] := Due2Lbl;
  DigitsSpin.MinValue := FLUKE_MIN_DIGITS;
  DigitsSpin.MaxValue := FLUKE_MAX_DIGITS;
  SpecGrid.Cells[C_RANGE, 0] := 'Range (V)';
  SpecGrid.Cells[C_PPM_READING, 0] := 'ppm of reading';
  SpecGrid.Cells[C_PPM_RANGE, 0] := 'ppm of range';
  SpecGrid.Cells[C_CAL_UNC, 0] := 'Cal. unc. (V)';
end;

destructor TFlukeFrame.Destroy;
begin
  FreeAndNil(Meters);
  inherited;
end;

procedure TFlukeFrame.Open(const AModel: TFlukeModel);
begin
  Model := AModel;
  Opened := True;
  TitleLbl.Caption := FLUKE_MANUFACTURER + ' ' + FLUKE_MODEL_NAME[Model];
  MetersLbl.Caption := Format('Meters (x%d)', [FLUKE_UNITS]);
  ScpiBox.Visible := FLUKE_HAS_SCPI[Model];
  Reload;
end;

procedure TFlukeFrame.ReloadSheet;
begin
  if Opened then Reload;
end;

procedure TFlukeFrame.Say(const Text: String; const Bad: Boolean);
begin
  InfoLbl.Caption := Text;
  if Bad then InfoLbl.Font.Color := clRed else InfoLbl.Font.Color := clWindowText;
end;

procedure TFlukeFrame.Reload;
var
  Why: String;
begin
  var FromFile := Meters.Load(Why);
  ShowMeter(Meters.Meters[Model]);
  if FromFile then Say(TAppConfig.FileName)
  else if Why <> '' then Say(Why + ' :: defaults shown', True)
  else Say('Nothing saved yet :: defaults shown, Save writes ' + TAppConfig.FileName);
end;

procedure TFlukeFrame.ShowDigitsNote;
begin
  var Sent := Format('RESL%d', [DigitsSpin.Value]);
  if ScpiBox.Visible and ScpiBox.Checked then Sent := 'its resolution on a fixed range';
  DigitsNoteLbl.Caption := Format('sent to the meter as %s at Connect  ::  resolution %s V  ::  default %d',
    [Sent, FloatToStrF(Power(10, -DigitsSpin.Value), ffGeneral, 3, 0, TFormatSettings.Invariant),
    FLUKE_DEFAULT_DIGITS[Model]]);
end;

procedure TFlukeFrame.ScpiBoxClick(Sender: TObject);
begin
  if Loading or not Opened then Exit;
  ShowDigitsNote;
end;

procedure TFlukeFrame.ShowDue(const Index: Integer);
begin
  if DuePicks[Index].Checked and (Date > Trunc(DuePicks[Index].Date)) then
  begin
    DueLbls[Index].Caption := 'Overdue';
    DueLbls[Index].Font.Color := clRed;
  end
  else
  begin
    DueLbls[Index].Caption := 'Cal. due';
    DueLbls[Index].Font.Color := clWindowText;
  end;
end;

procedure TFlukeFrame.ShowMeter(const Meter: TFlukeMeter);
begin
  Loading := True;
  try
    DigitsSpin.Value := EnsureRange(Meter.Digits, FLUKE_MIN_DIGITS, FLUKE_MAX_DIGITS);
    ScpiBox.Checked := Meter.Scpi;
    ShowDigitsNote;

    for var I := 0 to FLUKE_UNITS -1 do
    begin
      SerialEdits[I].Text := Meter.Units[I].Serial;
      { no date = unticked, showing today for when it is ticked }
      if Meter.Units[I].Due = 0 then DuePicks[I].Date := Date
      else DuePicks[I].Date := Meter.Units[I].Due;
      DuePicks[I].Checked := Meter.Units[I].Due <> 0;
      ShowDue(I);
    end;

    SpecGrid.RowCount := Max(Length(Meter.Ranges), SPEC_ROWS) +1;
    for var Row := 1 to SpecGrid.RowCount -1 do SpecGrid.Rows[Row].Clear;
    for var I := 0 to High(Meter.Ranges) do
    begin
      SpecGrid.Cells[C_RANGE, I +1] := CfgText(Meter.Ranges[I].RangeV);
      SpecGrid.Cells[C_PPM_READING, I +1] := CfgText(Meter.Ranges[I].PpmReading);
      SpecGrid.Cells[C_PPM_RANGE, I +1] := CfgText(Meter.Ranges[I].PpmRange);
      SpecGrid.Cells[C_CAL_UNC, I +1] := CfgText(Meter.Ranges[I].CalUnc);
    end;
    SpecGrid.Invalidate;
  finally
    Loading := False;
  end;
end;

function TFlukeFrame.ReadMeter(out Meter: TFlukeMeter): Boolean;
var
  R: TFlukeRange;
begin
  Result := False;
  Meter := Default(TFlukeMeter);
  Meter.Digits := DigitsSpin.Value;
  Meter.Scpi := FLUKE_HAS_SCPI[Model] and ScpiBox.Checked;

  for var I := 0 to FLUKE_UNITS -1 do
  begin
    Meter.Units[I].Serial := Trim(SerialEdits[I].Text);
    if DuePicks[I].Checked then Meter.Units[I].Due := Trunc(DuePicks[I].Date);
  end;

  for var Row := 1 to SpecGrid.RowCount -1 do
  begin
    if Trim(SpecGrid.Rows[Row].Text) = '' then Continue;
    if not (CfgNumber(SpecGrid.Cells[C_RANGE, Row], R.RangeV) and CfgNumber(SpecGrid.Cells[C_PPM_READING, Row], R.PpmReading)
      and CfgNumber(SpecGrid.Cells[C_PPM_RANGE, Row], R.PpmRange) and CfgNumber(SpecGrid.Cells[C_CAL_UNC, Row], R.CalUnc)) then
    begin
      Say(Format('Accuracy row %d has a cell that is not a number (use a point, e.g. 4.5)', [Row]), True);
      Exit;
    end;
    Meter.Ranges := Meter.Ranges + [R];
  end;
  Result := True;
end;

procedure TFlukeFrame.DigitsSpinChange(Sender: TObject);
begin
  if Loading or not Opened then Exit;
  ShowDigitsNote;
end;

procedure TFlukeFrame.DuePickChange(Sender: TObject);
begin
  if Loading or not Opened then Exit;
  for var I := 0 to FLUKE_UNITS -1 do
    if DuePicks[I] = Sender then ShowDue(I);
end;

{ alternating bands of clWindow and clInactiveBorder (the Record tab's look); a cell that is not a number shows red }
procedure TFlukeFrame.SpecGridDrawCell(Sender: TObject; ACol, ARow: LongInt; Rect: TRect; State: TGridDrawState);
var
  Value: Double;
begin
  if (ARow < 1) or (gdSelected in State) then Exit;

  var Text := SpecGrid.Cells[ACol, ARow];
  if ARow mod 2 <> 0 then SpecGrid.Canvas.Brush.Color := clInactiveBorder
  else SpecGrid.Canvas.Brush.Color := clWindow;
  if CfgNumber(Text, Value) then SpecGrid.Canvas.Font.Color := clWindowText
  else SpecGrid.Canvas.Font.Color := clRed;
  SpecGrid.Canvas.FillRect(Rect);
  DrawText(SpecGrid.Canvas.Handle, PChar(Text), Length(Text), Rect, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

procedure TFlukeFrame.DefaultsBtnClick(Sender: TObject);
begin
  ShowMeter(TFlukeMeters.Defaults(Model));
  Say('Defaults shown :: not saved yet');
end;

procedure TFlukeFrame.ReloadBtnClick(Sender: TObject);
begin
  Reload;
end;

procedure TFlukeFrame.SaveBtnClick(Sender: TObject);
var
  Draft: TFlukeMeter;
  Why: String;
begin
  if not ReadMeter(Draft) then Exit;

  { Meters takes the draft only once it has been written }
  var Keep := Meters.Meters[Model];
  Meters.Meters[Model] := Draft;
  if not Meters.Save(Model, Why) then
  begin
    Meters.Meters[Model] := Keep;
    Say(Why, True);
    Exit;
  end;
  ShowMeter(Meters.Meters[Model]);
  Say('Saved :: ' + TAppConfig.FileName);
end;

end.
