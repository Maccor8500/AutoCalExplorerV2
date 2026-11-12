unit AutoCalProtocolU;

{
  AutoCalibrator 528LB (Rev E) host-side protocol: JSON-RPC 2.0 over UDP, method "MacAutoCal".
  Mirrors include/JSONParser.h and include/AutoCal.h of the firmware. No UI, no sockets: only
  the message format, the calibration record (system_info_t) and its field rules.

  SHARED :: the one home for this unit (moved here from AutoCalibrator_528LB\test\Delphi on 2026-11-06).
  Used by the firmware test app (AutoCalv2) and by MacUniModCal's TAutoCalibrator (atModular); both
  reference it here, so a protocol change (firmware CHANGELOG.md, 0.5.2 at the move) lands once.
  Depends on nothing but the RTL: keep it that way so any project can take it.
}

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.DateUtils, System.Math, System.StrUtils, Generics.Collections;

const
  AUTOCAL_PORT    = 57590;        { board UDP port }
  ANNOUNCE_PORT   = 8989;         { the board broadcasts "Gratuitous Echo!!!." here at start-up }
  RPC_VERSION     = '2.0';
  METHOD_NAME     = 'MacAutoCal';
  DEVICE_NAME     = 'AutoCalibrator';
  CHANS           = 8;
  CLEAR_ALL_CHANS = 8;            { f_num releasing a whole relay group }
  TRACE_COUNT     = 8;

  { f_class }
  FC_SYS_STATUS   = 0;
  FC_VCHAN_RLY    = 1;            { Maccor channel voltage-sense relays CHVS1..8 }
  FC_ICHAN_RLY    = 2;            { Maccor channel current relays CHI1..8 }
  FC_VSENSE_RLY   = 3;            { voltage-sense shunt relays RNGV1..8 }
  FC_ISENSE_RLY   = 4;            { current shunt relays RNGI1..8 }
  FC_FAN_RLY      = 5;            { 0 = ON, 1 = OFF }
  FC_V_SRC_RLY    = 6;            { 0 = ON, 1 = OFF }
  FC_DPS_RLY      = 7;            { 0 = ON, 1 = OFF }
  FC_RESET        = 8;
  FC_SYS_UPDATE   = 9;
  FC_SYS_DOWNLD   = 10;
  FC_ERROR        = 10;           { reported with any error; f_num then carries the code }

  { f_num for FC_SYS_STATUS }
  ST_FIRMWARE     = 1;
  ST_RD_IDENTITY  = 2;
  ST_RD_SHUNT     = 3;            { params index 0..7 }
  ST_RD_TRACE     = 4;            { params index 0..7 }
  ST_RD_COMMENTS  = 5;
  ST_RD_STATE     = 6;

  { f_num for FC_SYS_UPDATE }
  SU_IDENTITY     = 0;
  SU_SHUNT        = 1;
  SU_TRACE        = 2;
  SU_COMMENTS     = 3;
  SU_COMMIT       = 4;

  { f_num for FC_RESET (2 was "external sources": rejected by the firmware) }
  RS_CHANNELS     = 0;
  RS_SHUNTS       = 1;
  RS_ALL          = 3;
  RS_FIRMWARE     = 4;

  { f_num for the supply classes; inverted on the wire }
  SUPPLY_ON       = 0;
  SUPPLY_OFF      = 1;

  { error codes }
  ERR_NONE        = 0;
  ERR_JSON        = 1;
  ERR_METHOD      = 100;
  ERR_RPC         = 101;
  INV_CHAN        = 102;
  INV_OPTION      = 103;
  INV_CLASS       = 104;
  ERR_INTERLOCK   = 105;
  INV_FIELD       = 106;
  ERR_EEPROM      = 107;
  STATUS_OK       = 'OK';

  { char-array capacities of system_info_t: the text must be shorter than the capacity }
  CAP_SERIAL        = 10;
  CAP_MODEL         = 15;
  CAP_CERT          = 20;
  CAP_MANUFACTURER  = 15;
  CAP_OWNER         = 15;
  CAP_TECH          = 35;
  CAP_COMMENTS      = 256;
  CAP_TRACE_SERIAL  = 25;
  CAP_TRACE_MANUF   = 25;
  CAP_TRACE_MODEL   = 10;
  MIN_YEAR          = 2000;       { parse_date() refuses earlier years (firmware 0.5.4; 2025 before it) }
  MAX_YEAR          = 4294967295; { date_t.year is a uint32_t }

