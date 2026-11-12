unit CertificateU;

{
  The certificate: the LDF-78 workbook's "Certificate" sheet, now the "certificate" member of the data file
  (AppConfigU.TAppData). It is rewritten whenever a shunt is accepted, and GenerateCertificate (CertificatePdfU)
  prints from it.

  Where each part of the sheet comes from:

    Measured Value, Unc       the meter sheet (MeterSheetU), worked out here from the data member's entries
                              (CalDataU) with the meter type's and the Ohm Labs figures of the configuration
                              (FlukeMetersU, OhmLabsU); written to the data file as its "meter" member
    Prev. Value               given at Accept (the value the record held before), kept from then on
    Calibration Date          the day of the latest accepted shunt
    Standards used            the meters of the type the bench ran with (serial, due date), then the lines typed
                              on the Certificate sheet of Configurations; an Ohm Labs line is shown only when
                              a shunt on the certificate was measured against a standard of its set (below)
    everything else typed     TCertInputs, the "certificate" section of the configuration file: owner,
                              instrument, procedure, technician, remarks, temperature, humidity, previous
                              calibration date, notes, comments, the other standards, the form's footer

  and the sheet's formula cells, kept as the sheet has them:

    Certificate Number   =CONCAT(serial_no, UPPER(TEXT(cal_date,"MMMYYYY")), a, b) where, for a technician
                         written "Last, First", a is the letter after the first space and b the first letter;
                         written without a comma, a is the first letter and b the letter after the first space
    Calibration Due      =IF(cal_date<>"", IF(LEFT(owner,6)="Maccor", IF(MAX(Diff)<0.01, cal_date+365, cal_date+180), ""), "")
    Days Since Last Cal. =IF(prev<>"", IF(AND(cal_date<>"", prev<>"N/a"), cal_date-prev, ""), "")
    Diff (%)             =IF(AND(measured<>"", prev<>""), ABS(measured-prev)/prev*100, "")

  One thing is not the sheet's: its Ohm Labs line was =IF(U17<1000, the MCS, the MRS), a guess from shunt 1's
  previous value at which of two boxes was on the bench. The MRS and the MCS are different tables for different
  shunts, and a box may use both, so the line follows the standards used instead: each accepted shunt's standard
  is looked up on the Ohm Labs sheet (OhmLabsU), and a typed Ohm Labs line is printed when its model names a set
  one of them is in ("MRS" the MRS; "MCS" either MCS table; "MCS 0.01" or "MCS 0.001" that table alone).

  No VCL.
}

interface

uses
  System.SysUtils, System.Classes, System.Math, System.DateUtils, System.Generics.Collections, System.JSON,
  AppConfigU, OhmLabsU, FlukeMetersU, CalDataU, MeterSheetU;

const
  CERT_SHUNTS = 8;

