unit MeterSheetU;

{
  The workbook's meter sheet ("8508A": "AutoCal using a Fluke 85x8A - all uncertainties expressed as a 95 %
  confidence where k = 2"): from a shunt's two voltages it works out the shunt's resistance and that
  resistance's uncertainty, which are the certificate's Measured Value and Unc. It is the "meter" member of
  the data file (AppConfigU.TAppData).

  Per shunt the sheet has a Ref row (the voltage across the standard) and a UUT row (the voltage across the
  shunt). The cells, by column, and how each is made here: a typed cell is an input, a formula cell is worked
  out by that same formula.

    col  member                  made
    D    ref_shunt_ohm           =Data!C, the standard's value
    E    dcv_range_V             typed: the meters' range (the Data sheet's column F)
    F    digits                  typed: digits of resolution
    G    recorded_V              =Data!M, the row's Average
    H    ppm_reading             typed: the meter's accuracy on that range
    I    ppm_range               typed
    J    resolution_V            =IF(F<1,F,10^(-1*F))
    K    repeatability_V         =Data!L
    L    unc_V                   =G*(H/1000000)+E*(I/1000000)
    M    cal_unc_V               typed: the meter's calibration uncertainty
    N    exp_unc_V               =2*SQRT(SUMSQ(L/2,J/SQRT(12),K,M/2))
    O    ppm                     =(N/G)*1000000
    P    calc_current_A          Ref row: =G/D
    Q    current_unc_A           Ref row: =SQRT(SUMSQ(N/G,'Ohm Labs'!F/D))*P
    R    calc_resistance_ohm     UUT row: =G/P
    S    resistance_unc_ppm      UUT row: =((R*SQRT(SUMSQ(N/G,Q/P)))/R)*1000000

  and under the two rows: Calc. Resistance =AVERAGE(R ref:R uut) and Unc. PPM =AVERAGE(S ref:S uut). The Ref
  row's R and S are empty, so each average is the UUT row's cell.

  The typed cells come from the configuration: E from the data entry, F, H, I and M from the meter type's
  sheet (FlukeMetersU), 'Ohm Labs'!F from the standard's entry (OhmLabsU).

  No VCL.
}

interface

uses
  System.SysUtils, System.Classes, System.Math, System.JSON, AppConfigU;

