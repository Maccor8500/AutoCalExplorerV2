unit RecordSummaryU;

{
  The calibration record as the configuration and data files have it: what goes into the box, at a glance.
  It is what the Calibration Record tab's Import button brings in, and RecordDifferences is what its Write
  button compares with before it writes.

  ApplyFilesToRecord takes a record (what the tab has painted) and lays over it everything the two
  JSON files say about the box. The certificate is worked out afresh from them (CertificateU, nothing is
  written), so a sheet of Configurations saved a moment ago already counts:

    record (system_info_t)        from
    serial, model, manufacturer   the Certificate sheet's instrument
    owner, technician             the Certificate sheet
    certificate number            the certificate's formula (once a shunt has been accepted)
    calibration date, due date    the certificate (the day of the latest accepted shunt; the sheet's due formula)
    previous calibration date     the Certificate sheet
    temperature, humidity         the Certificate sheet
    comments                      "Method: <procedure>; Remarks: <remarks>; Notes: <notes>", as a certificate
                                  import composes them; the certificate's long comment paragraph is print only,
                                  the board's field holds 255 characters
    shunts 1 to 8                 the certificate's row: measured value, previous value, difference, uncertainty,
                                  each as the certificate prints it. A shunt that has no value there keeps the
                                  record's own line
    standards                     the certificate's "Standards used": the meters, then the typed lines

  A text or date the files leave empty does not blank the record's. The board trims what is too long for a
  field when the record is written; nothing is trimmed here.

  The Certificate sheet counts only once it has been saved. Until then its fields would be the workbook's
  defaults (its serial, its technician, its standards), and those must not replace what a board holds: the
  typed part (identity, technician, conditions, comments, certificate number, standards) is then left as the
  record has it and Note says so. The shunt rows and the calibration dates come from the measurements and are
  laid over either way.

  The data file also keeps the board's own record, as its "record" member: what a Read gave. It is saved
  automatically by a Read when the file holds no valid one (KeepReadRecord), so the files start out from what
  the box really holds; a Read does not replace a valid one. The one other thing that saves it is a Write that
  was read back and found to be on the board as written (the Calibration Record tab does that, and says so):
  a value typed on the tab and pushed to the box is then the files' value too.

  Numbers and the board. The firmware keeps every number as a 32-bit float. Firmware 0.5.5 on sends a shunt's
  number back with seven significant digits, rounded (BoardPrints); up to 0.5.4, and for the other numbers
  still, it is six places after the point less the digits before it past the first (99.99935 has five,
  100.0067 four, 0.050001 six), rounded (BoardPrintsLegacy). A number that was sent counts as on the board when
  what comes back is either printing of it, so the printing is not taken for a difference. What the comparison
  does show up is a number the firmware read wrongly: up to 0.5.4 its JSON parser kept a float's digits only
  up to 8388607 and dropped, not rounded, the digit past that, so 99.99935 arrived as 99.9993 and 100.00667 as
  100.0066 (found 2026-11-12). From 0.5.5 the host sends each shunt number as text too (AutoCalBoardU) and the
  firmware stores that. On Import it goes in first, whole, and the Certificate sheet and the
  certificate go over it as above. Valid means: it is there, it reads, and it says something (a serial number
  or a shunt value).

  No VCL.
}

interface

uses
  System.SysUtils, System.Classes, System.Math, System.StrUtils, System.Generics.Collections, System.JSON,
  AutoCalProtocolU, AppConfigU, CertificateU, FlukeMetersU, OhmLabsU;

type
  TSummaryRows = set of 0..CHANS -1;

{
  Rows: the shunts (0-based) whose line now comes from the certificate. Note: '' or what was held back and
  why. False, with the reason in Why, when the files cannot be used: Info is then as it was
}
function ApplyFilesToRecord(var Info: TSystemInfo; out Rows: TSummaryRows; out Note, Why: String): Boolean;

{ the data file's "record" member. False = there is no valid one: Why = '' when there is none at all, else what is wrong with it }
function LoadStoredRecord(out Info: TSystemInfo; out Why: String): Boolean;
{ Source says where it came from ("Read from 192.168.126.214"). False, with the reason in Why, leaves the file as it was }
function SaveStoredRecord(const Info: TSystemInfo; const Source: String; out Why: String): Boolean;
{
  what a Read does with the record the board gave: saved when the data file has no valid one, left alone when
  it has. Saved says which. False, with the reason in Why, when it should have been saved and could not be
}
function KeepReadRecord(const Read: TSystemInfo; const Source: String; out Saved: Boolean; out Why: String): Boolean;

{ a shunt's number as firmware 0.5.5 on sends it back once it holds it: a 32-bit float, seven significant digits }
function BoardPrints(const Value: Double): Double;
{ the same for firmware up to 0.5.4, and for the numbers that still go out ArduinoJson's way (temperature, humidity) }
function BoardPrintsLegacy(const Value: Double): Double;

{
  what a Read does with the board's "Standards used" table: the configuration file takes it when it has none
  or has something else. Changes lists what was written, one line each, for the notice; none = the file
  already had it, or the board's table is empty (an empty table writes nothing).

  The table goes where the certificate takes it from: a line of a Fluke meter type the software knows
  (8508A, 8588A) is that type's serial number and due date on its sheet, in the order the lines come; every
  other line goes to the standards list.

  "Has something else" is judged by what the file would put on a record now, which is what Import paints: after
  this, Import shows the board's standards. So the list becomes the board's other lines. The one thing kept
  besides them is a line the certificate itself is leaving out at the moment (an Ohm Labs set none of the
  accepted shunts was measured against): it is not on the board because it was not used, not because it is gone.

  False, with the reason in Why, when the file cannot be read or written; Changes then holds what did get in
}
function KeepReadStandards(const Read: TSystemInfo; out Changes: TArray<String>; out Why: String): Boolean;

{
  what a Read does with the whole record the board gave: whatever of it the local files do not have, or have
  differently, is put where it belongs in them, so that an Import afterwards paints what was read. Changes
  lists what was written, one line each, with the file it went to; none = the files already had it all.

    standards                            the configuration file: the meters' sheets and the standards list
                                         (KeepReadStandards)
    serial, model, manufacturer, owner,  the configuration file's Certificate sheet, once that sheet has been
    technician, temperature, humidity,   saved (until then it is held back from Import anyway, and the data
    previous calibration date, comments  file's record carries them). The comment goes to the sheet's
                                         "comment for the box" when it is not the one the sheet makes up
    everything, shunts included          the data file's record of the box (its "record" member), which Import
                                         puts in first

  What is not touched: a shunt that has been accepted keeps its measurement and its certificate value. The box
  holding another value there is the usual state before a Write, not a mismatch; Import still brings the
  accepted value, with its grey dot.

  A record that says nothing (a blank board) writes nothing, and a field the board has blank does not blank a
  local one. A local text that the board holds cut to its field's length counts as the same.

  False, with the reason in Why, when a file cannot be read or written; Changes then holds what did get in
}
function KeepReadLocal(const Read: TSystemInfo; const Source: String; out Changes: TArray<String>; out Why: String): Boolean;

{
  where Mine (a record to write, or written) differs from Theirs (the one the board holds, or the file's), one
  line each ("Serial: the board has "A", to write "B""); none = the same. The firmware section is not compared:
  it is never written. AsBoardPrints = Theirs came from the board: a number of Mine counts as the same when
  it is what the board would send back for it (BoardPrints); False = number against number. TheyHave and IHave
  word the lines
}
function RecordDifferences(const Mine, Theirs: TSystemInfo; const AsBoardPrints: Boolean = True;
  const TheyHave: String = 'the board has'; const IHave: String = 'to write'): TArray<String>;

implementation

{ a number as the certificate prints it ("100.006 67") back to the number that text states }
function Stated(const Text: String; const Fallback: Double): Double;
begin
  if not TryStrToFloat(StringReplace(Text, ' ', '', [rfReplaceAll]), Result, TFormatSettings.Invariant) then Result := Fallback;
end;

const
  K_RECORD = 'record';
  K_SOURCE = 'source';
  K_SAVED = 'saved';
  K_SERIAL = 'serial';
  K_MODEL = 'model';
  K_CERT = 'certificate_number';
  K_MANUFACTURER = 'manufacturer';
  K_OWNER = 'owner';
  K_TECH = 'technician';
  K_CAL_DATE = 'calibration_date';
  K_CAL_PREV = 'prev_cal_date';
  K_CAL_DUE = 'calibration_due';
  K_TEMP = 'temp_C';
  K_HUMD = 'humidity_pct';
  K_COMMENTS = 'comments';
  K_SHUNTS = 'shunts';
  K_SHUNT = 'shunt';
  K_STANDARDS = 'standards';
  K_MFR = 'mfr';
  K_DUE = 'cal_due';
  K_FIRMWARE = 'firmware';
  SHUNT_KEY: array [TShuntField] of String = ('measured_ohm', 'prev_ohm', 'diff_pct', 'unc_ppm');
  VALUE_DIGITS = 15;

function TextOf(const Obj: TJSONObject; const Key: String): String;
begin
  Result := '';
  var V := Obj.GetValue(Key);
  if (V is TJSONString) and not (V is TJSONNumber) then Result := TJSONString(V).Value;
end;

function SaveStoredRecord(const Info: TSystemInfo; const Source: String; out Why: String): Boolean;
begin
  var R := TJSONObject.Create;
  R.AddPair(K_SOURCE, Source);
  R.AddPair(K_SAVED, FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', Now, TFormatSettings.Invariant));
  R.AddPair(K_SERIAL, Info.Serial);
  R.AddPair(K_MODEL, Info.Model);
  R.AddPair(K_CERT, Info.Cert);
  R.AddPair(K_MANUFACTURER, Info.Manufacturer);
  R.AddPair(K_OWNER, Info.Owner);
  R.AddPair(K_TECH, Info.Tech);
  R.AddPair(K_CAL_DATE, Info.CalDate.ToText);
  R.AddPair(K_CAL_PREV, Info.CalDatePrev.ToText);
  R.AddPair(K_CAL_DUE, Info.CalDue.ToText);
  R.AddPair(K_TEMP, CfgJson(Info.Temp));
  R.AddPair(K_HUMD, CfgJson(Info.Humd));
  R.AddPair(K_COMMENTS, Info.Comments);

  var Shunts := TJSONArray.Create;
  R.AddPair(K_SHUNTS, Shunts);
  for var I := 0 to CHANS -1 do
  begin
    var O := TJSONObject.Create;
    Shunts.AddElement(O);
    O.AddPair(K_SHUNT, TJSONNumber.Create(I +1));
    for var F := Low(TShuntField) to High(TShuntField) do O.AddPair(SHUNT_KEY[F], CfgJson(Info.Shunts[I].Value(F), VALUE_DIGITS));
  end;

  var Standards := TJSONArray.Create;
  R.AddPair(K_STANDARDS, Standards);
  for var I := 0 to TRACE_COUNT -1 do
  begin
    { all eight lines, empty ones too: a standard keeps its place in the board's table }
    var O := TJSONObject.Create;
    Standards.AddElement(O);
    O.AddPair(K_SERIAL, Info.Trace[I].Serial);
    O.AddPair(K_MFR, Info.Trace[I].Manufacturer);
    O.AddPair(K_MODEL, Info.Trace[I].Model);
    O.AddPair(K_DUE, Info.Trace[I].CalDueText);
  end;

  { the board's running build, for whoever reads the file: never read back, never written to a board }
  if Info.Firmware.Device <> '' then
    R.AddPair(K_FIRMWARE, Trim(Info.Firmware.Device + ' ' + Info.Firmware.Version + ' ' + Info.Firmware.DateTime));

  Result := TAppData.WriteSection(K_RECORD, R, Why);
end;

function LoadStoredRecord(out Info: TSystemInfo; out Why: String): Boolean;
var
  Arr: TJSONArray;

  { '' is no date; anything else must be one the board would take }
  function DateOf(const Obj: TJSONObject; const Key: String; out D: TCalDate): Boolean;
  begin
    D := TCalDate.Empty;
    var S := Trim(TextOf(Obj, Key));
    Result := (S = '') or TCalDate.Parse(S, D);
    if not Result then Why := Format('"%s" has "%s" for %s, which is not a date the board takes', [K_RECORD, S, Key]);
  end;

begin
  Result := False;
  Info.Clear;
  var R := TAppData.ReadSection(K_RECORD, Why);
  if R = nil then Exit;
  try
    Info.Serial := TextOf(R, K_SERIAL);
    Info.Model := TextOf(R, K_MODEL);
    Info.Cert := TextOf(R, K_CERT);
    Info.Manufacturer := TextOf(R, K_MANUFACTURER);
    Info.Owner := TextOf(R, K_OWNER);
    Info.Tech := TextOf(R, K_TECH);
    Info.Comments := TextOf(R, K_COMMENTS);
    Info.Temp := CfgDouble(R, K_TEMP, 0);
    Info.Humd := CfgDouble(R, K_HUMD, 0);
    if not (DateOf(R, K_CAL_DATE, Info.CalDate) and DateOf(R, K_CAL_PREV, Info.CalDatePrev) and DateOf(R, K_CAL_DUE, Info.CalDue)) then Exit;

    var Says := Trim(Info.Serial) <> '';
    if R.TryGetValue<TJSONArray>(K_SHUNTS, Arr) then
      for var V in Arr do
      begin
        if not (V is TJSONObject) then Continue;
        var N := Round(CfgDouble(TJSONObject(V), K_SHUNT, 0));
        if (N < 1) or (N > CHANS) then Continue;
        Info.Shunts[N -1].Index := N -1;
        for var F := Low(TShuntField) to High(TShuntField) do
          Info.Shunts[N -1].Put(F, CfgDouble(TJSONObject(V), SHUNT_KEY[F], 0));
        if Info.Shunts[N -1].Current <> 0 then Says := True;
      end;

    if R.TryGetValue<TJSONArray>(K_STANDARDS, Arr) then
      for var I := 0 to Min(Arr.Count, TRACE_COUNT) -1 do
      begin
        if not (Arr.Items[I] is TJSONObject) then Continue;
        var O := TJSONObject(Arr.Items[I]);
        Info.Trace[I].Serial := TextOf(O, K_SERIAL);
        Info.Trace[I].Manufacturer := TextOf(O, K_MFR);
        Info.Trace[I].Model := TextOf(O, K_MODEL);
        { a due date the firmware refuses (a year before 2000) is kept as the text it was }
        var Due := Trim(TextOf(O, K_DUE));
        Info.Trace[I].CalDueStr := Due;
        if (Due = '') or not TCalDate.Parse(Due, Info.Trace[I].CalDue) then Info.Trace[I].CalDue := TCalDate.Empty;
      end;

    Result := Says;
    if not Result then
    begin
      Info.Clear;
      Why := Format('"%s" is there but says nothing: no serial number and no shunt value', [K_RECORD]);
    end;
  finally
    R.Free;
  end;
end;

function KeepReadRecord(const Read: TSystemInfo; const Source: String; out Saved: Boolean; out Why: String): Boolean;
var
  Stored: TSystemInfo;
begin
  Saved := False;
  if LoadStoredRecord(Stored, Why) then
  begin
    Why := '';
    Exit(True);
  end;
  { none, or one that cannot be used: Why says which, for the log, once the new one is in }
  var Was := Why;
  Result := SaveStoredRecord(Read, Source, Why);
  Saved := Result;
  if Result then Why := Was;
end;

function BoardPrints(const Value: Double): Double;
var
  Held: Single;
begin
  if Value = 0 then Exit(0);
  Held := Value;
  { dtostre(value, text, 6, 0): one digit, the point, six more, the exponent }
  Result := StrToFloat(FloatToStrF(Held, ffExponent, 7, 2, TFormatSettings.Invariant), TFormatSettings.Invariant);
end;

{ single arithmetic kept single: the board's sums are 32-bit, and so must these be to print as it does }
{$EXCESSPRECISION OFF}
function BoardPrintsLegacy(const Value: Double): Double;
var
  V, Remainder: Single;
  Integral, Decimal, MaxPart, T: Cardinal;
begin
  if Value = 0 then Exit(0);
  V := Abs(Value);
  { beyond these the firmware prints with an exponent: the float itself is as near as this needs to be }
  if (V >= 1E7) or (V <= 1E-5) then Exit(Single(Value));

  { ArduinoJson's decomposeFloat for a float: six decimal places, one less for each integral digit past the first }
  MaxPart := 1000000;
  Integral := Trunc(V);
  T := Integral;
  while T >= 10 do
  begin
    MaxPart := MaxPart div 10;
    T := T div 10;
  end;
  Remainder := (V - Integral) * MaxPart;
  Decimal := Trunc(Remainder);
  Remainder := Remainder - Decimal;
  Decimal := Decimal + Cardinal(Trunc(Remainder * 2));      { up by one from a half on }
  if Decimal >= MaxPart then
  begin
    Decimal := 0;
    Inc(Integral);
  end;
  Result := Integral + Decimal / MaxPart;
  if Value < 0 then Result := -Result;
end;
{$EXCESSPRECISION ON}

function KeepReadStandards(const Read: TSystemInfo; out Changes: TArray<String>; out Why: String): Boolean;
var
  Other, Typed, Unused, Wanted: TCertStandards;
  MeterLines: array [TFlukeModel] of TCertStandards;
  Line: TCertStandard;
  Ignore: String;

  function Same(const A, B: TCertStandard): Boolean;
  begin
    Result := SameText(Trim(A.Serial), Trim(B.Serial)) and SameText(Trim(A.Mfr), Trim(B.Mfr))
      and SameText(Trim(A.Model), Trim(B.Model)) and (A.Due = B.Due);
  end;

  function SameList(const A, B: TCertStandards): Boolean;
  begin
    Result := Length(A) = Length(B);
    if Result then
      for var I := 0 to High(A) do
        if not Same(A[I], B[I]) then Exit(False);
  end;

  { the serial and model are in List, whatever its due date }
  function Listed(const List: TCertStandards; const S: TCertStandard): Boolean;
  begin
    Result := False;
    for var L in List do
      if SameText(Trim(L.Serial), Trim(S.Serial)) and SameText(Trim(L.Model), Trim(S.Model)) then Exit(True);
  end;

begin
  Changes := nil;
  Why := '';
  Result := True;

  { the board's lines, split by where they belong }
  var Count := 0;
  for var I := 0 to TRACE_COUNT -1 do
  begin
    var T := Read.Trace[I];
    if (Trim(T.Serial) = '') and (Trim(T.Model) = '') then Continue;
    Inc(Count);
    Line.Serial := Trim(T.Serial);
    Line.Mfr := Trim(T.Manufacturer);
    Line.Model := Trim(T.Model);
    { the text when there is one: a date the firmware refuses still has it }
    if not CfgTryDate(T.CalDueText, Line.Due) then Line.Due := 0;

    var Meter := False;
    if SameText(Line.Mfr, FLUKE_MANUFACTURER) then
      for var M := Low(TFlukeModel) to High(TFlukeModel) do
        if SameText(Line.Model, FLUKE_MODEL_NAME[M]) and (Length(MeterLines[M]) < FLUKE_UNITS) then
        begin
          MeterLines[M] := MeterLines[M] + [Line];
          Meter := True;
        end;
    if not Meter then Other := Other + [Line];
  end;
  if Count = 0 then Exit;

  { the meters' lines: their type's sheet }
  var Meters := TFlukeMeters.Create;
  try
    var Had := Meters.Load(Why);
    if Why <> '' then Exit(False);
    Why := '';
    for var M := Low(TFlukeModel) to High(TFlukeModel) do
    begin
      if Length(MeterLines[M]) = 0 then Continue;
      var Differs := not Had;
      for var U := 0 to FLUKE_UNITS -1 do
      begin
        var Serial := '';
        var Due: TDate := 0;
        if U <= High(MeterLines[M]) then
        begin
          Serial := MeterLines[M][U].Serial;
          Due := MeterLines[M][U].Due;
        end;
        if not SameText(Trim(Meters.Meters[M].Units[U].Serial), Serial) or (Meters.Meters[M].Units[U].Due <> Due) then Differs := True;
        Meters.Meters[M].Units[U].Serial := Serial;
        Meters.Meters[M].Units[U].Due := Due;
      end;
      if not Differs then Continue;
      if not Meters.Save(M, Why) then Exit(False);
      Changes := Changes + [Format('Fluke %s: the serial number and due date of %d meter(s)', [FLUKE_MODEL_NAME[M], Length(MeterLines[M])])];
    end;
  finally
    Meters.Free;
  end;

  {
    the other lines against what the file would put on a record now (the certificate worked out, not stored):
    the list as it is, less any Ohm Labs set the accepted shunts did not use
  }
  var Cert: TCertificate;
  if not TCertificateData.Refresh(Cert, Why, 0, 0, '', 0, False) then Exit(False);
  Typed := Cert.Inputs.Standards;
  Wanted := Cert.OtherStandards;
  var HadList := TCertInputs.LoadStandards(Unused, Ignore);
  if HadList and SameList(Wanted, Other) then Exit;

  { kept: what the certificate is leaving out for want of use, unless the board has it after all }
  Unused := nil;
  for var S in Typed do
    if not Listed(Wanted, S) and not Listed(Other, S) then Unused := Unused + [S];
  if not TCertInputs.SaveStandards(Other + Unused, Why) then Exit(False);
  Changes := Changes + [Format('Standards list: %d line(s) from the board%s', [Length(Other),
    IfThen(Length(Unused) > 0, Format(', %d line(s) the certificate is not using kept', [Length(Unused)]), '')])];
end;

function KeepReadLocal(const Read: TSystemInfo; const Source: String; out Changes: TArray<String>; out Why: String): Boolean;
var
  Blank, Stored: TSystemInfo;
  Inputs: TCertInputs;
  Part: TArray<String>;
  Ignore: String;
  Touched: Boolean;

  { a text of the sheet against the board's: the board's wins when it has one and it is not the local one cut to Cap }
  procedure Field(const Name: String; var Local: String; const OnBoard: String; const Cap: Integer);
  begin
    var B := Trim(OnBoard);
    if (B = '') or (TAutoCalProtocol.FitText(Trim(Local), Cap) = B) then Exit;
    Part := Part + [Format('%s: local "%s", the board has "%s"', [Name, Trim(Local), B])];
    Local := B;
    Touched := True;
  end;

  { a number the sheet keeps as text; 0 on the board counts as not given }
  procedure Value(const Name: String; var Local: String; const OnBoard: Double);
  var
    D: Double;
  begin
    if OnBoard = 0 then Exit;
    if TryStrToFloat(Trim(Local), D, TFormatSettings.Invariant)
      and (SameValue(BoardPrintsLegacy(D), OnBoard, Abs(OnBoard) * 1E-9) or SameValue(BoardPrints(D), OnBoard, Abs(OnBoard) * 1E-9)) then Exit;
    var B := TAutoCalProtocol.FormatValue(OnBoard);
    Part := Part + [Format('%s: local %s, the board has %s', [Name, IfThen(Trim(Local) = '', '(none)', Trim(Local)), B])];
    Local := B;
    Touched := True;
  end;

begin
  Changes := nil;
  Why := '';
  Result := True;

  { a blank board has nothing to put anywhere }
  Blank.Clear;
  Stored := Read;
  Stored.Firmware := Blank.Firmware;
  if Length(RecordDifferences(Stored, Blank, False)) = 0 then Exit;
  var Config := ExtractFileName(TAppConfig.FileName);
  var Data := ExtractFileName(TAppData.FileName);

  { the standards: the meters' sheets and the list }
  if not KeepReadStandards(Read, Part, Why) then Result := False;
  for var P in Part do Changes := Changes + [Config + ' :: ' + P];
  if not Result then Exit;

  { the Certificate sheet, once it has been saved: what it would put on the record must be what the board has }
  Part := nil;
  Touched := False;
  if TCertInputs.Load(Inputs, Ignore) then
  begin
    Field('Serial', Inputs.Serial, Read.Serial, CAP_SERIAL);
    Field('Model', Inputs.Model, Read.Model, CAP_MODEL);
    Field('Manufacturer', Inputs.Manufacturer, Read.Manufacturer, CAP_MANUFACTURER);
    Field('Owner', Inputs.OwnerName, Read.Owner, CAP_OWNER);
    Field('Technician', Inputs.Technician, Read.Tech, CAP_TECH);
    Value('Temp.', Inputs.Temp, Read.Temp);
    Value('Humidity', Inputs.Humidity, Read.Humd);

    var D: TDate;
    if Read.CalDatePrev.IsSet and CfgTryDate(Read.CalDatePrev.ToText, D) and (D <> Inputs.PrevCalDate) then
    begin
      Part := Part + [Format('Prev. cal. date: local %s, the board has %s',
        [IfThen(Inputs.PrevCalDate = 0, '(none)', CfgDate(Inputs.PrevCalDate)), CfgDate(D)])];
      Inputs.PrevCalDate := D;
      Touched := True;
    end;

    { the comment: the board's own text becomes the sheet's comment for the box }
    var OnBoard := Trim(Read.Comments);
    if (OnBoard <> '') and (TAutoCalProtocol.FitText(CertRecordComments(Inputs), CAP_COMMENTS) <> OnBoard) then
    begin
      Part := Part + [Format('Comments: local "%s", the board has "%s"',
        [Copy(CertRecordComments(Inputs), 1, 60), Copy(OnBoard, 1, 60)])];
      Inputs.RecordComments := OnBoard;
      Touched := True;
    end;

    if Touched then
    begin
      if not Inputs.Save(Why) then Exit(False);
      for var P in Part do Changes := Changes + [Config + ' :: Certificate sheet :: ' + P];
    end;
  end;

  { the data file's record of the box: all of it, as read }
  var Had := LoadStoredRecord(Stored, Ignore);
  Part := nil;
  if Had then Part := RecordDifferences(Read, Stored, False, 'local', 'the board has');
  if Had and (Length(Part) = 0) then Exit;
  if not SaveStoredRecord(Read, Source, Why) then Exit(False);
  if not Had then Changes := Changes + [Data + ' :: record of the box: there was none, the record read was saved']
  else
    for var P in Part do Changes := Changes + [Data + ' :: record of the box :: ' + P];
end;

function RecordDifferences(const Mine, Theirs: TSystemInfo; const AsBoardPrints: Boolean;
  const TheyHave, IHave: String): TArray<String>;
const
  SHUNT_FIELD: array [TShuntField] of String = ('measured', 'previous', 'diff', 'uncertainty');
var
  List: TArray<String>;

  function Short(const S: String): String;
  begin
    Result := S.Replace(#13#10, ' ').Replace(#10, ' ');
    if Length(Result) > 40 then Result := Copy(Result, 1, 37) + '...';
  end;

  procedure Text(const Name, A, B: String);
  begin
    if Trim(A) <> Trim(B) then
      List := List + [Format('%s: %s "%s", %s "%s"', [Name, TheyHave, Short(Trim(B)), IHave, Short(Trim(A))])];
  end;

  procedure Date(const Name: String; const A, B: TCalDate);
  begin
    if (A.Year <> B.Year) or (A.Month <> B.Month) or (A.Day <> B.Day) then
      List := List + [Format('%s: %s %s, %s %s', [Name, TheyHave, B.ToDisplay, IHave, A.ToDisplay])];
  end;

  procedure Number(const Name: String; const A, B: Double);
  begin
    { against the board: what it would send back for A, by either firmware's printing. Otherwise number against number }
    var Same: Boolean;
    if AsBoardPrints then
      Same := SameValue(BoardPrints(A), B, Abs(B) * 1E-9) or SameValue(BoardPrintsLegacy(A), B, Abs(B) * 1E-9)
    else
      Same := SameValue(A, B, Max(Abs(A), Abs(B)) * 1E-9);
    if not Same then
      List := List + [Format('%s: %s %s, %s %s',
        [Name, TheyHave, TAutoCalProtocol.FormatValue(B), IHave, TAutoCalProtocol.FormatValue(A)])];
  end;

begin
  List := nil;
  Text('Serial', Mine.Serial, Theirs.Serial);
  Text('Model', Mine.Model, Theirs.Model);
  Text('Certificate #', Mine.Cert, Theirs.Cert);
  Text('Manufacturer', Mine.Manufacturer, Theirs.Manufacturer);
  Text('Owner', Mine.Owner, Theirs.Owner);
  Text('Technician', Mine.Tech, Theirs.Tech);
  Date('Calibration date', Mine.CalDate, Theirs.CalDate);
  Date('Previous cal.', Mine.CalDatePrev, Theirs.CalDatePrev);
  Date('Calibration due', Mine.CalDue, Theirs.CalDue);
  Number('Temp.', Mine.Temp, Theirs.Temp);
  Number('Humidity', Mine.Humd, Theirs.Humd);
  for var I := 0 to CHANS -1 do
    for var F := Low(TShuntField) to High(TShuntField) do
      Number(Format('Shunt %d %s', [I +1, SHUNT_FIELD[F]]), Mine.Shunts[I].Value(F), Theirs.Shunts[I].Value(F));
  for var I := 0 to TRACE_COUNT -1 do
  begin
    var Name := Format('Standard %d', [I +1]);
    Text(Name + ' serial', Mine.Trace[I].Serial, Theirs.Trace[I].Serial);
    Text(Name + ' mfr.', Mine.Trace[I].Manufacturer, Theirs.Trace[I].Manufacturer);
    Text(Name + ' model', Mine.Trace[I].Model, Theirs.Trace[I].Model);
    Date(Name + ' cal. due', Mine.Trace[I].CalDue, Theirs.Trace[I].CalDue);
  end;
  Text('Comments', Mine.Comments, Theirs.Comments);
  Result := List;
end;

function ApplyFilesToRecord(var Info: TSystemInfo; out Rows: TSummaryRows; out Note, Why: String): Boolean;
var
  Cert: TCertificate;
  Saved: TCertInputs;
  Ignore: String;
  D: Double;

  procedure Take(var Field: String; const Value: String);
  begin
    if Trim(Value) <> '' then Field := Trim(Value);
  end;

  procedure TakeDate(var Field: TCalDate; const Value: TDate);
  begin
    if Value <> 0 then Field := TCalDate.FromDateTime(Value);
  end;

begin
  Rows := [];
  Note := '';
  { worked out from the files as they stand; not stored: looking at the record changes nothing }
  Result := TCertificateData.Refresh(Cert, Why, 0, 0, '', 0, False);
  if not Result then Exit;

  { the board's record as the data file keeps it goes in first, whole; the rest goes over it }
  var Stored: TSystemInfo;
  if LoadStoredRecord(Stored, Ignore) then
  begin
    Stored.Firmware := Info.Firmware;
    Info := Stored;
  end;

  { the measurements' part: the dates, and further down the shunt rows }
  TakeDate(Info.CalDate, Cert.CalDate);
  TakeDate(Info.CalDue, Cert.CalDue);

  var Typed := TCertInputs.Load(Saved, Ignore);
  if not Typed then
    Note := 'the Certificate sheet of Configurations has not been saved: identity, technician, conditions, comments, ' +
      'certificate number and standards are left as the record has them';

  var I := Cert.Inputs;
  if Typed then
  begin
  Take(Info.Serial, I.Serial);
  Take(Info.Model, I.Model);
  Take(Info.Manufacturer, I.Manufacturer);
  Take(Info.Owner, I.OwnerName);
  Take(Info.Tech, I.Technician);
  { the number is serial + month and year + initials: without a calibration date it is not one yet }
  if Cert.CalDate <> 0 then Take(Info.Cert, Cert.Number);
  TakeDate(Info.CalDatePrev, I.PrevCalDate);
  if TryStrToFloat(Trim(I.Temp), D, TFormatSettings.Invariant) then Info.Temp := D;
  if TryStrToFloat(Trim(I.Humidity), D, TFormatSettings.Invariant) then Info.Humd := D;

  Take(Info.Comments, CertRecordComments(I));
  end;

  for var N := 1 to Min(CERT_SHUNTS, CHANS) do
  begin
    var S := Cert.Shunts[N];
    if not S.HaveMeasured then Continue;
    var R := Default(TShuntRecord);
    R.Index := N -1;
    var Text := CertOhmsText(S.Measured, S.Nominal);
    R.Put(sfCurrent, Stated(Text, S.Measured), Text);
    Text := FormatFloat('0.00', S.Unc, TFormatSettings.Invariant);
    R.Put(sfUncertainty, Stated(Text, S.Unc), Text);
    if S.Previous > 0 then
    begin
      Text := CertOhmsText(S.Previous, S.Nominal);
      R.Put(sfPrevious, Stated(Text, S.Previous), Text);
    end;
    if S.HaveDiff then
    begin
      Text := FormatFloat('0.00000', S.Diff, TFormatSettings.Invariant);
      R.Put(sfDifference, Stated(Text, S.Diff), Text);
    end;
    Info.Shunts[N -1] := R;
    Include(Rows, N -1);
  end;

  { the certificate's table in place of the record's, when it has one }
  { the standards count once they are in the file, by the sheet's Save or by a Read of the board }
  var Lines: TCertStandards;
  if (Typed or TCertInputs.LoadStandards(Lines, Ignore)) and (Length(Cert.Standards) > 0) then
    for var N := 0 to TRACE_COUNT -1 do
    begin
      var T := Default(TTraceRecord);
      if N <= High(Cert.Standards) then
      begin
        T.Serial := Cert.Standards[N].Serial;
        T.Manufacturer := Cert.Standards[N].Mfr;
        T.Model := Cert.Standards[N].Model;
        if Cert.Standards[N].Due <> 0 then
        begin
          T.CalDue := TCalDate.FromDateTime(Cert.Standards[N].Due);
          T.CalDueStr := CfgDate(Cert.Standards[N].Due);
        end;
      end;
      Info.Trace[N] := T;
    end;
end;

end.
