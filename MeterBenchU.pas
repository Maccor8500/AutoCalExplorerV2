unit MeterBenchU;

{
  The reference meters of the calibration bench: two Fluke 8505A or two Fluke 8588A (the 8588A in its 8508A
  emulation) on one Prologix GPIB-ETHERNET gateway, through DigitalMultiMeterU's TGpibGateway. Each meter is
  on its own: which are in use, their model, GPIB addresses and what each one measures come from the caller.

  The 8588A (and the 8508A it emulates) is a TMultiMeter. The 8505A is not one of DigitalMultiMeterU's meters:
  it speaks the 8500 series' character commands (instruction manual, section 2A) and is driven here, straight
  through the gateway. It has no identity query; its status reply stands in for one.

  An 8588A whose Configurations sheet says native SCPI (FlukeMetersU; the meter's own Emulation setting must then
  be None) is the same TMultiMeter created with T8588A_Protocol.tpSCPI. The choice is taken at Connect. Such a
  meter is set up with SCPI lines (ApplyNative), is started with INIT instead of the group trigger and gives its
  reading to FETC? (Fire, Recall).

  A sample is one Group Execute Trigger to every meter in use, so they start converting together, followed by
  the recall of each reading. A run waits the settling time, then takes a number of samples with the interval
  between them, on a task, and hands each one back on
  the main thread.

  No VCL: meter and gateway messages go through TUtils.HandleEvent on the main thread.
}

interface

uses
  System.SysUtils, System.Classes, System.Math, System.SyncObjs, System.Threading, System.Diagnostics, CommonsU,
  DigitalMultiMeterU, DebugTapU, FlukeMetersU;

const
  BENCH_METERS = 2;

  {
    Fluke 8505A (8500 series) remote characters, IEEE-488 interface option -05. A command string is executed
    by its termination character: ',' executes only, '?' executes, takes a reading and sends it. A Group
    Execute Trigger takes a reading without sending it ('@'); 'G?' then sends that reading
  }
  F85_RESET     = '*';                        { immediate; nothing may follow it for F85_RESET_MS, not even LF }
  F85_RESET_MS  = 3000;
  { S7 = 128 samples a reading (about 0.5 s), F0 = fast filter, T0 = single reading, line synchronous,
    B0 = ASCII readings, J0 = CR LF after each. The function character also selects autorange }
  F85_SETUP     = 'S7F0T0B0J0,';
  F85_VOLT_DC   = 'V,';
  F85_CURR_DC   = 'I,';
  F85_RECALL    = 'G?';                       { the reading of the last trigger }
  F85_STATUS    = 'G1?';                      { seven characters, the first two an error code <00 = none> }

