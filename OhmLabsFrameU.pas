unit OhmLabsFrameU;

{
  Configurations > Ohm Labs: the three sets of Ohm Labs standards, one grid each, laid out as the workbook's
  "Ohm Labs" sheet was. Nominal, Actual, 12-month stability and the certificate's uncertainty are typed; the
  two columns on the right are worked out from them as the row is typed and are not entered.

  Above each grid: the date the set's calibration is due (given when its box is ticked). A set past its due
  date shows "Overdue" in red.

  The form is a draft: Save checks it and writes the "ohmLabs" section of the configuration file, Reload
  goes back to what is saved, Defaults shows the worksheet's figures (not saved until Save). The MCS grids
  read in milliohms, the file holds ohms. UI only: the figures and the maths are OhmLabsU's.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Math, System.DateUtils, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Grids, Vcl.ComCtrls, AppConfigU, OhmLabsU;

type
  TOhmLabsFrame = class(TFrame)
    MrsLbl: TLabel;
    MrsDueLbl: TLabel;
    MrsDuePick: TDateTimePicker;
    MrsGrid: TStringGrid;
    Mcs10Lbl: TLabel;
    Mcs10DueLbl: TLabel;
    Mcs10DuePick: TDateTimePicker;
    Mcs10Grid: TStringGrid;
    Mcs1Lbl: TLabel;
    Mcs1DueLbl: TLabel;
    Mcs1DuePick: TDateTimePicker;
    Mcs1Grid: TStringGrid;
    HintLbl: TLabel;
    InfoLbl: TLabel;
    DefaultsBtn: TButton;
    ReloadBtn: TButton;
    SaveBtn: TButton;
    procedure GridDrawCell(Sender: TObject; ACol, ARow: LongInt; Rect: TRect; State: TGridDrawState);
    procedure GridSelectCell(Sender: TObject; ACol, ARow: LongInt; var CanSelect: Boolean);
    procedure GridSetEditText(Sender: TObject; ACol, ARow: LongInt; const Value: string);
    procedure DuePickChange(Sender: TObject);
    procedure DefaultsBtnClick(Sender: TObject);
    procedure ReloadBtnClick(Sender: TObject);
    procedure SaveBtnClick(Sender: TObject);

  private
    Grids: array [TOhmSetId] of TStringGrid;
    DuePicks: array [TOhmSetId] of TDateTimePicker;
    DueLbls: array [TOhmSetId] of TLabel;
    Loading: Boolean;                         { the form is being filled: the pickers' changes are not the user's }

    function SetOf(const Control: TObject): TOhmSetId;
    procedure ShowAll(const Sets: TOhmSets; const Info: TOhmSetInfos);
    procedure ShowDate(const Picker: TDateTimePicker; const Date: TDate);
    { 'Due', or a red 'Overdue' for a set whose ticked due date has passed }
    procedure ShowDue(const Id: TOhmSetId);
    { a grid row as a standard; -1 when every typed cell reads, else the first column that does not }
    function RowOf(const Id: TOhmSetId; const Row: Integer; out S: TOhmStandard): Integer;
    procedure ShowDerived(const Id: TOhmSetId; const Row: Integer);
    { the form into Sets and Info; False, with the reason shown, when a cell does not read }
    function ReadAll(out Sets: TOhmSets; out Info: TOhmSetInfos): Boolean;
    procedure Reload;
    procedure Say(const Text: String; const Bad: Boolean = False);

  public
    Labs: TOhmLabs;                           { what is saved (or the defaults until something is) }

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

{$R *.dfm}

const
  { columns }
  C_NOMINAL = 0;
  C_ACTUAL = 1;
  C_STABILITY = 2;
  C_CERT_UNC = 3;
  C_UNC = 4;
  C_UNC_PPM = 5;
  DERIVED = [C_UNC, C_UNC_PPM];
  OHM = #$03A9;
  MICRO = #$00B5;

constructor TOhmLabsFrame.Create(AOwner: TComponent);
begin
  inherited;
  Labs := TOhmLabs.Create;
  Grids[osMRS] := MrsGrid;
  Grids[osMCS10] := Mcs10Grid;
  Grids[osMCS1] := Mcs1Grid;
  DuePicks[osMRS] := MrsDuePick;
  DuePicks[osMCS10] := Mcs10DuePick;
  DuePicks[osMCS1] := Mcs1DuePick;
  DueLbls[osMRS] := MrsDueLbl;
  DueLbls[osMCS10] := Mcs10DueLbl;
  DueLbls[osMCS1] := Mcs1DueLbl;

  for var Id := Low(TOhmSetId) to High(TOhmSetId) do
  begin
    var Units: String := OHM;
    if OHM_SET_SCALE[Id] = 1000 then Units := 'm' + OHM;
    var G := Grids[Id];
    G.Cells[C_NOMINAL, 0] := 'Nominal (' + OHM + ')';
    G.Cells[C_ACTUAL, 0] := 'Actual (' + Units + ')';
    G.Cells[C_STABILITY, 0] := '12 mo. Stab. (ppm)';
    G.Cells[C_CERT_UNC, 0] := 'Unc (' + MICRO + OHM + '/' + OHM + ')';
    G.Cells[C_UNC, 0] := 'Unc (' + Units + ')';
    G.Cells[C_UNC_PPM, 0] := 'Unc (ppm)';
  end;

  Reload;
end;

destructor TOhmLabsFrame.Destroy;
begin
  FreeAndNil(Labs);
  inherited;
end;

{ the set a grid or a due-date picker belongs to }
function TOhmLabsFrame.SetOf(const Control: TObject): TOhmSetId;
begin
  Result := Low(TOhmSetId);
  for var Id := Low(TOhmSetId) to High(TOhmSetId) do
    if (Grids[Id] = Control) or (DuePicks[Id] = Control) then Exit(Id);
end;

procedure TOhmLabsFrame.Say(const Text: String; const Bad: Boolean);
begin
  InfoLbl.Caption := Text;
  if Bad then InfoLbl.Font.Color := clRed else InfoLbl.Font.Color := clWindowText;
end;

procedure TOhmLabsFrame.Reload;
var
  Why: String;
begin
  var FromFile := Labs.Load(Why);
  ShowAll(Labs.Sets, Labs.Info);
  if FromFile then Say(TAppConfig.FileName)
  else if Why <> '' then Say(Why + ' :: worksheet defaults shown', True)
  else Say('Nothing saved yet :: worksheet defaults shown, Save writes ' + TAppConfig.FileName);
end;

{ no date = unticked, showing today for when it is ticked }
procedure TOhmLabsFrame.ShowDate(const Picker: TDateTimePicker; const Date: TDate);
begin
  Picker.Checked := False;
  if Date = 0 then
  begin
    Picker.Date := System.SysUtils.Date;
    Picker.Checked := False;
    Exit;
  end;
  Picker.Date := Date;
  Picker.Checked := True;
end;

procedure TOhmLabsFrame.ShowDue(const Id: TOhmSetId);
begin
  var Late := DuePicks[Id].Checked and (System.SysUtils.Date > Trunc(DuePicks[Id].Date));
  if Late then
  begin
    DueLbls[Id].Caption := 'Overdue';
    DueLbls[Id].Font.Color := clRed;
  end
  else
  begin
    DueLbls[Id].Caption := 'Due';
    DueLbls[Id].Font.Color := clWindowText;
  end;
end;

procedure TOhmLabsFrame.ShowAll(const Sets: TOhmSets; const Info: TOhmSetInfos);
begin
  Loading := True;
  try
    for var Id := Low(TOhmSetId) to High(TOhmSetId) do
    begin
      ShowDate(DuePicks[Id], Info[Id].Due);
      ShowDue(Id);

      var G := Grids[Id];
      { a set with no rows still shows one blank line under the titles: a grid needs a row below its fixed one }
      G.RowCount := Max(Length(Sets[Id]), 1) +1;
      G.Rows[1].Clear;

      for var I := 0 to High(Sets[Id]) do
      begin
        var S := Sets[Id][I];
        G.Cells[C_NOMINAL, I +1] := S.Caption;
        G.Cells[C_ACTUAL, I +1] := CfgText(S.Actual * OHM_SET_SCALE[Id]);
        G.Cells[C_STABILITY, I +1] := CfgText(S.Stability);
        G.Cells[C_CERT_UNC, I +1] := CfgText(S.CertUnc);
        ShowDerived(Id, I +1);
      end;
      G.Invalidate;
    end;
  finally
    Loading := False;
  end;
end;

function TOhmLabsFrame.RowOf(const Id: TOhmSetId; const Row: Integer; out S: TOhmStandard): Integer;
begin
  S := Default(TOhmStandard);
  var G := Grids[Id];
  if not TOhmStandard.Parse(G.Cells[C_NOMINAL, Row], S.Nominal, S.Current) then Exit(C_NOMINAL);
  if not CfgNumber(G.Cells[C_ACTUAL, Row], S.Actual) then Exit(C_ACTUAL);
  if not CfgNumber(G.Cells[C_STABILITY, Row], S.Stability) then Exit(C_STABILITY);
  if not CfgNumber(G.Cells[C_CERT_UNC, Row], S.CertUnc) then Exit(C_CERT_UNC);
  S.Actual := S.Actual / OHM_SET_SCALE[Id];
  Result := -1;
end;

{ what follows from a row as it stands in the grid; blank until the row reads and has a value }
procedure TOhmLabsFrame.ShowDerived(const Id: TOhmSetId; const Row: Integer);
var
  S: TOhmStandard;
begin
  var G := Grids[Id];
  if (RowOf(Id, Row, S) >= 0) or (S.Actual <= 0) then
  begin
    G.Cells[C_UNC, Row] := '';
    G.Cells[C_UNC_PPM, Row] := '';
    Exit;
  end;
  G.Cells[C_UNC, Row] := FloatToStrF(S.UncOhms * OHM_SET_SCALE[Id], ffGeneral, 4, 0, TFormatSettings.Invariant);
  G.Cells[C_UNC_PPM, Row] := FormatFloat('0.00', S.UncPpm, TFormatSettings.Invariant);
end;

function TOhmLabsFrame.ReadAll(out Sets: TOhmSets; out Info: TOhmSetInfos): Boolean;
var
  S: TOhmStandard;
begin
  Result := False;
  Info := Default(TOhmSetInfos);
  for var Id := Low(TOhmSetId) to High(TOhmSetId) do
  begin
    if DuePicks[Id].Checked then Info[Id].Due := Trunc(DuePicks[Id].Date);

    Sets[Id] := nil;
    var G := Grids[Id];
    for var Row := 1 to G.RowCount -1 do
    begin
      { the blank line of an empty set is not a standard }
      if Trim(G.Rows[Row].Text) = '' then Continue;
      var Col := RowOf(Id, Row, S);
      if Col >= 0 then
      begin
        Say(Format('%s row %d: "%s" in %s does not read (a number with a point, e.g. 9.999229; a nominal as 0.01 @ 6A)',
          [OHM_SET_NAME[Id], Row, G.Cells[Col, Row], G.Cells[Col, 0]]), True);
        Exit;
      end;
      Sets[Id] := Sets[Id] + [S];
    end;
  end;
  Result := True;
end;

procedure TOhmLabsFrame.DuePickChange(Sender: TObject);
begin
  if Loading then Exit;
  ShowDue(SetOf(Sender));
end;

{ the worked-out columns are not typed into }
procedure TOhmLabsFrame.GridSelectCell(Sender: TObject; ACol, ARow: LongInt; var CanSelect: Boolean);
begin
  var G := TStringGrid(Sender);
  if ACol in DERIVED then G.Options := G.Options - [goEditing]
  else G.Options := G.Options + [goEditing];
end;

procedure TOhmLabsFrame.GridSetEditText(Sender: TObject; ACol, ARow: LongInt; const Value: string);
begin
  if (ARow < 1) or (ACol in DERIVED) then Exit;
  ShowDerived(SetOf(Sender), ARow);
  TStringGrid(Sender).Invalidate;
end;

{
  the typed cells in alternating bands of clWindow and clInactiveBorder (the Record tab's look), the worked-out
  columns in grey; a typed cell that does not read shows red
}
procedure TOhmLabsFrame.GridDrawCell(Sender: TObject; ACol, ARow: LongInt; Rect: TRect; State: TGridDrawState);
var
  Value, Other: Double;
begin
  if ARow < 1 then Exit;

  var G := TStringGrid(Sender);
  var Text := G.Cells[ACol, ARow];
  var Back := clWindow;
  var Ink := clWindowText;

  if ACol in DERIVED then
  begin
    Back := clBtnFace;
    Ink := clGrayText;
  end
  else
  begin
    if ARow mod 2 <> 0 then Back := clInactiveBorder;
    var Reads: Boolean;
    if ACol = C_NOMINAL then Reads := (Trim(Text) = '') or TOhmStandard.Parse(Text, Value, Other)
    else Reads := CfgNumber(Text, Value);
    if not Reads then Ink := clRed;
    { the cell in hand keeps the grid's own look }
    if gdSelected in State then Exit;
  end;

  G.Canvas.Brush.Color := Back;
  G.Canvas.Font.Color := Ink;
  G.Canvas.FillRect(Rect);
  DrawText(G.Canvas.Handle, PChar(Text), Length(Text), Rect, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

procedure TOhmLabsFrame.DefaultsBtnClick(Sender: TObject);
begin
  var Sheet := TOhmLabs.Create;
  try
    Sheet.Seed;
    ShowAll(Sheet.Sets, Sheet.Info);
  finally
    Sheet.Free;
  end;
  Say('Worksheet defaults shown :: not saved yet');
end;

procedure TOhmLabsFrame.ReloadBtnClick(Sender: TObject);
begin
  Reload;
end;

procedure TOhmLabsFrame.SaveBtnClick(Sender: TObject);
var
  Sets: TOhmSets;
  Info: TOhmSetInfos;
  Why: String;
begin
  if not ReadAll(Sets, Info) then Exit;

  { Labs takes the draft only once it has been written }
  var KeepSets := Labs.Sets;
  var KeepInfo := Labs.Info;
  Labs.Sets := Sets;
  Labs.Info := Info;
  if not Labs.Save(Why) then
  begin
    Labs.Sets := KeepSets;
    Labs.Info := KeepInfo;
    Say(Why, True);
    Exit;
  end;
  ShowAll(Labs.Sets, Labs.Info);
  Say('Saved :: ' + TAppConfig.FileName);
end;

end.
