unit ShuntPlanU;

{
  The shunt plan: for each of the box's shunts, what it is (nominal ohms), the standard resistor it is measured
  against (certified ohms and its uncertainty) and the current to run. It belongs to the box and the procedure,
  not to one certificate, so it is kept in a file of its own beside the exe (<exe name>.shunts.ini) and the
  certificate workbook is only where results go.

  A row with neither a standard nor a current is a shunt not planned yet. The meters' range is not stored:
  it follows from the row (MeterRange of the larger of the two voltages to come).

  No VCL. The form that edits a plan is ShuntCfgFormU.
}

interface

uses
  System.SysUtils, System.Classes, System.Math, System.IniFiles, AutoCalBoardU;

const
  PLAN_FIRST = Low(SHUNT_VALUE);
  PLAN_LAST = High(SHUNT_VALUE);

type
  TPlanRow = record
    Nominal: Double;                          { ohms }
    Standard: Double;                         { certified ohms; 0 = none given }
    StandardUnc: Double;                      { ppm at k = 2; 0 = not given }
    Current: Double;                          { amps; 0 = none given }
    Note: String;

    function Planned: Boolean;                { a standard and a current are both given }
    function StandardVolts: Double;           { across the standard at the planned current; 0 = not planned }
    function ShuntVolts: Double;
    function Range: Double;                   { the meters' range for it, in volts; 0 = not planned or beyond the meter }
  end;
  TPlanRows = array [PLAN_FIRST..PLAN_LAST] of TPlanRow;

  TShuntPlan = class(TObject)
    public
      Rows: TPlanRows;

      { the defaults: today's fitted shunts, with the standards and currents known so far }
      procedure Seed;
      { the plan file, or the defaults when there is none yet (Seeded = True; nothing is written) }
      procedure Load(out Seeded: Boolean);
      { False, with the reason in Why, leaves the file as it was }
      function Save(out Why: String): Boolean;
      { '' when the rows can be saved, else what is wrong with which }
      function Check: String;

      class function FileName: String; static;
      { the lowest 8508A DC voltage range that holds Volts with a little to spare; 0 = none does }
      class function MeterRange(const Volts: Double): Double; static;
  end;

{ numbers as the file and the form write them: invariant, no trailing noise; '' for 0 }
function PlanText(const Value: Double): String;
{ '' counts as 0; False for anything that is not a number or is negative }
function PlanNumber(const Text: String; out Value: Double): Boolean;

implementation

const
  SECTION = 'Shunt%d';
  { a reading may go this far up a range before the next one is taken }
  RANGE_FILL = 0.99;
  RANGES: array [0..3] of Double = (0.2, 2, 20, 200);

function PlanText(const Value: Double): String;
begin
  if Value = 0 then Result := ''
  else Result := FloatToStrF(Value, ffGeneral, 10, 0, TFormatSettings.Invariant);
end;

function PlanNumber(const Text: String; out Value: Double): Boolean;
begin
  Value := 0;
  var S := Trim(Text);
  if S = '' then Exit(True);
  Result := TryStrToFloat(S, Value, TFormatSettings.Invariant) and (Value >= 0);
  if not Result then Value := 0;
end;

{ TPlanRow }

function TPlanRow.Planned: Boolean;
begin
  Result := (Standard > 0) and (Current > 0);
end;

function TPlanRow.StandardVolts: Double;
begin
  if Planned then Result := Standard * Current else Result := 0;
end;

function TPlanRow.ShuntVolts: Double;
begin
  if Planned then Result := Nominal * Current else Result := 0;
end;

function TPlanRow.Range: Double;
begin
  if Planned then Result := TShuntPlan.MeterRange(Max(StandardVolts, ShuntVolts)) else Result := 0;
end;

{ TShuntPlan }

class function TShuntPlan.FileName: String;
begin
  Result := ChangeFileExt(ParamStr(0), '.shunts.ini');
end;

class function TShuntPlan.MeterRange(const Volts: Double): Double;
begin
  Result := 0;
  if Volts <= 0 then Exit;
  for var R in RANGES do
    if Volts <= R * RANGE_FILL then Exit(R);
end;

procedure TShuntPlan.Seed;

  procedure Row(const Index: Integer; const Standard, Unc, Current: Double; const Note: String);
  begin
    Rows[Index].Standard := Standard;
    Rows[Index].StandardUnc := Unc;
    Rows[Index].Current := Current;
    Rows[Index].Note := Note;
  end;

const
  KNOWN = 'as the 2022 workbook';
  INFERRED = 'inferred from the 2022 workbook, to be confirmed';
  { the current is the given one; the standard is the one the 2022 workbook pairs with that current }
  GIVEN = 'current confirmed; standard as the 2022 workbook used at this current, to be confirmed';
begin
  Rows := Default(TPlanRows);
  for var I := PLAN_FIRST to PLAN_LAST do Rows[I].Nominal := SHUNT_VALUE[I];

  { the standards are the Ohm Labs set of the 2022 certificate (certified ohms, ppm at k = 2) }
  Row(1, 9999.733, 2.04, 0.00006, KNOWN);
  Row(2, 49999.67, 2.15, 0.000012, GIVEN);
  Row(3, 0.9992912, 2.09, 0.06, KNOWN);
  Row(4, 0.1000116, 3.44, 1.95, KNOWN);
  Row(5, 0.009999229, 10.85, 6, GIVEN);
  Row(6, 9.999291, 2.02, 0.012, INFERRED);
  Row(7, 499.975, 2.09, 0.00039, INFERRED);
  Row(8, 99.99935, 2.06, 0.00195, INFERRED);
end;

procedure TShuntPlan.Load(out Seeded: Boolean);

  function Number(const Ini: TMemIniFile; const Section, Key: String; const Default: Double): Double;
  begin
    if not PlanNumber(Ini.ReadString(Section, Key, PlanText(Default)), Result) then Result := Default;
  end;

begin
  Seed;
  Seeded := not FileExists(FileName);
  if Seeded then Exit;

  var Ini := TMemIniFile.Create(FileName);
  try
    for var I := PLAN_FIRST to PLAN_LAST do
    begin
      var S := Format(SECTION, [I]);
      { a shunt the file does not mention keeps its default row }
      if not Ini.SectionExists(S) then Continue;
      Rows[I].Nominal := Number(Ini, S, 'Nominal', Rows[I].Nominal);
      Rows[I].Standard := Number(Ini, S, 'Standard', 0);
      Rows[I].StandardUnc := Number(Ini, S, 'StandardUnc', 0);
      Rows[I].Current := Number(Ini, S, 'Current', 0);
      Rows[I].Note := Ini.ReadString(S, 'Note', '');
    end;
  finally
    Ini.Free;
  end;
end;

function TShuntPlan.Check: String;
begin
  Result := '';
  for var I := PLAN_FIRST to PLAN_LAST do
  begin
    var R := Rows[I];
    if R.Nominal <= 0 then Exit(Format('Shunt %d has no nominal value', [I]));
    if (R.Standard > 0) and (R.Current <= 0) then Exit(Format('Shunt %d has a standard but no current', [I]));
    if (R.Current > 0) and (R.Standard <= 0) then Exit(Format('Shunt %d has a current but no standard', [I]));
    if R.Planned and (R.Range = 0) then
      Exit(Format('Shunt %d: %.4g V is beyond the meters'' ranges', [I, Max(R.StandardVolts, R.ShuntVolts)]));
  end;
end;

function TShuntPlan.Save(out Why: String): Boolean;
begin
  Why := Check;
  Result := Why = '';
  if not Result then Exit;

  try
    var Ini := TMemIniFile.Create(FileName);
    try
      Ini.WriteInteger('Plan', 'Version', 1);
      for var I := PLAN_FIRST to PLAN_LAST do
      begin
        var S := Format(SECTION, [I]);
        Ini.WriteString(S, 'Nominal', PlanText(Rows[I].Nominal));
        Ini.WriteString(S, 'Standard', PlanText(Rows[I].Standard));
        Ini.WriteString(S, 'StandardUnc', PlanText(Rows[I].StandardUnc));
        Ini.WriteString(S, 'Current', PlanText(Rows[I].Current));
        Ini.WriteString(S, 'Note', Rows[I].Note);
      end;
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
    begin
      Why := E.Message;
      Result := False;
    end;
  end;
end;

end.
