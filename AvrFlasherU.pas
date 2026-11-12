unit AvrFlasherU;

{
  Bootloader programming over the Atmel-ICE (ISP) with avrdude: connect at a slow clock, back up,
  fuses on request, erase and flash the hex with verify. Runs on a task; every callback arrives on
  that task's thread and the caller marshals to its UI. No VCL.
}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.StrUtils, System.SyncObjs, System.Threading,
  System.IOUtils, System.Variants, System.Win.ComObj, Winapi.ActiveX, System.Zip;

const
  DEFAULT_FUSE: TArray<Integer> = [$FD, $D8, $FF];                     { EXT, HIGH, LOW: stock Mega 2560 Ariadne }
  AVRDUDE = 'C:\avrdude\avrdude.exe';                                  { 8.1 sees the ICE; PlatformIO's 6.3 cannot }
  AVRDUDE_RES = 'avr_dude';                                            { RCDATA: zip with avrdude.exe (+ avrdude.conf) at any depth }
  AVRDUDE_EXE = 'avrdude.exe';
  ICE_ID = 'VID_03EB&PID_2141';
  EXPECTED_SIGNATURE = '0x1e,0x98,0x1';                                { ATmega2560 }

  FLASH_SIZE = $40000;                                                 { ATmega2560: 256 KB }
  BOOT_START = $3E000;                                                 { BOOTSZ = 4096 words }

  DEFAULT_LOCK = $0F;                                                  { Arduino Mega: boot section protected from SPM, no ISP read lock }

{ the avrdude to run: AVRDUDE when installed, else the copy unpacked from the AVRDUDE_RES resource into
  %LOCALAPPDATA%\AutoCalv2\avrdude (unpacked once, on first need). '' when neither exists; Why says what was tried }
function AvrdudePath(out Why: String): String;

type
  TFuseSet = array [0..2] of Integer;                                  { EXT, HIGH, LOW; -1 = invalid entry }

  { what a run writes besides the hex. The order on the chip is fixed: fuses, erase, flash, verify, lock bits last
    (a chip erase clears the lock bits, so they can only be set after it) }
  TIspOptions = record
    Fuses: TFuseSet;
    WriteFuses: Boolean;
    Lock: Integer;                                                     { -1 = invalid entry }
    WriteLock: Boolean;
    Erase: Boolean;                                                    { chip erase before the write (avrdude -e; off = -D) }
    Verify: Boolean;                                                   { read back after the write (off = avrdude -V) }
  end;

  { Intel HEX image of the whole flash: merges files, checks where they land, writes one file back }
  TFlashImage = record
    Data: TBytes;                                                      { FLASH_SIZE, 0xFF where unused }
    Used: TBytes;                                                      { one flag per byte }
    procedure Init;
    { records of a file; raises on a malformed line or an address beyond the flash }
    procedure Load(const FileName: String);
    function LowestUsed: Integer;                                      { -1 when empty }
    function HighestUsed: Integer;
    function UsedBytes: Integer;
    function HasJumpTable: Boolean;                                    { 0x0C 0x94 at 0: the bootloader's "application present" test }
    procedure Save(const FileName: String);                            { 16-byte records, extended linear address per 64 KB }
  end;

  TAvrFlasher = class(TObject)
    private
      Task: ITask;
      Stop: TEvent;                                                    { manual-reset; set = cancel }
      FBackupRoot: String;

      function RunAvrdude(const Args: String; const OnLine: TProc<String>; const Cancel: TFunc<Boolean>;
        const OnPartial: TProc<String, Cardinal>): Cardinal;
      function Checks(const Opt: TIspOptions; out Refusal: String): Boolean;
      procedure Sequence(const Hex: String; const Opt: TIspOptions; const Done: String);

    public
      { all on the task thread }
      OnSay: TProc<String>;                                            { a finished line, also written to the log file }
      OnProgress: TProc<String>;                                       { the running phase's in-place line }
      OnAsk: TFunc<String, Boolean>;                                   { yes/no question; nil = no }
      OnCancelable: TProc<Boolean>;                                    { False while a step must not be interrupted }
      OnFinished: TProc<Boolean>;                                      { True when the flash was written (lock bits aside) }

      constructor Create(const BackupRoot: String);
      destructor Destroy; override;

      function Running: Boolean;
      { bootloader hex alone: the application area is erased. Opt.Erase and Opt.Verify are forced on }
      function Start(const HexFile: String; const Opt: TIspOptions; out Refusal: String): Boolean;
      { application hex, with the bootloader hex merged in when BootHex is not empty: one write, no network.
        Without Opt.Erase the write lands onto whatever is there, which only works on blank flash (bits can only
        go 1 -> 0). The merged image is written next to the run's backup folder }
      function StartDirect(const AppHex, BootHex: String; const Opt: TIspOptions; out Refusal: String): Boolean;
      procedure Cancel;

      { "0xFD", "$FD" or "FD" -> value, -1 if not one or two hex digits }
      class function ParseFuse(const Text: String): Integer; static;
      { "Atmel-ICE connected, serial ..., status ..." or "Atmel-ICE not connected", through WMI }
      class function IceStatus: String; static;
  end;

implementation

const
  ISP_SLOW: array [0..1] of String = ('125kHz', '32kHz');               { connect, backup and fuses: any chip state }
  ISP_FAST = '3.4MHz';                                                 { only once the chip is known to run at 16 MHz;
                                                                         under the 4 MHz (F_CPU/4) ISP limit with margin }
  EXIT_CANCELLED: Cardinal = $FFFFFFFE;

var
  AvrdudeFound: String;                                                { resolved once per run; '' = not resolved yet }

{ first avrdude.exe below Root (the zip may carry a top-level folder), '' if none }
function FindExe(const Root: String): String;
begin
  Result := '';
  if not TDirectory.Exists(Root) then Exit;
  var Hits := TDirectory.GetFiles(Root, AVRDUDE_EXE, TSearchOption.soAllDirectories);
  if Length(Hits) > 0 then Result := Hits[0];
end;

function AvrdudePath(out Why: String): String;
begin
  Why := '';
  if AvrdudeFound <> '' then Exit(AvrdudeFound);

  { 1. an installed copy }
  if FileExists(AVRDUDE) then
  begin
    AvrdudeFound := AVRDUDE;
    Exit(AvrdudeFound);
  end;

  { 2. already unpacked by an earlier run }
  var Root := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'AutoCalv2'), 'avrdude');
  Result := FindExe(Root);
  if Result <> '' then
  begin
    AvrdudeFound := Result;
    Exit;
  end;

  { 3. unpack the resource }
  if FindResource(HInstance, PChar(AVRDUDE_RES), RT_RCDATA) = 0 then
  begin
    Why := Format('%s not found and no %s resource in this build', [AVRDUDE, AVRDUDE_RES]);
    Exit('');
  end;

  try
    var Res := TResourceStream.Create(HInstance, AVRDUDE_RES, RT_RCDATA);
    var Zip := TZipFile.Create;
    try
      Zip.Open(Res, zmRead);
      TDirectory.CreateDirectory(Root);
      Zip.ExtractAll(Root);
    finally
      Zip.Free;
      Res.Free;
    end;
  except
    on E: Exception do
    begin
      Why := Format('%s not found; unpacking the %s resource to %s failed: %s', [AVRDUDE, AVRDUDE_RES, Root, E.Message]);
      Exit('');
    end;
  end;

  Result := FindExe(Root);
  if Result = '' then
    Why := Format('%s not found; the %s resource unpacked to %s holds no %s (the Windows release zip is needed, not the sources)',
      [AVRDUDE, AVRDUDE_RES, Root, AVRDUDE_EXE])
  else
  begin
    AvrdudeFound := Result;
    Why := Format('%s not found: using %s unpacked from the %s resource', [AVRDUDE, Result, AVRDUDE_RES]);
  end;
end;

{ TFlashImage }

procedure TFlashImage.Init;
begin
  SetLength(Data, FLASH_SIZE);
  FillChar(Data[0], FLASH_SIZE, $FF);
  SetLength(Used, FLASH_SIZE);
  FillChar(Used[0], FLASH_SIZE, 0);
end;

procedure TFlashImage.Load(const FileName: String);
var
  Base: Cardinal;                                                      { extended linear / segment address }
  LineNo: Integer;

  function Hex(const S: String; const Pos, Len: Integer): Integer;
  begin
    Result := StrToIntDef('$' + Copy(S, Pos, Len), -1);
    if Result < 0 then raise Exception.CreateFmt('%s line %d: not hexadecimal', [ExtractFileName(FileName), LineNo]);
  end;

begin
  Base := 0;
  LineNo := 0;
  for var Raw in TFile.ReadAllLines(FileName) do
  begin
    Inc(LineNo);
    var L := Trim(Raw);
    if L = '' then Continue;
    { ':' + 10 hex digits of header/checksum + 2 per data byte: always an odd length }
    if (L[1] <> ':') or (Length(L) < 11) or not Odd(Length(L)) then
      raise Exception.CreateFmt('%s line %d: not an Intel HEX record', [ExtractFileName(FileName), LineNo]);

    var Count := Hex(L, 2, 2);
    var Addr  := Hex(L, 4, 4);
    var Kind  := Hex(L, 8, 2);
    if Length(L) <> 11 + Count * 2 then
      raise Exception.CreateFmt('%s line %d: length does not match the record', [ExtractFileName(FileName), LineNo]);

    var Sum := 0;
    for var I := 0 to Count + 4 do Sum := Sum + Hex(L, 2 + I * 2, 2);
    if (Sum and $FF) <> 0 then raise Exception.CreateFmt('%s line %d: checksum error', [ExtractFileName(FileName), LineNo]);

    case Kind of
      0:
        for var I := 0 to Count -1 do
        begin
          var A := Base + Cardinal(Addr) + Cardinal(I);
          if A >= FLASH_SIZE then
            raise Exception.CreateFmt('%s line %d: address 0x%X is beyond the 256 KB flash', [ExtractFileName(FileName), LineNo, A]);
          Data[A] := Hex(L, 10 + I * 2, 2);
          Used[A] := 1;
        end;
      1: Break;                                                        { end of file }
      2: Base := Cardinal(Hex(L, 10, 4)) shl 4;                        { extended segment address }
      4: Base := Cardinal(Hex(L, 10, 4)) shl 16;                       { extended linear address }
      3, 5: ;                                                          { start addresses: irrelevant for flash }
      else raise Exception.CreateFmt('%s line %d: record type %d not supported', [ExtractFileName(FileName), LineNo, Kind]);
    end;
  end;
end;

function TFlashImage.LowestUsed: Integer;
begin
  for var I := 0 to FLASH_SIZE -1 do
    if Used[I] <> 0 then Exit(I);
  Result := -1;
end;

function TFlashImage.HighestUsed: Integer;
begin
  for var I := FLASH_SIZE -1 downto 0 do
    if Used[I] <> 0 then Exit(I);
  Result := -1;
end;

function TFlashImage.UsedBytes: Integer;
begin
  Result := 0;
  for var I := 0 to FLASH_SIZE -1 do
    if Used[I] <> 0 then Inc(Result);
end;

function TFlashImage.HasJumpTable: Boolean;
begin
  Result := (Used[0] <> 0) and (Used[1] <> 0) and (Data[0] = $0C) and (Data[1] = $94);
end;

procedure TFlashImage.Save(const FileName: String);
var
  Lines: TStringList;

  procedure Emit(const Kind, Addr: Integer; const Bytes: TBytes);
  begin
    var S := Format(':%.2X%.4X%.2X', [Length(Bytes), Addr, Kind]);
    var Sum := Length(Bytes) + (Addr shr 8) + (Addr and $FF) + Kind;
    for var B in Bytes do
    begin
      S := S + IntToHex(B, 2);
      Sum := Sum + B;
    end;
    Lines.Add(S + IntToHex((-Sum) and $FF, 2));
  end;

begin
  Lines := TStringList.Create;
  try
    var Segment := -1;
    var A := 0;
    while A < FLASH_SIZE do
    begin
      if Used[A] = 0 then begin Inc(A); Continue; end;

      if (A shr 16) <> Segment then
      begin
        Segment := A shr 16;
        Emit(4, 0, [Segment shr 8, Segment and $FF]);
      end;

      { a run of up to 16 used bytes that stays inside the 64 KB segment }
      var N := 0;
      while (N < 16) and (A + N < FLASH_SIZE) and (Used[A + N] <> 0) and (((A + N) shr 16) = Segment) do Inc(N);
      Emit(0, A and $FFFF, Copy(Data, A, N));
      Inc(A, N);
    end;
    Emit(1, 0, []);
    Lines.SaveToFile(FileName);
  finally
    Lines.Free;
  end;
end;

{ TAvrFlasher }

constructor TAvrFlasher.Create(const BackupRoot: String);
begin
  FBackupRoot := BackupRoot;
  Stop := TEvent.Create(nil, True, False, '');
end;

destructor TAvrFlasher.Destroy;
begin
  if Assigned(Stop) then Stop.SetEvent;
  if Assigned(Task) then Task.Wait(15000);
  FreeAndNil(Stop);
  inherited;
end;

function TAvrFlasher.Running: Boolean;
begin
  Result := Assigned(Task) and not (Task.Status in [TTaskStatus.Completed, TTaskStatus.Canceled, TTaskStatus.Exception]);
end;

procedure TAvrFlasher.Cancel;
begin
  if Running then Stop.SetEvent;
end;

class function TAvrFlasher.ParseFuse(const Text: String): Integer;
begin
  var S := Trim(Text);
  if S.StartsWith('0x', True) then S := S.Substring(2)
  else if S.StartsWith('$') then S := S.Substring(1);

  Result := -1;
  if Length(S) in [1, 2] then Result := StrToIntDef('$' + S, -1);
end;

class function TAvrFlasher.IceStatus: String;
begin
  Result := 'Atmel-ICE not connected';
  try
    var Locator: OleVariant := CreateOleObject('WbemScripting.SWbemLocator');
    var Svc: OleVariant := Locator.ConnectServer('.', 'root\cimv2');
    var Rows: OleVariant := Svc.ExecQuery('SELECT PNPDeviceID, Status FROM Win32_PnPEntity ' +
      'WHERE PNPDeviceID LIKE ''USB\\VID_03EB&PID_2141\\%''');

    var Enum := IUnknown(Rows._NewEnum) as IEnumVariant;
    var Dev: OleVariant;
    var Fetched: Cardinal;

    if Enum.Next(1, Dev, Fetched) = S_OK then
    begin
      var Id := String(Dev.PNPDeviceID);
      Result := Format('Atmel-ICE connected, serial %s, status %s',
        [Copy(Id, LastDelimiter('\', Id) +1, MaxInt), String(Dev.Status)]);
    end;
  except
    on E: Exception do Result := 'Atmel-ICE check failed: ' + E.Message;
  end;
end;

{
  blocking: runs avrdude with stdout and stderr merged, OnLine gets each CR/LF terminated line; returns the exit code.
  Cancel (may be nil) is polled every 25 ms: True kills avrdude and the result is EXIT_CANCELLED.
  OnPartial (may be nil) gets the unfinished line and the elapsed ms, about 4 times a second while output flows and
  once a second while avrdude is silent: a progress bar has no line break until it finishes
}
function TAvrFlasher.RunAvrdude(const Args: String; const OnLine: TProc<String>; const Cancel: TFunc<Boolean>;
  const OnPartial: TProc<String, Cardinal>): Cardinal;
begin
  Result := Cardinal(-1);
  var Sa: TSecurityAttributes;
  Sa.nLength := SizeOf(Sa);
  Sa.bInheritHandle := True;
  Sa.lpSecurityDescriptor := nil;
  var RdPipe, WrPipe: THandle;

  if not CreatePipe(RdPipe, WrPipe, @Sa, 0) then Exit;
  try
    SetHandleInformation(RdPipe, HANDLE_FLAG_INHERIT, 0);
    var Si: TStartupInfo;
    FillChar(Si, SizeOf(Si), 0);
    Si.cb := SizeOf(Si);
    Si.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    Si.wShowWindow := SW_HIDE;
    Si.hStdOutput := WrPipe;
    Si.hStdError := WrPipe;
    var Pi: TProcessInformation;
    var Why: String;
    var Cmd := '"' + AvrdudePath(Why) + '" ' + Args;
    OnLine('> ' + Cmd);
    UniqueString(Cmd);
    if not CreateProcess(nil, PChar(Cmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, Si, Pi) then Exit;
    CloseHandle(WrPipe);
    WrPipe := 0;

    try
      var Buf: TBytes;
      SetLength(Buf, 1024);
      var N, Avail: DWORD;
      var Line := '';
      var Cancelled := False;
      var Started := GetTickCount64;
      var Beat := Started;

      while True do
      begin
        Avail := 0;
        if not PeekNamedPipe(RdPipe, nil, 0, nil, @Avail, nil) then Break;

        if Avail > 0 then
        begin
          if not ReadFile(RdPipe, Buf[0], Length(Buf), N, nil) or (N = 0) then Break;
          for var I := 0 to Integer(N) -1 do
            if Buf[I] in [10, 13] then
            begin
              if Line <> '' then OnLine(Line);
              Line := '';
            end
            else Line := Line + Char(Buf[I]);
        end

        else if WaitForSingleObject(Pi.hProcess, 25) = WAIT_OBJECT_0 then
        begin
          { exited: one more look for output still in the pipe, none left means done }
          if not PeekNamedPipe(RdPipe, nil, 0, nil, @Avail, nil) or (Avail = 0) then Break;
        end;

        if Assigned(OnPartial) then
        begin
          var Interval: UInt64 := 1000;
          if Avail > 0 then Interval := 250;
          if GetTickCount64 -Beat >= Interval then
          begin
            Beat := GetTickCount64;
            OnPartial(Line, Cardinal(Beat -Started));
          end;
        end;

        if Assigned(Cancel) and Cancel() then
        begin
          TerminateProcess(Pi.hProcess, 1);
          Cancelled := True;
          Break;
        end;
      end;

      if Line <> '' then OnLine(Line);
      WaitForSingleObject(Pi.hProcess, INFINITE);
      GetExitCodeProcess(Pi.hProcess, Result);
      if Cancelled then Result := EXIT_CANCELLED;
    finally
      CloseHandle(Pi.hProcess);
      CloseHandle(Pi.hThread);
    end;
  finally
    CloseHandle(RdPipe);
    if WrPipe <> 0 then CloseHandle(WrPipe);
  end;
end;

function TAvrFlasher.Checks(const Opt: TIspOptions; out Refusal: String): Boolean;
begin
  Result := False;
  Refusal := '';
  if Running then begin Refusal := 'A flash is already running'; Exit; end;
  var Why: String;
  if AvrdudePath(Why) = '' then begin Refusal := Why; Exit; end;
  if (Why <> '') and Assigned(OnSay) then OnSay(Why);                 { unpacked just now (the Firmware tab normally did it on first show) }
  if not IceStatus.StartsWith('Atmel-ICE connected') then begin Refusal := 'Atmel-ICE not connected: nothing done'; Exit; end;

  if Opt.WriteFuses then
  begin
    if (Opt.Fuses[0] < 0) or (Opt.Fuses[1] < 0) or (Opt.Fuses[2] < 0) then begin Refusal := 'Fuse entries are invalid: nothing written'; Exit; end;
    if (Opt.Fuses[1] and $20) <> 0 then begin Refusal := Format('High fuse 0x%.2X would disable SPI programming: refused', [Opt.Fuses[1]]); Exit; end;
  end;
  if Opt.WriteLock and (Opt.Lock < 0) then begin Refusal := 'Lock entry is invalid: nothing written'; Exit; end;
  Result := True;
end;

function TAvrFlasher.Start(const HexFile: String; const Opt: TIspOptions; out Refusal: String): Boolean;
begin
  Result := False;
  if not Checks(Opt, Refusal) then Exit;
  if not FileExists(HexFile) then begin Refusal := 'Hex file not found: ' + HexFile; Exit; end;

  var Hex := HexFile;
  var O := Opt;
  O.Erase := True;                                                     { a bootloader over an old one needs the erase }
  O.Verify := True;
  Stop.ResetEvent;
  Task := TTask.Run(procedure begin
    Sequence(Hex, O, 'Bootloader flashed and verified. The application was erased: push the firmware with Update.');
  end);
  Result := True;
end;

function TAvrFlasher.StartDirect(const AppHex, BootHex: String; const Opt: TIspOptions; out Refusal: String): Boolean;
begin
  Result := False;
  if not Checks(Opt, Refusal) then Exit;
  if not FileExists(AppHex) then begin Refusal := 'Application hex not found: ' + AppHex; Exit; end;
  if (BootHex <> '') and not FileExists(BootHex) then begin Refusal := 'Bootloader hex not found: ' + BootHex; Exit; end;

  { one image: the application below BOOT_START, the bootloader at and above it }
  var App, Boot: TFlashImage;
  App.Init;
  try
    App.Load(AppHex);
  except
    on E: Exception do begin Refusal := E.Message; Exit; end;
  end;
  if not App.HasJumpTable then begin Refusal := 'Application hex has no JMP vector table at 0: is it the firmware .hex? Nothing done'; Exit; end;
  if App.HighestUsed >= BOOT_START then
  begin
    Refusal := Format('Application reaches 0x%X, into the boot section (0x%X): nothing done', [App.HighestUsed, BOOT_START]);
    Exit;
  end;
  var Merged := Format('application %d bytes', [App.UsedBytes]);

  if BootHex <> '' then
  begin
    Boot.Init;
    try
      Boot.Load(BootHex);
    except
      on E: Exception do begin Refusal := E.Message; Exit; end;
    end;

    if (Boot.LowestUsed < 0) or (Boot.LowestUsed < BOOT_START) then
    begin
      Refusal := Format('Bootloader hex has data at 0x%X, below the boot section (0x%X): are the two files swapped? Nothing done',
        [Boot.LowestUsed, BOOT_START]);
      Exit;
    end;
    for var I := BOOT_START to FLASH_SIZE -1 do
      if Boot.Used[I] <> 0 then begin App.Data[I] := Boot.Data[I]; App.Used[I] := 1; end;
    Merged := Merged + Format(' + bootloader %d bytes at 0x%X', [Boot.UsedBytes, Boot.LowestUsed]);
  end;

  var Dir := IncludeTrailingPathDelimiter(FBackupRoot);
  ForceDirectories(Dir);
  var Hex := Dir + 'direct_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.hex';
  try
    App.Save(Hex);
  except
    on E: Exception do begin Refusal := 'Cannot write the merged image: ' + E.Message; Exit; end;
  end;

  var O := Opt;
  var Done := IfThen(Opt.Verify, 'Flashed and verified: ', 'Flashed (not verified): ') + Merged + '. The board runs the application on the next reset' +
    IfThen(BootHex <> '', '; Update over the network stays available.', '; there is no bootloader, so Update over the network will not work.');
  Stop.ResetEvent;
  Task := TTask.Run(procedure begin Sequence(Hex, O, Done); end);
  Result := True;
end;

procedure TAvrFlasher.Sequence(const Hex: String; const Opt: TIspOptions; const Done: String);
begin
  var Want := Opt.Fuses;
  var WriteFuses := Opt.WriteFuses;
  var Erase := Opt.Erase;
  var Verify := Opt.Verify;
  var Vtarget: String := '?';
  var InitFailed := False;
  var Flashed := False;
  var Sig := '';
  var Cur: TArray<Integer>;

  { one folder per run: the log, and the backup of step 2 }
  var Dir := IncludeTrailingPathDelimiter(FBackupRoot) + FormatDateTime('yyyymmdd_hhnnss', Now) + '\';
  ForceDirectories(Dir);
  var LogFile := Dir + 'flash.log';
  var ToFile: TProc<String> :=
    procedure(S: String)
    begin
      try
        TFile.AppendAllText(LogFile, FormatDateTime('hh:nn:ss', Now) + '  ' + S + sLineBreak, TEncoding.UTF8);
      except
        { a full disk must never stop a flash }
      end;
    end;

  var Say: TProc<String> :=
    procedure(S: String)
    begin
      ToFile(S);
      if Assigned(OnSay) then OnSay(S);
    end;

  var Progress: TProc<String> :=
    procedure(S: String)
    begin
      if Assigned(OnProgress) then OnProgress(S);
    end;

  var LastBar := '';
  var BarName: TFunc<String, String> :=
    function(L: String): String
    begin
      Result := Copy(L, 1, Pos(' ', L + ' ') -1);
      if Result = 'Writing' then LastBar := 'Writing'
      else if (Result = 'Reading') and (LastBar = 'Writing') then Result := 'Verifying';
    end;

  var Tick: TProc<String, Cardinal> :=
    procedure(L: String; Ms: Cardinal)
    begin
      var Pct := -1;
      if Pos('|', L) > 0 then
      begin
        var P := Pos('%', L);
        if P > 0 then
        begin
          var Q := P -1;
          while (Q > 0) and CharInSet(L[Q], ['0'..'9']) do Dec(Q);
          Pct := StrToIntDef(Copy(L, Q +1, P -Q -1), -1);
        end
        else                                         // no figure yet: the bar is 50 characters wide
        begin
          var Hashes := 0;
          for var Ch in L do
            if Ch = '#' then Inc(Hashes);
          Pct := Hashes * 2;
        end;
      end;

      if Pct > 100 then Pct := 100;
      if Pct >= 0 then Progress(Format('%s: %d%%  (%d s)', [BarName(L), Pct, Ms div 1000]))
      else if Ms >= 2000 then Progress(Format('working... (%d s)', [Ms div 1000]));
    end;

  var Stopped: TFunc<Boolean> :=
    function: Boolean
    begin
      Result := Stop.WaitFor(0) = wrSignaled;
    end;

  var Cancelable: TProc<Boolean> :=
    procedure(B: Boolean)
    begin
      if Assigned(OnCancelable) then OnCancelable(B);
    end;

  var Finish: TProc :=
    procedure
    begin
      if Assigned(OnFinished) then OnFinished(Flashed);
    end;

  var OnLine: TProc<String> :=
    procedure(L: String)
    begin
      if L.StartsWith('> ') then LastBar := '';
      if ContainsText(L, 'Vtarget') then Vtarget := Trim(Copy(L, Pos(':', L) +1, MaxInt));
      if ContainsText(L, 'initialization failed') then InitFailed := True;

      if L.StartsWith('0x') then
      begin
        if Pos(',', L) > 0 then Sig := L                                      // signature line
        else Cur := Cur + [StrToIntDef('$' + Copy(L, 3, MaxInt), -1)];        // single byte, in -U order
      end;

      { a bar: Tick shows its progress, so only the finished one is kept, in place and in the log file }
      if (Pos(' | ', L) > 0) and (Pos('%', L) > 0) then
      begin
        if ContainsText(L, '100%') then
        begin
          var Shown := BarName(L) + Copy(L, Pos(' ', L), MaxInt);
          Progress(Shown);
          ToFile(Shown);
        end;
        Exit;
      end;
      Say(L);
    end;

  var Bail: TProc<String> :=
    procedure(S: String)
    begin
      Say(S);
      Finish();
    end;

  var Settle: TFunc<Cardinal, Boolean> :=
    function(Ms: Cardinal): Boolean
    begin
      Result := Stop.WaitFor(Ms) <> wrSignaled;
    end;

  var Ask: TFunc<String, Boolean> :=
    function(Q: String): Boolean
    begin
      Result := Assigned(OnAsk) and OnAsk(Q);
    end;

  Say('Log file: ' + LogFile);
  Say('Hex: ' + Hex);
  Say(Format('Fuses %s: E 0x%.2X H 0x%.2X L 0x%.2X', [IfThen(WriteFuses, 'will be written', 'not written'),
    Want[0], Want[1], Want[2]]));
  if Opt.WriteLock then Say(Format('Lock bits 0x%.2X will be written after the flash', [Opt.Lock]))
  else Say('Lock bits not written');

  { 1. connect and read, read-only: the first clock that answers wins }
  var Clock := '';
  var Code: Cardinal;

  for var C in ISP_SLOW do
  begin
    InitFailed := False;
    Cur := [];
    Sig := '';
    Say('ISP clock ' + C);
    Code := RunAvrdude('-c atmelice_isp -p m2560 -B ' + C +
      ' -U signature:r:-:h -U efuse:r:-:h -U hfuse:r:-:h -U lfuse:r:-:h -U lock:r:-:h', OnLine, Stopped, Tick);
    if (Code = 0) or (Code = EXIT_CANCELLED) or not InitFailed then begin Clock := C; Break; end;
    Say('No answer at ' + C);
  end;

  if Code = EXIT_CANCELLED then begin Bail('Cancelled: nothing was changed'); Exit; end;
  if (Code <> 0) or (Length(Cur) <> 4) then
  begin
    Bail(Format('Target not read (exit %d, Vtarget %s): check power, ISP cable, crystal. Nothing changed.', [Code, Vtarget]));
    Exit;
  end;

  Say(Format('Connected at %s: signature %s, fuses E 0x%.2X H 0x%.2X L 0x%.2X, lock 0x%.2X',
    [Clock, Sig, Cur[0], Cur[1], Cur[2], Cur[3]]));
  if Sig <> EXPECTED_SIGNATURE then begin Bail('Not an ATmega2560: nothing changed'); Exit; end;
  if not Settle(200) then begin Bail('Cancelled: nothing was changed'); Exit; end;

  { 1b. one read-only try of the fast clock. A chip already on its crystal takes it, and then the backup (the slow
    step: 256 KB is 71 s at 125 kHz, 5 s at 3.4 MHz) runs in seconds. A fresh chip at 1 MHz cannot, and stays slow }
  if Clock <> ISP_FAST then
  begin
    Code := RunAvrdude('-c atmelice_isp -p m2560 -B ' + ISP_FAST + ' -U signature:r:-:h', OnLine, Stopped, Tick);
    if Code = EXIT_CANCELLED then begin Bail('Cancelled: nothing was changed'); Exit; end;
    if Code = 0 then Clock := ISP_FAST
    else Say('Chip does not take ' + ISP_FAST + ' yet: staying at ' + Clock);
    if not Settle(200) then begin Bail('Cancelled: nothing was changed'); Exit; end;
  end;

  { 2. backup, before anything is erased or written }
  var BackupArgs := Format('-U "eeprom:r:%seeprom.eep:i"', [Dir]);
  if (Cur[3] and 3) <> 3 then                       // a lock mode is set: ISP cannot read the flash
  begin
    if not Ask(Format('The chip is read-protected (lock 0x%.2X): the flash cannot be backed up, only the EEPROM.'#13#10 +
      'Erase anyway?', [Cur[3]])) then
      begin Bail('Declined: nothing changed'); Exit; end;
  end
  else BackupArgs := Format('-U "flash:r:%sflash.hex:i" ', [Dir]) + BackupArgs;

  Say('Backing up to ' + Dir);
  Code := RunAvrdude(Format('-c atmelice_isp -p m2560 -B %s %s', [Clock, BackupArgs]), OnLine, Stopped, Tick);
  if Code = EXIT_CANCELLED then begin Bail('Cancelled: nothing was changed'); Exit; end;
  if Code <> 0 then begin Bail('Backup failed: nothing was erased or written'); Exit; end;
  if not Settle(200) then begin Bail('Cancelled: nothing was changed'); Exit; end;

  { 3. fuses, before the hex, only if ticked and different }
  if WriteFuses then
  begin
    if (Cur[0] = Want[0]) and (Cur[1] = Want[1]) and (Cur[2] = Want[2]) then Say('Fuses already as requested: not written')
    else
    begin
      if not Ask(Format('Write fuses?'#13#10'E 0x%.2X -> 0x%.2X'#13#10'H 0x%.2X -> 0x%.2X'#13#10'L 0x%.2X -> 0x%.2X'#13#10#13#10 +
        'This can change the clock source. Without a working crystal the chip becomes unreachable.',
        [Cur[0], Want[0], Cur[1], Want[1], Cur[2], Want[2]])) then
        begin Bail('Fuse write declined: nothing changed'); Exit; end;

      { no cancel here: stopping between fuse bytes could leave the clock fuse and the others mismatched }
      Cancelable(False);
      Say('Writing fuses: this cannot be cancelled');
      if RunAvrdude(Format('-c atmelice_isp -p m2560 -B %s -U efuse:w:0x%.2X:m -U hfuse:w:0x%.2X:m -U lfuse:w:0x%.2X:m',
           [Clock, Want[0], Want[1], Want[2]]), OnLine, nil, Tick) <> 0 then
        begin Bail('Fuse write failed: check the fuses before powering the board down'); Exit; end;
      Say('Fuses written and verified');
      Cancelable(True);

      { 3b. crystal proof: only a chip running at about 16 MHz answers at 3.4 MHz. The new clock applies at the
        next reset, and the crystal needs its start-up time, so wait and retry before declaring it bad }
      if Cur[2] <> Want[2] then
      begin
        Say('Checking that the chip answers at ' + ISP_FAST + ' (proves the crystal runs)');
        for var Attempt := 1 to 3 do
        begin
          var Pause: Cardinal := 500;
          if Attempt = 1 then Pause := 250;
          if not Settle(Pause) then begin Bail('Cancelled before the erase: the application is intact'); Exit; end;
          Code := RunAvrdude('-c atmelice_isp -p m2560 -B ' + ISP_FAST + ' -U signature:r:-:h', OnLine, Stopped, Tick);
          if Code = EXIT_CANCELLED then begin Bail('Cancelled before the erase: the application is intact'); Exit; end;
          if Code = 0 then Break;
          Say(Format('No answer yet (try %d of 3)', [Attempt]));
        end;

        if Code <> 0 then
        begin
          Bail('No answer at ' + ISP_FAST + ' after the clock fuse change: the crystal is not running as expected. ' +
            'Stopped before the erase: the application is intact.');
          Exit;
        end;
        Clock := ISP_FAST;
      end;
    end;
  end;

  if not Settle(200) then begin Bail('Cancelled before the erase: the application is intact'); Exit; end;

  { 4. flash at whichever clock the chip took. -e = chip erase first, -D = write onto what is there; -V = skip the read-back }
  var Flags := IfThen(Erase, '-e', '-D') + IfThen(Verify, '', ' -V');
  if not Erase then Say('No chip erase: the write only succeeds onto blank flash (bits can only go 1 -> 0)');
  if not Verify then Say('No verify: the write is not read back');
  Say(IfThen(Erase, 'Erasing and flashing at ', 'Flashing at ') + Clock);
  Code := RunAvrdude(Format('-c atmelice_isp -p m2560 -B %s %s -U "flash:w:%s:i"', [Clock, Flags, Hex]), OnLine, Stopped, Tick);
  if Code = EXIT_CANCELLED then begin Bail('Cancelled: the chip may be erased or partly written. ISP still works: run the flash again.'); Exit; end;
  if Code <> 0 then begin Bail(Format('Flash failed (exit %d). ISP still works: run it again%s.', [Code, IfThen(Erase, ' (the chip is erased)', ', with Erase ticked')])); Exit; end;
  Say(Done);
  Flashed := True;

  { 5. lock bits, last: the chip erase above cleared them, and nothing may be written after they are set.
    Lock bits can only be programmed (1 -> 0) until the next chip erase, so a value with more 1s than the chip
    holds cannot be applied without an erase }
  if Opt.WriteLock then
  begin
    var Have := $3F;                                                   { after a chip erase; otherwise what was read }
    if not Erase then Have := Cur[3] and $3F;
    var WantLock := Opt.Lock and $3F;
    if WantLock = Have then Say(Format('Lock bits already 0x%.2X: not written', [WantLock]))
    else if (WantLock and not Have) <> 0 then
      Say(Format('Lock bits 0x%.2X cannot be written over 0x%.2X without a chip erase: not written', [WantLock, Have]))
    else
    begin
      if ((WantLock and 3) <> 3) and not Ask(Format('Lock bits 0x%.2X set an ISP read/write lock: the flash can no longer be read back ' +
        'or backed up, only erased. Write them?', [WantLock])) then
        begin Bail('Lock write declined: the flash is programmed, lock bits unchanged'); Exit; end;

      Cancelable(False);
      Say(Format('Writing lock bits 0x%.2X', [WantLock]));
      if RunAvrdude(Format('-c atmelice_isp -p m2560 -B %s -U lock:w:0x%.2X:m', [Clock, WantLock]), OnLine, nil, Tick) <> 0 then
        Say('Lock write failed: the flash is programmed, check the lock bits')
      else Say('Lock bits written and verified');
    end;
  end;
  Finish();
end;

end.
