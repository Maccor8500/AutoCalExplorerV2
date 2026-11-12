unit ShuntCfgFormU;

{
  The shunt plan's form: one row per shunt, its nominal value, the standard it is measured against, the
  current, and a note. The voltages to expect and the meters' range are worked out beside them as the row is
  typed; they are not entered.

  The form edits a copy. Save checks it, writes the plan file and hands the rows back; Close leaves the plan
  as it was. UI only: the rules are ShuntPlanU's.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Math, System.UITypes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Grids, ShuntPlanU,
  Vcl.ExtCtrls;

type
  TShuntCfgForm = class(TForm)
    Grid: TStringGrid;
    InfoLbl: TLabel;
    DefaultsBtn: TButton;
    SaveBtn: TButton;
    Panel1: TPanel;
    procedure FormCreate(Sender: TObject);
    procedure GridDrawCell(Sender: TObject; ACol, ARow: LongInt; Rect: TRect; State: TGridDrawState);
    procedure GridSelectCell(Sender: TObject; ACol, ARow: LongInt; var CanSelect: Boolean);
    procedure GridSetEditText(Sender: TObject; ACol, ARow: LongInt; const Value: string);
    procedure DefaultsBtnClick(Sender: TObject);
    procedure SaveBtnClick(Sender: TObject);
    procedure GridMouseLeave(Sender: TObject);
    procedure FormMouseEnter(Sender: TObject);
  private
    Plan: TShuntPlan;                        { the caller's; written only by Save }
    Draft: TShuntPlan;                       { what the grid shows }
    Saved: Boolean;

    procedure ShowDraft;
    procedure ShowDerived(const Row: Integer);
    { the grid's typed cells into Draft; False, with the reason shown, when one is not a number }
    function ReadGrid: Boolean;
    procedure Say(const Text: String; const Bad: Boolean = False);
  public
    destructor Destroy; override;
    {
      edits Plan; True when it was saved (Plan then holds the new rows and the file is written)
    }
    class function Edit(const AOwner: TComponent; const Plan: TShuntPlan): Boolean;
  end;

implementation

{$R *.dfm}

const
  { columns }
  C_SHUNT = 0;
  C_NOMINAL = 1;
  C_STANDARD = 2;
  C_UNC = 3;
  C_CURRENT = 4;
  C_VSTD = 5;
  C_VSHUNT = 6;
  C_RANGE = 7;
  C_NOTE = 8;
  TITLES: array [C_SHUNT..C_NOTE] of String = ('#', 'Nominal (ohm)', 'Standard (ohm)', 'Unc. (ppm)', 'Current (A)',
    'V standard', 'V shunt', 'Range', 'Note');
  WIDTHS: array [C_SHUNT..C_NOTE] of Integer = (28, 96, 104, 76, 92, 84, 84, 60, 300);
  DERIVED = [C_VSTD, C_VSHUNT, C_RANGE];
  NUMERIC = [C_NOMINAL, C_STANDARD, C_UNC, C_CURRENT];

class function TShuntCfgForm.Edit(const AOwner: TComponent; const Plan: TShuntPlan): Boolean;
begin
  var Form := TShuntCfgForm.Create(AOwner);
  try
    Form.Plan := Plan;
    Form.Draft.Rows := Plan.Rows;
    Form.ShowDraft;
    Form.Say(TShuntPlan.FileName);
    Form.ShowModal;
    Result := Form.Saved;
  finally
    Form.Free;
  end;
end;

procedure TShuntCfgForm.FormCreate(Sender: TObject);
begin
  Draft := TShuntPlan.Create;

  Grid.ColCount := Length(TITLES);
  Grid.RowCount := PLAN_LAST - PLAN_FIRST + 2;
  for var C := Low(TITLES) to High(TITLES) do
  begin
    Grid.Cells[C, 0] := TITLES[C];
    Grid.ColWidths[C] := WIDTHS[C];
  end;
  Grid.ColWidths[8] := Grid.ColWidths[8] +4;
  for var I := PLAN_FIRST to PLAN_LAST do Grid.Cells[C_SHUNT, I - PLAN_FIRST + 1] := IntToStr(I);
end;

procedure TShuntCfgForm.FormMouseEnter(Sender: TObject);
begin
  Panel1.SetFocus;
end;

destructor TShuntCfgForm.Destroy;
begin
  FreeAndNil(Draft);
  inherited;
end;

procedure TShuntCfgForm.Say(const Text: String; const Bad: Boolean);
begin
  InfoLbl.Caption := Text;
  if Bad then InfoLbl.Font.Color := clRed else InfoLbl.Font.Color := clWindowText;
end;

procedure TShuntCfgForm.ShowDraft;
begin
  for var I := PLAN_FIRST to PLAN_LAST do
  begin
    var Row := I - PLAN_FIRST + 1;
    Grid.Cells[C_NOMINAL, Row] := PlanText(Draft.Rows[I].Nominal);
    Grid.Cells[C_STANDARD, Row] := PlanText(Draft.Rows[I].Standard);
    Grid.Cells[C_UNC, Row] := PlanText(Draft.Rows[I].StandardUnc);
    Grid.Cells[C_CURRENT, Row] := PlanText(Draft.Rows[I].Current);
    Grid.Cells[C_NOTE, Row] := Draft.Rows[I].Note;
    ShowDerived(Row);
  end;
  Grid.Invalidate;
end;

{ what follows from a row as it stands in the grid: the two voltages and the range; blank until the row is whole }
procedure TShuntCfgForm.ShowDerived(const Row: Integer);
var
  R: TPlanRow;
begin
  R := Default(TPlanRow);
  var Whole := PlanNumber(Grid.Cells[C_NOMINAL, Row], R.Nominal) and PlanNumber(Grid.Cells[C_STANDARD, Row], R.Standard)
    and PlanNumber(Grid.Cells[C_CURRENT, Row], R.Current) and R.Planned and (R.Nominal > 0);

  if not Whole then
  begin
    for var C in DERIVED do Grid.Cells[C, Row] := '';
    Exit;
  end;
  Grid.Cells[C_VSTD, Row] := FloatToStrF(R.StandardVolts, ffGeneral, 4, 0, TFormatSettings.Invariant) + ' V';
  Grid.Cells[C_VSHUNT, Row] := FloatToStrF(R.ShuntVolts, ffGeneral, 4, 0, TFormatSettings.Invariant) + ' V';
  if R.Range > 0 then Grid.Cells[C_RANGE, Row] := FloatToStrF(R.Range, ffGeneral, 4, 0, TFormatSettings.Invariant) + ' V'
  else Grid.Cells[C_RANGE, Row] := 'too high';
end;

function TShuntCfgForm.ReadGrid: Boolean;

  function Cell(const Col, Row: Integer; out Value: Double): Boolean;
  begin
    Result := PlanNumber(Grid.Cells[Col, Row], Value);
    if not Result then
      Say(Format('Shunt %s: "%s" in %s is not a number (use a point, e.g. 0.00006 or 6e-5)',
        [Grid.Cells[C_SHUNT, Row], Grid.Cells[Col, Row], TITLES[Col]]), True);
  end;

begin
  Result := False;
  for var I := PLAN_FIRST to PLAN_LAST do
  begin
    var Row := I - PLAN_FIRST + 1;
    var R := Default(TPlanRow);
    if not (Cell(C_NOMINAL, Row, R.Nominal) and Cell(C_STANDARD, Row, R.Standard) and Cell(C_UNC, Row, R.StandardUnc)
      and Cell(C_CURRENT, Row, R.Current)) then Exit;
    R.Note := Trim(Grid.Cells[C_NOTE, Row]);
    Draft.Rows[I] := R;
  end;
  Result := True;
end;

{ the worked-out columns are not typed into }
procedure TShuntCfgForm.GridSelectCell(Sender: TObject; ACol, ARow: LongInt; var CanSelect: Boolean);
begin
  if ACol in DERIVED then Grid.Options := Grid.Options - [goEditing]
  else Grid.Options := Grid.Options + [goEditing];
end;

procedure TShuntCfgForm.GridSetEditText(Sender: TObject; ACol, ARow: LongInt; const Value: string);
begin
  if (ARow >= 1) and (ACol in NUMERIC) then
  begin
    ShowDerived(ARow);
    Grid.Invalidate;
  end;
end;

{
  the worked-out columns in grey; a shunt with no standard or no current yet has those two cells marked, and a
  typed cell that is not a number shows red
}
procedure TShuntCfgForm.GridDrawCell(Sender: TObject; ACol, ARow: LongInt; Rect: TRect; State: TGridDrawState);
var
  Value: Double;
begin
  if (ARow < 1) or (ACol < 1) then Exit;

  var Text := Grid.Cells[ACol, ARow];
  var Back := clWindow;
  var Ink := clWindowText;

  if ACol in DERIVED then
  begin
    Back := clBtnFace;
    Ink := clGrayText;
    if Text = 'too high' then Ink := clRed;
  end
  else if ACol in NUMERIC then
  begin
    if not PlanNumber(Text, Value) then Ink := clRed
    else if (ACol in [C_STANDARD, C_CURRENT]) and (Value = 0) then Back := $00C8F0FF;     { pale amber: still to be given }
  end;

  { the cell in hand keeps the grid's own look }
  if (gdSelected in State) and not (ACol in DERIVED) then Exit;

  Grid.Canvas.Brush.Color := Back;
  Grid.Canvas.Font.Color := Ink;
  Grid.Canvas.FillRect(Rect);
  var Flags := DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS;
  if ACol = C_NOTE then Flags := Flags or DT_LEFT else Flags := Flags or DT_RIGHT;
  var Box := Rect;
  InflateRect(Box, -5, 0);
  DrawText(Grid.Canvas.Handle, PChar(Text), Length(Text), Box, Flags);
end;

procedure TShuntCfgForm.GridMouseLeave(Sender: TObject);
begin

end;

procedure TShuntCfgForm.DefaultsBtnClick(Sender: TObject);
begin
  Draft.Seed;
  ShowDraft;
  Say('Defaults shown :: not saved yet');
end;

procedure TShuntCfgForm.SaveBtnClick(Sender: TObject);
var
  Why: String;
begin
  if not ReadGrid then Exit;

  { the caller's plan takes the rows only once they have been written }
  var Keep := Plan.Rows;
  Plan.Rows := Draft.Rows;
  if not Plan.Save(Why) then
  begin
    Plan.Rows := Keep;
    Say(Why, True);
    Exit;
  end;
  Saved := True;
  ShowDraft;
  Say('Saved :: ' + TShuntPlan.FileName);
end;

end.