type
  { a line of "Standards used" }
  TCertStandard = record
    Serial, Mfr, Model: String;
    Due: TDate;                               { 0 = not given }
  end;
  TCertStandards = TArray<TCertStandard>;

  { what the certificate needs that neither the data file nor the rest of the configuration holds }
  TCertInputs = record
    OwnerName, OwnerAddress1, OwnerAddress2: String;
    Manufacturer, Description, Model, Serial: String;
    Procedure1, Procedure2: String;
    Technician, Remarks: String;
    Temp, Humidity: String;                   { a number as text; '' = not given }
    PrevCalDate: TDate;                       { 0 = not given }
    Notes, Comments: String;
    Standards: TCertStandards;                { besides the meters }
    FormNo, Rev, RevDate: String;             { the page footer }

    { the workbook's own }
    class function Defaults: TCertInputs; static;
    { '' when it can be saved, else what is wrong }
    function Check: String;
    { True = Inputs hold the saved section. False = the defaults: Why = '' when nothing is saved yet, else what is wrong with the file }
    class function Load(out Inputs: TCertInputs; out Why: String): Boolean; static;
    function Save(out Why: String): Boolean;
  end;

  { a row of the measurement table }
  TCertShunt = record
    Nominal: Double;                          { ohms; 0 = the shunt has not been accepted: the row is blank }
    HaveMeasured: Boolean;
    Measured: Double;                         { ohms }
    Unc: Double;                              { ppm (micro-ohm per ohm), k = 2 }
    Previous: Double;                         { ohms; 0 = none }
    HaveDiff: Boolean;
    Diff: Double;                             { % }
  end;

  TCertificate = record
    Number: String;
    Inputs: TCertInputs;                      { as they stood when the certificate was made; Standards = besides the meters }
    CalDate, CalDue: TDate;                   { 0 = none }
    HaveDays: Boolean;
    DaysSince: Integer;
    MeterModel: String;                       { '8508A' }
    Shunts: array [1..CERT_SHUNTS] of TCertShunt;
    Standards: TCertStandards;                { the whole "Standards used" table: the meters, then the inputs' }
    Gaps: TArray<String>;                     { why a shunt has no value, one line each; not kept in the file }
  end;

  TCertificateData = class(TObject)
    public
      {
        works the meter sheet and the certificate out from the data member and the configuration as they
        stand, and writes them to the data file as its "meter" and "certificate" members. Accepted (1-based;
        0 = none) names the shunt just accepted, for which Previous (0 = keep), Model ('' = keep) and Digits
        (0 = keep) are the value the record held before, the meter type the bench ran with and the digits of
        resolution it was set to. Store = False only works it out: nothing is written (the Calibration Record tab
        looks this way). False, with the reason in Why, leaves the file as it was
      }
      class function Refresh(out Cert: TCertificate; out Why: String; const Accepted: Integer = 0;
        const Previous: Double = 0; const Model: String = ''; const Digits: Integer = 0;
        const Store: Boolean = True): Boolean; static;
      { the certificate member as the file has it. False, with the reason in Why, when there is none or it cannot be read }
      class function Load(out Cert: TCertificate; out Why: String): Boolean; static;
  end;

{ the sheet's formula cells }
function CertNumber(const Serial: String; const CalDate: TDate; const Technician: String): String;
function CertDue(const CalDate: TDate; const OwnerName: String; const MaxDiff: Double): TDate;
{
  the typed standards that belong on the certificate: every line that is not an Ohm Labs set, and of the Ohm
  Labs lines those whose model names a set in UsedSets (OHM_SET_NAME of the sets the accepted shunts' standards
  are in). An Ohm Labs line whose model names no set at all is not judged and stays
}
function CertTypedStandards(const Typed: TCertStandards; const UsedSets: TArray<String>): TCertStandards;

{ a date as the certificate prints it: m/d/yyyy; '' for none }
function CertDateText(const D: TDate): String;
{
  a resistance as the certificate prints it, by the shunt's nominal value: the sheet's number formats 0.000,
  #0.000 00, ##0.000 000 0 and ##0.000 000 00 (thousands and up, hundreds, units and tens, below one)
}
function CertOhmsText(const Ohms, Nominal: Double): String;

implementation

const
  K_SECTION = 'certificate';
  K_METER = 'meter';
  K_MODEL = 'model';
  K_SHUNTS = 'shunts';
  K_SLOT = 'slot';

  K_NUMBER = 'certificate_number';
  K_OWNER = 'owner';
  K_NAME = 'name';
  K_ADDRESS1 = 'address_1';
  K_ADDRESS2 = 'address_2';
  K_INSTRUMENT = 'instrument';
  K_MANUFACTURER = 'manufacturer';
  K_DESCRIPTION = 'description';
  K_SERIAL = 'serial';
  K_PROCEDURE1 = 'procedure_1';
  K_PROCEDURE2 = 'procedure_2';
  K_TECHNICIAN = 'technician';
  K_REMARKS = 'remarks';
  K_CAL_DATE = 'calibration_date';
  K_CAL_DUE = 'calibration_due';
  K_TEMP = 'temp_C';
  K_HUMIDITY = 'humidity_pct';
  K_PREV_DATE = 'prev_cal_date';
  K_DAYS = 'days_since_last_cal';
  K_METER_MODEL = 'meter_model';
  K_SHUNT = 'shunt';
  K_NOMINAL = 'nominal_ohm';
  K_MEASURED = 'measured_ohm';
  K_UNC = 'unc_ppm';
  K_PREVIOUS = 'prev_ohm';
  K_DIFF = 'diff_pct';
  K_NOTES = 'notes';
  K_STANDARDS = 'standards';
  K_MFR = 'mfr';
  K_CAL_DUE_STD = 'cal_due';
  K_COMMENTS = 'comments';
  K_FORM = 'form';
  K_FORM_NO = 'number';
  K_REV = 'rev';
  K_REV_DATE = 'rev_date';
  VALUE_DIGITS = 15;                          { not DIGITS: Refresh has a parameter of that name }
  MONTHS: array [1..12] of String = ('JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC');

function CertDateText(const D: TDate): String;
var
  Y, M, Day: Word;
begin
  if D = 0 then Exit('');
  DecodeDate(D, Y, M, Day);
  Result := Format('%d/%d/%d', [M, Day, Y]);
end;

function CertOhmsText(const Ohms, Nominal: Double): String;
begin
  var Decimals := 8;
  if Nominal >= 1000 then Decimals := 3
  else if Nominal >= 100 then Decimals := 5
  else if Nominal >= 1 then Decimals := 7;

  Result := FloatToStrF(Ohms, ffFixed, 18, Decimals, TFormatSettings.Invariant);
  { the decimals in threes, a space between: 0.050 001 10 }
  var Dot := Pos('.', Result);
  if (Dot = 0) or (Decimals <= 3) then Exit;
  var Whole := Copy(Result, 1, Dot);
  var Frac := Copy(Result, Dot +1, MaxInt);
  Result := Whole;
  for var I := 1 to Length(Frac) do
  begin
    if (I > 1) and ((I -1) mod 3 = 0) then Result := Result + ' ';
    Result := Result + Frac[I];
  end;
end;

{ the letter after the first space, as MID(tech, SEARCH(" ", tech)+1, 1); '' where the sheet's cell would be an error }
function AfterSpace(const S: String): String;
begin
  var P := Pos(' ', S);
  if P = 0 then Exit('');
  Result := Copy(S, P +1, 1);
end;

function CertNumber(const Serial: String; const CalDate: TDate; const Technician: String): String;
var
  Y, M, D: Word;
begin
  Result := Serial;
  if CalDate <> 0 then
  begin
    DecodeDate(CalDate, Y, M, D);
    Result := Result + MONTHS[M] + IntToStr(Y);
  end;
  if Pos(',', Technician) = 0 then Result := Result + Copy(Technician, 1, 1) + AfterSpace(Technician)
  else Result := Result + AfterSpace(Technician) + Copy(Technician, 1, 1);
end;

function CertDue(const CalDate: TDate; const OwnerName: String; const MaxDiff: Double): TDate;
begin
  Result := 0;
  if CalDate = 0 then Exit;
  if not SameText(Copy(OwnerName, 1, 6), 'Maccor') then Exit;
  if MaxDiff < 0.01 then Result := CalDate + 365 else Result := CalDate + 180;
end;

function CertTypedStandards(const Typed: TCertStandards; const UsedSets: TArray<String>): TCertStandards;

  { the line's model names the set: 'MCS' names 'MCS 0.01' and 'MCS 0.001', 'MCS 0.01' only itself }
  function Names(const Model, SetName: String): Boolean;
  begin
    Result := (Model <> '') and SameText(Copy(SetName, 1, Length(Model)), Model);
  end;

begin
  Result := nil;
  for var S in Typed do
  begin
    var Model := Trim(S.Model);
    var Known := False;
    var Used := False;
    if SameText(Trim(S.Mfr), 'Ohm Labs') then
    begin
      for var Id := Low(TOhmSetId) to High(TOhmSetId) do Known := Known or Names(Model, OHM_SET_NAME[Id]);
      for var Name in UsedSets do Used := Used or Names(Model, Name);
    end;
    if Used or not Known then Result := Result + [S];
  end;
end;

function Text(const Obj: TJSONObject; const Key: String): String;
begin
  Result := '';
  if Obj = nil then Exit;
  var V := Obj.GetValue(Key);
  if (V is TJSONString) and not (V is TJSONNumber) then Result := TJSONString(V).Value;
end;

function Child(const Obj: TJSONObject; const Key: String): TJSONObject;
begin
  Result := nil;
  if Obj = nil then Exit;
  var V := Obj.GetValue(Key);
  if V is TJSONObject then Result := TJSONObject(V);
end;

{ a number kept as text: the member's number, shown; '' when it is not there }
function NumberText(const Obj: TJSONObject; const Key: String): String;
begin
  Result := '';
  if Obj = nil then Exit;
  var V := Obj.GetValue(Key);
  if V is TJSONNumber then Result := TJSONNumber(V).Value;
end;

procedure AddNumberText(const Obj: TJSONObject; const Key, Value: String);
var
  D: Double;
begin
  if (Trim(Value) <> '') and TryStrToFloat(Trim(Value), D, TFormatSettings.Invariant) then Obj.AddPair(Key, CfgJson(D));
end;

procedure AddDate(const Obj: TJSONObject; const Key: String; const D: TDate);
begin
  if D <> 0 then Obj.AddPair(Key, CfgDate(D));
end;

function StandardsJson(const List: TCertStandards): TJSONArray;
begin
  Result := TJSONArray.Create;
  for var S in List do
  begin
    var O := TJSONObject.Create;
    Result.AddElement(O);
    O.AddPair(K_SERIAL, S.Serial);
    O.AddPair(K_MFR, S.Mfr);
    O.AddPair(K_MODEL, S.Model);
    AddDate(O, K_CAL_DUE_STD, S.Due);
  end;
end;

{ False when a line's date is not a date }
function StandardsOf(const Obj: TJSONObject; out List: TCertStandards): Boolean;
var
  Arr: TJSONArray;
  S: TCertStandard;
begin
  List := nil;
  Result := True;
  if (Obj = nil) or not Obj.TryGetValue<TJSONArray>(K_STANDARDS, Arr) then Exit;
  for var V in Arr do
  begin
    if not (V is TJSONObject) then Continue;
    S.Serial := Text(TJSONObject(V), K_SERIAL);
    S.Mfr := Text(TJSONObject(V), K_MFR);
    S.Model := Text(TJSONObject(V), K_MODEL);
    if not CfgDateOf(TJSONObject(V), K_CAL_DUE_STD, S.Due) then Exit(False);
    List := List + [S];
  end;
end;

{ the typed part, the same members in the configuration's section and in the certificate }
procedure InputsToJson(const I: TCertInputs; const Obj: TJSONObject; const Standards: TCertStandards);
begin
  var Owner := TJSONObject.Create;
  Obj.AddPair(K_OWNER, Owner);
  Owner.AddPair(K_NAME, I.OwnerName);
  Owner.AddPair(K_ADDRESS1, I.OwnerAddress1);
  Owner.AddPair(K_ADDRESS2, I.OwnerAddress2);

  var Instrument := TJSONObject.Create;
  Obj.AddPair(K_INSTRUMENT, Instrument);
  Instrument.AddPair(K_MANUFACTURER, I.Manufacturer);
  Instrument.AddPair(K_DESCRIPTION, I.Description);
  Instrument.AddPair(K_MODEL, I.Model);
  Instrument.AddPair(K_SERIAL, I.Serial);

  Obj.AddPair(K_PROCEDURE1, I.Procedure1);
  Obj.AddPair(K_PROCEDURE2, I.Procedure2);
  Obj.AddPair(K_TECHNICIAN, I.Technician);
  Obj.AddPair(K_REMARKS, I.Remarks);
  AddNumberText(Obj, K_TEMP, I.Temp);
  AddNumberText(Obj, K_HUMIDITY, I.Humidity);
  AddDate(Obj, K_PREV_DATE, I.PrevCalDate);
  Obj.AddPair(K_NOTES, I.Notes);
  Obj.AddPair(K_STANDARDS, StandardsJson(Standards));
  Obj.AddPair(K_COMMENTS, I.Comments);

  var Form := TJSONObject.Create;
  Obj.AddPair(K_FORM, Form);
  Form.AddPair(K_FORM_NO, I.FormNo);
  Form.AddPair(K_REV, I.Rev);
  Form.AddPair(K_REV_DATE, I.RevDate);
end;

{ False, with the reason in Why, when a date in it is not a date }
function InputsOfJson(const Obj: TJSONObject; out I: TCertInputs; out Why: String): Boolean;
begin
  I := Default(TCertInputs);
  Why := '';
  var Owner := Child(Obj, K_OWNER);
  I.OwnerName := Text(Owner, K_NAME);
  I.OwnerAddress1 := Text(Owner, K_ADDRESS1);
  I.OwnerAddress2 := Text(Owner, K_ADDRESS2);
  var Instrument := Child(Obj, K_INSTRUMENT);
  I.Manufacturer := Text(Instrument, K_MANUFACTURER);
  I.Description := Text(Instrument, K_DESCRIPTION);
  I.Model := Text(Instrument, K_MODEL);
  I.Serial := Text(Instrument, K_SERIAL);
  I.Procedure1 := Text(Obj, K_PROCEDURE1);
  I.Procedure2 := Text(Obj, K_PROCEDURE2);
  I.Technician := Text(Obj, K_TECHNICIAN);
  I.Remarks := Text(Obj, K_REMARKS);
  I.Temp := NumberText(Obj, K_TEMP);
  I.Humidity := NumberText(Obj, K_HUMIDITY);
  I.Notes := Text(Obj, K_NOTES);
  I.Comments := Text(Obj, K_COMMENTS);
  var Form := Child(Obj, K_FORM);
  I.FormNo := Text(Form, K_FORM_NO);
  I.Rev := Text(Form, K_REV);
  I.RevDate := Text(Form, K_REV_DATE);

  Result := CfgDateOf(Obj, K_PREV_DATE, I.PrevCalDate) and StandardsOf(Obj, I.Standards);
  if not Result then Why := Format('"%s" has a date that is not yyyy-mm-dd', [K_SECTION]);
end;

{ TCertInputs }

class function TCertInputs.Defaults: TCertInputs;

  procedure Standard(const Serial, Mfr, Model: String; const Due: TDate);
  var
    S: TCertStandard;
  begin
    S.Serial := Serial;
    S.Mfr := Mfr;
    S.Model := Model;
    S.Due := Due;
    Result.Standards := Result.Standards + [S];
  end;

begin
  Result := Default(TCertInputs);
  { the "Certificate" sheet of the December 2022 workbook }
  Result.OwnerName := 'Maccor, Inc.';
  Result.OwnerAddress1 := '4322 S. 49th W. Ave.';
  Result.OwnerAddress2 := 'Tulsa, OK  74107';
  Result.Manufacturer := 'Maccor';
  Result.Description := '8 Shunt Autocalibrator';
  Result.Model := 'BT700507';
  Result.Serial := 'Prototype';
  Result.Procedure1 := 'LOP-72-01 Calibration of AutoCalibrators';
  Result.Procedure2 := 'and Shunts, Rev. 01';
  Result.Technician := 'Baldus, J.';
  Result.Temp := '23.54';
  Result.Humidity := '17';
  Result.Notes := 'Temperature Coefficient of Resistance uncertainty has been accounted for, but not shown due to ' +
    'negligible impact on overall uncertainty.';
  Result.Comments := 'MACCOR, Inc. hereby certifies that the above-referenced instrument meets or exceeds its ' +
    'published specifications, and measurement and calibration procedures are compliant with ISO/IEC 17025:2017.  ' +
    'Calibration and measurement procedures are defined in the MACCOR Laboratory Quality and Procedure Manual ' +
    '(LQPM) and associated procedures.  Procedures use primary or secondary standards whose calibration is ' +
    'traceable, through NIST or other National Measurement Institute, to the International System of Units (SI) ' +
    'or to accepted intrinsic standards of measurement, or whose accuracy have been determined by ratio-type ' +
    'calibration techniques.  The reported expanded uncertainty is based on standard uncertainty multiplied by a ' +
    'coverage factor k=2, providing a level of confidence of approximately 95%.  The reported data is valid only ' +
    'at the time of test and does not take into account the effects of supply voltage/current, humidity, ' +
    'long-term drift, transportation or other factors that may affect the stability of the tested device. This ' +
    'document relates only to the items, identified herein, and complies with all requirements of the referenced ' +
    'Purchase Order associated with this certificate.';
  { its "Standards used" besides the meters: both Ohm Labs lines of its formula; which are printed follows the standards used (CertTypedStandards) }
  Standard('10195', 'Ohm Labs', 'MRS', EncodeDate(2023, 9, 1));
  Standard('18471', 'Ohm Labs', 'MCS', EncodeDate(2023, 9, 7));
  Standard('221238210', 'Control Company', '4410', EncodeDate(2024, 2, 9));
  { its page footer }
  Result.FormNo := 'LDF-78-03';
  Result.Rev := 'Rev. 04';
  Result.RevDate := '06/30/2021';
end;

function TCertInputs.Check: String;
var
  D: Double;
begin
  Result := '';
  if (Trim(Temp) <> '') and not TryStrToFloat(Trim(Temp), D, TFormatSettings.Invariant) then
    Exit('Temp. is not a number (use a point, e.g. 23.5)');
  if (Trim(Humidity) <> '') and not TryStrToFloat(Trim(Humidity), D, TFormatSettings.Invariant) then
    Exit('Humidity is not a number (use a point, e.g. 17.0)');
end;

class function TCertInputs.Load(out Inputs: TCertInputs; out Why: String): Boolean;
begin
  Inputs := Defaults;
  Result := False;
  var Section := TAppConfig.ReadSection(K_SECTION, Why);
  if Section = nil then Exit;
  try
    var Read: TCertInputs;
    Result := InputsOfJson(Section, Read, Why);
    if Result then Inputs := Read;
  finally
    Section.Free;
  end;
end;

function TCertInputs.Save(out Why: String): Boolean;
begin
  Why := Check;
  if Why <> '' then Exit(False);
  var Section := TJSONObject.Create;
  InputsToJson(Self, Section, Standards);
  Result := TAppConfig.WriteSection(K_SECTION, Section, Why);
end;

{ TCertificateData }

class function TCertificateData.Refresh(out Cert: TCertificate; out Why: String; const Accepted: Integer;
  const Previous: Double; const Model: String; const Digits: Integer; const Store: Boolean): Boolean;
var
  Entries: TDataShunts;
  Labs: TOhmLabs;
  Meters: TFlukeMeters;
  OldDigits: array [1..CERT_SHUNTS] of Integer;
  OldPrevious: array [1..CERT_SHUNTS] of Double;
  OldModel, Ignore: String;
  Kind: TFlukeModel;
  Arr: TJSONArray;
  A: TMeterInputs;
  Spec: TFlukeRange;
  Std: TOhmStandard;
  StdSet: TOhmSetId;
  UsedSets: TArray<String>;                   { the Ohm Labs sets the accepted shunts' standards are in }

  { what the file's members hold of the things only an Accept knows }
  procedure ReadKept;
  begin
    OldModel := '';
    for var I := 1 to CERT_SHUNTS do
    begin
      OldDigits[I] := 0;
      OldPrevious[I] := 0;
    end;

    var Meter := TAppData.ReadSection(K_METER, Ignore);
    if Meter <> nil then
    try
      OldModel := Text(Meter, K_MODEL);
      if Meter.TryGetValue<TJSONArray>(K_SHUNTS, Arr) then
        for var V in Arr do
        begin
          if not (V is TJSONObject) then Continue;
          var Slot := Round(CfgDouble(TJSONObject(V), K_SLOT, 0));
          var Row := Child(TJSONObject(V), 'ref');
          if (Slot >= 1) and (Slot <= CERT_SHUNTS) and (Row <> nil) then OldDigits[Slot] := Round(CfgDouble(Row, 'digits', 0));
        end;
    finally
      Meter.Free;
    end;

    var Old := TAppData.ReadSection(K_SECTION, Ignore);
    if Old <> nil then
    try
      if Old.TryGetValue<TJSONArray>(K_SHUNTS, Arr) then
        for var V in Arr do
        begin
          if not (V is TJSONObject) then Continue;
          var Slot := Round(CfgDouble(TJSONObject(V), K_SHUNT, 0));
          if (Slot >= 1) and (Slot <= CERT_SHUNTS) then OldPrevious[Slot] := CfgDouble(TJSONObject(V), K_PREVIOUS, 0);
        end;
    finally
      Old.Free;
    end;
  end;

  procedure Gap(const Shunt: Integer; const Reason: String);
  begin
    Cert.Gaps := Cert.Gaps + [Format('Shunt %d: %s', [Shunt, Reason])];
  end;

begin
  Result := False;
  Cert := Default(TCertificate);

  TCertInputs.Load(Cert.Inputs, Why);
  if Why <> '' then Exit;
  if not TCalData.Load(Entries, Why) then Exit;
  ReadKept;

  Labs := TOhmLabs.Create;
  Meters := TFlukeMeters.Create;
  try
    Labs.Load(Why);
    if Why <> '' then Exit;
    Meters.Load(Why);
    if Why <> '' then Exit;

    Cert.MeterModel := Model;
    if Cert.MeterModel = '' then Cert.MeterModel := OldModel;
    Kind := Low(TFlukeModel);
    for var M := Low(TFlukeModel) to High(TFlukeModel) do
      if SameText(Cert.MeterModel, FLUKE_MODEL_NAME[M]) then Kind := M;
    Cert.MeterModel := FLUKE_MODEL_NAME[Kind];
    var Meter := Meters.Meters[Kind];

    var MeterSection := TJSONObject.Create;
    try
      MeterSection.AddPair(K_MODEL, Cert.MeterModel);
      var MeterArr := TJSONArray.Create;
      MeterSection.AddPair(K_SHUNTS, MeterArr);

      var MaxDiff: Double := 0;                    { MAX over no cells is 0 }
      for var E in Entries do
      begin
        if (E.Shunt < 1) or (E.Shunt > CERT_SHUNTS) then Continue;
        var Row := Default(TCertShunt);
        Row.Nominal := E.Nominal;

        { the meter sheet's typed cells }
        A := Default(TMeterInputs);
        A.Shunt := E.Shunt;
        A.Standard := E.Standard;
        A.Digits := OldDigits[E.Shunt];
        if (E.Shunt = Accepted) and (Digits > 0) then A.Digits := Digits;
        if A.Digits = 0 then A.Digits := Meter.Digits;
        A.RefG := E.Ref.Average;
        A.UutG := E.Uut.Average;

        var Missing := '';
        if not E.DmmRange(A.RangeV) then Missing := 'the standard times the current is 2 V or more: no meter range'
        else if not Meter.RangeSpec(A.RangeV, Spec) then
          Missing := Format('the %s sheet has no accuracy for the %s V range', [Cert.MeterModel, CfgText(A.RangeV)])
        else if not Labs.Find(E.Standard, Std, StdSet) then
          Missing := Format('the standard %s ohm is not on the Ohm Labs sheet', [CfgText(E.Standard)])
        else if not (E.Ref.Repeatability(E.Samples, A.RefK) and E.Uut.Repeatability(E.Samples, A.UutK)) then
          Missing := 'no samples: no repeatability';

        { the set the shunt was measured against, whatever else may be missing for its value }
        if Labs.Find(E.Standard, Std, StdSet) then UsedSets := UsedSets + [OHM_SET_NAME[StdSet]];

        var Answer := Default(TMeterAnswer);
        if Missing = '' then
        begin
          A.PpmReading := Spec.PpmReading;
          A.PpmRange := Spec.PpmRange;
          A.CalUnc := Spec.CalUnc;
          A.StandardUnc := Std.UncOhms;
          Answer := SolveMeter(A);
        end
        else Answer.Why := Missing;
        MeterArr.AddElement(MeterJson(A, Answer));

        Row.HaveMeasured := Answer.Ok;
        if Answer.Ok then
        begin
          Row.Measured := Answer.Resistance;
          Row.Unc := Answer.UncPpm;
        end
        else Gap(E.Shunt, Answer.Why);

        Row.Previous := OldPrevious[E.Shunt];
        if (E.Shunt = Accepted) and (Previous > 0) then Row.Previous := Previous;
        Row.HaveDiff := Row.HaveMeasured and (Row.Previous > 0);
        if Row.HaveDiff then
        begin
          Row.Diff := Abs(Row.Measured - Row.Previous) / Row.Previous * 100;
          MaxDiff := Max(MaxDiff, Row.Diff);
        end;
        Cert.Shunts[E.Shunt] := Row;

        if (E.Accepted <> 0) and (DateOf(E.Accepted) > Cert.CalDate) then Cert.CalDate := DateOf(E.Accepted);
      end;

      Cert.CalDue := CertDue(Cert.CalDate, Cert.Inputs.OwnerName, MaxDiff);
      Cert.HaveDays := (Cert.Inputs.PrevCalDate <> 0) and (Cert.CalDate <> 0);
      if Cert.HaveDays then Cert.DaysSince := Round(Cert.CalDate - Cert.Inputs.PrevCalDate);
      Cert.Number := CertNumber(Cert.Inputs.Serial, Cert.CalDate, Cert.Inputs.Technician);

      { the meters the bench ran with: those of the type that have a serial number }
      for var I := 0 to FLUKE_UNITS -1 do
        if Meter.Units[I].Serial <> '' then
        begin
          var S: TCertStandard;
          S.Serial := Meter.Units[I].Serial;
          S.Mfr := FLUKE_MANUFACTURER;
          S.Model := Cert.MeterModel;
          S.Due := Meter.Units[I].Due;
          Cert.Standards := Cert.Standards + [S];
        end;
      Cert.Standards := Cert.Standards + CertTypedStandards(Cert.Inputs.Standards, UsedSets);

      { the certificate member, in the sheet's order from the top }
      var Section := TJSONObject.Create;
      try
        Section.AddPair(K_NUMBER, Cert.Number);
        AddDate(Section, K_CAL_DATE, Cert.CalDate);
        AddDate(Section, K_CAL_DUE, Cert.CalDue);
        if Cert.HaveDays then Section.AddPair(K_DAYS, TJSONNumber.Create(Cert.DaysSince));
        Section.AddPair(K_METER_MODEL, Cert.MeterModel);

        var Rows := TJSONArray.Create;
        Section.AddPair(K_SHUNTS, Rows);
        for var I := 1 to CERT_SHUNTS do
        begin
          var R := Cert.Shunts[I];
          var O := TJSONObject.Create;
          Rows.AddElement(O);
          O.AddPair(K_SHUNT, TJSONNumber.Create(I));
          if R.Nominal > 0 then O.AddPair(K_NOMINAL, CfgJson(R.Nominal, VALUE_DIGITS)) else O.AddPair(K_NOMINAL, TJSONNull.Create);
          if R.HaveMeasured then
          begin
            O.AddPair(K_MEASURED, CfgJson(R.Measured, VALUE_DIGITS));
            O.AddPair(K_UNC, CfgJson(R.Unc, VALUE_DIGITS));
          end
          else
          begin
            O.AddPair(K_MEASURED, TJSONNull.Create);
            O.AddPair(K_UNC, TJSONNull.Create);
          end;
          if R.Previous > 0 then O.AddPair(K_PREVIOUS, CfgJson(R.Previous, VALUE_DIGITS)) else O.AddPair(K_PREVIOUS, TJSONNull.Create);
          if R.HaveDiff then O.AddPair(K_DIFF, CfgJson(R.Diff, VALUE_DIGITS)) else O.AddPair(K_DIFF, TJSONNull.Create);
        end;

        InputsToJson(Cert.Inputs, Section, Cert.Standards);

        if not Store then
        begin
          Result := True;                     { both members are freed on the way out, unwritten }
          Exit;
        end;

        { the meter member first: the certificate is made from it }
        if not TAppData.WriteSection(K_METER, MeterSection, Why) then
        begin
          MeterSection := nil;
          Exit;
        end;
        MeterSection := nil;
        Result := TAppData.WriteSection(K_SECTION, Section, Why);
        Section := nil;
      finally
        Section.Free;
      end;
    finally
      MeterSection.Free;
    end;
  finally
    Labs.Free;
    Meters.Free;
  end;
end;

class function TCertificateData.Load(out Cert: TCertificate; out Why: String): Boolean;
var
  Arr: TJSONArray;
begin
  Result := False;
  Cert := Default(TCertificate);
  var Section := TAppData.ReadSection(K_SECTION, Why);
  if Section = nil then
  begin
    if Why = '' then Why := Format('%s has no certificate yet: accept a shunt first', [ExtractFileName(TAppData.FileName)]);
    Exit;
  end;

  try
    if not InputsOfJson(Section, Cert.Inputs, Why) then Exit;
    { in the member the standards are the whole table }
    Cert.Standards := Cert.Inputs.Standards;
    Cert.Number := Text(Section, K_NUMBER);
    Cert.MeterModel := Text(Section, K_METER_MODEL);
    if not (CfgDateOf(Section, K_CAL_DATE, Cert.CalDate) and CfgDateOf(Section, K_CAL_DUE, Cert.CalDue)) then
    begin
      Why := Format('"%s" has a date that is not yyyy-mm-dd', [K_SECTION]);
      Exit;
    end;
    Cert.HaveDays := Section.GetValue(K_DAYS) is TJSONNumber;
    if Cert.HaveDays then Cert.DaysSince := Round(CfgDouble(Section, K_DAYS, 0));

    if Section.TryGetValue<TJSONArray>(K_SHUNTS, Arr) then
      for var V in Arr do
      begin
        if not (V is TJSONObject) then Continue;
        var O := TJSONObject(V);
        var Slot := Round(CfgDouble(O, K_SHUNT, 0));
        if (Slot < 1) or (Slot > CERT_SHUNTS) then Continue;
        var R := Default(TCertShunt);
        R.Nominal := CfgDouble(O, K_NOMINAL, 0);
        R.HaveMeasured := O.GetValue(K_MEASURED) is TJSONNumber;
        R.Measured := CfgDouble(O, K_MEASURED, 0);
        R.Unc := CfgDouble(O, K_UNC, 0);
        R.Previous := CfgDouble(O, K_PREVIOUS, 0);
        R.HaveDiff := O.GetValue(K_DIFF) is TJSONNumber;
        R.Diff := CfgDouble(O, K_DIFF, 0);
        Cert.Shunts[Slot] := R;
      end;
    Result := True;
  finally
    Section.Free;
  end;
end;

end.
