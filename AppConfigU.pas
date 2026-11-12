unit AppConfigU;

{
  The application's two JSON files, both beside the exe:

    <exe name>.config.json    TAppConfig   what the software is set up with: the reference data the workbook used
                                           to hold (the Ohm Labs standards, the meters, and the rest as it moves over)
    <exe name>.data.json      TAppData     what the software puts out: everything that is not configuration,
                                           first of all the measurements the workbook's "Data" sheet took

  Each file is one object: "schemaVersion": 1 first, then one member per named section. A unit that owns a
  section reads and writes only that section through here; the other sections of the file are carried over
  untouched and keep their order. A write goes to a temporary file that then replaces the real one, so a crash
  mid-write leaves the old file whole. A file that does not parse is never overwritten.

  No VCL.
}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.JSON;

const
  CONFIG_SCHEMA = 1;

type
  { a sectioned JSON file by its path: what TAppConfig and TAppData are each one of }
  TJsonStore = class(TObject)
    private
      { Root = nil with True when there is no file yet; False, with the reason in Why, when it cannot be used }
      class function LoadRoot(const Path: String; out Root: TJSONObject; out Why: String): Boolean; static;
      class procedure WriteText(const Path, Text: String); static;

    public
      {
        a copy of one section, the caller's to free. nil with Why = '' when the file or the section is not
        there yet; nil with the reason in Why when the file cannot be read or the section is not an object
      }
      class function Read(const Path, Name: String; out Why: String): TJSONObject; static;
      {
        puts Value in place of the section (or adds it), leaving the others as they are. Value is taken over
        either way. False, with the reason in Why, leaves the file as it was
      }
      class function Write(const Path, Name: String; const Value: TJSONObject; out Why: String): Boolean; static;
  end;

  TAppConfig = class(TObject)
    public
      class function FileName: String; static;
      class function ReadSection(const Name: String; out Why: String): TJSONObject; static;
      class function WriteSection(const Name: String; const Value: TJSONObject; out Why: String): Boolean; static;
  end;

  TAppData = class(TObject)
    public
      class function FileName: String; static;
      class function ReadSection(const Name: String; out Why: String): TJSONObject; static;
      class function WriteSection(const Name: String; const Value: TJSONObject; out Why: String): Boolean; static;
  end;

{ a number as a file holds it: invariant, Digits significant digits (12 for curated figures), no trailing noise }
function CfgJson(const Value: Double; const Digits: Integer = 12): TJSONNumber;
{ the member's number, or Default when it is not there or not a number }
function CfgDouble(const Obj: TJSONObject; const Key: String; const Default: Double): Double;
{ a number as a form shows it: invariant, 10 significant digits }
function CfgText(const Value: Double): String;
{ '' counts as 0; False for anything that is not a number or is negative }
function CfgNumber(const Text: String; out Value: Double): Boolean;
{ a date as a file holds it: yyyy-mm-dd; '' for none (0) }
function CfgDate(const D: TDate): String;
{ '' counts as no date (0); False for anything else that is not yyyy-mm-dd }
function CfgTryDate(const Text: String; out D: TDate): Boolean;
{ the member's date; True when it is not there (D = 0) or reads, False when it is there and is not a date }
function CfgDateOf(const Obj: TJSONObject; const Key: String; out D: TDate): Boolean;

implementation

const
  KEY_VERSION = 'schemaVersion';

function CfgJson(const Value: Double; const Digits: Integer): TJSONNumber;
begin
  Result := TJSONNumber.Create(FloatToStrF(Value, ffGeneral, Digits, 0, TFormatSettings.Invariant));
end;

function CfgDouble(const Obj: TJSONObject; const Key: String; const Default: Double): Double;
begin
  Result := Default;
  var V := Obj.GetValue(Key);
  if not (V is TJSONNumber) then Exit;
  if not TryStrToFloat(TJSONNumber(V).Value, Result, TFormatSettings.Invariant) then Result := Default;
end;

function CfgText(const Value: Double): String;
begin
  Result := FloatToStrF(Value, ffGeneral, 10, 0, TFormatSettings.Invariant);
end;

function CfgNumber(const Text: String; out Value: Double): Boolean;
begin
  Value := 0;
  var S := Trim(Text);
  if S = '' then Exit(True);
  Result := TryStrToFloat(S, Value, TFormatSettings.Invariant) and (Value >= 0);
  if not Result then Value := 0;
end;

function CfgDate(const D: TDate): String;
begin
  if D = 0 then Result := ''
  else Result := FormatDateTime('yyyy"-"mm"-"dd', D, TFormatSettings.Invariant);
end;

function CfgTryDate(const Text: String; out D: TDate): Boolean;
var
  Y, M, Day: Integer;
  Full: TDateTime;
begin
  D := 0;
  var S := Trim(Text);
  if S = '' then Exit(True);
  Result := (Length(S) = 10) and (S[5] = '-') and (S[8] = '-') and TryStrToInt(Copy(S, 1, 4), Y)
    and TryStrToInt(Copy(S, 6, 2), M) and TryStrToInt(Copy(S, 9, 2), Day) and (Y >= 1) and (M >= 1) and (Day >= 1)
    and TryEncodeDate(Word(Y), Word(M), Word(Day), Full);
  if Result then D := Full;
end;

function CfgDateOf(const Obj: TJSONObject; const Key: String; out D: TDate): Boolean;
begin
  D := 0;
  var V := Obj.GetValue(Key);
  if V = nil then Exit(True);
  Result := (V is TJSONString) and not (V is TJSONNumber) and CfgTryDate(TJSONString(V).Value, D);
end;

{ TJsonStore }

class function TJsonStore.LoadRoot(const Path: String; out Root: TJSONObject; out Why: String): Boolean;
begin
  Root := nil;
  Why := '';
  if not FileExists(Path) then Exit(True);

  try
    var V := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8), False, True);
    if V is TJSONObject then
    begin
      Root := TJSONObject(V);
      Exit(True);
    end;
    V.Free;
    Why := ExtractFileName(Path) + ' is not a JSON object';
  except
    on E: Exception do Why := Format('%s does not parse: %s', [ExtractFileName(Path), E.Message]);
  end;
  Result := False;