type
  TBenchKind = (bkFluke8505A, bkFluke8508A, bkFluke8588A);

  TBenchSpec = record
    Use: Boolean;
    Kind: TBenchKind;
    { 8508A family, both off = 7 1/2 digits, normal conversion (about 6 s a reading): the quicker conversion,
      and 6 1/2 digits. Each trades noise for time; the 8505A has neither }
    Fast: Boolean;
    Res6: Boolean;
    { 8508A family: the range to hold, in volts (0.2, 2, 20, 200), or 0 = autorange. A measurement stays on
      one range for both polarities; autorange is for inputs nobody has worked out }
    RangeV: Double;
    GpibAddr: Byte;
    Mode: TMeterMode;                         { mmVoltageDC across the shunt, or mmCurrentDC in the path }
  end;
  TBenchSpecs = array [0..BENCH_METERS -1] of TBenchSpec;

  TBenchSample = record
    Index: Integer;                           { 1-based }
    Time: Double;                             { s from the run's start to this sample's trigger }
    Took: Double;                             { ms from the trigger to the last reading back }
    Ok: array [0..BENCH_METERS -1] of Boolean;
    Value: array [0..BENCH_METERS -1] of Double;    { V or A, by the meter's mode }
    ProbeOk: Boolean;                         { the caller's probe answered (see TBenchProbe) }
    Probe: Double;
  end;

  {
    asked on the sample task right after each trigger, while the meters convert: whatever else the caller
    wants measured at that instant (the tester channel's own current). nil = nothing
  }
  TBenchProbe = reference to function(out Value: Double): Boolean;

  {
    waiting for the readings to settle before the samples that count: readings are taken (and thrown away)
    until the last Window of them lie within LimitPpm of each other, or TimeoutMs has passed. With two meters
    in use it is the ratio of their readings that must hold (the source's noise is common to both and is not
    the measurement's concern); with one meter, its readings. Not Enabled = the settling time instead: a plain wait of WaitMs before the first sample
  }
  TBenchSettle = record
    Enabled: Boolean;
    WaitMs: Integer;
    Window: Integer;
    LimitPpm: Double;
    TimeoutMs: Integer;
  end;

  { all fired on the main thread }
  TOnBenchSettled = reference to procedure(const Stable: Boolean; const Readings: Integer; const Seconds: Double);
  TOnBenchSample = reference to procedure(const Sample: TBenchSample);
  TOnBenchDone = reference to procedure(const Taken: Integer; const Completed: Boolean);

  TBenchStats = record
    N: Integer;
    Mean, Dev, Min, Max: Double;
    Sem: Double;                              { standard error of the mean, Dev / sqrt(N) }
    Slope: Double;                            { least-squares drift, units per second }
  end;

  TMeterBench = class(TObject)
    private
      Bus: TGpibGateway;
      Meters: array [0..BENCH_METERS -1] of TMultiMeter;    { nil for an 8505A }
      Settings: array [0..BENCH_METERS -1] of TMeterSettings;
      { what answered at Connect, and as what }
      Up: array [0..BENCH_METERS -1] of Boolean;
      Kinds: array [0..BENCH_METERS -1] of TBenchKind;
      Addrs: array [0..BENCH_METERS -1] of Byte;
      Modes: array [0..BENCH_METERS -1] of TMeterMode;       { of an 8505A; a TMultiMeter keeps its own }
      Setups: array [0..BENCH_METERS -1] of AnsiString;      { the configuration line a TMultiMeter last got }
      Native: array [0..BENCH_METERS -1] of Boolean;         { an 8588A connected in its own SCPI }
      SampleTask: ITask;
      Cancel: TEvent;
      MySession: Integer;                     { see Session in the implementation }

      procedure OnMeterEvent(const Evt: PAppEvent);
      procedure Say(const Msg: String);
      function Connect8505(const Index: Integer; const Spec: TBenchSpec): Boolean;
      function SetMode8505(const Index: Integer; const Mode: TMeterMode): Boolean;
      function Apply(const Index: Integer; const Spec: TBenchSpec): Boolean;
      function ApplyNative(const Index: Integer; const Spec: TBenchSpec): Boolean;
      function SetupKey(const Index: Integer; const Spec: TBenchSpec): AnsiString;
      { starts a conversion on every listed meter: the group trigger, or INIT to a native 8588A }
      function Fire(const Addrs: TArray<Byte>; const Slots: TArray<Integer>): Boolean;
      { the reading of the last Fire }
      function Recall(const Slot: Integer; const Addr: Byte; out Value: Double): Boolean;
      function GetMode(const Index: Integer): TMeterMode;

    public
      constructor Create;
      destructor Destroy; override;

      {
        gateway first, then every meter in use: reset, identity, mode. True when at least one meter answered;
        Why names whatever did not. Blocks for a few seconds (connect timeout, the meters' reset)
      }
      function Connect(const Gateway: String; const Specs: TBenchSpecs; out Why: String): Boolean;
      { front panels back to local, everything closed. Waits for a sample still being taken }
      procedure Disconnect;
      function Connected: Boolean;

      {
        Count samples, with a wait of IntervalMs between one sample's readings and the next trigger, from every
        connected meter in use. A meter whose Mode changed since the last run is switched first. False if a
        run is already going or nothing is connected
      }
      function StartSampling(const Specs: TBenchSpecs; const Count, IntervalMs: Integer; const Settle: TBenchSettle;
        const Probe: TBenchProbe; const OnSettled: TOnBenchSettled; const OnSample: TOnBenchSample;
        const OnDone: TOnBenchDone): Boolean;
      { ends the run after the sample in hand; OnDone still fires, with Completed = False }
      procedure StopSampling;
      function Sampling: Boolean;

      { T in seconds, X in the meter's unit, same length }
      class function Stats(const T, X: TArray<Double>): TBenchStats; static;
      class function KindName(const Kind: TBenchKind): String; static;
  end;

implementation

const
  READ_TIMEOUT_MS = 30000;
  KIND_NAMES: array [TBenchKind] of String = ('Fluke 8505A', 'Fluke 8508A', 'Fluke 8588A');
  KIND_TYPES: array [TBenchKind] of TMeterType = (ManualMeter, FL8508A, FL8588A);    { 8505A: not a TMultiMeter }
  {
    the precision each kind is set to while connected: digits of resolution on the meter (RESLn) and the same
    number as TMultiMeter's read precision. On disconnect both go back to the shared unit's defaults
    (its own function line, RESL7, and DEFAULT_READ_PRECISION). 8505A: not set this way
  }
  KIND_PRECISION: array [TBenchKind] of Byte = (0, 7, 8);
  RECALLS: array [TBenchKind] of AnsiString = (F85_RECALL, FL_CMD_RECALL, FL_CMD_RECALL);

{
  the digits of resolution a kind is set to: for the 8508A and the 8588A what its Configurations sheet has saved
  (FlukeMetersU; 7 and 8 until something is), read from the configuration file each time it is asked for
}
function KindDigits(const Kind: TBenchKind): Byte;
begin
  case Kind of
    bkFluke8508A: Result := TFlukeMeters.SavedDigits(fm8508A);
    bkFluke8588A: Result := TFlukeMeters.SavedDigits(fm8588A);
  else
    Result := KIND_PRECISION[Kind];
  end;
end;

{
  a reading as either family sends it. The 8505A answers a failed reading with a lone '0': a reading proper
  always carries its exponent <+1.234567E+1>
}
function ParseReading(const Kind: TBenchKind; const Reply: String; out Value: Double): Boolean;
begin
  var S := Trim(Reply);
  Result := (S <> '') and ((Kind <> bkFluke8505A) or (Pos('E', S) > 0))
    and TryStrToFloat(S, Value, TFormatSettings.Invariant);
end;

var
  {
    bumped by every Connect and Disconnect: a result queued to the main thread carries the value it was taken
    under and is dropped when that is no longer current (the bench, or its owner, may be gone by then)
  }
  Session: Integer = 0;

{ TMeterBench }

constructor TMeterBench.Create;
begin
  inherited;
  Cancel := TEvent.Create(nil, True, False, '');
end;

destructor TMeterBench.Destroy;
begin
  Disconnect;
  FreeAndNil(Cancel);
  inherited;
end;

{ from the caller's thread, the sample task or a meter's ping thread: the text is copied here and logged on the main one }
procedure TMeterBench.OnMeterEvent(const Evt: PAppEvent);
begin
  if (Evt = nil) or (Evt^.Msg = '') then Exit;
  var S := Evt^.Msg;
  UniqueString(S);
  TThread.ForceQueue(nil, procedure begin TUtils.HandleEvent(etMessage, S); end);
end;

procedure TMeterBench.Say(const Msg: String);
begin
  var S := Msg;
  TThread.ForceQueue(nil, procedure begin TUtils.HandleEvent(etMessage, S); end);
end;

class function TMeterBench.KindName(const Kind: TBenchKind): String;
begin
  Result := KIND_NAMES[Kind];
end;

function TMeterBench.Connected: Boolean;
begin
  Result := Assigned(Bus) and Bus.Connected;
  if not Result then Exit;
  Result := False;
  for var I := 0 to BENCH_METERS -1 do
    if Up[I] then Exit(True);
end;

{$REGION ' FLUKE 8505A '}
{ reset, DC volts on autorange, then its status: the 8505A has no identity to ask for, an answer is the proof }
function TMeterBench.Connect8505(const Index: Integer; const Spec: TBenchSpec): Boolean;
var
  Status: String;
begin
  Result := False;
  var A := Spec.GpibAddr;
  Say(Format('initializing meter [%s] at GPIB address %d!'#13#10, [KIND_NAMES[Spec.Kind], A]));

  if not Bus.Write(A, F85_RESET) then Exit;
  Sleep(F85_RESET_MS);
  if not Bus.Write(A, F85_SETUP) then Exit;
  Modes[Index] := mmVoltageDC;
  if not SetMode8505(Index, Spec.Mode) then Exit;

  Result := Bus.Query(A, F85_STATUS, Status, 5000) and (Trim(Status) <> '');
  if not Result then Exit;
  Status := Trim(Status);
  if Copy(Status, 1, 2) = '00' then
    Say(Format('%s at GPIB address %d online :: status %s'#13#10, [KIND_NAMES[Spec.Kind], A, Status]))
  else
    Say(Format('%s at GPIB address %d online, error code %s :: status %s'#13#10,
      [KIND_NAMES[Spec.Kind], A, Copy(Status, 1, 2), Status]));
end;

function TMeterBench.SetMode8505(const Index: Integer; const Mode: TMeterMode): Boolean;
begin
  var Cmd: AnsiString := F85_VOLT_DC;
  if Mode = mmCurrentDC then Cmd := F85_CURR_DC;
  Result := Bus.Write(Addrs[Index], Cmd);
  if Result then Modes[Index] := Mode;
end;
{$ENDREGION}

{
  the 8508A family's function line for a meter: DigitalMultiMeterU's own <FL_CMD_VOLT_DC, FL_CMD_CURR_DC> with
  the resolution and the conversion speed the caller asked for
}
function SetupLine(const Spec: TBenchSpec): AnsiString;
begin
  var Res: Integer := KindDigits(Spec.Kind);
  if Res = 0 then Res := 7;
  if Spec.Res6 then Res := 6;
  var Speed := 'FAST_OFF';
  if Spec.Fast then Speed := 'FAST_ON';
  { DCV <v> selects the range that holds <v>: a value just inside the wanted range leaves no doubt at its edge }
  var Range := 'AUTO';
  { anything that is not one of the meter's ranges (0.2 V the lowest, 1000 V the highest) is autorange }
  if (Spec.RangeV >= 0.1) and (Spec.RangeV <= 1000) and (Spec.Mode <> mmCurrentDC) then
    Range := FloatToStrF(Spec.RangeV * 0.95, ffGeneral, 6, 0, TFormatSettings.Invariant);
  if Spec.Mode = mmCurrentDC then Result := AnsiString(Format('DCI AUTO,FILT_OFF,RESL%d,%s', [Res, Speed]))
  else Result := AnsiString(Format('DCV %s,FILT_OFF,RESL%d,%s,TWO_WR', [Range, Res, Speed]));
end;

{ a range the caller wants held, as SetupLine reads it }
function HeldRange(const Spec: TBenchSpec): Boolean;
begin
  Result := (Spec.RangeV >= 0.1) and (Spec.RangeV <= 1000) and (Spec.Mode <> mmCurrentDC);
end;

function SpecDigits(const Spec: TBenchSpec): Integer;
begin
  Result := KindDigits(Spec.Kind);
  if Result = 0 then Result := 7;
  if Spec.Res6 then Result := 6;
end;

{
  the same for an 8588A in its own SCPI, one program message: the range (RANG <v> = the range holding <v>) or
  autorange, and the aperture left to the meter (AUTO) or its quick one (FAST). The resolution is not in it:
  SCPI wants it in volts, which takes the range the meter chose (ApplyNative)
}
function NativeLine(const Spec: TBenchSpec): AnsiString;
begin
  var Speed := 'AUTO';
  if Spec.Fast then Speed := 'FAST';
  if Spec.Mode = mmCurrentDC then
    Result := AnsiString(Format('CURR:DC:RANG:AUTO ON;:CURR:DC:APER:MODE %s', [Speed]))
  else if HeldRange(Spec) then
    Result := AnsiString(Format('%s %s;:VOLT:DC:APER:MODE %s', [FL88_CMD_RANG_V,
      FloatToStrF(Spec.RangeV * 0.95, ffGeneral, 6, 0, TFormatSettings.Invariant), Speed]))
  else
    Result := AnsiString(Format('%s;:VOLT:DC:APER:MODE %s', [FL88_CMD_RANG_V_AUTO, Speed]));
end;

{ what Setups remembers of a meter's configuration: a spec that gives another key is sent again }
function TMeterBench.SetupKey(const Index: Integer; const Spec: TBenchSpec): AnsiString;
begin
  if Native[Index] then Result := NativeLine(Spec) + AnsiString(Format(' #%d', [SpecDigits(Spec)]))
  else Result := SetupLine(Spec);
end;

function TMeterBench.ApplyNative(const Index: Integer; const Spec: TBenchSpec): Boolean;
var
  Reply: String;
  Range, Ten: Double;
begin
  var A := Addrs[Index];
  Meters[Index].SetMode(Spec.Mode);
  var Line := NativeLine(Spec);
  Result := Bus.Write(A, Line);
  if not Result then Exit;
  var Shown := String(Line);

  { digits of resolution, in volts of the range the meter took. On autorange it keeps its own default }
  if HeldRange(Spec) and Bus.Query(A, FL88_CMD_RANG_V + '?', Reply, 3000)
    and TryStrToFloat(Trim(Reply), Range, TFormatSettings.Invariant) and (Range > 0) then
  begin
    Ten := 10;
    var Res := AnsiString('VOLT:DC:RES ' + FloatToStrF(Range * Power(Ten, -SpecDigits(Spec)), ffExponent, 3, 2,
      TFormatSettings.Invariant));
    Bus.Write(A, Res);
    Shown := Shown + Format('; %s <range %s V>', [String(Res), Trim(Reply)]);
  end;

  { what the meter refused: '<number>,"<text>"' per entry, 0 = nothing more }
  for var I := 1 to 10 do
  begin
    if not Bus.Query(A, FL88_CMD_ERROR, Reply, 2000) then Break;
    var P := Pos(',', Reply);
    if P = 0 then P := Length(Reply) +1;
    if StrToIntDef(Trim(Copy(Reply, 1, P -1)), -1) = 0 then Break;
    Say(Format('%s at GPIB address %d refused a setting :: %s'#13#10, [KIND_NAMES[Kinds[Index]], A, Trim(Reply)]));
  end;

  var Key := SetupKey(Index, Spec);
  if Key <> Setups[Index] then
    Say(Format('%s at GPIB address %d (native SCPI) :: %s'#13#10, [KIND_NAMES[Kinds[Index]], A, Shown]));
  Setups[Index] := Key;
end;

function TMeterBench.Fire(const Addrs: TArray<Byte>; const Slots: TArray<Integer>): Boolean;
var
  Group: TArray<Byte>;
begin
  Result := Length(Addrs) > 0;
  for var K := 0 to High(Slots) do
    if not Native[Slots[K]] then Group := Group + [Addrs[K]];
  if Length(Group) > 0 then Result := Bus.Trigger(Group);

  { trigger source IMMediate (TMultiMeter.Reset): INIT is the start. One after the other, a gateway write apart }
  for var K := 0 to High(Slots) do
    if Native[Slots[K]] then Result := Bus.Write(Addrs[K], FL88_CMD_ARM) and Result;
end;

function TMeterBench.Recall(const Slot: Integer; const Addr: Byte; out Value: Double): Boolean;
var
  Reply: String;
begin
  Value := 0;
  if not Native[Slot] then
    Exit(Bus.Query(Addr, RECALLS[Kinds[Slot]], Reply, READ_TIMEOUT_MS) and ParseReading(Kinds[Slot], Reply, Value));

  { FETC? answers 9.91E+37 while there is no reading yet: asked again until the conversion is in }
  var Clock := TStopwatch.StartNew;
  repeat
    if not (Bus.Query(Addr, FL88_CMD_RECALL, Reply, READ_TIMEOUT_MS) and ParseReading(Kinds[Slot], Reply, Value)) then
      Exit(False);
    if Abs(Value) < FL88_NO_READING then Exit(True);
    Sleep(100);
  until Clock.ElapsedMilliseconds >= READ_TIMEOUT_MS;
  Result := False;
end;

{ what a meter measures and how: its mode, then (8508A family) the resolution and speed on top of it }
function TMeterBench.Apply(const Index: Integer; const Spec: TBenchSpec): Boolean;
begin
  if not Assigned(Meters[Index]) then Exit(SetMode8505(Index, Spec.Mode));
  if Native[Index] then Exit(ApplyNative(Index, Spec));

  Meters[Index].SetMode(Spec.Mode);
  var Line := SetupLine(Spec);
  Result := Bus.Write(Addrs[Index], Line);
  if Result then
  begin
    if Line <> Setups[Index] then
      Say(Format('%s at GPIB address %d :: %s'#13#10, [KIND_NAMES[Kinds[Index]], Addrs[Index], String(Line)]));
    Setups[Index] := Line;
  end;
end;

function TMeterBench.GetMode(const Index: Integer): TMeterMode;
begin
  if Assigned(Meters[Index]) then Result := Meters[Index].GetMode
  else Result := Modes[Index];
end;

function TMeterBench.Sampling: Boolean;
begin
  Result := Assigned(SampleTask) and not (SampleTask.Status in
    [TTaskStatus.Completed, TTaskStatus.Canceled, TTaskStatus.Exception]);
end;

function TMeterBench.Connect(const Gateway: String; const Specs: TBenchSpecs; out Why: String): Boolean;
begin
  Result := False;
  Why := '';
  Disconnect;

  var Addr := Trim(Gateway);
  if not ValidAddress(Addr) then
  begin
    Why := 'the gateway address is not an IP address';
    Exit;
  end;

  var Wanted := 0;
  for var I := 0 to BENCH_METERS -1 do
    if Specs[I].Use then Inc(Wanted);
  if Wanted = 0 then
  begin
    Why := 'no meter is ticked';
    Exit;
  end;
  if Specs[0].Use and Specs[1].Use and (Specs[0].GpibAddr = Specs[1].GpibAddr) then
  begin
    Why := 'both meters have the same GPIB address';
    Exit;
  end;

  Inc(Session);
  MySession := Session;
  Bus := TGpibGateway.Create(Addr, TMeterUtils.GPIB_PORT, OnMeterEvent);
  if not Bus.Connect then
  begin
    Why := Format('the GPIB gateway at %s did not connect', [Addr]);
    Disconnect;
    Exit;
  end;

  {
    an 8505A on the bus: nothing may trail its reset character, so the gateway stops appending LF to what it
    passes on (EOI still closes every message, which the 8508A family accepts too); and in case the 8505A
    does not close its replies with EOI, the gateway's wait for more is kept short (a reply still to come is
    simply asked for again, see TGpibGateway.Query). '++' lines are the gateway's own, whatever the address
  }
  for var I := 0 to BENCH_METERS -1 do
    if Specs[I].Use and (Specs[I].Kind = bkFluke8505A) then
    begin
      Bus.Write(Specs[I].GpibAddr, '++eos 3');
      Bus.Write(Specs[I].GpibAddr, '++read_tmo_ms 500');
      Break;
    end;

  for var I := 0 to BENCH_METERS -1 do
  begin
    if not Specs[I].Use then Continue;
    Kinds[I] := Specs[I].Kind;
    Addrs[I] := Specs[I].GpibAddr;

    if Specs[I].Kind = bkFluke8505A then Up[I] := Connect8505(I, Specs[I])
    else
    begin
      Settings[I] := Default(TMeterSettings);
      Settings[I].Identity := KIND_TYPES[Specs[I].Kind];
      Settings[I].Socket.Kind := stSockTCP;
      Settings[I].LocalOnExit := True;
      var P: PMeterSettings := @Settings[I];

      { the shared-gateway constructor: the bench owns the gateway, each meter only its GPIB address }
      Native[I] := (Specs[I].Kind = bkFluke8588A) and TFlukeMeters.SavedScpi(fm8588A);
      var Protocol := tpEmulated8508A;
      if Native[I] then Protocol := tpSCPI;
      Meters[I] := TMultiMeter.Create(P, Bus, Specs[I].GpibAddr, OnMeterEvent, Protocol);
      Up[I] := Meters[I].Connect;
      Setups[I] := '';
      if Up[I] then
      begin
        { the kind's precision: here for what TMultiMeter reads, and in the function line Apply sends (RESLn) }
        Meters[I].SetReadPrecision(KindDigits(Specs[I].Kind));
        Apply(I, Specs[I]);
      end
      else FreeAndNil(Meters[I]);
    end;

    if not Up[I] then
    begin
      if Why <> '' then Why := Why + '; ';
      Why := Why + Format('%s at GPIB address %d did not answer', [KIND_NAMES[Specs[I].Kind], Specs[I].GpibAddr]);
    end;
  end;

  Result := Connected;
  if not Result then Disconnect;
end;

procedure TMeterBench.Disconnect;
begin
  Inc(Session);                               { a sample still on its way back is dropped }
  if Assigned(SampleTask) then
  begin
    Cancel.SetEvent;
    try
      SampleTask.Wait(READ_TIMEOUT_MS * BENCH_METERS + 5000);
    except
      { a failed sample task has nothing more to say }
    end;
    SampleTask := nil;
  end;

  { meters before the gateway they talk through; an 8505A only gets its front panel back }
  for var I := 0 to BENCH_METERS -1 do
  begin
    if Up[I] and not Assigned(Meters[I]) and Assigned(Bus) and Bus.Connected then Bus.Local(Addrs[I]);
    {
      the 8508A family is left as the shared unit sets a meter up, not as this bench had it: SetMode sends the
      unit's own function line (autorange, RESL7, FAST_OFF), and the read precision goes back to its default
    }
    if Up[I] and Assigned(Meters[I]) and Assigned(Bus) and Bus.Connected then
    begin
      if Meters[I].SetMode(Meters[I].GetMode) then
        Say(Format('%s at GPIB address %d :: defaults restored'#13#10, [KIND_NAMES[Kinds[I]], Addrs[I]]));
      Meters[I].SetReadPrecision(DEFAULT_READ_PRECISION);
    end;
    Up[I] := False;
    Native[I] := False;
    FreeAndNil(Meters[I]);
  end;
  FreeAndNil(Bus);
end;

procedure TMeterBench.StopSampling;
begin
  if Sampling then Cancel.SetEvent;
end;

function TMeterBench.StartSampling(const Specs: TBenchSpecs; const Count, IntervalMs: Integer; const Settle: TBenchSettle;
  const Probe: TBenchProbe; const OnSettled: TOnBenchSettled; const OnSample: TOnBenchSample;
  const OnDone: TOnBenchDone): Boolean;
begin
  Result := False;
  if Sampling or not Connected then Exit;

  var Want: TBenchSpecs := Specs;
  var Total := Max(Count, 1);
  var Pace := Max(IntervalMs, 0);
  var Hold: TBenchSettle := Settle;
  var Told: TOnBenchSettled := OnSettled;
  var Ask: TBenchProbe := Probe;
  var Each: TOnBenchSample := OnSample;
  var Done: TOnBenchDone := OnDone;
  var Queued := MySession;
  Cancel.ResetEvent;

  SampleTask := TTask.Run(
    procedure
    var
      Addrs: TArray<Byte>;
      Slots: TArray<Integer>;
    begin
      var Taken := 0;

      { who takes part; a role, resolution or speed changed since the last run is set before the first trigger }
      for var I := 0 to BENCH_METERS -1 do
        if Want[I].Use and Up[I] then
        begin
          if (GetMode(I) <> Want[I].Mode) or (Assigned(Meters[I]) and (SetupKey(I, Want[I]) <> Setups[I])) then
            Apply(I, Want[I]);
          Addrs := Addrs + [Want[I].GpibAddr];
          Slots := Slots + [I];
        end;

      { the wait for stable readings: same trigger, same recall, nothing kept }
      if (Length(Addrs) > 0) and Hold.Enabled and (Hold.Window > 1) then
      begin
        var Recent: TArray<TArray<Double>>;
        SetLength(Recent, Length(Slots));
        var Ratios: TArray<Double>;
        var Clock := TStopwatch.StartNew;
        var Seen := 0;
        var Stable := False;

        while not Stable and (Clock.ElapsedMilliseconds < Hold.TimeoutMs) and (Cancel.WaitFor(0) <> wrSignaled) do
        begin
          var Got := Fire(Addrs, Slots);
          var Shown := '';                     { debug tap: the readings thrown away here are shown nowhere else }
          for var K := 0 to High(Slots) do
          begin
            var V: Double;
            if Got and Recall(Slots[K], Addrs[K], V) then
            begin
              Recent[K] := Recent[K] + [V];
              if Length(Recent[K]) > Hold.Window then Delete(Recent[K], 0, 1);
              Shown := Shown + Format(' m%d=%s', [Slots[K] +1, FloatToStrF(V, ffGeneral, 10, 0, TFormatSettings.Invariant)]);
            end
            else
            begin
              Recent[K] := nil;                 { a missed reading starts that meter's window again }
              Shown := Shown + Format(' m%d=-', [Slots[K] +1]);
            end;
          end;
          Inc(Seen);

          {
            what must hold still. Two meters on one trigger: their ratio, which is what the measurement uses;
            the source's own noise and drift are in both readings alike and leave it. Each reading on its own
            follows the source and may never come within the limit. One meter: its readings, there is no other
          }
          var Series: TArray<TArray<Double>>;
          if Length(Slots) = 2 then
          begin
            if (Length(Recent[0]) > 0) and (Length(Recent[1]) > 0) and (Recent[0][High(Recent[0])] <> 0) then
            begin
              Ratios := Ratios + [Recent[1][High(Recent[1])] / Recent[0][High(Recent[0])]];
              if Length(Ratios) > Hold.Window then Delete(Ratios, 0, 1);
            end
            else Ratios := nil;
            Series := [Ratios];
          end
          else Series := Recent;

          Stable := Length(Series) > 0;
          var Spread := 0.0;
          for var K := 0 to High(Series) do
          begin
            var Centre := 0.0;
            if Length(Series[K]) > 0 then Centre := Abs(Mean(Series[K]));
            if (Length(Series[K]) < Hold.Window) or (Centre = 0) then Stable := False
            else
            begin
              Spread := Max(Spread, (MaxValue(Series[K]) - MinValue(Series[K])) / Centre * 1E6);
              if Spread > Hold.LimitPpm then Stable := False;
            end;
          end;
          var Judged := 'meter';
          if Length(Slots) = 2 then Judged := 'ratio';
          Tap('SETTLE %d t=%.1fs%s %s spread=%.2fppm of %g stable=%d', [Seen, Clock.Elapsed.TotalSeconds, Shown,
            Judged, Spread, Hold.LimitPpm, Ord(Stable)]);
        end;

        var Seconds := Clock.Elapsed.TotalSeconds;
        TThread.Queue(nil,
          procedure
          begin
            if (Queued = Session) and Assigned(Told) then Told(Stable, Seen, Seconds);
          end);
      end
      { the settling time: the wait before the first sample. A Stop during it ends the run with nothing taken }
      else if (Length(Addrs) > 0) and (Hold.WaitMs > 0) then Cancel.WaitFor(Hold.WaitMs);

      if Length(Addrs) > 0 then
      begin
        var Watch := TStopwatch.StartNew;
        for var N := 1 to Total do
        begin
          if Cancel.WaitFor(0) = wrSignaled then Break;

          var S := Default(TBenchSample);
          S.Index := N;
          var Mark := Watch.Elapsed.TotalMilliseconds;
          S.Time := Mark / 1000;

          { one trigger for all: the conversions start together. The readings are then collected in turn }
          if Fire(Addrs, Slots) then
          begin
            { the probe falls inside the meters' conversion: all three belong to the same moment }
            if Assigned(Ask) then S.ProbeOk := Ask(S.Probe);
            for var K := 0 to High(Slots) do
              S.Ok[Slots[K]] := Recall(Slots[K], Addrs[K], S.Value[Slots[K]]);
          end;
          S.Took := Watch.Elapsed.TotalMilliseconds - Mark;

          Inc(Taken);
          TThread.Queue(nil,
            procedure
            begin
              if (Queued = Session) and Assigned(Each) then Each(S);
            end);

          { the interval: the wait between every sample, from the last reading in to the next trigger }
          if (N < Total) and (Pace >= 1) and (Cancel.WaitFor(Pace) = wrSignaled) then Break;
        end;
      end;

      TThread.Queue(nil,
        procedure
        begin
          if (Queued = Session) and Assigned(Done) then Done(Taken, Taken = Total);
        end);
    end);
  Result := True;
end;

class function TMeterBench.Stats(const T, X: TArray<Double>): TBenchStats;
begin
  Result := Default(TBenchStats);
  Result.N := Length(X);
  if Result.N = 0 then Exit;

  Result.Mean := Mean(X);
  Result.Min := MinValue(X);
  Result.Max := MaxValue(X);
  if Result.N < 2 then Exit;

  Result.Dev := StdDev(X);
  Result.Sem := Result.Dev / Sqrt(Result.N);

  { drift: slope of the least-squares line through the samples over time }
  if Length(T) <> Result.N then Exit;
  var Tm := Mean(T);
  var Sxy := 0.0;
  var Sxx := 0.0;
  for var I := 0 to Result.N -1 do
  begin
    Sxy := Sxy + (T[I] - Tm) * (X[I] - Result.Mean);
    Sxx := Sxx + Sqr(T[I] - Tm);
  end;
  if Sxx > 0 then Result.Slope := Sxy / Sxx;
end;

end.