type
  { the cells of one shunt that are not formulas }
  TMeterInputs = record
    Shunt: Integer;                           { 1-based }
    Standard: Double;                         { D, ohms }
    RangeV: Double;                           { E, volts }
    Digits: Integer;                          { F }
    PpmReading, PpmRange: Double;             { H, I }
    CalUnc: Double;                           { M, volts }
    StandardUnc: Double;                      { 'Ohm Labs'!F: the standard's expanded uncertainty, ohms }
    RefG, RefK: Double;                       { G and K of the Ref row, volts }
    UutG, UutK: Double;                       { G and K of the UUT row, volts }
  end;

  { one row's formula cells }
  TMeterLine = record
    J, L, N, O: Double;
  end;

  TMeterAnswer = record
    Ok: Boolean;                              { False = a formula has no answer; Why says which }
    Why: String;
    Ref, Uut: TMeterLine;
    P, Q: Double;                             { Ref row }
    R, S: Double;                             { UUT row }

    function Resistance: Double;              { Calc. Resistance, ohms }
    function UncPpm: Double;                  { Unc. PPM }
  end;

{ the sheet's formulas for one shunt }
function SolveMeter(const A: TMeterInputs): TMeterAnswer;
{ the shunt as a member of the data file: the cells in the sheet's column order; null where a formula has no answer }
function MeterJson(const A: TMeterInputs; const Answer: TMeterAnswer): TJSONObject;

implementation

const
  DIGITS = 15;

{ =IF(F<1,F,10^(-1*F)) }
function Resolution(const F: Integer): Double;
var
  Ten: Double;
begin
  if F < 1 then Exit(F);
  Ten := 10;                                  { a literal 10 would take Power's Single overload }
  Result := Power(Ten, -1 * F);
end;

function TMeterAnswer.Resistance: Double;
begin
  Result := R;                                { AVERAGE of an empty cell and R }
end;

function TMeterAnswer.UncPpm: Double;
begin
  Result := S;
end;

function SolveMeter(const A: TMeterInputs): TMeterAnswer;

  { False = the row's O divides by a zero G }
  function Line(const G, K: Double; out Row: TMeterLine): Boolean;
  begin
    Row.J := Resolution(A.Digits);
    Row.L := G * (A.PpmReading / 1000000) + A.RangeV * (A.PpmRange / 1000000);
    Row.N := 2 * Sqrt(Sqr(Row.L / 2) + Sqr(Row.J / Sqrt(12)) + Sqr(K) + Sqr(A.CalUnc / 2));
    Result := G <> 0;
    if Result then Row.O := (Row.N / G) * 1000000 else Row.O := 0;
  end;

begin
  Result := Default(TMeterAnswer);
  if not Line(A.RefG, A.RefK, Result.Ref) then
  begin
    Result.Why := 'the reference voltage is 0';
    Exit;
  end;
  if not Line(A.UutG, A.UutK, Result.Uut) then
  begin
    Result.Why := 'the shunt voltage is 0';
    Exit;
  end;
  if A.Standard = 0 then
  begin
    Result.Why := 'no standard value';
    Exit;
  end;

  Result.P := A.RefG / A.Standard;
  Result.Q := Sqrt(Sqr(Result.Ref.N / A.RefG) + Sqr(A.StandardUnc / A.Standard)) * Result.P;
  { P cannot be 0 here: the reference voltage is not }
  Result.R := A.UutG / Result.P;
  if Result.R = 0 then
  begin
    Result.Why := 'the resistance works out to 0';
    Exit;
  end;
  Result.S := ((Result.R * Sqrt(Sqr(Result.Uut.N / A.UutG) + Sqr(Result.Q / Result.P))) / Result.R) * 1000000;
  Result.Ok := True;
end;

function MeterJson(const A: TMeterInputs; const Answer: TMeterAnswer): TJSONObject;

  procedure Formula(const Obj: TJSONObject; const Key: String; const Value: Double);
  begin
    if Answer.Ok then Obj.AddPair(Key, CfgJson(Value, DIGITS))
    else Obj.AddPair(Key, TJSONNull.Create);
  end;

  function Row(const Index: String; const G, K: Double; const L: TMeterLine): TJSONObject;
  begin
    Result := TJSONObject.Create;
    Result.AddPair('meas_index', Index);
    Result.AddPair('ref_shunt_ohm', CfgJson(A.Standard, DIGITS));
    Result.AddPair('dcv_range_V', CfgJson(A.RangeV));
    Result.AddPair('digits', TJSONNumber.Create(A.Digits));
    Result.AddPair('recorded_V', CfgJson(G, DIGITS));
    Result.AddPair('ppm_reading', CfgJson(A.PpmReading));
    Result.AddPair('ppm_range', CfgJson(A.PpmRange));
    Formula(Result, 'resolution_V', L.J);
    Result.AddPair('repeatability_V', CfgJson(K, DIGITS));
    Formula(Result, 'unc_V', L.L);
    Result.AddPair('cal_unc_V', CfgJson(A.CalUnc));
    Formula(Result, 'exp_unc_V', L.N);
    Formula(Result, 'ppm', L.O);
  end;

begin
  Result := TJSONObject.Create;
  Result.AddPair('slot', TJSONNumber.Create(A.Shunt));
  Result.AddPair('standard_unc_ohm', CfgJson(A.StandardUnc, DIGITS));

  var R := Row(Format('%d Ref', [A.Shunt]), A.RefG, A.RefK, Answer.Ref);
  Result.AddPair('ref', R);
  Formula(R, 'calc_current_A', Answer.P);
  Formula(R, 'current_unc_A', Answer.Q);

  var U := Row(Format('%d UUT', [A.Shunt]), A.UutG, A.UutK, Answer.Uut);
  Result.AddPair('uut', U);
  Formula(U, 'calc_resistance_ohm', Answer.R);
  Formula(U, 'resistance_unc_ppm', Answer.S);

  Formula(Result, 'calc_resistance_ohm', Answer.Resistance);
  Formula(Result, 'unc_ppm', Answer.UncPpm);
  if not Answer.Ok then Result.AddPair('no_answer', Answer.Why);
end;

end.
