unit FlukeMetersU;

{
  The Fluke meter types the bench measures with (8508A and 8588A, a pair of each) and what the software keeps
  about them:

    digits of resolution    what the meter is set to while connected (RESLn); it is also the resolution term of
                            the uncertainty budget (10^-digits volts)
    per meter of the pair   its serial number and the date its calibration is due: the certificate's
                            "Standards used" lines, with the manufacturer and the model
    DC voltage accuracy     per range, ppm of reading + ppm of range and the calibration uncertainty in volts:
                            what the workbook's meter sheet budgets each voltage with (its columns H, I and M)

  The figures live in the "meters" section of the configuration file (AppConfigU). Seed holds what the LDF-78
  workbook of December 2022 had: the two 8508A serials and due dates of its certificate, and the 0.2 V and 2 V
  accuracy rows of its meter sheet (given to both types: the workbook has the one sheet).

  No VCL. The form is FlukeFrameU.
}

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections, System.JSON, AppConfigU;

const
  FLUKE_UNITS = 2;                            { meters of a type on the bench }
  FLUKE_MIN_DIGITS = 5;                       { RESL5 .. RESL8 }
  FLUKE_MAX_DIGITS = 8;
  FLUKE_MANUFACTURER = 'Fluke';

type
  TFlukeModel = (fm8508A, fm8588A);

  TFlukeUnit = record
    Serial: String;                           { '' = not given }
    Due: TDate;                               { calibration due; 0 = not given }

    { a due date is given and Today is past it }
    function Overdue(const Today: TDate): Boolean;
  end;

  TFlukeRange = record
    RangeV: Double;                           { the DC voltage range, volts }
    PpmReading: Double;
    PpmRange: Double;
    CalUnc: Double;                           { the meter's calibration uncertainty on the range, volts at k = 2 }
  end;
  TFlukeRanges = TArray<TFlukeRange>;

  TFlukeMeter = record
    Digits: Integer;
    { 8588A only: spoken to in its own SCPI (the meter's Emulation set to None) instead of as an 8508A }
    Scpi: Boolean;
    Units: array [0..FLUKE_UNITS -1] of TFlukeUnit;
    Ranges: TFlukeRanges;

    { volts }
    function Resolution: Double;
    { the accuracy row of a range; False when the meter has none for it }
    function RangeSpec(const RangeV: Double; out Spec: TFlukeRange): Boolean;
  end;
  TFlukeMeterSet = array [TFlukeModel] of TFlukeMeter;

  TFlukeMeters = class(TObject)
    public
      Meters: TFlukeMeterSet;

      class function Defaults(const Model: TFlukeModel): TFlukeMeter; static;
      procedure Seed;
      {
        True = Meters hold the saved section. False = they hold the defaults: Why = '' when nothing is saved
        yet, else what is wrong with the file. A type the section does not name keeps its defaults
      }
      function Load(out Why: String): Boolean;
      { one type is written, the other is carried over as the file has it. False, with the reason in Why, leaves the file as it was }
      function Save(const Model: TFlukeModel; out Why: String): Boolean;
      { '' when the type can be saved, else what is wrong with it }
      function Check(const Model: TFlukeModel): String;

      { the digits of resolution to use now: what is saved for the type, else its default }
      class function SavedDigits(const Model: TFlukeModel): Integer; static;
      { whether the type is to be spoken to in native SCPI now: what is saved for it; never for a type without the choice }
      class function SavedScpi(const Model: TFlukeModel): Boolean; static;
  end;

const
  FLUKE_MODEL_NAME: array [TFlukeModel] of String = ('8508A', '8588A');
  FLUKE_DEFAULT_DIGITS: array [TFlukeModel] of Integer = (7, 8);
  { the types that have a command set of their own besides the 8508A's }
  FLUKE_HAS_SCPI: array [TFlukeModel] of Boolean = (False, True);

implementation

const
  K_SECTION = 'meters';
  K_MODELS = 'models';
  K_MANUFACTURER = 'manufacturer';
  K_MODEL = 'model';
  K_DIGITS = 'digits';
  K_PROTOCOL = 'protocol';                    { 8588A: V_SCPI or V_8508A; absent = V_8508A }
  V_SCPI = 'scpi';
  V_8508A = '8508a';
  K_UNITS = 'units';
  K_SERIAL = 'serial';
  K_DUE = 'cal_due';
  K_RANGES = 'dcv_accuracy';
  K_RANGE = 'range_V';
  K_PPM_READING = 'ppm_reading';
  K_PPM_RANGE = 'ppm_range';
  K_CAL_UNC = 'cal_unc_V';

{ TFlukeUnit }

function TFlukeUnit.Overdue(const Today: TDate): Boolean;
begin
  Result := (Due <> 0) and (Today > Due);
end;

{ TFlukeMeter }

function TFlukeMeter.Resolution: Double;
var
  Ten: Double;
begin
  Ten := 10;                                  { a literal 10 would take Power's Single overload }
  Result := Power(Ten, -Digits);
end;

function TFlukeMeter.RangeSpec(const RangeV: Double; out Spec: TFlukeRange): Boolean;
begin
  for var R in Ranges do
    if SameValue(R.RangeV, RangeV, RangeV * 1E-6) then
    begin
      Spec := R;
      Exit(True);
    end;
  Spec := Default(TFlukeRange);
  Result := False;
end;

{ TFlukeMeters }

class function TFlukeMeters.Defaults(const Model: TFlukeModel): TFlukeMeter;

  procedure Range(const RangeV, PpmReading, PpmRange: Double);
  var
    R: TFlukeRange;
  begin
    R.CalUnc := 0;                            { column M: 0 on every row of the sheet }
    R.RangeV := RangeV;
    R.PpmReading := PpmReading;
    R.PpmRange := PpmRange;
    Result.Ranges := Result.Ranges + [R];
  end;

begin
  Result := Default(TFlukeMeter);
  Result.Digits := FLUKE_DEFAULT_DIGITS[Model];

  { the workbook's meter sheet, columns E (range), H (ppm reading), I (ppm range) }
  Range(0.2, 4.5, 0.6);
  Range(2, 3, 0.3);

  { its certificate's "Standards used", rows 29 and 30 }
  if Model = fm8508A then
  begin
    Result.Units[0].Serial := '431874115';
    Result.Units[0].Due := EncodeDate(2023, 10, 11);
    Result.Units[1].Serial := '431874139';
    Result.Units[1].Due := EncodeDate(2023, 10, 10);
  end;
end;

procedure TFlukeMeters.Seed;
begin
  for var M := Low(TFlukeModel) to High(TFlukeModel) do Meters[M] := Defaults(M);
end;

function TFlukeMeters.Check(const Model: TFlukeModel): String;
begin
  Result := '';
  var Name := FLUKE_MODEL_NAME[Model];
  var Meter := Meters[Model];
  if (Meter.Digits < FLUKE_MIN_DIGITS) or (Meter.Digits > FLUKE_MAX_DIGITS) then
    Exit(Format('%s: digits of resolution must be %d to %d', [Name, FLUKE_MIN_DIGITS, FLUKE_MAX_DIGITS]));

  for var I := 0 to High(Meter.Ranges) do
  begin
    var R := Meter.Ranges[I];
    if R.RangeV <= 0 then Exit(Format('%s accuracy row %d has no range', [Name, I +1]));
    if (R.PpmReading < 0) or (R.PpmRange < 0) or (R.CalUnc < 0) then Exit(Format('%s accuracy row %d has a negative figure', [Name, I +1]));
    for var J := 0 to I -1 do
      if SameValue(Meter.Ranges[J].RangeV, R.RangeV, R.RangeV * 1E-6) then
        Exit(Format('%s has the %s V range twice', [Name, CfgText(R.RangeV)]));
  end;
end;

function TFlukeMeters.Load(out Why: String): Boolean;
var
  Loaded: TFlukeMeterSet;
  Have: set of TFlukeModel;
  Arr, Items: TJSONArray;

  function One(const Model: TFlukeModel; const Obj: TJSONObject): Boolean;
  var
    M: TFlukeMeter;
    R: TFlukeRange;
  begin
    Result := False;
    var Name := Format('"%s" %s', [K_SECTION, FLUKE_MODEL_NAME[Model]]);
    M := Default(TFlukeMeter);
    M.Digits := Round(CfgDouble(Obj, K_DIGITS, FLUKE_DEFAULT_DIGITS[Model]));
    if (M.Digits < FLUKE_MIN_DIGITS) or (M.Digits > FLUKE_MAX_DIGITS) then
    begin
      Why := Format('%s: "%s" must be %d to %d', [Name, K_DIGITS, FLUKE_MIN_DIGITS, FLUKE_MAX_DIGITS]);
      Exit;
    end;

    var Protocol := '';
    if FLUKE_HAS_SCPI[Model] and Obj.TryGetValue<String>(K_PROTOCOL, Protocol) then
    begin
      M.Scpi := SameText(Trim(Protocol), V_SCPI);
      if not (M.Scpi or SameText(Trim(Protocol), V_8508A)) then
      begin
        Why := Format('%s: "%s" must be "%s" or "%s"', [Name, K_PROTOCOL, V_8508A, V_SCPI]);
        Exit;
      end;
    end;

    { the meters of the pair, in their order; one the file does not give stays blank }
    if Obj.TryGetValue<TJSONArray>(K_UNITS, Items) then
      for var I := 0 to Min(Items.Count, FLUKE_UNITS) -1 do
      begin
        if not (Items.Items[I] is TJSONObject) then Continue;
        var U := TJSONObject(Items.Items[I]);
        var Text := '';
        if U.TryGetValue<String>(K_SERIAL, Text) then M.Units[I].Serial := Trim(Text);
        if not CfgDateOf(U, K_DUE, M.Units[I].Due) then
        begin
          Why := Format('%s meter %d: "%s" is not yyyy-mm-dd', [Name, I +1, K_DUE]);
          Exit;
        end;
      end;

    if Obj.TryGetValue<TJSONArray>(K_RANGES, Items) then
      for var V in Items do
      begin
        if not (V is TJSONObject) then Continue;
        R.RangeV := CfgDouble(TJSONObject(V), K_RANGE, 0);
        R.PpmReading := CfgDouble(TJSONObject(V), K_PPM_READING, 0);
        R.PpmRange := CfgDouble(TJSONObject(V), K_PPM_RANGE, 0);
        R.CalUnc := CfgDouble(TJSONObject(V), K_CAL_UNC, 0);
        if (R.RangeV <= 0) or (R.PpmReading < 0) or (R.PpmRange < 0) or (R.CalUnc < 0) then
        begin
          Why := Format('%s accuracy row %d needs "%s" above 0 and no negative figure', [Name, Length(M.Ranges) +1, K_RANGE]);
          Exit;
        end;
        M.Ranges := M.Ranges + [R];
      end;

    Loaded[Model] := M;
    Result := True;
  end;

begin
  Seed;
  Result := False;
  var Section := TAppConfig.ReadSection(K_SECTION, Why);
  if Section = nil then Exit;

  try
    if not Section.TryGetValue<TJSONArray>(K_MODELS, Arr) then
    begin
      Why := Format('"%s" has no "%s"', [K_SECTION, K_MODELS]);
      Exit;
    end;

    Have := [];
    for var V in Arr do
    begin
      if not (V is TJSONObject) then Continue;
      var Name := '';
      if not TJSONObject(V).TryGetValue<String>(K_MODEL, Name) then Continue;
      for var M := Low(TFlukeModel) to High(TFlukeModel) do
        if SameText(Trim(Name), FLUKE_MODEL_NAME[M]) then
        begin
          if not One(M, TJSONObject(V)) then Exit;
          Include(Have, M);
        end;
    end;

    { nothing is taken from a section that has a fault anywhere }
    for var M := Low(TFlukeModel) to High(TFlukeModel) do
      if M in Have then Meters[M] := Loaded[M];
    Result := True;
  finally
    Section.Free;
  end;
end;

function TFlukeMeters.Save(const Model: TFlukeModel; out Why: String): Boolean;
var
  Saved: TFlukeMeters;
  Ignore: String;
begin
  Why := Check(Model);
  if Why <> '' then Exit(False);

  { each type has its own sheet and its own Save: the other type goes back as the file has it, not as this object does }
  Saved := TFlukeMeters.Create;
  try
    Saved.Load(Ignore);
    Saved.Meters[Model] := Meters[Model];

    var Section := TJSONObject.Create;
    var Arr := TJSONArray.Create;
    Section.AddPair(K_MODELS, Arr);

    for var M := Low(TFlukeModel) to High(TFlukeModel) do
    begin
      var Meter := Saved.Meters[M];
      var Obj := TJSONObject.Create;
      Arr.AddElement(Obj);
      Obj.AddPair(K_MANUFACTURER, FLUKE_MANUFACTURER);
      Obj.AddPair(K_MODEL, FLUKE_MODEL_NAME[M]);
      Obj.AddPair(K_DIGITS, TJSONNumber.Create(Meter.Digits));
      if FLUKE_HAS_SCPI[M] then
      begin
        if Meter.Scpi then Obj.AddPair(K_PROTOCOL, V_SCPI) else Obj.AddPair(K_PROTOCOL, V_8508A);
      end;

      var Units := TJSONArray.Create;
      Obj.AddPair(K_UNITS, Units);
      for var I := 0 to FLUKE_UNITS -1 do
      begin
        { a meter with nothing given is still written, as an empty object: the pair keeps its order }
        var U := TJSONObject.Create;
        Units.AddElement(U);
        if Meter.Units[I].Serial <> '' then U.AddPair(K_SERIAL, Meter.Units[I].Serial);
        if Meter.Units[I].Due <> 0 then U.AddPair(K_DUE, CfgDate(Meter.Units[I].Due));
      end;

      var Ranges := TJSONArray.Create;
      Obj.AddPair(K_RANGES, Ranges);
      for var R in Meter.Ranges do
      begin
        var O := TJSONObject.Create;
        Ranges.AddElement(O);
        O.AddPair(K_RANGE, CfgJson(R.RangeV));
        O.AddPair(K_PPM_READING, CfgJson(R.PpmReading));
        O.AddPair(K_PPM_RANGE, CfgJson(R.PpmRange));
        O.AddPair(K_CAL_UNC, CfgJson(R.CalUnc));
      end;
    end;

    Result := TAppConfig.WriteSection(K_SECTION, Section, Why);
  finally
    Saved.Free;
  end;
end;

class function TFlukeMeters.SavedDigits(const Model: TFlukeModel): Integer;
var
  Why: String;
begin
  var All := TFlukeMeters.Create;
  try
    All.Load(Why);                            { a missing or faulty section leaves the defaults }
    Result := All.Meters[Model].Digits;
  finally
    All.Free;
  end;
end;

class function TFlukeMeters.SavedScpi(const Model: TFlukeModel): Boolean;
var
  Why: String;
begin
  var All := TFlukeMeters.Create;
  try
    All.Load(Why);
    Result := FLUKE_HAS_SCPI[Model] and All.Meters[Model].Scpi;
  finally
    All.Free;
  end;
end;

end.
