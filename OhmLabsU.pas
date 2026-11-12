unit OhmLabsU;

{
  The Ohm Labs standard resistors: the reference a shunt is measured against. Three sets, as the LDF-78
  workbook's "Ohm Labs" sheet had them: the MRS decade resistors (0.1 ohm to 50 k) and the two MCS current
  shunts (0.01 ohm and 0.001 ohm), each MCS certified at five currents.

  Per set: the date its calibration is due (optional). Per standard the curated figures are the certified
  value, the 12-month stability and the certificate's uncertainty (both ppm, the uncertainty at k = 2). The expanded uncertainty is not stored, it follows:

    Unc (ppm) = sqrt(stability^2 + certificate uncertainty^2)        Unc (ohm) = actual x Unc (ppm) / 1e6

  which is the sheet's SQRT(SUMSQ(C*E*0.000001, C*(D/1000000))).

  The figures live in the "ohmLabs" section of the configuration file (AppConfigU), always in ohms and amps.
  Seed holds the sheet's figures of the December 2022 workbook and is what shows until a section is saved.

  No VCL. The form is OhmLabsFrameU.
}

interface

uses
  System.SysUtils, System.Classes, System.Math, System.JSON, AppConfigU;

type
  TOhmSetId = (osMRS, osMCS10, osMCS1);

  TOhmStandard = record
    Nominal: Double;                          { ohms }
    Current: Double;                          { amps the value is certified at; 0 = not tied to a current }
    Actual: Double;                           { certified ohms }
    Stability: Double;                        { 12-month stability, ppm }
    CertUnc: Double;                          { the certificate's uncertainty, ppm (micro-ohm per ohm) at k = 2 }

    function UncPpm: Double;                  { expanded, k = 2 }
    function UncOhms: Double;
    { '10000', or '0.01 @ 6A' for a value certified at a current }
    function Caption: String;
    { the reverse of Caption; False when Text is not that or the nominal is not above 0 }
    class function Parse(const Text: String; out Nominal, Current: Double): Boolean; static;
  end;
  TOhmStandards = TArray<TOhmStandard>;
  TOhmSets = array [TOhmSetId] of TOhmStandards;

  { what is kept of a set besides its figures: when its calibration is due. The seed has none }
  TOhmSetInfo = record
    Due: TDate;                               { 0 = not given }

    { a due date is given and Today is past it }
    function Overdue(const Today: TDate): Boolean;
  end;
  TOhmSetInfos = array [TOhmSetId] of TOhmSetInfo;

  TOhmLabs = class(TObject)
    public
      Sets: TOhmSets;
      Info: TOhmSetInfos;

      { the worksheet's figures }
      procedure Seed;
      {
        True = Sets hold the saved section. False = they hold the defaults: Why = '' when nothing is saved yet,
        else what is wrong with the file. A set the section does not name keeps its defaults
      }
      function Load(out Why: String): Boolean;
      { False, with the reason in Why, leaves the file as it was }
      function Save(out Why: String): Boolean;
      { '' when the sets can be saved, else what is wrong with which row }
      function Check: String;
      { the standard whose certified value is Ohms (to a part in a million), whichever set it is in }
      function Find(const Ohms: Double; out S: TOhmStandard): Boolean; overload;
      { the same, and the set it is in }
      function Find(const Ohms: Double; out S: TOhmStandard; out Id: TOhmSetId): Boolean; overload;
  end;

const
  OHM_SET_NAME: array [TOhmSetId] of String = ('MRS', 'MCS 0.01', 'MCS 0.001');
  { the MCS values are read in milliohms, as their certificates and the worksheet give them }
  OHM_SET_SCALE: array [TOhmSetId] of Double = (1, 1000, 1000);

implementation

const
  K_SECTION = 'ohmLabs';
  K_SETS = 'sets';
  K_NAME = 'name';
  K_STANDARDS = 'standards';
  K_NOMINAL = 'nominal_ohm';
  K_CURRENT = 'current_A';
  K_ACTUAL = 'actual_ohm';
  K_STABILITY = 'stability_12mo_ppm';
  K_CERT_UNC = 'cert_unc_ppm';
  K_COVERAGE = 'coverage_k';
  K_DUE = 'due';

{ TOhmSetInfo }

function TOhmSetInfo.Overdue(const Today: TDate): Boolean;
begin
  Result := (Due <> 0) and (Today > Due);
end;

{ TOhmStandard }

{ the sheet's column G, =((C+F)-C)/C*1000000, as it stands there }
function TOhmStandard.UncPpm: Double;
begin
  if Actual = 0 then Exit(0);
  Result := ((Actual + UncOhms) - Actual) / Actual * 1000000;
end;

{ the sheet's column F, =SQRT(SUMSQ(C*E*0.000001,C*(D/1000000))), as it stands there }
function TOhmStandard.UncOhms: Double;
begin
  Result := Sqrt(Sqr(Actual * CertUnc * 0.000001) + Sqr(Actual * (Stability / 1000000)));
end;

function TOhmStandard.Caption: String;
begin
  Result := CfgText(Nominal);
  if Current > 0 then Result := Result + ' @ ' + CfgText(Current) + 'A';
end;

class function TOhmStandard.Parse(const Text: String; out Nominal, Current: Double): Boolean;
begin
  Nominal := 0;
  Current := 0;
  var Left := Trim(Text);
  var Right := '';
  var At := Pos('@', Left);
  if At > 0 then
  begin
    Right := Trim(Copy(Left, At +1, MaxInt));
    Left := Trim(Copy(Left, 1, At -1));
    if Right.EndsWith('A', True) then Right := Trim(Copy(Right, 1, Length(Right) -1));
    if Right = '' then Exit(False);                 { an '@' with no current after it }
  end;

  Result := (Left <> '') and CfgNumber(Left, Nominal) and (Nominal > 0)
    and ((At = 0) or (CfgNumber(Right, Current) and (Current > 0)));
  if not Result then
  begin
    Nominal := 0;
    Current := 0;
  end;
end;

{ TOhmLabs }

procedure TOhmLabs.Seed;

  procedure Add(const Id: TOhmSetId; const Nominal, Current, Actual, Stability, CertUnc: Double);
  var
    S: TOhmStandard;
  begin
    S.Nominal := Nominal;
    S.Current := Current;
    S.Actual := Actual;
    S.Stability := Stability;
    S.CertUnc := CertUnc;
    Sets[Id] := Sets[Id] + [S];
  end;

begin
  for var Id := Low(TOhmSetId) to High(TOhmSetId) do Sets[Id] := nil;
  Info := Default(TOhmSetInfos);

  { "Ohm Labs" sheet rows 3..9 }
  Add(osMRS, 50000, 0, 49999.67, 2, 0.8);
  Add(osMRS, 10000, 0, 9999.733, 2, 0.4);
  Add(osMRS, 500, 0, 499.975, 2, 0.6);
  Add(osMRS, 100, 0, 99.99935, 2, 0.5);
  Add(osMRS, 10, 0, 9.999291, 2, 0.3);
  Add(osMRS, 1, 0, 0.9992912, 2, 0.6);
  Add(osMRS, 0.1, 0, 0.1000116, 2, 2.8);

  { rows 13..17; the sheet gives these in milliohms }
  Add(osMCS10, 0.01, 6, 0.009999229, 10, 4.2);
  Add(osMCS10, 0.01, 12, 0.009999294, 10, 4.9);
  Add(osMCS10, 0.01, 18, 0.009999468, 10, 9.9);
  Add(osMCS10, 0.01, 24, 0.009999469, 10, 9.8);
  Add(osMCS10, 0.01, 30, 0.009999194, 10, 7.7);

  { rows 21..25, milliohms likewise }
  Add(osMCS1, 0.001, 20, 0.0009999998, 10, 4.8);
  Add(osMCS1, 0.001, 40, 0.0009999908, 10, 5.5);
  Add(osMCS1, 0.001, 60, 0.0009999728, 10, 4);
  Add(osMCS1, 0.001, 80, 0.0009999338, 10, 5.5);
  Add(osMCS1, 0.001, 100, 0.0009998978, 10, 6.9);
end;

function TOhmLabs.Check: String;
begin
  Result := '';
  for var Id := Low(TOhmSetId) to High(TOhmSetId) do
    for var I := 0 to High(Sets[Id]) do
    begin
      var S := Sets[Id][I];
      var Row := Format('%s row %d', [OHM_SET_NAME[Id], I +1]);
      if S.Nominal <= 0 then Exit(Row + ' has no nominal value');
      if S.Actual <= 0 then Exit(Row + ' has no actual value');
      if (S.Stability < 0) or (S.CertUnc < 0) or (S.Current < 0) then Exit(Row + ' has a negative figure');
    end;
end;

function TOhmLabs.Find(const Ohms: Double; out S: TOhmStandard): Boolean;
var
  Id: TOhmSetId;
begin
  Result := Find(Ohms, S, Id);
end;

function TOhmLabs.Find(const Ohms: Double; out S: TOhmStandard; out Id: TOhmSetId): Boolean;
begin
  S := Default(TOhmStandard);
  Id := Low(TOhmSetId);
  if Ohms <= 0 then Exit(False);
  for var Each := Low(TOhmSetId) to High(TOhmSetId) do
    for var Item in Sets[Each] do
      if Abs(Item.Actual - Ohms) <= Ohms * 1E-6 then
      begin
        S := Item;
        Id := Each;
        Exit(True);
      end;
  Result := False;
end;

function TOhmLabs.Load(out Why: String): Boolean;
var
  Loaded: TOhmSets;
  LoadedInfo: TOhmSetInfos;
  Have: set of TOhmSetId;
  Arr, Items: TJSONArray;

  function SetInfo(const Id: TOhmSetId; const SetObj: TJSONObject): Boolean;
  var
    R: TOhmSetInfo;
  begin
    Result := CfgDateOf(SetObj, K_DUE, R.Due);
    if Result then LoadedInfo[Id] := R
    else Why := Format('"%s" set %s has a due date that is not yyyy-mm-dd', [K_SECTION, OHM_SET_NAME[Id]]);
  end;

  function Standards(const Id: TOhmSetId; const SetObj: TJSONObject): Boolean;
  var
    S: TOhmStandard;
  begin
    Result := False;
    if not SetObj.TryGetValue<TJSONArray>(K_STANDARDS, Items) then
    begin
      Why := Format('"%s" set %s has no "%s"', [K_SECTION, OHM_SET_NAME[Id], K_STANDARDS]);
      Exit;
    end;

    Loaded[Id] := nil;
    for var V in Items do
    begin
      var Row := Format('"%s" set %s row %d', [K_SECTION, OHM_SET_NAME[Id], Length(Loaded[Id]) +1]);
      if not (V is TJSONObject) then
      begin
        Why := Row + ' is not an object';
        Exit;
      end;
      var O := TJSONObject(V);
      S.Nominal := CfgDouble(O, K_NOMINAL, 0);
      S.Current := CfgDouble(O, K_CURRENT, 0);
      S.Actual := CfgDouble(O, K_ACTUAL, 0);
      S.Stability := CfgDouble(O, K_STABILITY, 0);
      S.CertUnc := CfgDouble(O, K_CERT_UNC, 0);
      if (S.Nominal <= 0) or (S.Actual <= 0) then
      begin
        Why := Format('%s needs "%s" and "%s" above 0', [Row, K_NOMINAL, K_ACTUAL]);
        Exit;
      end;
      Loaded[Id] := Loaded[Id] + [S];
    end;
    Result := True;
  end;

begin
  Seed;
  Result := False;
  var Section := TAppConfig.ReadSection(K_SECTION, Why);
  if Section = nil then Exit;

  try
    if not Section.TryGetValue<TJSONArray>(K_SETS, Arr) then
    begin
      Why := Format('"%s" has no "%s"', [K_SECTION, K_SETS]);
      Exit;
    end;

    Have := [];
    for var V in Arr do
    begin
      if not (V is TJSONObject) then Continue;
      var Name := '';
      if not TJSONObject(V).TryGetValue<String>(K_NAME, Name) then Continue;
      for var Id := Low(TOhmSetId) to High(TOhmSetId) do
        if SameText(Name, OHM_SET_NAME[Id]) then
        begin
          if not Standards(Id, TJSONObject(V)) or not SetInfo(Id, TJSONObject(V)) then Exit;
          Include(Have, Id);
        end;
    end;

    { nothing is taken from a section that has a fault anywhere }
    for var Id := Low(TOhmSetId) to High(TOhmSetId) do
      if Id in Have then
      begin
        Sets[Id] := Loaded[Id];
        Info[Id] := LoadedInfo[Id];
      end;
    Result := True;
  finally
    Section.Free;
  end;
end;

function TOhmLabs.Save(out Why: String): Boolean;
begin
  Why := Check;
  if Why <> '' then Exit(False);

  var Section := TJSONObject.Create;
  Section.AddPair(K_COVERAGE, TJSONNumber.Create(2));
  var Arr := TJSONArray.Create;
  Section.AddPair(K_SETS, Arr);

  for var Id := Low(TOhmSetId) to High(TOhmSetId) do
  begin
    var SetObj := TJSONObject.Create;
    Arr.AddElement(SetObj);
    SetObj.AddPair(K_NAME, OHM_SET_NAME[Id]);
    { what is not given is left out }
    if Info[Id].Due <> 0 then SetObj.AddPair(K_DUE, CfgDate(Info[Id].Due));
    var Items := TJSONArray.Create;
    SetObj.AddPair(K_STANDARDS, Items);

    for var S in Sets[Id] do
    begin
      var O := TJSONObject.Create;
      Items.AddElement(O);
      O.AddPair(K_NOMINAL, CfgJson(S.Nominal));
      if S.Current > 0 then O.AddPair(K_CURRENT, CfgJson(S.Current));
      O.AddPair(K_ACTUAL, CfgJson(S.Actual));
      O.AddPair(K_STABILITY, CfgJson(S.Stability));
      O.AddPair(K_CERT_UNC, CfgJson(S.CertUnc));
    end;
  end;

  Result := TAppConfig.WriteSection(K_SECTION, Section, Why);
end;

end.