type
  { calendar date as the firmware keeps it; Year 0 = not set }
  TCalDate = record
    Year: UInt64;
    Month, Day: Byte;

    function IsSet: Boolean;
    function ToText: String;                                   { "YYYY-MM-DD" or "" }
    function ToDisplay: String;                                { same, or "(not set)" }
    class function Parse(const Text: String; out Date: TCalDate): Boolean; static;   { the firmware's rules }
    class function FromDateTime(const Value: TDateTime): TCalDate; static;
    class function Empty: TCalDate; static;
  end;

  TShuntField = (sfCurrent, sfPrevious, sfDifference, sfUncertainty);

  TShuntRecord = record
    Index: Byte;
    Current, Previous, Difference, Uncertainty: Double;
    { the entry as imported or typed, kept beside the number for exactness (MacUniModCal's TShuntInfo.AsStr):
      it is what the grid shows and what goes to the board, digit for digit. '' = no entry, the number's
      shortest exact text stands in }
    AsStr: array [TShuntField] of String;

    function Value(const F: TShuntField): Double;
    { the number and its entry together; an empty Entry leaves the number to speak for itself }
    procedure Put(const F: TShuntField; const V: Double; const Entry: String = '');
    function Text(const F: TShuntField): String;        { AsStr, else FormatValue }
    function JsonText(const F: TShuntField): String;    { AsStr when it is a JSON number, else FormatValue }
  end;

  TTraceRecord = record
    Serial, Manufacturer, Model: String;
    CalDue: TCalDate;
    { the due date as read or typed ("2023-10-11"), kept so a date the firmware refuses (a year before
      MIN_YEAR) still shows; '' = CalDue speaks for itself }
    CalDueStr: String;
    function CalDueText: String;        { CalDueStr, else CalDue.ToText }
  end;

  TFirmwareInfo = record
    Device: String;
    Major, Minor, Patch: Integer;
    DateTime, Notes: String;
    function Version: String;
  end;

  { system_info_t }
  PSystemInfo = ^TSystemInfo;
  TSystemInfo = record
    Serial, Model, Cert, Manufacturer, Owner: String;
    CalDate, CalDatePrev, CalDue: TCalDate;
    Temp, Humd: Double;
    Tech: String;
    Comments: String;
    Shunts: array [0..CHANS -1] of TShuntRecord;
    Trace: array [0..TRACE_COUNT -1] of TTraceRecord;
    { firmware_t: read-only on the host, the board fills it with its running build (ST_FIRMWARE) }
    Firmware: TFirmwareInfo;

    procedure Clear;
    { trims every text to its capacity; returns what was cut, one line per field }
    function Fit(const Problems: TStrings = nil): Boolean;
  end;

  TRecordState = record
    Valid, Dirty: Boolean;
    Version, Bytes: Integer;
    function ToText: String;
  end;

  { the message format; every function is static and allocation ownership is stated per function }
  TAutoCalProtocol = record
    class function ErrorText(const Code: Integer): String; static;
    class function ClassName(const FClass: Integer): String; static;

    { request document; Params (may be nil) is merged into "params" next to FClass/FNum and freed }
    class function Request(const FClass, FNum: Integer; const Id: Word; const Params: TJSONObject = nil): TJSONObject; static;
    { reply inspection; Reply stays owned by the caller }
    class function StatusOf(const Reply: TJSONObject): String; static;
    class function IsOk(const Reply: TJSONObject): Boolean; static;
    class function ErrorOf(const Reply: TJSONObject): Integer; static;        { the f_num of an error reply, else ERR_NONE }
    class function ParamsOf(const Reply: TJSONObject): TJSONObject; static;   { nil if absent }
    class function IdOf(const Reply: TJSONObject): Integer; static;

    { section payloads for FC_SYS_UPDATE: new objects, owned by the caller }
    class function IdentityToJSON(const Info: TSystemInfo): TJSONObject; static;
    class function ShuntToJSON(const Info: TSystemInfo; const Index: Integer): TJSONObject; static;
    class function TraceToJSON(const Info: TSystemInfo; const Index: Integer): TJSONObject; static;
    class function CommentsToJSON(const Info: TSystemInfo): TJSONObject; static;
    class function IndexToJSON(const Index: Integer): TJSONObject; static;

    { section readback from a FC_SYS_STATUS reply's params }
    class procedure IdentityFromJSON(const P: TJSONObject; var Info: TSystemInfo); static;
    class function ShuntFromJSON(const P: TJSONObject; var Info: TSystemInfo): Integer; static;   { index stored, -1 if bad }
    class function TraceFromJSON(const P: TJSONObject; var Info: TSystemInfo): Integer; static;
    class procedure CommentsFromJSON(const P: TJSONObject; var Info: TSystemInfo); static;
    class function FirmwareFromJSON(const P: TJSONObject; out FW: TFirmwareInfo): Boolean; static;
    class function StateFromJSON(const P: TJSONObject; out State: TRecordState): Boolean; static;

    class function FitText(const S: String; const Cap: Integer): String; static;
    class function FormatValue(const V: Double): String; static;      { shortest round-trip text for display }
  end;

implementation

{ TCalDate }

function TCalDate.IsSet: Boolean;
begin
  Result := Year <> 0;
end;

function TCalDate.ToText: String;
begin
  if not IsSet then Exit('');
  Result := Format('%s-%.2d-%.2d', [UIntToStr(Year).PadLeft(4, '0'), Month, Day]);
end;

function TCalDate.ToDisplay: String;
begin
  Result := ToText;
  if Result = '' then Result := '(not set)';
end;

class function TCalDate.Empty: TCalDate;
begin
  Result.Year := 0;
  Result.Month := 0;
  Result.Day := 0;
end;

class function TCalDate.FromDateTime(const Value: TDateTime): TCalDate;
var
  Y, M, D: Word;
begin
  DecodeDate(Value, Y, M, D);
  Result.Year := Y;
  Result.Month := M;
  Result.Day := D;
end;

{ "YYYY-MM-DD" with 4..10 year digits (no leading zeros past 4), real Gregorian day, year >= 2025; "" clears }
class function TCalDate.Parse(const Text: String; out Date: TCalDate): Boolean;
const
  DAYS: array [1..12] of Byte = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
begin
  Result := False;
  Date := Empty;
  if Text = '' then Exit(True);

  var L := Length(Text);
  if (L < 10) or (L > 16) then Exit;
  var Y := L -6;
  if (Text[Y +1] <> '-') or (Text[Y +4] <> '-') then Exit;
  for var I := 1 to L do
    if (I <> Y +1) and (I <> Y +4) and not CharInSet(Text[I], ['0'..'9']) then Exit;
  if (Y > 4) and (Text[1] = '0') then Exit;

  var Year: UInt64 := 0;
  for var I := 1 to Y do Year := Year *10 +UInt64(Ord(Text[I]) -Ord('0'));
  if (Year < MIN_YEAR) or (Year > MAX_YEAR) then Exit;

  var Month := StrToIntDef(Copy(Text, Y +2, 2), 0);
  var Day   := StrToIntDef(Copy(Text, Y +5, 2), 0);
  if (Month < 1) or (Month > 12) or (Day < 1) then Exit;

  var Last: Integer := DAYS[Month];
  var Leap := ((Year mod 4 = 0) and (Year mod 100 <> 0)) or (Year mod 400 = 0);
  if (Month = 2) and Leap then Last := 29;
  if Day > Last then Exit;

  Date.Year := Year;
  Date.Month := Month;
  Date.Day := Day;
  Result := True;
end;

{ TShuntRecord }

function TShuntRecord.Value(const F: TShuntField): Double;
begin
  case F of
    sfCurrent:     Result := Current;
    sfPrevious:    Result := Previous;
    sfDifference:  Result := Difference;
    else           Result := Uncertainty;
  end;
end;

procedure TShuntRecord.Put(const F: TShuntField; const V: Double; const Entry: String);
begin
  case F of
    sfCurrent:     Current := V;
    sfPrevious:    Previous := V;
    sfDifference:  Difference := V;
    else           Uncertainty := V;
  end;
  AsStr[F] := Trim(Entry);
end;

function TShuntRecord.Text(const F: TShuntField): String;
begin
  Result := AsStr[F];
  if Result = '' then Result := TAutoCalProtocol.FormatValue(Value(F));
end;

{ RFC 8259 number: -?int frac? exp?, int = 0 | [1-9][0-9]* }
function IsJsonNumber(const S: String): Boolean;
var
  I, N: Integer;

  function Digits: Boolean;         { one or more, advancing I }
  begin
    var Start := I;
    while (I <= N) and CharInSet(S[I], ['0'..'9']) do Inc(I);
    Result := I > Start;
  end;

begin
  Result := False;
  N := Length(S);
  I := 1;
  if (I <= N) and (S[I] = '-') then Inc(I);
  if I > N then Exit;
  if S[I] = '0' then Inc(I)
  else if not Digits then Exit;
  if (I <= N) and (S[I] = '.') then
  begin
    Inc(I);
    if not Digits then Exit;
  end;
  if (I <= N) and CharInSet(S[I], ['e', 'E']) then
  begin
    Inc(I);
    if (I <= N) and CharInSet(S[I], ['+', '-']) then Inc(I);
    if not Digits then Exit;
  end;
  Result := I > N;
end;

function TShuntRecord.JsonText(const F: TShuntField): String;
begin
  Result := AsStr[F];
  if not IsJsonNumber(Result) then Result := TAutoCalProtocol.FormatValue(Value(F));
end;

{ TTraceRecord }

function TTraceRecord.CalDueText: String;
begin
  if CalDueStr <> '' then Result := CalDueStr else Result := CalDue.ToText;
end;

{ TSystemInfo }

procedure TSystemInfo.Clear;
begin
  Self := Default(TSystemInfo);
  for var I := 0 to CHANS -1 do Shunts[I].Index := I;
end;

function TSystemInfo.Fit(const Problems: TStrings): Boolean;

  procedure Cut(var S: String; const Cap: Integer; const Name: String);
  begin
    if Length(S) < Cap then Exit;
    if Assigned(Problems) then Problems.Add(Format('%s: "%s" cut to %d characters', [Name, S, Cap -1]));
    S := TAutoCalProtocol.FitText(S, Cap);
    Result := False;
  end;

begin
  Result := True;
  Cut(Serial,       CAP_SERIAL,       'serial');
  Cut(Model,        CAP_MODEL,        'model');
  Cut(Cert,         CAP_CERT,         'cert');
  Cut(Manufacturer, CAP_MANUFACTURER, 'manufacturer');
  Cut(Owner,        CAP_OWNER,        'owner');
  Cut(Tech,         CAP_TECH,         'tech');
  Cut(Comments,     CAP_COMMENTS,     'comments');

  for var I := 0 to TRACE_COUNT -1 do
  begin
    Cut(Trace[I].Serial,       CAP_TRACE_SERIAL, Format('trace %d serial', [I]));
    Cut(Trace[I].Manufacturer, CAP_TRACE_MANUF,  Format('trace %d manufacturer', [I]));
    Cut(Trace[I].Model,        CAP_TRACE_MODEL,  Format('trace %d model', [I]));
  end;
end;

{ TFirmwareInfo }

function TFirmwareInfo.Version: String;
begin
  Result := Format('%d.%d.%d', [Major, Minor, Patch]);
end;

{ TRecordState }

function TRecordState.ToText: String;
begin
  Result := Format('record %s, %s, layout v%d, %d bytes',
    [IfThen(Valid, 'valid', 'blank/invalid'), IfThen(Dirty, 'uncommitted changes', 'committed'), Version, Bytes]);
end;

{ TAutoCalProtocol }

class function TAutoCalProtocol.ErrorText(const Code: Integer): String;
begin
  case Code of
    ERR_NONE:      Result := STATUS_OK;
    ERR_JSON:      Result := 'JSON Error';
    ERR_METHOD:    Result := 'Invalid Device Method!';
    ERR_RPC:       Result := 'Invalid JSON rpc!';
    INV_CHAN:      Result := 'Invalid Channel';
    INV_OPTION:    Result := 'Invalid FNum';
    INV_CLASS:     Result := 'Invalid FClass';
    ERR_INTERLOCK: Result := 'Interlock: V source and shunts exclusive';
    INV_FIELD:     Result := 'Invalid Field';
    ERR_EEPROM:    Result := 'EEPROM write failed';
    else           Result := Format('Error %d', [Code]);
  end;
end;

class function TAutoCalProtocol.ClassName(const FClass: Integer): String;
begin
  case FClass of
    FC_SYS_STATUS:  Result := 'status';
    FC_VCHAN_RLY:   Result := 'channel V-sense';
    FC_ICHAN_RLY:   Result := 'channel current';
    FC_VSENSE_RLY:  Result := 'V-sense shunt';
    FC_ISENSE_RLY:  Result := 'current shunt';
    FC_FAN_RLY:     Result := 'fan';
    FC_V_SRC_RLY:   Result := 'voltage source';
    FC_DPS_RLY:     Result := 'discharge supply';
    FC_RESET:       Result := 'reset';
    FC_SYS_UPDATE:  Result := 'system update';
    FC_SYS_DOWNLD:  Result := 'download';
    else            Result := Format('class %d', [FClass]);
  end;
end;

class function TAutoCalProtocol.Request(const FClass, FNum: Integer; const Id: Word; const Params: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', RPC_VERSION);
  Result.AddPair('method', METHOD_NAME);

  var P := TJSONObject.Create;
  P.AddPair('FClass', TJSONNumber.Create(FClass));
  P.AddPair('FNum',   TJSONNumber.Create(FNum));

  if Params <> nil then
  begin
    { move the pairs over: the request owns everything }
    while Params.Count > 0 do
    begin
      var Pair := Params.Pairs[0];
      Params.RemovePair(Pair.JsonString.Value);
      P.AddPair(Pair);
    end;
    Params.Free;
  end;

  Result.AddPair('params', P);
  Result.AddPair('id', TJSONNumber.Create(Id));
end;

class function TAutoCalProtocol.StatusOf(const Reply: TJSONObject): String;
begin
  Result := '';
  if Reply <> nil then Result := Reply.GetValue<String>('params.status', '');
end;

class function TAutoCalProtocol.IsOk(const Reply: TJSONObject): Boolean;
begin
  Result := StatusOf(Reply) = STATUS_OK;
end;

class function TAutoCalProtocol.ErrorOf(const Reply: TJSONObject): Integer;
begin
  Result := ERR_NONE;
  if (Reply = nil) or IsOk(Reply) then Exit;
  { an error reply replaces the class/number pair with FC_ERROR / code }
  if Reply.GetValue<Integer>('params.FClass', -1) = FC_ERROR then
    Result := Reply.GetValue<Integer>('params.FNum', -1);
end;

class function TAutoCalProtocol.ParamsOf(const Reply: TJSONObject): TJSONObject;
begin
  Result := nil;
  if Reply = nil then Exit;
  var V := Reply.GetValue('params');
  if V is TJSONObject then Result := TJSONObject(V);
end;

class function TAutoCalProtocol.IdOf(const Reply: TJSONObject): Integer;
begin
  Result := -1;
  if Reply <> nil then Result := Reply.GetValue<Integer>('id', -1);
end;

class function TAutoCalProtocol.FitText(const S: String; const Cap: Integer): String;
begin
  Result := S;
  if Length(Result) >= Cap then Result := Copy(Result, 1, Cap -1);
end;

class function TAutoCalProtocol.FormatValue(const V: Double): String;
begin
  { FloatToStr stops at 15 digits, which loses the last bits of a value like 10000.442205768586;
    the fewest digits (15, 16 or 17) that read back as the same double are the shortest exact text }
  for var Digits := 15 to 17 do
  begin
    Result := FloatToStrF(V, ffGeneral, Digits, 0, TFormatSettings.Invariant);
    var Back: Double;
    if TryStrToFloat(Result, Back, TFormatSettings.Invariant) and (Back = V) then Exit;
  end;
end;

class function TAutoCalProtocol.IdentityToJSON(const Info: TSystemInfo): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('serial',        Info.Serial);
  Result.AddPair('model',         Info.Model);
  Result.AddPair('cert',          Info.Cert);
  Result.AddPair('manufacturer',  Info.Manufacturer);
  Result.AddPair('owner',         Info.Owner);
  Result.AddPair('cal_date',      Info.CalDate.ToText);
  Result.AddPair('cal_date_prev', Info.CalDatePrev.ToText);
  Result.AddPair('cal_due',       Info.CalDue.ToText);
  Result.AddPair('temp',          TJSONNumber.Create(Info.Temp));
  Result.AddPair('humd',          TJSONNumber.Create(Info.Humd));
  Result.AddPair('tech',          Info.Tech);
end;

class function TAutoCalProtocol.ShuntToJSON(const Info: TSystemInfo; const Index: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  { numbers as entered, digit for digit; TJSONNumber's Double constructor would round to 15 digits }
  var S := Info.Shunts[Index];
  Result.AddPair('index',       TJSONNumber.Create(Index));
  Result.AddPair('current',     TJSONNumber.Create(S.JsonText(sfCurrent)));
  Result.AddPair('previous',    TJSONNumber.Create(S.JsonText(sfPrevious)));
  Result.AddPair('difference',  TJSONNumber.Create(S.JsonText(sfDifference)));
  Result.AddPair('uncertainty', TJSONNumber.Create(S.JsonText(sfUncertainty)));
end;

class function TAutoCalProtocol.TraceToJSON(const Info: TSystemInfo; const Index: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('index',        TJSONNumber.Create(Index));
  Result.AddPair('serial',       Info.Trace[Index].Serial);
  Result.AddPair('manufacturer', Info.Trace[Index].Manufacturer);
  Result.AddPair('model',        Info.Trace[Index].Model);
  Result.AddPair('cal_due',      Info.Trace[Index].CalDue.ToText);
end;

class function TAutoCalProtocol.CommentsToJSON(const Info: TSystemInfo): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('comments', Info.Comments);
end;

class function TAutoCalProtocol.IndexToJSON(const Index: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('index', TJSONNumber.Create(Index));
end;

class procedure TAutoCalProtocol.IdentityFromJSON(const P: TJSONObject; var Info: TSystemInfo);
begin
  if P = nil then Exit;
  Info.Serial       := P.GetValue<String>('serial', '');
  Info.Model        := P.GetValue<String>('model', '');
  Info.Cert         := P.GetValue<String>('cert', '');
  Info.Manufacturer := P.GetValue<String>('manufacturer', '');
  Info.Owner        := P.GetValue<String>('owner', '');
  TCalDate.Parse(P.GetValue<String>('cal_date', ''),      Info.CalDate);
  TCalDate.Parse(P.GetValue<String>('cal_date_prev', ''), Info.CalDatePrev);
  TCalDate.Parse(P.GetValue<String>('cal_due', ''),       Info.CalDue);
  Info.Temp         := P.GetValue<Double>('temp', 0);
  Info.Humd         := P.GetValue<Double>('humd', 0);
  Info.Tech         := P.GetValue<String>('tech', '');
end;

class function TAutoCalProtocol.ShuntFromJSON(const P: TJSONObject; var Info: TSystemInfo): Integer;
begin
  Result := -1;
  if P = nil then Exit;
  var Index := P.GetValue<Integer>('index', -1);
  if (Index < 0) or (Index >= CHANS) then Exit;

  { the board's floats are the truth here: no entry text, the numbers show as they are }
  Info.Shunts[Index].Index := Index;
  Info.Shunts[Index].Put(sfCurrent,     P.GetValue<Double>('current', 0));
  Info.Shunts[Index].Put(sfPrevious,    P.GetValue<Double>('previous', 0));
  Info.Shunts[Index].Put(sfDifference,  P.GetValue<Double>('difference', 0));
  Info.Shunts[Index].Put(sfUncertainty, P.GetValue<Double>('uncertainty', 0));
  Result := Index;
end;

class function TAutoCalProtocol.TraceFromJSON(const P: TJSONObject; var Info: TSystemInfo): Integer;
begin
  Result := -1;
  if P = nil then Exit;
  var Index := P.GetValue<Integer>('index', -1);
  if (Index < 0) or (Index >= TRACE_COUNT) then Exit;

  Info.Trace[Index].Serial       := P.GetValue<String>('serial', '');
  Info.Trace[Index].Manufacturer := P.GetValue<String>('manufacturer', '');
  Info.Trace[Index].Model        := P.GetValue<String>('model', '');
  TCalDate.Parse(P.GetValue<String>('cal_due', ''), Info.Trace[Index].CalDue);
  Info.Trace[Index].CalDueStr    := '';                            { the board's date is the truth here }
  Result := Index;
end;

class procedure TAutoCalProtocol.CommentsFromJSON(const P: TJSONObject; var Info: TSystemInfo);
begin
  if P <> nil then Info.Comments := P.GetValue<String>('comments', '');
end;

class function TAutoCalProtocol.FirmwareFromJSON(const P: TJSONObject; out FW: TFirmwareInfo): Boolean;
begin
  FW := Default(TFirmwareInfo);
  Result := (P <> nil) and (P.GetValue('major') <> nil);
  if not Result then Exit;

  FW.Device   := P.GetValue<String>('device', '');
  FW.Major    := P.GetValue<Integer>('major', 0);
  FW.Minor    := P.GetValue<Integer>('minor', 0);
  FW.Patch    := P.GetValue<Integer>('patch', 0);
  FW.DateTime := P.GetValue<String>('dtime', '');
  FW.Notes    := P.GetValue<String>('notes', '');
end;

class function TAutoCalProtocol.StateFromJSON(const P: TJSONObject; out State: TRecordState): Boolean;
begin
  State := Default(TRecordState);
  Result := (P <> nil) and (P.GetValue('record_version') <> nil);
  if not Result then Exit;

  State.Valid   := P.GetValue<Boolean>('record_valid', False);
  State.Dirty   := P.GetValue<Boolean>('record_dirty', False);
  State.Version := P.GetValue<Integer>('record_version', 0);
  State.Bytes   := P.GetValue<Integer>('record_bytes', 0);
end;

end.
