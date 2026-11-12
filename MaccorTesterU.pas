unit MaccorTesterU;

{
  The Maccor tester, as MacUniModCal reaches it: the calibration engine dll (MacTest32Cal.dll for a legacy
  system, MacTestCal.dll for a NextGen one) loaded through MacUniModCal's own DLLInterfaceU, started with
  InitializeSystem and driven with the calls its Check Channel form uses (SetActiveChan, CheckChannel,
  StopChannel). No VCL: messages go through TUtils.HandleEvent on the main thread, channel data comes back
  through OnData on the main thread.

  The engine dll sits beside the exe (DLLInterfaceU looks nowhere else). On a development PC a missing or
  older copy is fetched from MacUniModCal's own output folder for the same platform and configuration.
}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Math, System.StrUtils, System.Threading, CommonsU, MacUniModCalUtilsU, MacUniModCalAPI,
  DLLInterfaceU;

type
  { fired on the main thread for every data frame of the active channel }
  TOnTesterData = reference to procedure(const Raw: TMaccorChanData; const Data: TTranslatedChanData);

  TMaccorTester = class(TObject)
    private
      FOnline: Boolean;

      MySession: Integer;                     { see Session in the implementation }
      PrepTask: ITask;                        { the download the operator asked for, see Download }

      procedure OnEngineEvent(const Evt: PAppEvent);
      procedure OnChannelData(const Data: PMaccorChanData);
      procedure OnAuxData(const Data: PLegacyAuxData);
      function FindAdapter(out Adapter: TAdapterInfo; out Why: String): Boolean;
      class procedure Log(const S: String); static;
      class procedure FetchEngine(const System: TMaccorSystemConfiguration); static;

    public
      OnData: TOnTesterData;

      destructor Destroy; override;

      class function EngineFile(const System: TMaccorSystemConfiguration): String; static;
      { the system is configured on this PC }
      class function Configured(const System: TMaccorSystemConfiguration): Boolean; static;
      {
        the system this PC is set up for, no choice offered: the legacy system that <drive>:\BatTest.cfg points
        to; a PC without one falls back to its NextGen configuration. mscUNSET = neither is there
      }
      class function DefaultSystem: TMaccorSystemConfiguration; static;
      { where the default system comes from, for the display: the BatTest.cfg path, or the NextGen config file }
      class function DefaultSource: String; static;

      { loads the engine (once per process) and starts it; False with the reason in Why }
      function Open(const System: TMaccorSystemConfiguration; out Why: String): Boolean;
      procedure Close;

      function SystemName: String;
      function ChanCount: Integer;
      { the range's full scale for the mode, in A; 0 = no specification for that channel and range }
      function MaxCurrent(const Chan: Integer; const Mode: TMaccorControlMode; const Range: TMaccorBrickRange): Single;
      { makes Chan (0-based) the engine's active channel; Wait = ms to let it land (0 = do not wait) }
      function Select(const Chan: Integer; const Wait: Integer = 0): Boolean;
      {
        Check Channel's start: Amps against the range's full scale, scaled to the 16-bit control word, sent
        with CheckChannel. CtrlValue and MaxValue come back for the display
      }
      function Run(const Chan: Integer; const Mode: TMaccorControlMode; const Range: TMaccorBrickRange;
        const Control: TMaccorControlType; const Amps: Single; out CtrlValue: Word; out MaxValue: Single;
        out Why: String): Boolean;
      procedure Stop;

      {
        on the operator's request only, and for one board only: the engine's own board download for the
        controller board that carries Chan (0-based). That one engine call sends the board its firmware and
        then the calibration and configuration of the channels on it; nothing else is sent from here. Other
        boards are left alone. Runs on a task and logs as it goes; False if the engine is not up or a download
        is already running
      }
      function Download(const Chan: Integer): Boolean;
      { True while Download runs: the engine selects channels itself, none is selected or started meanwhile }
      function Preparing: Boolean;
      {
        the running channel's own current, as CalibrateU's CollectSamples takes it: waits for the channel's
        next data (CheckDataUpdate) and converts the raw word for the range. Callable from a task
      }
      function ReadCurrent(const Chan: Integer; const Mode: TMaccorControlMode; const Range: TMaccorBrickRange;
        out Amps: Double; const TimeoutMs: Cardinal = ONE_SEC): Boolean;

      property Online: Boolean read FOnline;
  end;

implementation

var
  Loaded: TMaccorSystemConfiguration = mscUNSET;
  {
    bumped by every Open and Close. A data frame queued to the main thread carries the value it was queued
    under and is dropped when that is no longer current: the frame may run after the engine, or the tester
    object itself, is gone (MacUniModCal guards the same way with its Closing flag)
  }
  Session: Integer = 0;

{ the machine type in a PE file's header: True when it could be read, Is64 = an x64 image }
function Is64BitImage(const FileName: String; out Is64: Boolean): Boolean;
var
  Offset: Integer;
  Machine: Word;
begin
  Result := False;
  Is64 := False;
  try
    var F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      F.Position := $3C;
      if F.Read(Offset, SizeOf(Offset)) <> SizeOf(Offset) then Exit;
      F.Position := Offset + 4;
      if F.Read(Machine, SizeOf(Machine)) <> SizeOf(Machine) then Exit;
      Is64 := Machine = $8664;
      Result := True;
    finally
      F.Free;
    end;
  except
    Result := False;
  end;
end;

{ TMaccorTester }

destructor TMaccorTester.Destroy;
begin
  Close;
  inherited;
end;

class procedure TMaccorTester.Log(const S: String);
begin
  TThread.ForceQueue(nil, procedure begin TUtils.HandleEvent(etMessage, S); end);
end;

class function TMaccorTester.EngineFile(const System: TMaccorSystemConfiguration): String;
begin
  case System of
    mscLegacy:  Result := ExtractFilePath(ParamStr(0)) + 'MacTest32Cal.dll';
    mscNextGen: Result := ExtractFilePath(ParamStr(0)) + 'MacTestCal.dll';
  else
    Result := '';
  end;
end;

class function TMaccorTester.Configured(const System: TMaccorSystemConfiguration): Boolean;
begin
  Result := (MacSysPtr <> nil) and (System in MacSysPtr^.Config);
end;

class function TMaccorTester.DefaultSystem: TMaccorSystemConfiguration;
begin
  if Configured(mscLegacy) then Result := mscLegacy
  else if Configured(mscNextGen) then Result := mscNextGen
  else Result := mscUNSET;
end;

class function TMaccorTester.DefaultSource: String;
begin
  case DefaultSystem of
    mscLegacy:  Result := MacSysPtr^.BatTest;
    mscNextGen: Result := MacSysPtr^.LocalPaths.MaccorSysConfig;
  else
    Result := '';
  end;
end;

{
  development convenience: the exe runs from test\Delphi\<Platform>\<Config>; MacUniModCal builds its engine
  into Delphi\MacUniModCal\<Platform>\<Config>, six levels up and across. A file missing here, or older here
  than there, is copied. Nothing happens on a PC without that folder
}
class procedure TMaccorTester.FetchEngine(const System: TMaccorSystemConfiguration);
begin
  var ExeDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  var Config := ExtractFileName(ExeDir);
  var Platform := ExtractFileName(ExtractFileDir(ExeDir));
  var DevDir := ExpandFileName(Format('%s\..\..\..\..\..\..\Delphi\MacUniModCal\%s\%s\', [ExeDir, Platform, Config]));
  if not DirectoryExists(DevDir) then Exit;

  for var Name in [ExtractFileName(EngineFile(System)), 'RawSocket.dll'] do
  begin
    var Src := DevDir + Name;
    var Dst := ExeDir + '\' + Name;
    var SrcAge, DstAge: TDateTime;
    if not FileAge(Src, SrcAge) then Continue;
    if FileAge(Dst, DstAge) and (DstAge >= SrcAge) then Continue;
    if CopyFile(PChar(Src), PChar(Dst), False) then Log(Format('Tester: %s copied from %s'#13#10, [Name, DevDir]))
    else Log(Format('Tester: could not copy %s from %s: %s'#13#10, [Name, DevDir, SysErrorMessage(GetLastError)]));
  end;
end;

{
  engine and loader events, from any thread, all of them to the log. The message of an engine event is a string of the dll's own
  memory manager (neither side uses ShareMem): it is copied character by character here, inside the call,
  and never kept by reference
}
procedure TMaccorTester.OnEngineEvent(const Evt: PAppEvent);
begin
  if Evt = nil then Exit;

  var S: String;
  SetString(S, PChar(Evt^.Msg), Length(Evt^.Msg));
  if S <> '' then Log(S);
end;

{ on the engine's thread: copy, then hand to the main thread }
procedure TMaccorTester.OnChannelData(const Data: PMaccorChanData);
begin
  if Data = nil then Exit;
  var Raw: TMaccorChanData := Data^;
  var Queued := MySession;

  TThread.Queue(nil,
    procedure
    var
      Translated: TTranslatedChanData;
    begin
      if Queued <> Session then Exit;         { closed since: Self may be gone, touch nothing }
      TranslateChannelData(MacSysPtr^.SysId, @Raw, Translated);
      if Assigned(OnData) then OnData(Raw, Translated);
    end);
end;

procedure TMaccorTester.OnAuxData(const Data: PLegacyAuxData);
begin
  { auxiliary inputs are not part of a shunt run }
end;

{ the adapter the tester's own configuration names (MacUniModCal offers a picker when it is gone; here it is an error) }
function TMaccorTester.FindAdapter(out Adapter: TAdapterInfo; out Why: String): Boolean;
begin
  Result := False;
  Adapter := Default(TAdapterInfo);
  var Wanted := MacSysPtr^.SysCfg.LanAdapterName;
  if Wanted = '' then
  begin
    Why := 'the tester configuration names no network adapter';
    Exit;
  end;

  var Adapters: TAdapterList;
  GetAdaptersEx(Adapters);
  for var A in Adapters do
    if String(A.PCAPName) = Wanted then
    begin
      if A.DHCPEnabled then
      begin
        Why := Format('the tester''s network adapter (%s) is set to DHCP: it needs a fixed address', [String(A.Desc)]);
        Exit;
      end;
      Adapter := A;
      Exit(True);
    end;

  Why := Format('the tester''s network adapter is not present (%s)', [Wanted]);
end;

function TMaccorTester.Open(const System: TMaccorSystemConfiguration; out Why: String): Boolean;
begin
  Result := False;
  Why := '';
  if FOnline then Exit(True);

  if not Configured(System) then
  begin
    Why := 'that system is not configured on this PC';
    Exit;
  end;
  if (Loaded <> mscUNSET) and (Loaded <> System) then
  begin
    Why := 'another engine is already loaded: restart the application to switch systems';
    Exit;
  end;

  if Loaded = mscUNSET then
  begin
    FetchEngine(System);
    if not FileExists(EngineFile(System)) then
    begin
      Why := ExtractFileName(EngineFile(System)) + ' is not beside the application';
      Exit;
    end;
    {
      the legacy engine reaches the tester through RawSocket.dll. Without it the engine still loads and even
      reports itself started, but it has no socket: nothing reaches the tester and nothing says why (seen
      2026-11-10 with the Win32 build; RawSocket.dll exists as a 64-bit build only). Refused here instead
    }
    if System = mscLegacy then
    begin
      var Socket := ExtractFilePath(ParamStr(0)) + 'RawSocket.dll';
      var Is64: Boolean;
      if not FileExists(Socket) then
      begin
        Why := 'RawSocket.dll is not beside the application'
          {$IFDEF WIN32} + ' (it only exists as a 64-bit build: run the Win64 build of this application)'{$ENDIF};
        Exit;
      end;
      { a dll of the other bitness is as good as none: Windows will not load it into this process }
      if Is64BitImage(Socket, Is64) and (Is64 <> (SizeOf(Pointer) = 8)) then
      begin
        Why := Format('RawSocket.dll beside the application is a %s build and this is the %s application: ' +
          'run the Win64 build', [IfThen(Is64, '64-bit', '32-bit'), IfThen(SizeOf(Pointer) = 8, '64-bit', '32-bit')]);
        Exit;
      end;
    end;

    { the loader's own account (the dll, its build time, every export it binds) goes to the log like the rest }
    var Code := LoadDLL(System, OnEngineEvent);
    if Code <> 0 then
    begin
      Why := Format('%s did not load completely (code %d)', [ExtractFileName(EngineFile(System)), Code]);
      Exit;
    end;
    Loaded := System;
    Log(Format('Tester: %s loaded'#13#10, [ExtractFileName(EngineFile(System))]));
  end;

  var Adapter: TAdapterInfo;
  if not FindAdapter(Adapter, Why) then Exit;

  Inc(Session);
  MySession := Session;
  { the same three calls, in the same order, as MacUniModCal's StartSystem }
  if InitializeSystem(OnEngineEvent, [], @Adapter) <> 0 then
  begin
    Why := 'the engine did not start';
    Exit;
  end;
  SetEventHandler(nil, OnChannelData, OnAuxData);
  FOnline := True;

  if Assigned(SystemStatus) and not SystemStatus then
    Log('Tester: the engine started but reports the system as not ready (see its messages above)'#13#10);
  Log(Format('Tester: %s started on %s, %d channels'#13#10, [SystemName, String(Adapter.Desc), ChanCount]));
  Result := True;
end;

procedure TMaccorTester.Close;
begin
  Inc(Session);                               { frames already queued are dropped }
  if not FOnline then Exit;
  FOnline := False;
  { a download sees FOnline go and leaves between two engine calls: the engine is not closed under it }
  if Assigned(PrepTask) then
  begin
    try
      PrepTask.Wait(30000);
    except
      { a failed push has already said so }
    end;
    PrepTask := nil;
  end;
  if Assigned(StopChannel) then StopChannel;
  if Assigned(CloseSystem) then CloseSystem;
  Log('Tester: engine closed'#13#10);
end;

function TMaccorTester.SystemName: String;
begin
  if MacSysPtr = nil then Exit('');
  Result := MacSysPtr^.SysName;
end;

function TMaccorTester.ChanCount: Integer;
begin
  if MacSysPtr = nil then Exit(0);
  Result := MacSysPtr^.SysCfg.ChanCount;
end;

function TMaccorTester.MaxCurrent(const Chan: Integer; const Mode: TMaccorControlMode; const Range: TMaccorBrickRange): Single;
var
  Specs: PMaccorChannelConfig;
  Limits: PMaccorChannelRangeSpec;
begin
  Result := 0;
  if MacSysPtr = nil then Exit;
  MacSysPtr^.GetChannelSpecs(Chan, Specs);
  MacSysPtr^.GetRangeSpecs(Specs, Range, Limits);
  if Limits = nil then Exit;

  case Mode of
    cmCharge:    Result := Limits^.Charge;
    cmDischarge: Result := Limits^.Discharge;
  end;
end;

function TMaccorTester.Select(const Chan: Integer; const Wait: Integer): Boolean;
begin
  { a download is walking the channels: it restores the active one when it is done }
  Result := FOnline and not Preparing and SetActiveChan(Chan, nil, Wait);
end;

function TMaccorTester.Run(const Chan: Integer; const Mode: TMaccorControlMode; const Range: TMaccorBrickRange;
  const Control: TMaccorControlType; const Amps: Single; out CtrlValue: Word; out MaxValue: Single;
  out Why: String): Boolean;
begin
  Result := False;
  CtrlValue := 0;
  MaxValue := MaxCurrent(Chan, Mode, Range);
  Why := '';

  if not FOnline then
  begin
    Why := 'Tester not started!';
    Exit;
  end;
  if Preparing then
  begin
    Why := 'The tester is still downloading';
    Exit;
  end;
  if MaxValue <= 0 then
  begin
    Why := Format('No R%d specification for channel %d', [Ord(Range) +1, Chan +1]);
    Exit;
  end;
  if Amps > MaxValue then
  begin
    Why := Format('Asking: %f > Max: %.6f', [Amps, MaxValue]);
    Exit;
  end;

  { CheckChannel refuses any channel but the active one }
  if (GetActiveChan <> Chan) and not SetActiveChan(Chan, nil, ONE_SEC) then
  begin
    Why := Format('Channel %d did not become the active channel', [Chan +1]);
    Exit;
  end;

  { asking entry to word :: 65535 }
  CtrlValue := Round(Abs(Amps) / MaxValue * MAXWORD);
  Result := CheckChannel(Chan, Mode, Range, Control, CtrlValue);
  if not Result then Why := 'Channel failed to start!';
end;

function TMaccorTester.Preparing: Boolean;
begin
  Result := Assigned(PrepTask) and not (PrepTask.Status in
    [TTaskStatus.Completed, TTaskStatus.Canceled, TTaskStatus.Exception]);
end;

{
  the engine's DownloadBoard is the whole job: its DownloadROM sends the firmware to the ACTIVE channel's
  controller board and follows it with that board's channel calibrations and settings
  (DownloadCalibrationsAndConfig). So this only makes sure Chan is the active channel, asks for the download
  and waits it out.

  Nothing else is done to the engine here, on purpose: an earlier version walked the board's channels itself
  (SetActiveChan + DownloadChannelCalibration for each) after the download, which repeated what the engine had
  just done. With that version the download was reported not working (2026-11-10); which of its extra steps
  was at fault was not pinned down, so all of them went. The engine drops a
  download request it meets while busy (DownloadROM: "if Busy then Exit"), so the channel is only switched
  when it is not already the active one, and the request waits a moment after a switch
}
function TMaccorTester.Download(const Chan: Integer): Boolean;
begin
  Result := False;
  if not FOnline or Preparing then Exit;
  if not Assigned(DownloadBoard) then Exit;
  if (Chan < 0) or (Chan >= ChanCount) then Exit;
  Result := True;

  var Target := Chan;
  PrepTask := TTask.Run(
    procedure
    begin
      try
        if GetActiveChan <> Target then
        begin
          if not SetActiveChan(Target, nil, ONE_SEC) then
          begin
            Log(Format('Tester: channel %d did not become the active channel: nothing downloaded'#13#10, [Target +1]));
            Exit;
          end;
          Sleep(ONE_SEC);
        end;

        Log(Format('Tester: board download requested for channel %d''s board...'#13#10, [Target +1]));
        DownloadBoard;

        { the request is picked up by the engine's own loop: give it a moment to begin, then wait it out }
        Sleep(ONE_SEC);
        var Started := GetTickCount64;
        while FOnline and Assigned(GetCtlrDwnldStatus) and GetCtlrDwnldStatus(nil)
          and (GetTickCount64 - Started < 180000) do Sleep(250);
        if FOnline then Log('Tester: board download finished (the engine''s messages above say how it went)'#13#10);
      except
        on E: Exception do Log(Format('Tester: download failed: %s'#13#10, [E.Message]));
      end;
    end);
end;

function TMaccorTester.ReadCurrent(const Chan: Integer; const Mode: TMaccorControlMode; const Range: TMaccorBrickRange;
  out Amps: Double; const TimeoutMs: Cardinal): Boolean;
var
  Raw, DAC: Word;
begin
  Amps := 0;
  Raw := 0;
  DAC := 0;
  Result := FOnline and Assigned(CheckDataUpdate)
    and CheckDataUpdate(taVerify, rmCurrent, @Raw, @DAC, nil, TimeoutMs);
  if Result then MacSysPtr^.ConversionDAC(Chan, rmCurrent, Mode, Range, Raw, Amps);
end;

procedure TMaccorTester.Stop;
begin
  if FOnline and Assigned(StopChannel) then StopChannel;
end;

end.
