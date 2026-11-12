unit DebugTapU;

{
  A debug tap: everything the application logs, and what it does not show line by line (every meter sample,
  the settings a sample run started with, each polarity's result), appended to a text file beside the exe,
  <exe name>.tap.log, one time-stamped line each. It is there to be read after a bench run.

  Any thread may tap. A file that cannot be written is given up on quietly: the tap never disturbs a run.
  A log over TAP_LIMIT bytes at start-up is kept once as <name>.old and a new one begun.
}

interface

{ one line; line ends inside S become ' | ' so a multi-line message stays one record }
procedure Tap(const S: String); overload;
procedure Tap(const Fmt: String; const Args: array of const); overload;
function TapFile: String;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.IOUtils;

const
  TAP_LIMIT = 5 * 1024 * 1024;

var
  Lock: TCriticalSection;
  Started: Boolean = False;
  Broken: Boolean = False;

function TapFile: String;
begin
  Result := ChangeFileExt(ParamStr(0), '.tap.log');
end;

procedure Append(const Line: String);
begin
  var Stream := TFileStream.Create(TapFile, fmOpenReadWrite or fmShareDenyWrite);
  try
    Stream.Seek(0, soEnd);
    var Bytes := TEncoding.UTF8.GetBytes(Line + #13#10);
    Stream.WriteBuffer(Bytes, Length(Bytes));
  finally
    Stream.Free;
  end;
end;

procedure Start;
begin
  Started := True;
  var Name := TapFile;
  if FileExists(Name) and (TFile.GetSize(Name) > TAP_LIMIT) then
  begin
    var Old := Name + '.old';
    if FileExists(Old) then DeleteFile(Old);
    RenameFile(Name, Old);
  end;
  if not FileExists(Name) then TFile.WriteAllText(Name, '');
  Append('');
  Append(Format('==== %s started %s ====', [ExtractFileName(ParamStr(0)), FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]));
end;

procedure Tap(const S: String);
begin
  if Broken or (Lock = nil) then Exit;

  var Text := S.TrimRight([#13, #10, ' ']);
  if Text = '' then Exit;
  Text := Text.Replace(#13#10, ' | ').Replace(#10, ' | ').Replace(#13, ' | ');

  Lock.Enter;
  try
    try
      if not Started then Start;
      Append(FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + Text);
    except
      Broken := True;
    end;
  finally
    Lock.Leave;
  end;
end;

procedure Tap(const Fmt: String; const Args: array of const);
begin
  try
    Tap(Format(Fmt, Args, TFormatSettings.Invariant));
  except
    { a bad format string is the tap's own fault, never the caller's problem }
    Tap('TAP FORMAT ERROR: ' + Fmt);
  end;
end;

initialization
  Lock := TCriticalSection.Create;

finalization
  FreeAndNil(Lock);

end.
