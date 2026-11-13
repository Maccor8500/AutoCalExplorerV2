unit AutoCalBoardU;

{
  One AutoCalibrator 528LB board on the wire: socket, request/reply, relay commands, calibration
  record read/write, bootloader hand-over and TFTP firmware push. No VCL: every message goes
  through TUtils.HandleEvent (queued to the main thread) and every long job runs on a task with
  callbacks the caller marshals itself.
}

interface

uses
  System.SysUtils, System.Classes, System.StrUtils, System.Math, System.SyncObjs, System.Threading, System.JSON,
  Winapi.WinSock2, CommonsU, AutoCalProtocolU;

const
  {
    the shunts fitted in the box, slot 1..8, as read off the hardware (given by the user, 2026-11-10): the one
    list every tab shows. SHUNT_OHMS is the label, SHUNT_VALUE the same in ohms. These are the nominal values:
    what each shunt measures is in the calibration record
  }
  SHUNT_OHMS: array [1..CHANS] of String = ('10K', '24.9K', '1', '0.05', '0.005', '10', '500', '100');
  SHUNT_VALUE: array [1..CHANS] of Double = (10000, 24900, 1, 0.05, 0.005, 10, 500, 100);

type
  { fired on a pool thread: the subscriber marshals to the UI }
  TOnUpdateProgress = reference to procedure(const Percent: Integer);
  TOnUpdateFinished = reference to procedure(const Ok: Boolean);
  { asked on a pool thread; the subscriber may Synchronize a dialog. nil = decline }
  TOnConfirm = reference to function(const Question: String): Boolean;
  { fired on the main thread when the connect retry ends: True = the application answered }
  TOnConnected = reference to procedure(const Online: Boolean);

  TAutoCalBoard = class(TObject)
    private
      FAddress: String;
      Sock: TUdpSocketEx;
      Via: Integer;                           { which candidate adapter answered (feeds LocalNet) }
      ViaIp: String;                          { the adapter address the socket is bound to ('' = any) }
      ConnectTask: ITask;                     { the connect retry, see WaitOnline }
      ReqId: Word;
      ReplyEvent: TEvent;
      PendingId: Integer;                     { -1 = no reply awaited }
      PendingReply: TJSONObject;              { written by the socket thread, taken by Request }
      QuietReply: Boolean;                    { probes, section reads and post-update polling are not echoed }
      RequestLock: TCriticalSection;          { one pending-reply slot: callers serialize }
      UpdateTask: ITask;
      UpdateStop: TEvent;
      Flasher: TAriadneManagerEx;
      FLastStatus: String;
      FLastError: Integer;
      FOnline: Boolean;                       { the connect ping was answered }

      procedure CreateSocket;
      { tries every candidate adapter with a fresh socket; True leaves Sock on the one the board answered from }
      function Probe: Boolean;
      { no answer anywhere: binds to the adapter in the board's own /24 so later requests leave by it }
      procedure BindFallback;
      function LocalNet(const Nth: Integer; out Ip, Gateway, Subnet: String): Boolean;
      procedure OnDataRecvcd(const Payload: PSocketPayload);
      procedure Log(const S: String);
      function Request(const FClass, FNum: Integer; const Params: TJSONObject = nil; const Quiet: Boolean = False): TJSONObject;
      function Call(const FClass, FNum: Integer; out Reply: TJSONObject; const Params: TJSONObject = nil; const Quiet: Boolean = False): Boolean;
      function Simple(const FClass, FNum: Integer): Boolean;
      function UpdateBoard(const Ip, FileName: String; const InBootloader: Boolean): String;

    public
      OnUpdateProgress: TOnUpdateProgress;
      OnUpdateFinished: TOnUpdateFinished;
      OnConfirm: TOnConfirm;
      OnConnected: TOnConnected;

      constructor Create(const Address: String);
      destructor Destroy; override;

      {
        a board that did not answer the connect ping (booting, or in its bootloader's TFTP window) is probed
        again every second for CONNECT_WAIT_S seconds on a task; OnConnected reports the outcome on the
        main thread. False if the board is already online or a retry is running. Destroy cancels it
      }
      function WaitOnline: Boolean;
      function Connecting: Boolean;

      { FC_SYS_STATUS / ST_FIRMWARE; Quiet = not echoed in the log }
      function Ping(const Quiet: Boolean = False): Boolean;
      function Firmware(out FW: TFirmwareInfo): Boolean;

      { relays: FClass FC_VCHAN_RLY..FC_ISENSE_RLY, Chan 0..7 or CLEAR_ALL_CHANS }
      function SelectRelay(const FClass, Chan: Integer): Boolean;
      { supplies: FClass FC_FAN_RLY..FC_DPS_RLY }
      function Supply(const FClass: Integer; const TurnOn: Boolean): Boolean;
      function Reset(const Option: Integer): Boolean;

      { calibration record: every section its own datagram }
      function ReadSystemInfo(var Info: TSystemInfo): Boolean;
      function ReadRecordState(out State: TRecordState): Boolean;
      function WriteSystemInfo(const Info: TSystemInfo; const Commit: Boolean): Boolean;
      function CommitSystemInfo: Boolean;

      { reboot into Ariadne (the board keeps its address; replies before it goes) }
      function Download: Boolean;
      { full firmware push: ping, release, download, TFTP, wait for the application. Runs on a task }
      function Update(const FileName: String): Boolean;
      function Updating: Boolean;
      procedure CancelUpdate;


      property Address: String read FAddress;
      property Online: Boolean read FOnline;          { the first ping (at connect) was answered }
      property LastStatus: String read FLastStatus;   { status text of the last reply }
      property LastError: Integer read FLastError;    { ERR_* of the last reply, -1 = no reply }
  end;

  { listens for the start-up broadcast on ANNOUNCE_PORT and logs the sender: a board shows up here when it boots }
  TAnnounceListener = class(TObject)
    private
      Sock: TUdpSocketEx;
      procedure OnDataRecvcd(const Payload: PSocketPayload);
    public
      constructor Create;
      destructor Destroy; override;
  end;

implementation

const
  REPLY_TIMEOUT_MS = 500;
  BOOT_WAIT_MS     = 3000;        { from the download reply to Ariadne listening }
  APP_WAIT_TRIES   = 36;          { x 2.5 s = 90 s for the application to come back }
  CONNECT_WAIT_S     = 30;        { a board sent to Ariadne answers again after about 20 s (15 s TFTP window, hand-over, start-up) }
  CONNECT_RETRY_MS   = 1000;      { pause between probes; a probe itself takes 500 ms per candidate adapter }

{ the application runs as a /24 (Ethernet.begin with only MAC and IP): it answers sources inside x.y.z.* only }
function SameNet24(const A, B: String): Boolean;
begin
  Result := Copy(A, 1, LastDelimiter('.', A)) = Copy(B, 1, LastDelimiter('.', B));
end;

{
  request ids stay in 1..32767: the firmware reads the id as an AVR int (16-bit signed) and echoes 0 for anything
  larger, which the reply matching then discards. Found 2026-11-06: a session that started at a random id
  >= 32768 never got a matching reply, so half of all connects "failed" while the board answered every one
}
function NextId(const Id: Word): Word;
begin
  Result := (Id + 1) and $7FFF;
  if Result = 0 then Result := 1;
end;

{ TAutoCalBoard }

constructor TAutoCalBoard.Create(const Address: String);
begin
  FAddress := Trim(Address);
  FLastError := -1;
  Randomize;
  ReqId := NextId(Word(Random($10000)));
  PendingId := -1;
  Via := -1;
  RequestLock := TCriticalSection.Create;
  UpdateStop := TEvent.Create(nil, True, False, '');
  ReplyEvent := TEvent.Create(nil, True, False, '');
  Flasher := TAriadneManagerEx.Create(1);
  CreateSocket;
end;

destructor TAutoCalBoard.Destroy;
begin
  Log('Closing ' +FAddress);
  { the tasks use Request and the socket, so they go before anything those touch }
  if Assigned(UpdateStop) then UpdateStop.SetEvent;
  if Assigned(Flasher) then Flasher.Cancel;
  if Assigned(UpdateTask) then UpdateTask.Wait(10000);
  if Assigned(ConnectTask) then ConnectTask.Wait(5000);
  FreeAndNil(Flasher);

  { socket first: its thread calls OnDataRecvcd, which signals ReplyEvent }
  FreeAndNil(Sock);
  FreeAndNil(ReplyEvent);
  FreeAndNil(UpdateStop);
  FreeAndNil(RequestLock);
  inherited;
end;

procedure TAutoCalBoard.CreateSocket;
begin
  Log('Starting socket for ' +FAddress);
  if Probe then
  begin
    FOnline := True;
    Log(Format('%s reached via %s', [FAddress, ViaIp]));
  end
  else
  begin
    BindFallback;
    Log(Format('%s: no reply to ping, listening via %s', [FAddress, IfThen(ViaIp <> '', ViaIp, 'the OS route')]));
  end;
end;

{
  one candidate adapter at a time: those in the board's own /24; the other adapters of the board's /16 only when
  the PC has none in the /24. Sock is nil on entry.

  Why not always try the rest: the board (a /16) answers every source by ARP. A PC address that shares its /16
  but sits on another wire (this PC: a Wi-Fi address and a second address on the Realtek NIC) makes the board
  wait out the W5100 ARP timeout, about 1.7 s, during which nothing else is answered, so the probes that could
  succeed time out behind it (measured 2026-11-06: 3 of 8 reconnects failed this way)
}
function TAutoCalBoard.Probe: Boolean;
begin
  Result := False;
  var Ip, Gateway, Subnet: String;
  var Candidates := 0;
  for var Pass := 0 to 1 do
  begin
    if (Pass = 1) and (Candidates > 0) then Break;
    var N := 0;
	
    while not Result and LocalNet(N, Ip, Gateway, Subnet) do
    begin
      if SameNet24(Ip, FAddress) = (Pass = 0) then
      begin
        Inc(Candidates);
        Sock := TUdpSocketEx.Create(0, OnDataRecvcd, nil, nil, Ip);
        if Ping(True) then
        begin
          Via := N;
          ViaIp := Ip;
          Result := True;
        end
        else
        begin
          Log(Format('  %s: no answer', [Ip]));
          FreeAndNil(Sock);                     // wrong NIC, or no board yet: try the next
        end;
      end;
      Inc(N);
    end;
  end;
end;

{
  nothing answered (a board in its bootloader has no RPC): still bind to the adapter in the board's own /24,
  so later requests, such as the polling after a firmware push, leave by the adapter the board answers
}
procedure TAutoCalBoard.BindFallback;
begin
  var Ip, Gateway, Subnet: String;
  var Best := -1;
  var BestIp := '';
  var N := 0;
  while LocalNet(N, Ip, Gateway, Subnet) do
  begin
    if (Best < 0) or (SameNet24(Ip, FAddress) and not SameNet24(BestIp, FAddress)) then
    begin
      Best := N;
      BestIp := Ip;
    end;
    Inc(N);
  end;

  Via := Best;
  ViaIp := BestIp;
  if Best >= 0 then Sock := TUdpSocketEx.Create(0, OnDataRecvcd, nil, nil, BestIp)
  else Sock := TUdpSocketEx.Create(0, OnDataRecvcd);   // no adapter on the subnet at all: unbound
end;

function TAutoCalBoard.Connecting: Boolean;
begin
  Result := Assigned(ConnectTask) and not (ConnectTask.Status in
    [TTaskStatus.Completed, TTaskStatus.Canceled, TTaskStatus.Exception]);
end;

{
  every retry probes the adapters afresh, as the connect did, so a board that turns out to answer on another
  NIC is found too. The socket is swapped under RequestLock: no request is in flight while it changes
}
function TAutoCalBoard.WaitOnline: Boolean;
begin
  Result := False;
  if FOnline or Connecting then Exit;
  Log(Format('%s: retrying for up to %d s (a board in its bootloader, or just reset, needs that long)',
    [FAddress, CONNECT_WAIT_S]));

  ConnectTask := TTask.Run(
    procedure
    begin
      var Ok := False;
      var Stopped := False;
      var SaidReachable := False;
      var Started := TThread.GetTickCount64;
      while (TThread.GetTickCount64 - Started) < CONNECT_WAIT_S * 1000 do
      begin
        if UpdateStop.WaitFor(CONNECT_RETRY_MS) = wrSignaled then begin Stopped := True; Break; end;
        RequestLock.Enter;
        try
          FreeAndNil(Sock);
          Ok := Probe;
          if not Ok then BindFallback;
        finally
          RequestLock.Leave;
        end;
        if Ok then Break;

        { Ariadne answers ICMP but has no RPC: say so once, a firmware update needs no more than that }
        if not SaidReachable and CommonsU.Ping(AnsiString(FAddress), 500) then
        begin
          SaidReachable := True;
          Log(FAddress + ': answers ping but not the RPC: in the bootloader (a firmware update is possible), or still starting');
        end;
      end;

      FOnline := Ok;
      if Ok then Log(Format('%s reached via %s', [FAddress, IfThen(ViaIp <> '', ViaIp, 'the OS route')]))
      else if not Stopped then Log(Format('%s: no reply in %d s', [FAddress, CONNECT_WAIT_S]));

      var Cb: TOnConnected := OnConnected;
      if Assigned(Cb) and not Stopped then TThread.Queue(nil, procedure begin Cb(Ok) end);
    end);
  Result := True;
end;

{ the Nth PC adapter address that shares the board's subnet, with that adapter's gateway and mask }
function TAutoCalBoard.LocalNet(const Nth: Integer; out Ip, Gateway, Subnet: String): Boolean;
begin
  Result := False;
  var Seen := 0;
  var BoardIP := inet_addr(PAnsiChar(AnsiString(FAddress)));
  var Adapters: TArray<TAdapterInfo>;
  GetAdapters(Adapters);

  for var K := 0 to High(Adapters) do
  begin
    var A: PAdapterInfo := @Adapters[K];
    if not A^.Enabled then Continue;

    for var J := 0 to A^.IPCount -1 do
    begin
      var Mask := inet_addr(PAnsiChar(AnsiString(A^.AssociatedIPs[J].Mask)));
      var Addr := inet_addr(PAnsiChar(AnsiString(A^.AssociatedIPs[J].Addr)));
      if (Mask = 0) or ((Addr and Mask) <> (BoardIP and Mask)) then Continue;

      if Seen = Nth then
      begin
        Ip      := String(A^.AssociatedIPs[J].Addr);
        Subnet  := String(A^.AssociatedIPs[J].Mask);
        Gateway := IfThen(A^.GWCount > 0, String(A^.Gateway[0]), '');
        if Gateway = '0.0.0.0' then Gateway := '';
        Exit(True);
      end;
      Inc(Seen);
    end;
  end;
end;

{ HandleEvent runs the handler on the calling thread and the log is VCL: hand it to the main thread, FIFO }
procedure TAutoCalBoard.Log(const S: String);
begin
  TThread.ForceQueue(nil, procedure begin TUtils.HandleEvent(etMessage, S +#13#10); end);
end;

{ runs on the socket thread }
procedure TAutoCalBoard.OnDataRecvcd(const Payload: PSocketPayload);
var
  Raw: AnsiString;
  Id: Integer;
begin
  if Payload = nil then Exit;
  SetString(Raw, PAnsiChar(@Payload^.AsBytes[0]), Payload^.Size);

  var V := TJSONObject.ParseJSONValue(String(Raw));
  if not QuietReply then
  begin
    if V <> nil then Log('<< ' + Payload^.Remote.Addr + #13#10 + V.Format(4))
    else Log('<< ' + Payload^.Remote.Addr + #13#10 + String(Raw));
  end;

  if (V is TJSONObject) and TJSONObject(V).TryGetValue<Integer>('id', Id) and (Id = PendingId) then
  begin
    PendingReply := TJSONObject(V);
    ReplyEvent.SetEvent;
  end
  else if (V is TJSONObject) and (PendingId >= 0) then
  begin
    { a reply that does not match is worth a line: it is how the firmware's 16-bit id showed up }
    if not TJSONObject(V).TryGetValue<Integer>('id', Id) then Id := -1;
    Log(Format('  %s: reply id %d while awaiting %d, ignored', [Payload^.Remote.Addr, Id, PendingId]));
    V.Free;
  end
  else V.Free;
end;

function TAutoCalBoard.Request(const FClass, FNum: Integer; const Params: TJSONObject; const Quiet: Boolean): TJSONObject;
begin
  Result := nil;
  RequestLock.Enter;
  var Req: TJSONObject := nil;

  try
    ReqId := NextId(ReqId);
    Req := TAutoCalProtocol.Request(FClass, FNum, ReqId, Params);

    PendingId := ReqId;
    QuietReply := Quiet;
    ReplyEvent.ResetEvent;
    if not Quiet then Log('>> ' + FAddress + #13#10 + Req.Format(4));
    if not Sock.SendData(FAddress, AUTOCAL_PORT, AnsiString(Req.ToJSON)) then Exit;

    if ReplyEvent.WaitFor(REPLY_TIMEOUT_MS) = wrSignaled then
      Result := PendingReply;
  finally
    PendingId := -1;
    PendingReply := nil;
    RequestLock.Leave;
    Req.Free;
  end;
end;

{ Request plus the status check; Reply is the caller's to free (nil on timeout). Logs any refusal }
function TAutoCalBoard.Call(const FClass, FNum: Integer; out Reply: TJSONObject; const Params: TJSONObject; const Quiet: Boolean): Boolean;
begin
  Reply := Request(FClass, FNum, Params, Quiet);
  if Reply = nil then
  begin
    FLastStatus := 'no reply';
    FLastError := -1;
    if not Quiet then Log(Format('%s %d: no reply from %s', [TAutoCalProtocol.ClassName(FClass), FNum, FAddress]));
    Exit(False);
  end;

  FLastStatus := TAutoCalProtocol.StatusOf(Reply);
  FLastError := TAutoCalProtocol.ErrorOf(Reply);
  Result := TAutoCalProtocol.IsOk(Reply);
  if not Result then
    Log(Format('%s %d refused: %s (%d)', [TAutoCalProtocol.ClassName(FClass), FNum, FLastStatus, FLastError]));
end;

function TAutoCalBoard.Simple(const FClass, FNum: Integer): Boolean;
begin
  var Reply: TJSONObject;
  Result := Call(FClass, FNum, Reply);
  Reply.Free;
end;

function TAutoCalBoard.Ping(const Quiet: Boolean): Boolean;
begin
  var Reply: TJSONObject;
  Result := Call(FC_SYS_STATUS, ST_FIRMWARE, Reply, nil, Quiet);
  Reply.Free;
end;

function TAutoCalBoard.Firmware(out FW: TFirmwareInfo): Boolean;
begin
  var Reply: TJSONObject;
  Result := Call(FC_SYS_STATUS, ST_FIRMWARE, Reply);
  try
    if Result then Result := TAutoCalProtocol.FirmwareFromJSON(TAutoCalProtocol.ParamsOf(Reply), FW);
    if Result then
      Log(Format('%s firmware %s, built %s'#13#10'%s', [FW.Device, FW.Version, FW.DateTime, FW.Notes]));
  finally
    Reply.Free;
  end;
end;

function TAutoCalBoard.SelectRelay(const FClass, Chan: Integer): Boolean;
begin
  Result := False;
  if (FClass < FC_VCHAN_RLY) or (FClass > FC_ISENSE_RLY) then Exit;
  if (Chan < 0) or (Chan > CLEAR_ALL_CHANS) then Exit;
  Result := Simple(FClass, Chan);
end;

function TAutoCalBoard.Supply(const FClass: Integer; const TurnOn: Boolean): Boolean;
begin
  Result := False;
  if (FClass < FC_FAN_RLY) or (FClass > FC_DPS_RLY) then Exit;
  Result := Simple(FClass, IfThen(TurnOn, SUPPLY_ON, SUPPLY_OFF));
end;

function TAutoCalBoard.Reset(const Option: Integer): Boolean;
begin
  Result := Simple(FC_RESET, Option);
end;

function TAutoCalBoard.ReadSystemInfo(var Info: TSystemInfo): Boolean;
begin
  Result := False;
  var Reply: TJSONObject;
  Info.Clear;

  if not Call(FC_SYS_STATUS, ST_RD_IDENTITY, Reply) then begin Reply.Free; Exit; end;
  TAutoCalProtocol.IdentityFromJSON(TAutoCalProtocol.ParamsOf(Reply), Info);
  Reply.Free;

  for var I := 0 to CHANS -1 do
  begin
    if not Call(FC_SYS_STATUS, ST_RD_SHUNT, Reply, TAutoCalProtocol.IndexToJSON(I), True) then begin Reply.Free; Exit; end;
    if TAutoCalProtocol.ShuntFromJSON(TAutoCalProtocol.ParamsOf(Reply), Info) <> I then begin Reply.Free; Exit; end;
    Reply.Free;
  end;

  for var I := 0 to TRACE_COUNT -1 do
  begin
    if not Call(FC_SYS_STATUS, ST_RD_TRACE, Reply, TAutoCalProtocol.IndexToJSON(I), True) then begin Reply.Free; Exit; end;
    if TAutoCalProtocol.TraceFromJSON(TAutoCalProtocol.ParamsOf(Reply), Info) <> I then begin Reply.Free; Exit; end;
    Reply.Free;
  end;

  if not Call(FC_SYS_STATUS, ST_RD_COMMENTS, Reply, nil, True) then begin Reply.Free; Exit; end;
  TAutoCalProtocol.CommentsFromJSON(TAutoCalProtocol.ParamsOf(Reply), Info);
  Reply.Free;

  { firmware_t is part of the record on the board; it reports the running build }
  if not Call(FC_SYS_STATUS, ST_FIRMWARE, Reply, nil, True) then begin Reply.Free; Exit; end;
  if not TAutoCalProtocol.FirmwareFromJSON(TAutoCalProtocol.ParamsOf(Reply), Info.Firmware) then begin Reply.Free; Exit; end;
  Reply.Free;

  Log('Calibration record read: ' + IfThen(Info.Serial <> '', Info.Serial + ' / ' + Info.Cert, '(blank)'));
  Result := True;
end;

function TAutoCalBoard.ReadRecordState(out State: TRecordState): Boolean;
begin
  var Reply: TJSONObject;
  Result := Call(FC_SYS_STATUS, ST_RD_STATE, Reply);
  try
    if Result then Result := TAutoCalProtocol.StateFromJSON(TAutoCalProtocol.ParamsOf(Reply), State);
    if Result then Log('Record state: ' + State.ToText);
  finally
    Reply.Free;
  end;
end;

{ stages every section; nothing reaches the EEPROM until the commit. A refused section stops the write }
function TAutoCalBoard.WriteSystemInfo(const Info: TSystemInfo; const Commit: Boolean): Boolean;
begin
  Result := False;
  var Reply: TJSONObject;

  if not Call(FC_SYS_UPDATE, SU_IDENTITY, Reply, TAutoCalProtocol.IdentityToJSON(Info)) then begin Reply.Free; Exit; end;
  Reply.Free;

  for var I := 0 to CHANS -1 do
  begin
    {
      each number once more as text, under its key with _text appended. The firmware's JSON parser keeps a
      float's digits only up to 8388607 and drops the one past that (99.99935 arrived as 99.9993); firmware
      0.5.5 on reads the text instead and keeps every digit a float holds. An older firmware ignores the text
    }
    var Shunt := TAutoCalProtocol.ShuntToJSON(Info, I);
    Shunt.AddPair('current_text',     Info.Shunts[I].JsonText(sfCurrent));
    Shunt.AddPair('previous_text',    Info.Shunts[I].JsonText(sfPrevious));
    Shunt.AddPair('difference_text',  Info.Shunts[I].JsonText(sfDifference));
    Shunt.AddPair('uncertainty_text', Info.Shunts[I].JsonText(sfUncertainty));
    if not Call(FC_SYS_UPDATE, SU_SHUNT, Reply, Shunt, True) then begin Reply.Free; Exit; end;
    Reply.Free;
  end;

  for var I := 0 to TRACE_COUNT -1 do
  begin
    if not Call(FC_SYS_UPDATE, SU_TRACE, Reply, TAutoCalProtocol.TraceToJSON(Info, I), True) then begin Reply.Free; Exit; end;
    Reply.Free;
  end;

  if not Call(FC_SYS_UPDATE, SU_COMMENTS, Reply, TAutoCalProtocol.CommentsToJSON(Info), True) then begin Reply.Free; Exit; end;
  Reply.Free;
  Log('Calibration record staged on the board');

  Result := not Commit or CommitSystemInfo;
end;

function TAutoCalBoard.CommitSystemInfo: Boolean;
begin
  { the commit may take a few seconds when most of the record changed: it feeds the watchdog per byte, we wait longer }
  var Reply: TJSONObject := nil;
  RequestLock.Enter;
  try
    ReqId := NextId(ReqId);
    var Req := TAutoCalProtocol.Request(FC_SYS_UPDATE, SU_COMMIT, ReqId);
    try
      PendingId := ReqId;
      QuietReply := False;
      ReplyEvent.ResetEvent;
      Log('>> ' + FAddress + #13#10 + Req.Format(4));
      if Sock.SendData(FAddress, AUTOCAL_PORT, AnsiString(Req.ToJSON)) and (ReplyEvent.WaitFor(10 * REPLY_TIMEOUT_MS) = wrSignaled) then
        Reply := PendingReply;
    finally
      PendingId := -1;
      PendingReply := nil;
      Req.Free;
    end;
  finally
    RequestLock.Leave;
  end;

  try
    FLastStatus := TAutoCalProtocol.StatusOf(Reply);
    FLastError := TAutoCalProtocol.ErrorOf(Reply);
    Result := TAutoCalProtocol.IsOk(Reply);
    if Reply = nil then Log('Commit: no reply')
    else if Result then Log('Calibration record committed to EEPROM')
    else Log(Format('Commit refused: %s (%d)', [FLastStatus, FLastError]));
  finally
    Reply.Free;
  end;
end;

function TAutoCalBoard.Download: Boolean;
begin
  Result := Simple(FC_SYS_DOWNLD, 0);
  if Result then Log(FAddress + ': rebooting into the bootloader (TFTP window about 15 s)');
end;

function TAutoCalBoard.Updating: Boolean;
begin
  Result := Assigned(UpdateTask) and not (UpdateTask.Status in
    [TTaskStatus.Completed, TTaskStatus.Canceled, TTaskStatus.Exception]);
end;

procedure TAutoCalBoard.CancelUpdate;
begin
  if not Updating then Exit;
  UpdateStop.SetEvent;
  Flasher.Cancel;
  Log('Update cancel requested');
end;

function TAutoCalBoard.Update(const FileName: String): Boolean;
begin
  Result := False;
  if Updating then begin Log('Update already running'); Exit; end;
  if not FileExists(FileName) then begin Log('Update: file not found: ' + FileName); Exit; end;

  UpdateStop.ResetEvent;

  UpdateTask := TTask.Run(
    procedure
    begin
      var Ok := False;
      try
        {
          where is the board? decided here, on its own ICMP ping, not on what the connect-time RPC ping found:
          Ariadne answers ping but has no RPC, the application answers both, a missing board answers neither
        }
        var Reachable := CommonsU.Ping(AnsiString(FAddress), 500);
        var InApp := Reachable and Ping(True);
        if InApp then Log(FAddress + ': application running')
        else if Reachable then Log(FAddress + ': answers ping but not the RPC: taken to be in the bootloader')
        else
        begin
          Log(FAddress + ': not answering ping');
          var Yes := False;
          var Ask: TOnConfirm := OnConfirm;
          if Assigned(Ask) then
            Yes := Ask(Format('%s does not answer ping.'#13#10'Send %s to its bootloader anyway?', [FAddress, ExtractFileName(FileName)]));
          if not Yes then begin Log('Declined, update aborted'); Exit; end;
        end;

        if InApp then
        begin
          { nothing may stay energised across the reboot }
          if not Reset(RS_ALL) then begin Log('Update aborted: release not confirmed'); Exit; end;
          if not Download then begin Log('Update aborted: download refused'); Exit; end;
        end;

        { the TFTP transfer leaves by the adapter the board answers; a silent board gets the one in its own /24 }
        var Ip, Gateway, Subnet: String;
        if InApp and (Via >= 0) then
        begin
          if not LocalNet(Via, Ip, Gateway, Subnet) then Ip := '';
        end
        else
        begin
          var First := '';
          var Pick := '';
          var N := 0;
          while LocalNet(N, Ip, Gateway, Subnet) do
          begin
            if First = '' then First := Ip;
            if SameNet24(Ip, FAddress) then begin Pick := Ip; Break; end;
            Inc(N);
          end;
          if Pick = '' then Pick := First;
          Ip := Pick;
        end;
        if Ip = '' then begin Log('No local interface on the board''s subnet, update aborted'); Exit; end;

        Ok := UpdateBoard(Ip, FileName, not InApp) = '';
      finally
        Log('Update finished');
        var Cb: TOnUpdateFinished := OnUpdateFinished;
        var Done := Ok;
        if Assigned(Cb) then TThread.Queue(nil, procedure begin Cb(Done) end);
      end;
    end);
  Result := True;
end;

function TAutoCalBoard.UpdateBoard(const Ip, FileName: String; const InBootloader: Boolean): String;
begin
  { download just reset the board: give it time to reach the bootloader; a board already there needs none }
  if InBootloader then Log('Sending to the bootloader')
  else
  begin
    Log('Waiting for the bootloader');
    if UpdateStop.WaitFor(BOOT_WAIT_MS) = wrSignaled then Exit('cancelled');
  end;

  Result := Flasher.Add(FAddress, FileName, Ip, '',
    procedure(Sent, Total: Int64)
    begin
      var Pct := Integer(Sent * 100 div Total);
      var Cb: TOnUpdateProgress := OnUpdateProgress;
      if Assigned(Cb) then TThread.Queue(nil, procedure begin Cb(Pct) end);
    end).Value;

  if Result <> '' then
  begin
    Log('Upload failed: ' + Result);
    Exit;
  end;

  Log('Sent, waiting for the application');
  for var Attempt := 1 to APP_WAIT_TRIES do
  begin
    if Ping(True) then
    begin
      FOnline := True;
      Log('Application is back');
      Exit('');
    end;
    if UpdateStop.WaitFor(2000) = wrSignaled then Exit('cancelled');
  end;

  Result := 'application did not answer within 90 s';
  Log(Result);
end;

{ TAnnounceListener }

constructor TAnnounceListener.Create;
begin
  Sock := TUdpSocketEx.Create(ANNOUNCE_PORT, OnDataRecvcd);
end;

destructor TAnnounceListener.Destroy;
begin
  FreeAndNil(Sock);
  inherited;
end;

procedure TAnnounceListener.OnDataRecvcd(const Payload: PSocketPayload);
var
  Raw: AnsiString;
begin
  if Payload = nil then Exit;
  SetString(Raw, PAnsiChar(@Payload^.AsBytes[0]), Payload^.Size);
  var S := Format('Board announced itself from %s: %s', [Payload^.Remote.Addr, String(Raw)]);
  TThread.ForceQueue(nil, procedure begin TUtils.HandleEvent(etMessage, S +#13#10); end);
end;

end.