end;

class procedure TJsonStore.WriteText(const Path, Text: String);
begin
  var Tmp := Path + '.tmp';
  var Enc := TUTF8Encoding.Create(False);             { no byte order mark }
  try
    TFile.WriteAllText(Tmp, Text + sLineBreak, Enc);
  finally
    Enc.Free;
  end;
  if not MoveFileEx(PChar(Tmp), PChar(Path), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
    RaiseLastOSError;
end;

class function TJsonStore.Read(const Path, Name: String; out Why: String): TJSONObject;
var
  Root: TJSONObject;
begin
  Result := nil;
  if not LoadRoot(Path, Root, Why) or (Root = nil) then Exit;
  try
    var V := Root.GetValue(Name);
    if V = nil then Exit;
    if V is TJSONObject then Result := TJSONObject(V.Clone)
    else Why := Format('"%s" in %s is not an object', [Name, ExtractFileName(Path)]);
  finally
    Root.Free;
  end;
end;

class function TJsonStore.Write(const Path, Name: String; const Value: TJSONObject; out Why: String): Boolean;
var
  Old, Fresh: TJSONObject;
  Mine: Boolean;                                      { Value is still ours to free }
begin
  Result := False;
  Mine := True;
  try
    try
      if not LoadRoot(Path, Old, Why) then Exit;
      Fresh := TJSONObject.Create;
      try
        Fresh.AddPair(KEY_VERSION, TJSONNumber.Create(CONFIG_SCHEMA));

        { the other sections as they were, the named one replaced where it stood }
        if Old <> nil then
          for var Pair in Old do
          begin
            var Key := Pair.JsonString.Value;
            if Key = KEY_VERSION then Continue;
            if Key <> Name then Fresh.AddPair(Key, TJSONValue(Pair.JsonValue.Clone))
            else if Mine then
            begin
              Fresh.AddPair(Name, Value);
              Mine := False;
            end;
          end;
        if Mine then
        begin
          Fresh.AddPair(Name, Value);
          Mine := False;
        end;

        WriteText(Path, Fresh.Format(2));
        Result := True;
      finally
        Fresh.Free;
        Old.Free;
      end;
    except
      on E: Exception do Why := E.Message;
    end;
  finally
    if Mine then Value.Free;
  end;
end;

{ TAppConfig }

class function TAppConfig.FileName: String;
begin
  Result := ChangeFileExt(ParamStr(0), '.config.json');
end;

class function TAppConfig.ReadSection(const Name: String; out Why: String): TJSONObject;
begin
  Result := TJsonStore.Read(FileName, Name, Why);
end;

class function TAppConfig.WriteSection(const Name: String; const Value: TJSONObject; out Why: String): Boolean;
begin
  Result := TJsonStore.Write(FileName, Name, Value, Why);
end;

{ TAppData }

class function TAppData.FileName: String;
begin
  Result := ChangeFileExt(ParamStr(0), '.data.json');
end;

class function TAppData.ReadSection(const Name: String; out Why: String): TJSONObject;
begin
  Result := TJsonStore.Read(FileName, Name, Why);
end;

class function TAppData.WriteSection(const Name: String; const Value: TJSONObject; out Why: String): Boolean;
begin
  Result := TJsonStore.Write(FileName, Name, Value, Why);
end;

end.
