unit CalDataU;

{
  The measurements: the LDF-78 workbook's "Data" sheet, now the "data" section of the data file
  (<exe name>.data.json, AppConfigU.TAppData). One entry per shunt; accepting a shunt again replaces its entry.

  The sheet is reproduced cell for cell: what a cell held as a constant or a typed figure is an input here, and
  what it held as a formula is worked out here by that same formula, term for term. Per shunt the sheet has two
  rows, "n Ref" (VSTD, volts across the standard resistor) and "n UUT" (VDUT, volts across the shunt, same
  current, same instant). With C and D of the UUT row (the standard's ohms and the current command) and L2 (the
  number of samples behind each mean):

    col  member              Ref row                                  UUT row
    B    shunt               "AC-n" (once, for both rows)
    C    standard            the standard's name, "10 k(ohm)"         standard_ohm, the standard's value
    D                        (the tester range's name: not kept)      current_A, the current command
    E    signal              "VSTD"                                   "VDUT"
    F    dmm_range_V         =IFS(C*D<0.2, 0.2, C*D<2, 2)             the same formula
    G    expected_V          =C*D-(1/1000000)                         =nominal*D-(1/1000000)
    H    charge_V            typed: the measurement
    I    charge_dev_ppm      typed
    J    discharge_V         typed
    K    discharge_dev_ppm   typed
    L    repeatability_V     =AVERAGE(H*I/1000000,ABS(J*K/1000000))/SQRT($L$2)
    M    average_V           =(H-J)/2
    N    rdut_ohm                                                     =C*(M uut/M ref)
    O    meas_index          "n Ref"                                  "n UUT"
    L2   samples             (kept per shunt: the count that was in force when it was accepted)

  Where the sheet's formula has no answer (IFS with neither condition true, a division by zero) the member is null.
  The formulas are kept as the sheet has them, quirks included: column L takes H*I as it is and only J*K by
  its absolute value, and RDUT carries the sign of the ratio.

  Two things the sheet had as constants come from the shunt plan instead, because the sheet's were those of the
  2022 shunt set: the nominal value in the UUT row's G formula, and the standard's name in the Ref row's C
  (written from the standard's value). The Ref row's D, the tester range's name, has no source here.

  No VCL.
}

interface

uses
  System.SysUtils, System.Classes, System.Math, System.DateUtils, System.Generics.Collections, System.JSON, AppConfigU;

type
  { the four typed cells of a row, H to K }
  TDataRow = record
    Charge, ChargeDev: Double;                { V, and the readings' standard deviation in ppm of it }
    Discharge, DischargeDev: Double;

    function Average: Double;                 { column M }
    function Repeatability(const Samples: Integer; out Volts: Double): Boolean;     { column L; False = no answer }
  end;

  TDataShunt = record
    Shunt: Integer;                           { 1-based }
    Accepted: TDateTime;                      { local time; 0 = not known }
    Samples: Integer;                         { L2 }
    Nominal: Double;                          { the shunt's nominal ohms: the constant of the UUT row's G formula }
    Standard: Double;                         { C of the UUT row, ohms }
    Current: Double;                          { D of the UUT row, amps }
    Ref, Uut: TDataRow;

    function DmmRange(out Volts: Double): Boolean;          { column F, both rows; False = no answer }
    function ExpectedRef: Double;                           { column G of the Ref row }
    function ExpectedUut: Double;                           { column G of the UUT row }
    function RDut(out Ohms: Double): Boolean;               { column N; False = no answer }
    function Label_: String;                                { column B, 'AC-1' }
    function StandardName: String;                          { column C of the Ref row, '10 k(ohm)' }
  end;
  TDataShunts = TArray<TDataShunt>;

  TCalData = class(TObject)
    public
      { the entries in the file's order. False, with the reason in Why, when the file or the section cannot be used; no file yet = True and none }
      class function Load(out Entries: TDataShunts; out Why: String): Boolean; static;
      { puts Entry in place of its shunt's (or adds it), the entries in shunt order. False, with the reason in Why, leaves the file as it was }
      class function Put(const Entry: TDataShunt; out Why: String): Boolean; static;
  end;

implementation

const
  K_SECTION = 'data';
  K_SHUNTS = 'shunts';
  K_SLOT = 'slot';
  K_SHUNT = 'shunt';
  K_ACCEPTED = 'accepted';
  K_SAMPLES = 'samples';
  K_NOMINAL = 'nominal_ohm';
  K_REF = 'ref';
  K_UUT = 'uut';
  K_INDEX = 'meas_index';
  K_SIGNAL = 'signal';
  K_STANDARD_NAME = 'standard';
  K_STANDARD = 'standard_ohm';
  K_CURRENT = 'current_A';
  K_RANGE = 'dmm_range_V';
  K_EXPECTED = 'expected_V';
  K_CHARGE = 'charge_V';
  K_CHARGE_DEV = 'charge_dev_ppm';
  K_DISCHARGE = 'discharge_V';
  K_DISCHARGE_DEV = 'discharge_dev_ppm';
  K_REPEAT = 'repeatability_V';
  K_AVERAGE = 'average_V';
  K_RDUT = 'rdut_ohm';
  { readings and what follows from them at the 15 significant digits a cell shows }
  DIGITS = 15;
  OHM = #$03A9;

{ TDataRow }

{ =IF(AND(H<>"",J<>""),(H-J)/2,"") : both are always there by the time a shunt is accepted }
function TDataRow.Average: Double;
begin
  Result := (Charge - Discharge) / 2;
end;

{ =AVERAGE(H*I/1000000,ABS(J*K/1000000))/SQRT($L$2) }
function TDataRow.Repeatability(const Samples: Integer; out Volts: Double): Boolean;
begin
  Volts := 0;
  Result := Samples > 0;                      { SQRT(0) under a division: #DIV/0! }
  if not Result then Exit;
  var A := Charge * ChargeDev / 1000000;
  var B := Abs(Discharge * DischargeDev / 1000000);
  Volts := ((A + B) / 2) / Sqrt(Samples);
end;

{ TDataShunt }

{ =_xlfn.IFS(C*D<0.2, 0.2, C*D<2, 2) : #N/A when the product is 2 or more }
function TDataShunt.DmmRange(out Volts: Double): Boolean;
begin
  Result := True;
  var P := Standard * Current;
  if P < 0.2 then Volts := 0.2
  else if P < 2 then Volts := 2
  else
  begin
    Volts := 0;
    Result := False;
  end;
end;

{ =C*D-(1/1000000) }
function TDataShunt.ExpectedRef: Double;
begin
  Result := Standard * Current - (1 / 1000000);
end;

{ =10000*D-(1/1000000), the 10000 being the shunt's nominal value }
function TDataShunt.ExpectedUut: Double;
begin
  Result := Nominal * Current - (1 / 1000000);
end;

{ =IF(AND(M ref<>"",M uut<>""),C*(M uut/M ref),"") }
function TDataShunt.RDut(out Ohms: Double): Boolean;
begin
  Ohms := 0;
  var MRef := Ref.Average;
  Result := MRef <> 0;                        { #DIV/0! }
  if Result then Ohms := Standard * (Uut.Average / MRef);
end;

function TDataShunt.Label_: String;
begin
  Result := Format('AC-%d', [Shunt]);
end;

{ the standard by its round value, as the sheet titled it: 9999.733 -> '10 k(ohm)', 0.1000116 -> '0.1 (ohm)' }
function TDataShunt.StandardName: String;
begin
  if Standard <= 0 then Exit('');
  var Round2 := StrToFloat(FloatToStrF(Standard, ffExponent, 2, 0, TFormatSettings.Invariant), TFormatSettings.Invariant);
  if Round2 >= 1000 then Result := FloatToStrF(Round2 / 1000, ffGeneral, 6, 0, TFormatSettings.Invariant) + ' k' + OHM
  else Result := FloatToStrF(Round2, ffGeneral, 6, 0, TFormatSettings.Invariant) + ' ' + OHM;
end;

{ TCalData }

{ a formula's answer, or null where the sheet's cell would show an error }
procedure AddAnswer(const Obj: TJSONObject; const Key: String; const Ok: Boolean; const Value: Double);
begin
  if Ok then Obj.AddPair(Key, CfgJson(Value, DIGITS))
  else Obj.AddPair(Key, TJSONNull.Create);
end;

procedure AddTyped(const Obj: TJSONObject; const Row: TDataRow);
begin
  Obj.AddPair(K_CHARGE, CfgJson(Row.Charge, DIGITS));
  Obj.AddPair(K_CHARGE_DEV, CfgJson(Row.ChargeDev, DIGITS));
  Obj.AddPair(K_DISCHARGE, CfgJson(Row.Discharge, DIGITS));
  Obj.AddPair(K_DISCHARGE_DEV, CfgJson(Row.DischargeDev, DIGITS));
end;

function EntryJson(const E: TDataShunt): TJSONObject;
var
  Range, Repeat_, Ohms: Double;
begin
  Result := TJSONObject.Create;
  Result.AddPair(K_SLOT, TJSONNumber.Create(E.Shunt));
  Result.AddPair(K_SHUNT, E.Label_);
  if E.Accepted <> 0 then
    Result.AddPair(K_ACCEPTED, FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', E.Accepted, TFormatSettings.Invariant));
  Result.AddPair(K_SAMPLES, TJSONNumber.Create(E.Samples));
  Result.AddPair(K_NOMINAL, CfgJson(E.Nominal, DIGITS));
  var HaveRange := E.DmmRange(Range);

  { the members in the sheet's column order }
  var R := TJSONObject.Create;
  Result.AddPair(K_REF, R);
  R.AddPair(K_STANDARD_NAME, E.StandardName);
  R.AddPair(K_SIGNAL, 'VSTD');
  AddAnswer(R, K_RANGE, HaveRange, Range);
  R.AddPair(K_EXPECTED, CfgJson(E.ExpectedRef, DIGITS));
  AddTyped(R, E.Ref);
  AddAnswer(R, K_REPEAT, E.Ref.Repeatability(E.Samples, Repeat_), Repeat_);
  R.AddPair(K_AVERAGE, CfgJson(E.Ref.Average, DIGITS));
  R.AddPair(K_INDEX, Format('%d Ref', [E.Shunt]));

  var U := TJSONObject.Create;
  Result.AddPair(K_UUT, U);
  U.AddPair(K_STANDARD, CfgJson(E.Standard, DIGITS));
  U.AddPair(K_CURRENT, CfgJson(E.Current, DIGITS));
  U.AddPair(K_SIGNAL, 'VDUT');
  AddAnswer(U, K_RANGE, HaveRange, Range);
  U.AddPair(K_EXPECTED, CfgJson(E.ExpectedUut, DIGITS));
  AddTyped(U, E.Uut);
  AddAnswer(U, K_REPEAT, E.Uut.Repeatability(E.Samples, Repeat_), Repeat_);
  U.AddPair(K_AVERAGE, CfgJson(E.Uut.Average, DIGITS));
  AddAnswer(U, K_RDUT, E.RDut(Ohms), Ohms);
  U.AddPair(K_INDEX, Format('%d UUT', [E.Shunt]));
end;

{ the typed cells of a row: the worked-out members are not read back, they are worked out again }
function RowOf(const Obj: TJSONObject; const Key: String; out O: TJSONObject): TDataRow;
begin
  Result := Default(TDataRow);
  if not Obj.TryGetValue<TJSONObject>(Key, O) then
  begin
    O := nil;
    Exit;
  end;
  Result.Charge := CfgDouble(O, K_CHARGE, 0);
  Result.ChargeDev := CfgDouble(O, K_CHARGE_DEV, 0);
  Result.Discharge := CfgDouble(O, K_DISCHARGE, 0);
  Result.DischargeDev := CfgDouble(O, K_DISCHARGE_DEV, 0);
end;

class function TCalData.Load(out Entries: TDataShunts; out Why: String): Boolean;
var
  Arr: TJSONArray;
  E: TDataShunt;
  RefObj, UutObj: TJSONObject;
begin
  Entries := nil;
  var Section := TAppData.ReadSection(K_SECTION, Why);
  if Section = nil then Exit(Why = '');

  try
    if not Section.TryGetValue<TJSONArray>(K_SHUNTS, Arr) then
    begin
      Why := Format('"%s" has no "%s"', [K_SECTION, K_SHUNTS]);
      Exit(False);
    end;

    for var V in Arr do
    begin
      if not (V is TJSONObject) then Continue;
      var O := TJSONObject(V);
      E := Default(TDataShunt);
      E.Shunt := Round(CfgDouble(O, K_SLOT, 0));
      if E.Shunt < 1 then
      begin
        Why := Format('"%s" has an entry with no "%s"', [K_SECTION, K_SLOT]);
        Entries := nil;
        Exit(False);
      end;
      var Stamp := '';
      if O.TryGetValue<String>(K_ACCEPTED, Stamp) then
        { True = as written: the stamp is local time with no zone, and must not be shifted as if it were UTC }
        if not TryISO8601ToDate(Stamp, E.Accepted, True) then E.Accepted := 0;
      E.Samples := Round(CfgDouble(O, K_SAMPLES, 0));
      E.Nominal := CfgDouble(O, K_NOMINAL, 0);
      E.Ref := RowOf(O, K_REF, RefObj);
      E.Uut := RowOf(O, K_UUT, UutObj);
      if UutObj <> nil then
      begin
        E.Standard := CfgDouble(UutObj, K_STANDARD, 0);
        E.Current := CfgDouble(UutObj, K_CURRENT, 0);
      end;
      Entries := Entries + [E];
    end;
    Result := True;
  finally
    Section.Free;
  end;
end;

class function TCalData.Put(const Entry: TDataShunt; out Why: String): Boolean;
var
  Entries: TDataShunts;
begin
  if Entry.Shunt < 1 then
  begin
    Why := 'the entry names no shunt';
    Exit(False);
  end;
  { a section that cannot be read is not built upon: the entries it may hold would be lost }
  if not Load(Entries, Why) then Exit(False);

  var Section := TJSONObject.Create;
  var Arr := TJSONArray.Create;
  Section.AddPair(K_SHUNTS, Arr);

  { in shunt order, this one in its place }
  var Placed := False;
  for var E in Entries do
  begin
    if E.Shunt = Entry.Shunt then Continue;
    if (not Placed) and (E.Shunt > Entry.Shunt) then
    begin
      Arr.AddElement(EntryJson(Entry));
      Placed := True;
    end;
    Arr.AddElement(EntryJson(E));
  end;
  if not Placed then Arr.AddElement(EntryJson(Entry));

  Result := TAppData.WriteSection(K_SECTION, Section, Why);
end;

end.
