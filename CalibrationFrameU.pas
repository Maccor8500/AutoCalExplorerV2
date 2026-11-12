unit CalibrationFrameU;

{
  Calibration tab: runs a current from a Maccor tester channel through one of the board's shunts, so the shunt
  can be calibrated. It is MacUniModCal's Check Channel form without its AutoCal, history and safeties boxes:
  the operator picks the shunt, enters the current and clicks Start.

  Start = route, then run:  voltage source OFF, channel current relay (CHI) of the box position, current shunt
  relay (RNGI) and voltage sense shunt relay (RNGV) of the shunt, then the tester channel is started at the
  current asked. Stop = stop the channel, wait for the current to die, release those three relay groups.

  The tester engine runs only while this tab is the open one: it starts every time the tab is entered
  (Activate), for the system this PC is set up for (BatTest.cfg), and stops when the tab is left or the
  application exits (Shutdown). No such system, or an engine that does not
  start: a warning, and the whole tab stays disabled. While a current runs (Busy) the main form keeps the
  operator on this tab and refuses to exit or to drop the board: only Stop ends it.

  UI only: the board is a TAutoCalBoard (handed over by the main form), the tester a TMaccorTester.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.UITypes, System.Diagnostics, System.Math,
  System.StrUtils, System.IniFiles, Vcl.Graphics, Vcl.ComCtrls,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, Vcl.Grids, Vcl.Samples.Spin, CommonsU,
  MacUniModCalUtilsU, DigitalMultiMeterU, AutoCalProtocolU, AutoCalBoardU, MaccorTesterU, MeterBenchU,
  DebugTapU, ShuntPlanU, ShuntCfgFormU, AppConfigU, CalDataU, FlukeMetersU, CertificateU;

type
  { one polarity's sample run under current, reduced: per meter the mean and the readings' deviation }
  TPolarityRun = record
    Valid: Boolean;
    Shunt: Integer;                           { 0-based, as selected }
    Samples: Integer;
    Mean, DevPpm: array [0..BENCH_METERS -1] of Double;
  end;

  { what a run of one shunt goes by, from the shunt plan: the standard, its uncertainty and the current }
  TRunSlot = record
    Found: Boolean;                           { the plan has both a standard and a current for it }
    Standard: Double;                         { ohms; 0 = not given }
    StandardUnc: Double;                      { ppm at k = 2; 0 = not given }
    Command: Double;                          { amps; 0 = not given }
  end;
  TRunSlots = array [PLAN_FIRST..PLAN_LAST] of TRunSlot;

  { both polarities of one shunt, worked out the way the Data sheet does (CalDataU) }
  TRatioResult = record
    Shunt: Integer;
    StdAvg, DutAvg: Double;                   { (charge - discharge) / 2, volts }
    Ratio: Double;                            { DutAvg / StdAvg }
    RepeatPpm: Double;                        { repeatability of the ratio, ppm }
    Standard, StandardUnc: Double;            { from the shunt plan: ohms, and ppm at k = 2; 0 = not given }
    RDut: Double;                             { Standard * Ratio; 0 = no standard value }
    UncPpm: Double;                           { expanded uncertainty of RDut, ppm at k = 2; 0 = not worked out }
    UncWhy: String;                           { why not, when it is 0 }
  end;

  { UncPpm = 0: no uncertainty was worked out, the record keeps the one it has }
  TShuntAccepted = reference to procedure(const Index: Integer; const Ohms, UncPpm: Double);
  { the value the record held for a shunt (0-based) before anything was accepted; 0 = none }
  TShuntPrevious = reference to function(const Index: Integer): Double;

  TCalibrationFrame = class(TFrame)

    DataGB: TGroupBox;
    Grid: TStringGrid;
    ControlGB: TGroupBox;
    ErrLbl: TLabel;
    StatGB: TGroupBox;
    StatGrid: TStringGrid;
    AcceptPanel: TPanel;
    AcceptBtn: TSpeedButton;
    Panel1: TPanel;
    AutoCalGB: TGroupBox;
    PosRBG: TRadioGroup;
    ShuntRBG: TRadioGroup;
    MeterGB: TGroupBox;
    MeterPanel: TPanel;
    Meter1Box: TCheckBox;
    Meter2Box: TCheckBox;
    BenchPanel: TPanel;
    GatewayLbl: TLabel;
    MeterBtn: TSpeedButton;
    ReadBtn: TSpeedButton;
    SampleLbl: TLabel;
    SettleLbl: TLabel;
    IntervalLbl: TLabel;
    GatewayEdit: TEdit;
    Use1Box: TCheckBox;
    Addr1Edit: TSpinEdit;
    Role1Combo: TComboBox;
    Use2Box: TCheckBox;
    Addr2Edit: TSpinEdit;
    Role2Combo: TComboBox;
    SampleEdit: TSpinEdit;
    AutoReadBox: TCheckBox;
    AutoSettleBox: TCheckBox;
    FastBox: TCheckBox;
    Res6Box: TCheckBox;
    AutoConnectBox: TCheckBox;
    SettleEdit: TSpinEdit;
    IntervalEdit: TSpinEdit;
    TesterGB: TGroupBox;
    ChanLbl: TLabel;
    ModeLbl: TLabel;
    RangeLbl: TLabel;
    CtrlLbl: TLabel;
    CurrLbl: TLabel;
    StartStopBtn: TSpeedButton;
    DownloadBtn: TSpeedButton;
    BothBox: TCheckBox;
    ChanEdit: TSpinEdit;
    ModeCombo: TComboBox;
    RangeCombo: TComboBox;
    ControlCombo: TComboBox;
    CurrEdit: TEdit;
    ShuntCfgBtn: TSpeedButton;
    procedure StartStopBtnClick(Sender: TObject);
    procedure DownloadBtnClick(Sender: TObject);
    procedure AcceptBtnClick(Sender: TObject);
    procedure CurrEditKeyPress(Sender: TObject; var Key: Char);
    procedure ChanEditChange(Sender: TObject);
    procedure GridDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
    procedure StatGridDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
    procedure MeterBoxClick(Sender: TObject);
    procedure MeterBtnClick(Sender: TObject);
    procedure ReadBtnClick(Sender: TObject);
    { up here with the other handlers the form file names: the dfm binds ShuntCfgBtn.OnClick to it by name }
    procedure ShuntCfgBtnClick(Sender: TObject);

  private
    FBoard: TAutoCalBoard;
    Tester: TMaccorTester;
    Bench: TMeterBench;

    SettleTimer: TTimer;                     { from the run's start to the first automatic sample }
    Taken: TArray<TBenchSample>;             { the samples of the run in hand, or of the last one }
    SampleSpecs: TBenchSpecs;                { what each meter measured in that run }
    SampleShunt: Integer;                    { the shunt selected then, -1 = none }
    SampleSize: Integer;                     { the samples that run was asked for }
    SampleRange: Double;                     { the meter range it was given, in volts; 0 = autorange }
    SampleAmps: Double;                     { the current commanded then, 0 = no current was running }
    RunAmps: Double;                         { the current of the run in hand, 0 = none }
    RunChan: Integer;                        { its tester channel (0-based), mode and range: the channel is sampled with them }
    RunMode: TMaccorControlMode;
    RunRange: TMaccorBrickRange;
    AutoSampling: Boolean;                   { the sampling was started by the run: its end stops the run }
    SampleMode: TMaccorControlMode;          { the polarity of the current the samples were taken under }
    SampleLive: Boolean;                     { a current was running when the sampling began }
    Pol: array [TMaccorControlMode] of TPolarityRun;    { the last finished run of each polarity }
    { Run Charge and Discharge: 0 = no sequence, 1 = the charge run, 2 = the discharge run (or the pause before it) }
    SeqStep: Integer;
    NextTimer: TTimer;                       { the pause between the two runs }
    LastDataTick: UInt64;                    { when the selected channel last sent data (or was last selected) }
    LiveTimer: TTimer;                       { keeps the Data box's caption saying whether that channel is alive }
    { what a run goes by, per shunt: the standard, its uncertainty and the current, from the plan (ApplyPlan); valid while HaveSlots }
    Slots: TRunSlots;
    HaveSlots: Boolean;
    Plan: TShuntPlan;                        { the box's own record: ShuntPlanU, edited through ShuntCfgBtn }
    ConfigLoaded: Boolean;                   { the saved configuration has been applied: changes are saved from now on }

    Usable: Boolean;                         { the engine is up: until then, and after a failure, the tab is disabled }
    Running: Boolean;
    Routed: Boolean;                         { this tab closed relays that are still to be released }
    Filter: TDataFilter;
    AvgI: Word;
    CurrentMax: Single;
    StartTime: TStopwatch;

    procedure SetBoard(const Value: TAutoCalBoard);
    function BenchSpecs: TBenchSpecs;
    procedure ShowBench;
    function ConfigFile: String;
    procedure LoadConfig;
    procedure SaveConfig;
    procedure ConfigChange(Sender: TObject);
    function ConnectMeters: Boolean;
    function BeginSampling(const Auto: Boolean): Boolean;
    procedure OnSample(const Sample: TBenchSample);
    procedure SamplingDone(const Count: Integer; const Completed: Boolean);
    procedure ArmAutoRead;
    procedure SettleTimerTimer(Sender: TObject);
    function ValueText(const Index: Integer; const Sample: TBenchSample): String;
    procedure ShowStats;
    function RoleMeter(const Role: Integer): Integer;
    procedure StorePolarity;
    function RatioResult(out Res: TRatioResult): Boolean;
    procedure ApplyPlan;
    procedure ShuntClick(Sender: TObject);
    procedure NextTimerTimer(Sender: TObject);
    function ChannelAlive: Boolean;
    procedure LiveTimerTimer(Sender: TObject);
    procedure AutoSettleClick(Sender: TObject);
    procedure Settled(const Stable: Boolean; const Readings: Integer; const Seconds: Double);    procedure StartTester;
    procedure Warn(const Why: String);
    procedure ShowRunning;
    procedure ResetDisplay;
    procedure StartIt;
    procedure StopIt;
    function Route(const Position, Shunt: Integer): Boolean;
    procedure Release;
    procedure UpdateChannel(const Raw: TMaccorChanData; const Data: TTranslatedChanData);

  protected
    procedure SetParent(AParent: TWinControl); override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { stops a run, releases the relays and closes the engine: on leaving the tab, and before the board goes at exit }
    procedure Shutdown;
    { at exit, while the form and its log still stand: the meters are released and their last messages logged }
    procedure CloseMeters;
    { the tab was entered: starts the tester engine }
    procedure Activate;
    { True while a current runs }
    function Busy: Boolean;
    { a line in the tab's red message row }
    procedure Notice(const S: String);
    property Board: TAutoCalBoard read FBoard write SetBoard;

  public
    { a shunt (0-based) measured and accepted: the main form passes it to the Calibration Record tab }
    OnShuntAccepted: TShuntAccepted;
    { asked at Accept: the shunt's value before this calibration, for the certificate's Prev. Value }
    OnShuntPrevious: TShuntPrevious;
  end;

implementation

{$R *.dfm}

const
  SAMPLES = 16;
  { from the channel's stop to the relays opening: no relay opens under current }
  RELEASE_SETTLE_MS = 500;
  { a selected channel sends data about twice a second: this long without any, and its board is taken to be silent }
  CHANNEL_SILENT_MS = 2000;
  { Auto Settle: sampling starts when each meter's last SETTLE_WINDOW readings lie within SETTLE_LIMIT_PPM of each
    other; after SETTLE_TIMEOUT_MS it starts anyway, with a warning }
  SETTLE_WINDOW = 5;
  SETTLE_LIMIT_PPM = 10;
  SETTLE_TIMEOUT_MS = 60000;
  { Auto Connect asks the gateway this many times, each this long, before it gives up }
  AUTO_CONNECT_PINGS = 2;
  AUTO_CONNECT_PING_MS = 500;
  { the shunt list itself (SHUNT_OHMS, SHUNT_VALUE) is AutoCalBoardU's: one table for every tab }
  { the meter pairs of the Meter(s) box: both meters of a pair are the same model, told apart by their row }
  { in the order of Meter1Box, Meter2Box, which is also the saved pair number - 1 }
  BENCH_PAIRS = 2;
  PAIR_KINDS: array [0..BENCH_PAIRS -1] of TBenchKind = (bkFluke8508A, bkFluke8588A);
  PAIR_NAMES: array [0..BENCH_PAIRS -1] of String = ('Fluke 8508A', 'Fluke 8588A');

{ the pair ticked in the Meter(s) box: 0 or 1, -1 = none }
function BenchPair(const Frame: TCalibrationFrame): Integer;
begin
  if Frame.Meter1Box.Checked then Result := 0
  else if Frame.Meter2Box.Checked then Result := 1
  else Result := -1;
end;

{ a meter row of that pair, as the row and its statistics column are titled }
function BenchName(const Pair, Index: Integer): String;
begin
  if Pair < 0 then Result := '-'
  else Result := Format('%s #%d', [PAIR_NAMES[Pair], Index +1]);
end;

constructor TCalibrationFrame.Create(AOwner: TComponent);
var
  FilterSettings: TFilterConfig;
begin
  inherited;
  FilterSettings := Default(TFilterConfig);
  FilterSettings.Inputs := 1;
  FilterSettings.InUse := 1;
  FilterSettings.Weight := SAMPLES;
  Filter := TDataFilter.Create(FilterSettings, @AvgI, nil);

  Bench := TMeterBench.Create;
  Meter1Box.Caption := PAIR_NAMES[0] + ' (x2)';
  Meter2Box.Caption := PAIR_NAMES[1] + ' (x2)';
  Use1Box.Caption := BenchName(0, 0);
  Use2Box.Caption := BenchName(0, 1);
  IntervalLbl.Caption := 'Interval (ms)';
  { both are waits and may be none: the settling time before the first sample, the interval between samples }
  SettleEdit.MinValue := 0;
  IntervalEdit.MinValue := 0;
  SettleLbl.Hint := 'Wait before the first sample is taken (ms)';
  SettleEdit.Hint := SettleLbl.Hint;
  IntervalLbl.Hint := 'Wait between every two samples (ms)';
  IntervalEdit.Hint := IntervalLbl.Hint;
  for var C in [TControl(SettleLbl), TControl(SettleEdit), TControl(IntervalLbl), TControl(IntervalEdit)] do
    C.ShowHint := True;
  SampleShunt := -1;

  { StatGrid: columns 0..2 = a statistic and its value per meter; columns 3..5 = what the run says about the
    shunt and about the sampling. Sizes and looks are the dfm's; only the text is written here }
  StatGrid.Cells[0, 0] := 'Measure';
  StatGrid.Cells[1, 0] := BenchName(0, 0);
  StatGrid.Cells[2, 0] := BenchName(0, 1);
  StatGrid.Cells[3, 0] := 'Result';
  StatGrid.Cells[4, 0] := 'Value';
  StatGrid.Cells[5, 0] := 'Detail';
  StatGrid.ColWidths[5]:= StatGrid.ColWidths[5] +5;

  SettleTimer := TTimer.Create(Self);
  SettleTimer.Enabled := False;
  SettleTimer.OnTimer := SettleTimerTimer;

  NextTimer := TTimer.Create(Self);
  NextTimer.Enabled := False;
  NextTimer.Interval := 1500;
  NextTimer.OnTimer := NextTimerTimer;

  LiveTimer := TTimer.Create(Self);
  LiveTimer.Interval := 500;
  LiveTimer.OnTimer := LiveTimerTimer;

  { the saved meter configuration is applied in SetParent: a combo box takes a selection only once it has a window }
  ShowBench;
  ShowStats;

  Tester := TMaccorTester.Create;
  Tester.OnData := procedure(const Raw: TMaccorChanData; const Data: TTranslatedChanData)
    begin
      UpdateChannel(Raw, Data);
    end;

  with Grid do
  begin
    Cells[0, 0] := 'Control';
    Cells[0, 1] := 'I :: OUT';
    Cells[0, 2] := 'I :: IN';
    Cells[0, 3] := 'V :: IN';
    Cells[0, 4] := Format('I :: AVG[%d]', [SAMPLES]);

    Cells[2, 0] := 'Current (A)';
    Cells[2, 1] := 'Voltage (V)';
    Cells[2, 2] := 'Power (W)';
    Cells[2, 3] := Format('Resistance (%s)', [OHMS]);
    Cells[2, 4] := 'I :: AVG';

    ColWidths[3] := ColWidths[3] +15;
  end;

  { relay number, then the shunt's nominal resistance }
  ShuntRBG.Items.Clear;
  for var I := 1 to CHANS do ShuntRBG.Items.Add(Format('%d (%s %s)', [I, SHUNT_OHMS[I], OHMS]));
  ShuntRBG.ItemIndex := -1;
  PosRBG.Items.Clear;
  for var I := 1 to CHANS do PosRBG.Items.Add(IntToStr(I));
  PosRBG.ItemIndex := -1;

  ResetDisplay;
  ShowRunning;
end;

{
  the main form parents the frame right after creating it. Only from then on can the controls have windows,
  and a TComboBox neither takes nor reports its selection without one: the saved configuration (the role
  combos among it) is applied here, once, and from here on every change to the meter box is saved as it is made
}
procedure TCalibrationFrame.SetParent(AParent: TWinControl);
begin
  inherited;
  if (AParent = nil) or ConfigLoaded then Exit;

  HandleNeeded;
  { both meters read volts: one across the standard resistor, one across the shunt (the workbook's VSTD and VDUT) }
  for var Combo in [Role1Combo, Role2Combo] do
  begin
    Combo.Items.Clear;
    Combo.Items.Add('Standard (VSTD)');
    Combo.Items.Add('Shunt (VDUT)');
  end;
  Role1Combo.ItemIndex := 0;
  Role2Combo.ItemIndex := 1;  { set here, not in the dfm: the IDE saves its own copy of the form over a default changed on disk }
  ControlCombo.ItemIndex := Ord(ctConstCurrent);
  LoadConfig;
  ConfigLoaded := True;

  { the shunt plan: what every run goes by }
  Plan := TShuntPlan.Create;
  var Seeded: Boolean;
  Plan.Load(Seeded);
  if Seeded then
    TUtils.HandleEvent(etMessage, 'Shunt plan: no plan file yet, the defaults are in use (Configure Shunts saves one)'#13#10)
  else
    TUtils.HandleEvent(etMessage, Format('Shunt plan: %s'#13#10, [TShuntPlan.FileName]));
  ApplyPlan;
  BothBox.OnClick := ConfigChange;
  ShuntRBG.OnClick := ShuntClick;
  AutoConnectBox.OnClick := ConfigChange;
  AutoReadBox.OnClick := ConfigChange;
  AutoSettleBox.OnClick := AutoSettleClick;
  { the meters' conversion: both off = 7 1/2 digits, normal speed. Taken up at Connect and at the next sample run }
  FastBox.Hint := 'Quicker conversion (FAST_ON): less time per reading, more noise';
  Res6Box.Hint := '6'#189' digits (RESL6) instead of the meter''s own setting (8508A: RESL7, 8588A: RESL8): less time per reading';
  FastBox.ShowHint := True;
  Res6Box.ShowHint := True;
  FastBox.OnClick := ConfigChange;
  Res6Box.OnClick := ConfigChange;
  Use1Box.OnClick := ConfigChange;
  Use2Box.OnClick := ConfigChange;
  Role1Combo.OnChange := ConfigChange;
  Role2Combo.OnChange := ConfigChange;
  Addr1Edit.OnChange := ConfigChange;
  Addr2Edit.OnChange := ConfigChange;
  SettleEdit.OnChange := ConfigChange;
  SampleEdit.OnChange := ConfigChange;
  IntervalEdit.OnChange := ConfigChange;
  GatewayEdit.OnChange := ConfigChange;
  ShowBench;
end;

{ nothing is saved here: by now the controls' windows are gone, and a combo box without one reports the
  selection it was loaded with, not the one the operator made. Shutdown and the change handlers save }
destructor TCalibrationFrame.Destroy;
begin
  FreeAndNil(Bench);
  FreeAndNil(Plan);
  FreeAndNil(Tester);
  FreeAndNil(Filter);
  inherited;
end;

procedure TCalibrationFrame.Shutdown;
begin
  SaveConfig;
  SeqStep := 0;
  NextTimer.Enabled := False;
  if Running then StopIt;
  Tester.Close;
  Usable := False;
  ShowRunning;
end;

{
  the meters go while the application is still whole. Left to the destructor, the disconnect ran during the
  form's teardown: it waits on the gateway's socket thread, that wait runs whatever is queued for the main
  thread, and the meters' queued log lines then wrote to a log that was already gone
}
procedure TCalibrationFrame.CloseMeters;
begin
  if not Assigned(Bench) then Exit;
  Screen.Cursor := crHourGlass;
  try
    Bench.StopSampling;
    Bench.Disconnect;
    CheckSynchronize;                         { what the disconnect had to say, logged now }
  finally
    Screen.Cursor := crDefault;
  end;
  ShowBench;
end;

function TCalibrationFrame.Busy: Boolean;
begin
  { the pause between a charge run and its discharge run is part of the action }
  Result := Running or (SeqStep > 0);
end;

procedure TCalibrationFrame.Notice(const S: String);
begin
  ErrLbl.Caption := S;
end;

procedure TCalibrationFrame.Activate;
begin
  if not Tester.Online then
  begin
    ErrLbl.Caption := '';
    { engine status goes to the main form's log, like every other message }
    TUtils.HandleEvent(etMessage, 'Calibration: starting the tester engine...'#13#10);
    Update;                                 { the tab is painted before the engine takes its moment }
    StartTester;
  end;

  { Auto Connect: the meters of the saved configuration come up with the tab }
  if AutoConnectBox.Checked and (BenchPair(Self) >= 0) and not Bench.Connected and (Trim(GatewayEdit.Text) <> '') then
  begin
    { only a gateway that is there: two pings without an answer and Auto Connect is given up (Connect still tries) }
    var Addr := Trim(GatewayEdit.Text);
    var Online := False;
    if ValidAddress(Addr) then
      for var Attempt := 1 to AUTO_CONNECT_PINGS do
        if CommonsU.Ping(AnsiString(Addr), AUTO_CONNECT_PING_MS) then
        begin
          Online := True;
          Break;
        end;

    if Online then ConnectMeters
    else
    begin
      ErrLbl.Caption := Format('Auto Connect: the GPIB gateway at %s is offline', [Addr]);
      TUtils.HandleEvent(etMessage, Format('Meters: Auto Connect given up, the GPIB gateway at %s did not answer %d pings'#13#10,
        [Addr, AUTO_CONNECT_PINGS]));
    end;
  end;
end;

{ the main form drops the board (nil) before it frees it: a run still going is stopped while the relays can be released }
procedure TCalibrationFrame.SetBoard(const Value: TAutoCalBoard);
begin
  if Value = FBoard then Exit;
  if Running then
  begin
    StopIt;
    ErrLbl.Caption := 'Stopped: the board was disconnected';
    SeqStep := 0;
    NextTimer.Enabled := False;
  end;
  FBoard := Value;
end;

{ the system is the PC's default one (BatTest.cfg): started here, never chosen }
procedure TCalibrationFrame.StartTester;
begin
  if TMaccorTester.DefaultSystem = mscUNSET then
  begin
    Warn('no Maccor system is set up on this PC (no BatTest.cfg)');
    Exit;
  end;

  var Why: String;
  Screen.Cursor := crHourGlass;
  try
    if not Tester.Open(TMaccorTester.DefaultSystem, Why) then
    begin
      Warn(Why);
      Exit;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  if Tester.ChanCount > 0 then ChanEdit.MaxValue := Tester.ChanCount;
  Tester.Select(ChanEdit.Value -1);
  LastDataTick := GetTickCount64;
  TUtils.HandleEvent(etMessage, Format('Calibration: tester engine running: %s (%s), %d channels'#13#10,
    [Tester.SystemName, TMaccorTester.DefaultSource, Tester.ChanCount]));
  Usable := True;
  ShowRunning;
end;

{ no tester, no tab: the reason goes to the log, and stays in the tab's red message row }
procedure TCalibrationFrame.Warn(const Why: String);
begin
  Usable := False;
  ShowRunning;
  ErrLbl.Caption := 'Calibration disabled: ' + Why;
  TUtils.HandleEvent(etMessage, Format('Calibration tab disabled: %s'#13#10, [Why]));
end;

{ the control box is locked during a run, and altogether while there is no tester }
procedure TCalibrationFrame.ShowRunning;

  {
    the inputs sit in group boxes and panels inside the control box. Those stay enabled: a control in a
    disabled parent takes no clicks, and the Stop button lives in one of them
  }
  procedure Lock(const Box: TWinControl);
  begin
    for var I := 0 to Box.ControlCount -1 do
    begin
      var C := Box.Controls[I];
      { the meters are read while the current runs: their box is never locked }
      if (C = StartStopBtn) or (C = ErrLbl) or (C = MeterGB) then Continue;
      if ((C is TCustomGroupBox) and not (C is TCustomRadioGroup)) or (C is TCustomPanel) then Lock(TWinControl(C))
      else C.Enabled := Usable and not (Running or (SeqStep > 0));
    end;
  end;

begin
  Lock(ControlGB);
  StartStopBtn.Enabled := Usable;

  if Running or (SeqStep > 0) then
  begin
    StartStopBtn.Caption := 'Stop';
    StartStopBtn.Font.Color := clRed;
  end
  else
  begin
    StartStopBtn.Caption := 'Start';
    StartStopBtn.Font.Color := clWindowText;
  end;
end;

procedure TCalibrationFrame.ResetDisplay;
begin
  with Grid do
    for var R := 0 to 4 do
    begin
      Cells[1, R] := '-';
      Cells[3, R] := '-';
    end;
  Grid.Cells[2, 4] := 'I :: AVG';
end;

{ the idle readings in the grid follow the channel box }
procedure TCalibrationFrame.ChanEditChange(Sender: TObject);
begin
  if not Assigned(Tester) then Exit;          { fires while the frame is still loading }
  if Running or not Tester.Online then Exit;
  if Tester.Preparing then Exit;              { it selects channels itself for now, and restores afterwards }
  if (ChanEdit.Text = '') or (ChanEdit.Value < 1) then Exit;
  Tester.Select(ChanEdit.Value -1);
  LastDataTick := GetTickCount64;             { the newly selected channel gets its two seconds to answer }
  ResetDisplay;
end;

procedure TCalibrationFrame.CurrEditKeyPress(Sender: TObject; var Key: Char);
begin
  if Ord(Key) = VK_RETURN then
  begin
    Key := #0;
    StartStopBtn.Click;
    Exit;
  end;
  NumbersOnly(Sender, Key);
end;

{ boards and channel calibration go to the tester only when the operator says so }
procedure TCalibrationFrame.DownloadBtnClick(Sender: TObject);
begin
  ErrLbl.Caption := '';
  if Running then
  begin
    ErrLbl.Caption := 'A current is running: Stop it before downloading';
    Exit;
  end;
  if not Tester.Online then
  begin
    ErrLbl.Caption := 'The tester engine is not running';
    Exit;
  end;
  if Tester.Preparing then
  begin
    ErrLbl.Caption := 'A download is already running';
    Exit;
  end;

  if ShowDialog(TForm(GetParentForm(Self)), dtConfirm,
    Format('Download the controller board of tester channel %d (firmware, then its channels'' calibration)?', [ChanEdit.Value]),
    [mbYes, mbNo], '', mbNo) <> mrYes then Exit;

  if Tester.Download(ChanEdit.Value -1) then ErrLbl.Caption := 'Downloading: progress is in the log. Start is held until it finishes'
  else ErrLbl.Caption := 'The download could not be started';
end;

procedure TCalibrationFrame.StartStopBtnClick(Sender: TObject);
begin
  StartStopBtn.Enabled := False;
  Screen.Cursor := crHourGlass;
  try
    { Stop also ends a charge-and-discharge sequence, wherever it stands }
    if Running or (SeqStep > 0) then
    begin
      SeqStep := 0;
      NextTimer.Enabled := False;
      if Running then StopIt else ShowRunning;
    end
    else StartIt;
  finally
    Screen.Cursor := crDefault;
    StartStopBtn.Enabled := True;
  end;
end;

{ MacUniModCal's modular SetCurrent, in the same order: the voltage source is off before any current path closes }
function TCalibrationFrame.Route(const Position, Shunt: Integer): Boolean;
begin
  Routed := True;
  Result := FBoard.Supply(FC_V_SRC_RLY, False)
    and FBoard.SelectRelay(FC_ICHAN_RLY, Position)
    and FBoard.SelectRelay(FC_ISENSE_RLY, Shunt)
    and FBoard.SelectRelay(FC_VSENSE_RLY, Shunt);
end;

{ the channel first, so the shunt relays open with nothing connected to them }
procedure TCalibrationFrame.Release;
begin
  if not Routed or not Assigned(FBoard) then Exit;
  var Ok := FBoard.SelectRelay(FC_ICHAN_RLY, CLEAR_ALL_CHANS);
  Ok := FBoard.SelectRelay(FC_ISENSE_RLY, CLEAR_ALL_CHANS) and Ok;
  Ok := FBoard.SelectRelay(FC_VSENSE_RLY, CLEAR_ALL_CHANS) and Ok;
  Routed := not Ok;
  if not Ok then
    TUtils.HandleEvent(etMessage, 'Calibration: the board did not confirm the release of its relays'#13#10);
end;

procedure TCalibrationFrame.StartIt;
var
  FltValue, MaxValue: Single;
  CtrlValue: Word;
  Why: String;
begin
  ErrLbl.Caption := '';

  { Run Charge and Discharge: the first of the two runs is the charge. Both are sampled by Auto Read }
  var StartSeq := BothBox.Checked and (SeqStep = 0);
  if StartSeq then
  begin
    if not (AutoReadBox.Checked and Bench.Connected) then
    begin
      ErrLbl.Caption := 'Run Charge and Discharge needs the meters connected and Auto Read ticked';
      Exit;
    end;
    if (RoleMeter(0) < 0) or (RoleMeter(1) < 0) then
    begin
      ErrLbl.Caption := 'One meter must be on the Standard and one on the Shunt';
      Exit;
    end;
    ModeCombo.ItemIndex := Ord(cmCharge);
  end;

  var ValStr := Trim(CurrEdit.Text);
  if (ValStr <> '') and (ValStr[1] = '.') then
  begin
    ValStr := '0' + ValStr;
    CurrEdit.Text := ValStr;
  end;
  if not TryStrToFloat(ValStr, FltValue) or (FltValue <= 0) then
  begin
    ErrLbl.Caption := 'Invalid entry!';
    Exit;
  end;
  if ShuntRBG.ItemIndex < 0 then
  begin
    ErrLbl.Caption := 'Select the shunt first';
    Exit;
  end;
  if PosRBG.ItemIndex < 0 then
  begin
    ErrLbl.Caption := 'Select the box position first';
    Exit;
  end;
  if not Assigned(FBoard) or not FBoard.Online then
  begin
    ErrLbl.Caption := 'The AutoCalibrator board is not connected (Start, bottom left)';
    Exit;
  end;
  if FBoard.Updating then
  begin
    ErrLbl.Caption := 'A firmware update is running';
    Exit;
  end;
  if not Tester.Online then
  begin
    ErrLbl.Caption := 'The tester engine is not running';
    Exit;
  end;

  { a board that is not answering cannot run a channel: the technician picks a channel on one that is }
  if not Tester.Preparing and not ChannelAlive then
  begin
    ErrLbl.Caption := Format('Channel %d''s board is not answering: pick a channel on another board', [ChanEdit.Value]);
    Exit;
  end;

  var Chan := ChanEdit.Value -1;
  var Mode := TMaccorControlMode(ModeCombo.ItemIndex);
  var Range := TMaccorBrickRange(RangeCombo.ItemIndex);
  var Control := TMaccorControlType(ControlCombo.ItemIndex);

  { the limit is checked before a relay moves; Run checks it again }
  MaxValue := Tester.MaxCurrent(Chan, Mode, Range);
  if MaxValue <= 0 then
  begin
    ErrLbl.Caption := Format('No R%d specification for channel %d', [Ord(Range) +1, Chan +1]);
    Exit;
  end;
  if FltValue > MaxValue then
  begin
    ErrLbl.Caption := Format('Asking: %f > Max: %.6f', [FltValue, MaxValue]);
    Exit;
  end;

  if not Route(PosRBG.ItemIndex, ShuntRBG.ItemIndex) then
  begin
    ErrLbl.Caption := Format('The board refused the routing: %s', [FBoard.LastStatus]);
    Release;
    Exit;
  end;

  if not Tester.Run(Chan, Mode, Range, Control, FltValue, CtrlValue, MaxValue, Why) then
  begin
    ErrLbl.Caption := Why;
    Release;
    Exit;
  end;

  CurrentMax := MaxValue;
  Filter.Reset;
  Grid.Cells[1, 0] := Format('0x%s', [IntToHex(CtrlValue, 4)]);
  Grid.Cells[2, 4] := 'I :: AVG';
  StartTime := TStopwatch.StartNew;
  Running := True;
  if StartSeq then
  begin
    SeqStep := 1;
    Pol[cmCharge].Valid := False;
    Pol[cmDischarge].Valid := False;
  end;
  RunAmps := FltValue;
  RunChan := Chan;
  RunMode := Mode;
  RunRange := Range;
  ArmAutoRead;
  ShowRunning;
  TUtils.HandleEvent(etMessage, Format('Calibration: channel %d, %s R%d, %s A through shunt %d (box position %d)'#13#10,
    [Chan +1, ModeCombo.Text, Ord(Range) +1, ValStr, ShuntRBG.ItemIndex +1, PosRBG.ItemIndex +1]));
end;

procedure TCalibrationFrame.StopIt;
begin
  if not Running then Exit;
  Running := False;
  { no sample is wanted from a current that is going away }
  SettleTimer.Enabled := False;
  Bench.StopSampling;
  RunAmps := 0;
  Tester.Stop;
  StartTime.Stop;
  Filter.Reset;
  AvoidBusyWait(RELEASE_SETTLE_MS);
  Release;
  ResetDisplay;
  ShowRunning;
  TUtils.HandleEvent(etMessage, 'Calibration: channel stopped, relays released'#13#10);
end;

{ Check Channel's UpdateChannel: every data frame of the active channel, on the main thread }
procedure TCalibrationFrame.UpdateChannel(const Raw: TMaccorChanData; const Data: TTranslatedChanData);
var
  Summary: TChannelSummary;
  Index: Integer;
  RawI: Word;
begin
  LastDataTick := GetTickCount64;
  if not HandleAllocated then Exit;
  Summary.AsTestTime := Raw.Test_Time;

  with Grid do
  begin
    if Data.Current <> 0 then
    begin
      Cells[3, 2] := FormatFloat('0.00E+0', Data.Current * Data.Voltage);
      Cells[3, 3] := FormatFloat('0.00E+0', Data.Voltage / Data.Current);
    end
    else
    begin
      Cells[3, 2] := '0.0000';
      Cells[3, 3] := '0.0000';
    end;

    Cells[1, 1] := Format('0x%s', [IntToHex(Summary.AsChanData.CurrentDAC)]);
    Cells[1, 2] := Format('0x%s', [IntToHex(Summary.AsChanData.CurrentRaw)]);
    Cells[1, 3] := Format('0x%s', [IntToHex(Summary.AsChanData.VoltageRaw)]);

    if not Running then
    begin
      Cells[1, 4] := '-';
      Cells[3, 4] := '-';
      Cells[3, 0] := Format('%.4f', [Data.Current]);
      Cells[3, 1] := Format('%.4f', [Data.Voltage]);
      Exit;
    end;

    Cells[3, 0] := Format('%.4f', [(Raw.Current / MAXWORD) * CurrentMax]);
    Cells[3, 1] := Format('%.4f', [Data.Voltage]);

    { the average starts once the output has had two seconds to settle; the dashes blink until then }
    if StartTime.ElapsedMilliseconds >= TWO_SEC then
    begin
      RawI := Raw.Current;
      Index := 0;
      Filter.Update(@RawI, @Index);
      Cells[1, 4] := Format('%d', [AvgI]);
      Cells[3, 4] := Format('%.4f', [(AvgI / MAXWORD) * CurrentMax]);
      Cells[2, 4] := Format('I :: AVG[%.2d]', [Index]);
    end
    else
    begin
      if Cells[1, 4] = '-' then Cells[1, 4] := '' else Cells[1, 4] := '-';
      if Cells[3, 4] = '-' then Cells[3, 4] := '' else Cells[3, 4] := '-';
    end;
  end;
end;

{$REGION ' METERS '}
{
  the meter pairs: one pair is in use at a time. CommonsU keeps the selection single; it tells the boxes apart
  by Tag, so each box in MeterPanel carries its own
}
procedure TCalibrationFrame.MeterBoxClick(Sender: TObject);
begin
  EnforceSingleCheckboxSelection(MeterPanel, Sender);
  ShowBench;
  if ConfigLoaded then SaveConfig;
end;

{ what the rows under the pair selection say: each meter on its own, in use or not, with its address and role }
function TCalibrationFrame.BenchSpecs: TBenchSpecs;

  procedure Fill(const Index: Integer; const Box: TCheckBox; const Addr: TSpinEdit; const Role: TComboBox);
  begin
    { no pair ticked = no meter in use; both meters of a pair are its model }
    var Pair := BenchPair(Self);
    Result[Index].Use := Box.Checked and (Pair >= 0);
    Result[Index].Kind := PAIR_KINDS[Max(Pair, 0)];
    Result[Index].GpibAddr := Byte(Addr.Value);
    Result[Index].Fast := FastBox.Checked;
    Result[Index].Res6 := Res6Box.Checked;
    { both roles read volts: the role says across what (RoleMeter) }
    Result[Index].Mode := mmVoltageDC;
  end;

begin
  { a record result starts as whatever was on the stack: what Fill does not set (the range) must read 0 = autorange }
  Result := Default(TBenchSpecs);
  Fill(0, Use1Box, Addr1Edit, Role1Combo);
  Fill(1, Use2Box, Addr2Edit, Role2Combo);
end;

{
  the pair, the gateway and the meters' use and addresses are fixed while connected; roles, sample count and
  pace are fixed while a sample run is going
}
procedure TCalibrationFrame.ShowBench;
begin
  var Pair := BenchPair(Self);
  var Defined := Pair >= 0;

  { the selected pair names the two meter rows and the two meter columns of the statistics grid }
  for var I := 0 to BENCH_METERS -1 do
  begin
    var Name := BenchName(Pair, I);

    StatGrid.Cells[I +1, 0] := Name;
    if I = 0 then Use1Box.Caption := Name else Use2Box.Caption := Name;
  end;
  var Up := Bench.Connected;
  var Busy := Bench.Sampling;

  MeterPanel.Enabled := not Up;
  GatewayEdit.Enabled := Defined and not Up;
  for var C in [TControl(Use1Box), TControl(Addr1Edit), TControl(Use2Box), TControl(Addr2Edit)] do
    C.Enabled := Defined and not Up;
  for var C in [TControl(Role1Combo), TControl(Role2Combo)] do
    C.Enabled := Defined and not Busy;
  for var C in [TControl(SampleEdit), TControl(IntervalEdit), TControl(AutoSettleBox), TControl(FastBox),
    TControl(Res6Box)] do
    C.Enabled := not Busy;
  SettleEdit.Enabled := not Busy and not AutoSettleBox.Checked;
  MeterBtn.Enabled := (Defined or Up) and not Busy;
  ReadBtn.Enabled := Up;

  if Up then
  begin
    MeterBtn.Caption := 'Disconnect';
    MeterBtn.Font.Color := clRed;
  end
  else
  begin
    MeterBtn.Caption := 'Connect';
    MeterBtn.Font.Color := clWindowText;
  end;

  if Busy then
  begin
    ReadBtn.Caption := 'Stop';
    ReadBtn.Font.Color := clRed;
  end
  else
  begin
    ReadBtn.Caption := 'Read';
    ReadBtn.Font.Color := clWindowText;
  end;
end;

{$REGION ' SAVED CONFIGURATION '}
{ beside the exe, named after it: AutoCalv2.ini, section [Meters] }
function TCalibrationFrame.ConfigFile: String;
begin
  Result := ChangeFileExt(ParamStr(0), '.ini');
end;

procedure TCalibrationFrame.LoadConfig;
const
  S = 'Meters';

  procedure Spin(const Ini: TMemIniFile; const Edit: TSpinEdit; const Key: String);
  begin
    Edit.Value := EnsureRange(Ini.ReadInteger(S, Key, Edit.Value), Edit.MinValue, Edit.MaxValue);
  end;

  procedure Role(const Ini: TMemIniFile; const Combo: TComboBox; const Key: String);
  begin
    Combo.ItemIndex := EnsureRange(Ini.ReadInteger(S, Key, Combo.ItemIndex), 0, Combo.Items.Count -1);
  end;

begin
  var Ini := TMemIniFile.Create(ConfigFile);
  try
    { the pair: 1 or 2; the boxes' own handler keeps the selection single }
    var Pair := Ini.ReadInteger(S, 'Pair', 1);
    Meter1Box.Checked := Pair <> 2;
    Meter2Box.Checked := Pair = 2;

    GatewayEdit.Text := Ini.ReadString(S, 'Gateway', GatewayEdit.Text);
    if Trim(GateWayEdit.Text) = '' then GatewayEdit.Text := '192.168.126.216';
    
    Use1Box.Checked := Ini.ReadBool(S, 'Use1', Use1Box.Checked);
    Use2Box.Checked := Ini.ReadBool(S, 'Use2', Use2Box.Checked);
    Spin(Ini, Addr1Edit, 'Addr1');
    Spin(Ini, Addr2Edit, 'Addr2');
    Role(Ini, Role1Combo, 'Role1');
    Role(Ini, Role2Combo, 'Role2');
    { one meter per role: a configuration saved before the roles meant Standard and Shunt has both the same }
    if Role1Combo.ItemIndex = Role2Combo.ItemIndex then Role2Combo.ItemIndex := 1 - Role1Combo.ItemIndex;

    AutoConnectBox.Checked := Ini.ReadBool(S, 'AutoConnect', AutoConnectBox.Checked);
    AutoReadBox.Checked := Ini.ReadBool(S, 'AutoRead', AutoReadBox.Checked);
    AutoSettleBox.Checked := Ini.ReadBool(S, 'AutoSettle', True);
    FastBox.Checked := Ini.ReadBool(S, 'Fast', False);
    Res6Box.Checked := Ini.ReadBool(S, 'Res6', False);
    Spin(Ini, SettleEdit, 'SettleMs');
    Spin(Ini, SampleEdit, 'Samples');
    Spin(Ini, IntervalEdit, 'IntervalMs');
    BothBox.Checked := Ini.ReadBool(S, 'ChargeAndDischarge', True);
  finally
    Ini.Free;
  end;
end;

procedure TCalibrationFrame.SaveConfig;
const
  S = 'Meters';
begin
  { before the saved configuration is applied the controls hold the form's defaults: writing them would lose it }
  if not ConfigLoaded then Exit;

  try
    var Ini := TMemIniFile.Create(ConfigFile);
    try
      Ini.WriteInteger(S, 'Pair', Max(BenchPair(Self), 0) +1);
      Ini.WriteString(S, 'Gateway', Trim(GatewayEdit.Text));
      Ini.WriteBool(S, 'Use1', Use1Box.Checked);
      Ini.WriteBool(S, 'Use2', Use2Box.Checked);
      Ini.WriteInteger(S, 'Addr1', Addr1Edit.Value);
      Ini.WriteInteger(S, 'Addr2', Addr2Edit.Value);
      Ini.WriteInteger(S, 'Role1', Role1Combo.ItemIndex);
      Ini.WriteInteger(S, 'Role2', Role2Combo.ItemIndex);
      Ini.WriteBool(S, 'AutoConnect', AutoConnectBox.Checked);
      Ini.WriteBool(S, 'AutoRead', AutoReadBox.Checked);
      Ini.WriteBool(S, 'AutoSettle', AutoSettleBox.Checked);
      Ini.WriteBool(S, 'Fast', FastBox.Checked);
      Ini.WriteBool(S, 'Res6', Res6Box.Checked);
      Ini.WriteInteger(S, 'SettleMs', SettleEdit.Value);
      Ini.WriteInteger(S, 'Samples', SampleEdit.Value);
      Ini.WriteInteger(S, 'IntervalMs', IntervalEdit.Value);
      Ini.WriteBool(S, 'ChargeAndDischarge', BothBox.Checked);
      Ini.DeleteKey(S, 'Workbook');               { left by the versions that wrote to a certificate workbook }
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    { a folder that cannot be written loses the configuration, nothing else }
    on E: Exception do
      TUtils.HandleEvent(etMessage, Format('Meters: configuration not saved: %s'#13#10, [E.Message]));
  end;
end;

procedure TCalibrationFrame.ConfigChange(Sender: TObject);
begin
  if ConfigLoaded then SaveConfig;
end;
{$ENDREGION}

{ the Connect button and Auto Connect; the configuration that connected is the one worth keeping }
function TCalibrationFrame.ConnectMeters: Boolean;
var
  Why: String;
begin
  Screen.Cursor := crHourGlass;
  try
    Result := Bench.Connect(GatewayEdit.Text, BenchSpecs, Why);
    { a partial connect still says which meter stayed silent }
    if Why <> '' then
    begin
      ErrLbl.Caption := 'Meters: ' + Why;
      TUtils.HandleEvent(etMessage, Format('Meters: %s'#13#10, [Why]));
    end
    else if Result then ErrLbl.Caption := '';
    if Result then SaveConfig;
  finally
    Screen.Cursor := crDefault;
    ShowBench;
  end;
end;

procedure TCalibrationFrame.MeterBtnClick(Sender: TObject);
begin
  MeterBtn.Enabled := False;
  if Bench.Connected then
  begin
    Screen.Cursor := crHourGlass;
    try
      Bench.Disconnect;
    finally
      Screen.Cursor := crDefault;
      ShowBench;
    end;
  end
  else ConnectMeters;
end;

{$REGION ' SAMPLING '}
{ Read starts a sample run by hand; during a run the same button ends it }
procedure TCalibrationFrame.ReadBtnClick(Sender: TObject);
begin
  if Bench.Sampling then Bench.StopSampling
  else BeginSampling(False);
end;

{
  a sample run, by hand (Read) or by Auto Read alike: the settling time (SettleEdit ms, the wait before the
  first sample; or, with Auto ticked, the wait for stable readings), then SampleEdit samples with IntervalEdit
  ms of wait between every two, each one a single trigger to every meter in use. Auto = the run started it
  (Auto Read): when the last sample is in, the current is stopped as well
}
function TCalibrationFrame.BeginSampling(const Auto: Boolean): Boolean;
begin
  Result := False;
  if Bench.Sampling or not Bench.Connected then Exit;

  Taken := nil;
  SampleSpecs := BenchSpecs;
  SampleShunt := ShuntRBG.ItemIndex;
  SampleSize := SampleEdit.Value;
  SampleAmps := RunAmps;
  SampleMode := RunMode;
  SampleLive := Running;
  AutoSampling := Auto;
  SaveConfig;

  {
    the meters' range, for a run under current: both on the lowest 8508A range that holds the larger of the two
    voltages to come (shunt = its nominal value x the current, standard = the plan's value x the current). One range for both polarities and no ranging in
    between. Without a current there is nothing to work it out from: autorange
  }
  SampleRange := 0;
  if Running and (SampleAmps > 0) and (SampleShunt >= 0) then
  begin
    var Volts := Plan.Rows[SampleShunt +1].Nominal * SampleAmps;
    if HaveSlots and Slots[SampleShunt +1].Found then Volts := Max(Volts, Slots[SampleShunt +1].Standard * SampleAmps);
    SampleRange := TShuntPlan.MeterRange(Volts);
  end;
  for var I := 0 to BENCH_METERS -1 do SampleSpecs[I].RangeV := SampleRange;

  { with a current running, the channel's own reading is taken with every trigger }
  var Probe: TBenchProbe := nil;
  if Running then
  begin
    var Chan := RunChan;
    var Mode := RunMode;
    var Range := RunRange;
    Probe := function(out Value: Double): Boolean
      begin
        Result := Tester.ReadCurrent(Chan, Mode, Range, Value);
      end;
  end;

  var Settle := Default(TBenchSettle);
  Settle.Enabled := AutoSettleBox.Checked;
  Settle.WaitMs := SettleEdit.Value;
  Settle.Window := SETTLE_WINDOW;
  Settle.LimitPpm := SETTLE_LIMIT_PPM;
  Settle.TimeoutMs := SETTLE_TIMEOUT_MS;

  Result := Bench.StartSampling(SampleSpecs, SampleEdit.Value, IntervalEdit.Value, Settle, Probe,
    procedure(const Stable: Boolean; const Readings: Integer; const Seconds: Double)
    begin
      Settled(Stable, Readings, Seconds);
    end,
    procedure(const Sample: TBenchSample)
    begin
      OnSample(Sample);
    end,
    procedure(const Count: Integer; const Completed: Boolean)
    begin
      SamplingDone(Count, Completed);
    end);

  if Result then
  begin
    Tap('RUN shunt=%d amps=%g mode=%d live=%d auto=%d samples=%d settle=%s interval=%dms fast=%d res6=%d ' +
      'range=%gV pair=%d m1(use=%d addr=%d std=%d) m2(use=%d addr=%d std=%d)',
      [SampleShunt +1, SampleAmps, Ord(SampleMode), Ord(SampleLive), Ord(Auto), SampleSize,
       IfThen(Settle.Enabled, 'auto', IntToStr(Settle.WaitMs) + 'ms'), IntervalEdit.Value,
       Ord(FastBox.Checked), Ord(Res6Box.Checked), SampleRange, BenchPair(Self) +1,
       Ord(SampleSpecs[0].Use), SampleSpecs[0].GpibAddr, Ord(RoleMeter(0) = 0),
       Ord(SampleSpecs[1].Use), SampleSpecs[1].GpibAddr, Ord(RoleMeter(0) = 1)]);
    ShowStats;
    TUtils.HandleEvent(etMessage, Format('Meters: sampling on %s, %s, then %d samples with %d ms between them%s'#13#10,
      [IfThen(SampleRange > 0, Format('the %g V range', [SampleRange]), 'autorange'),
       IfThen(Settle.Enabled, 'waiting for stable readings', Format('settling %d ms', [Settle.WaitMs])),
       SampleEdit.Value, IntervalEdit.Value, IfThen(Auto, ' (Auto Read)', '')]));
  end
  else AutoSampling := False;
  ShowBench;
end;

function TCalibrationFrame.ValueText(const Index: Integer; const Sample: TBenchSample): String;
begin
  if not SampleSpecs[Index].Use then Exit('');
  if not Sample.Ok[Index] then Exit('no reading');
  Result := Format('%.9g V', [Sample.Value[Index]]);
end;

procedure TCalibrationFrame.OnSample(const Sample: TBenchSample);
begin
  Taken := Taken + [Sample];
  { debug tap: the log shows a run's start and end, the tap every sample of it }
  Tap('SAMPLE %d/%d t=%.3fs took=%.0fms m1=%s m2=%s chan=%s',
    [Sample.Index, SampleSize, Sample.Time, Sample.Took,
     IfThen(Sample.Ok[0], FloatToStrF(Sample.Value[0], ffGeneral, 10, 0, TFormatSettings.Invariant), '-'),
     IfThen(Sample.Ok[1], FloatToStrF(Sample.Value[1], ffGeneral, 10, 0, TFormatSettings.Invariant), '-'),
     IfThen(Sample.ProbeOk, FloatToStrF(Sample.Probe, ffGeneral, 8, 0, TFormatSettings.Invariant), '-')]);
  ShowStats;
end;

procedure TCalibrationFrame.SamplingDone(const Count: Integer; const Completed: Boolean);
begin
  var WasAuto := AutoSampling;
  AutoSampling := False;
  ShowStats;
  ShowBench;
  TUtils.HandleEvent(etMessage, Format('Meters: %d of %d samples taken%s'#13#10,
    [Count, SampleEdit.Value, IfThen(Completed, '', ' (stopped)')]));

  { a full run under current is that polarity's result }
  if Completed and SampleLive then
  begin
    StorePolarity;
    ShowStats;
  end;

  { Auto Read: the samples were the purpose of the run. Stop all; a charge run of a sequence is followed by its discharge }
  if WasAuto and Completed and Running then
  begin
    TUtils.HandleEvent(etMessage, 'Calibration: samples complete, stopping the current'#13#10);
    StopIt;
    case SeqStep of
      1:
      begin
        SeqStep := 2;
        NextTimer.Enabled := True;
        ShowRunning;
        TUtils.HandleEvent(etMessage, 'Calibration: charge run done, the discharge run follows'#13#10);
      end;
      2:
      begin
        SeqStep := 0;
        ShowRunning;
        TUtils.HandleEvent(etMessage, 'Calibration: charge and discharge done :: Accept writes the data file, the certificate and the record'#13#10);
      end;
    end;
  end
  else if (SeqStep > 0) and not Completed then
  begin
    { a sequence whose sampling was cut short is over }
    SeqStep := 0;
    NextTimer.Enabled := False;
    ShowRunning;
  end;
end;

{ at the start of a run: with Auto Read ticked, the first sample is taken once the current has settled }
procedure TCalibrationFrame.ArmAutoRead;
begin
  SettleTimer.Enabled := False;
  if not AutoReadBox.Checked then Exit;

  if not Bench.Connected then
  begin
    ErrLbl.Caption := 'Auto Read: the meters are not connected';
    Exit;
  end;
  { the sample run begins with the current and does its own settling first (BeginSampling) }
  SettleTimer.Interval := 1;
  SettleTimer.Enabled := True;
end;

procedure TCalibrationFrame.Settled(const Stable: Boolean; const Readings: Integer; const Seconds: Double);
begin
  if Stable then
    TUtils.HandleEvent(etMessage, Format('Meters: stable after %d readings (%.1f s): sampling'#13#10, [Readings, Seconds]))
  else
  begin
    ErrLbl.Caption := Format('Readings not stable within %d s: sampled anyway', [SETTLE_TIMEOUT_MS div 1000]);
    TUtils.HandleEvent(etMessage, Format('Meters: NOT stable after %d readings (%.1f s; %d readings within %d ppm wanted): sampling anyway'#13#10,
      [Readings, Seconds, SETTLE_WINDOW, SETTLE_LIMIT_PPM]));
  end;
end;

{ the fixed settling time is only in play while Auto Settle is off }
procedure TCalibrationFrame.AutoSettleClick(Sender: TObject);
begin
  ShowBench;
  ConfigChange(Sender);
end;

procedure TCalibrationFrame.SettleTimerTimer(Sender: TObject);
begin
  SettleTimer.Enabled := False;
  if not Running then Exit;
  if not BeginSampling(True) then ErrLbl.Caption := 'Auto Read: the meters could not be sampled';
end;
{$ENDREGION}

{$REGION ' STATISTICS '}
{
  from the samples of the run in hand (or the last one). Per meter: how good the number is (noise, standard
  error) and whether it is still moving (drift: a shunt warming under current shows here). Then what the run
  is for: with one meter on the shunt's voltage and one on the current, the shunt's resistance from each
  simultaneous pair, against its nominal value; with one meter, the same against the current commanded
}
procedure TCalibrationFrame.ShowStats;
var
  T, X: array [0..BENCH_METERS -1] of TArray<Double>;
  St: array [0..BENCH_METERS -1] of TBenchStats;
  Side: Integer;                             { 0 = the per-meter block (columns 0..2), 1 = the shunt block (3..5) }
  Next: array [0..1] of Integer;             { the next free row of each block }

  procedure Row(const Name: String; const A: String = ''; const B: String = '');
  begin
    var R := Next[Side];
    Inc(Next[Side]);
    if R >= StatGrid.RowCount then StatGrid.RowCount := R +1;
    StatGrid.Cells[Side * 3, R] := Name;
    StatGrid.Cells[Side * 3 +1, R] := A;
    StatGrid.Cells[Side * 3 +2, R] := B;
  end;

  function UnitOf(const I: Integer): String;
  begin
    if SampleSpecs[I].Mode = mmCurrentDC then Result := 'A' else Result := 'V';
  end;

  function Num(const V: Double; const U: String): String;
  begin
    Result := Format('%.8g %s', [V, U]);
  end;

  { Part as parts per million of Whole }
  function Ppm(const Part, Whole: Double; const Signed: Boolean = False; const Per: String = ''): String;
  begin
    if Whole = 0 then Exit('-');
    if Signed then Result := Format('%+.1f ppm%s', [Part / Abs(Whole) * 1E6, Per])
    else Result := Format('%.1f ppm%s', [Abs(Part / Whole) * 1E6, Per]);
  end;

  { one per-meter figure; '' for a meter not in use, '-' for one without readings }
  function Cell(const I, What: Integer): String;
  begin
    if not SampleSpecs[I].Use then Exit('');
    { count of size: the readings in so far, of the samples the run was asked for }
    if What = 0 then Exit(Format('%d of %d', [St[I].N, Max(SampleSize, Length(Taken))]));
    if St[I].N = 0 then Exit('-');
    case What of
      1: Result := Num(St[I].Mean, UnitOf(I));
      2: Result := Num(St[I].Dev, UnitOf(I));
      3: Result := Ppm(St[I].Dev, St[I].Mean);
      4: Result := Num(St[I].Max - St[I].Min, UnitOf(I));
      5: Result := Ppm(St[I].Sem, St[I].Mean);
      6: Result := Ppm(St[I].Slope, St[I].Mean, True, '/s');
    else
      Result := '';
    end;
  end;

begin
  for var I := 0 to BENCH_METERS -1 do
  begin
    for var S in Taken do
      if S.Ok[I] then
      begin
        T[I] := T[I] + [S.Time];
        X[I] := X[I] + [S.Value[I]];
      end;
    St[I] := TMeterBench.Stats(T[I], X[I]);
  end;

  for var GC := 0 to StatGrid.ColCount -1 do
    for var GR := 1 to StatGrid.RowCount -1 do
      StatGrid.Cells[GC, GR] := '';
  Side := 0;
  Next[0] := 1;
  Next[1] := 1;

  try
    if Length(Taken) = 0 then
    begin
      Row('Samples', 'none yet');
      Exit;
    end;

    Row('Samples',   Cell(0, 0), Cell(1, 0));
    { the newest reading of each meter, as it came }
    Row('Last',      ValueText(0, Taken[High(Taken)]), ValueText(1, Taken[High(Taken)]));
    Row('Mean',      Cell(0, 1), Cell(1, 1));
    Row('Std dev',   Cell(0, 2), Cell(1, 2));
    Row('Noise',     Cell(0, 3), Cell(1, 3));
    Row('Pk-Pk',     Cell(0, 4), Cell(1, 4));
    Row('Std error', Cell(0, 5), Cell(1, 5));
    Row('Drift',     Cell(0, 6), Cell(1, 6));

    {
      the right-hand block from here on: the workbook's ratio method. Each polarity's run leaves the mean and
      deviation of both meters; with both polarities in, the shunt follows from the standard
    }
    Side := 1;
    var StdM := RoleMeter(0);
    var DutM := RoleMeter(1);
    var Slot := Default(TRunSlot);
    if HaveSlots and (SampleShunt >= 0) then Slot := Slots[SampleShunt +1];
    var Nominal := 0.0;
    if SampleShunt >= 0 then Nominal := Plan.Rows[SampleShunt +1].Nominal;

    for var P := Low(TMaccorControlMode) to High(TMaccorControlMode) do
      if Pol[P].Valid then
      begin
        var Name := IfThen(P = cmCharge, 'charge', 'disch.');
        if StdM >= 0 then Row('VSTD ' + Name, Num(Pol[P].Mean[StdM], 'V'), Format('dev %.1f ppm', [Pol[P].DevPpm[StdM]]));
        if DutM >= 0 then Row('VDUT ' + Name, Num(Pol[P].Mean[DutM], 'V'), Format('dev %.1f ppm', [Pol[P].DevPpm[DutM]]));
      end;

    var Res: TRatioResult;
    if RatioResult(Res) then
    begin
      Row('VSTD average', Num(Res.StdAvg, 'V'), '(chg - dis) / 2');
      Row('VDUT average', Num(Res.DutAvg, 'V'), '(chg - dis) / 2');
      Row('Ratio DUT/STD', Format('%.9g', [Res.Ratio]), Format('repeat. %.2f ppm', [Res.RepeatPpm]));
      if Res.Standard > 0 then
      begin
        Row('R standard', Num(Res.Standard, OHMS),
          IfThen(Res.StandardUnc > 0, Format('U %.3g ppm, k=2', [Res.StandardUnc]), 'no uncertainty'));
        Row('RDUT', Num(Res.RDut, OHMS), IfThen(Nominal > 0, Ppm(Res.RDut - Nominal, Nominal, True) + ' vs nom.', ''));
        if Res.UncPpm > 0 then Row('Uncertainty', Format('%.2f ppm', [Res.UncPpm]), 'k=2, meter budget')
        else Row('Uncertainty', '-', Res.UncWhy);
      end
      else Row('RDUT', '-', 'no standard value');
    end
    else if (StdM >= 0) and (DutM >= 0) and (St[StdM].N > 0) and (St[DutM].N > 0) and (St[StdM].Mean <> 0) then
      Row('Ratio (this run)', Format('%.9g', [St[DutM].Mean / St[StdM].Mean]), 'one polarity');

    {
      the tester channel's own current, taken with each trigger: how steady the source is, and how far the
      channel reads from the true current, which is the standard's voltage over the standard's resistance
    }
    var TC, XC, TE, XE: TArray<Double>;
    var RefMean := 0.0;
    for var S in Taken do
    begin
      if not S.ProbeOk then Continue;
      TC := TC + [S.Time];
      XC := XC + [Abs(S.Probe)];

      if (StdM >= 0) and S.Ok[StdM] and (Slot.Standard > 0) then
      begin
        var Ref := Abs(S.Value[StdM]) / Slot.Standard;
        TE := TE + [S.Time];
        XE := XE + [Abs(S.Probe) - Ref];
        RefMean := RefMean + Ref;
      end;
    end;

    var SC := TMeterBench.Stats(TC, XC);
    if SC.N > 0 then
    begin
      Row('Channel I', Num(SC.Mean, 'A'), Format('%d of %d', [SC.N, Max(SampleSize, Length(Taken))]));
      Row('Channel noise', Ppm(SC.Dev, SC.Mean), Ppm(SC.Slope, SC.Mean, True, '/s'));
      var SE := TMeterBench.Stats(TE, XE);
      if SE.N > 0 then
        Row('Channel error', Ppm(SE.Mean, RefMean / SE.N, True), 'vs VSTD / R std');
      if SampleAmps > 0 then Row('Chan. vs cmd', Ppm(SC.Mean - SampleAmps, SampleAmps, True), Num(SampleAmps, 'A'));
    end;

    { how the sampling itself went }
    var Took := 0.0;
    for var S in Taken do Took := Took + S.Took;
    Row('Sample took', Format('%.1f ms', [Took / Length(Taken)]), 'trigger to data');
    if Length(Taken) > 1 then
      Row('Pace', Format('%.1f ms', [(Taken[High(Taken)].Time - Taken[0].Time) * 1000 / (Length(Taken) -1)]),
        Format('took + %d ms interval', [IntervalEdit.Value]));
    if SampleSpecs[0].Use and SampleSpecs[1].Use then Row('Trigger', 'one for both', 'simultaneous');
  finally
    StatGrid.Invalidate;
  end;
end;
{$ENDREGION}
{$ENDREGION}

{$REGION ' RATIO METHOD, WORKBOOK, ACCEPT '}
{ the meter (0 or 1) that is in use in the given role: 0 = on the standard, 1 = on the shunt; -1 = none }
function TCalibrationFrame.RoleMeter(const Role: Integer): Integer;
begin
  Result := -1;
  if Use1Box.Checked and (Role1Combo.ItemIndex = Role) then Exit(0);
  if Use2Box.Checked and (Role2Combo.ItemIndex = Role) then Exit(1);
end;

{ a completed sample run under current becomes that polarity's entry: per meter the mean and the deviation in ppm }
procedure TCalibrationFrame.StorePolarity;
var
  T, X: TArray<Double>;
begin
  var Run := Default(TPolarityRun);
  Run.Valid := True;
  Run.Shunt := SampleShunt;
  Run.Samples := Length(Taken);

  for var I := 0 to BENCH_METERS -1 do
  begin
    T := nil;
    X := nil;
    for var S in Taken do
      if S.Ok[I] then
      begin
        T := T + [S.Time];
        X := X + [S.Value[I]];
      end;
    var St := TMeterBench.Stats(T, X);
    Run.Mean[I] := St.Mean;
    if St.Mean <> 0 then Run.DevPpm[I] := Abs(St.Dev / St.Mean) * 1E6;
  end;

  Pol[SampleMode] := Run;
  Tap('POLARITY mode=%d shunt=%d samples=%d m1 mean=%.10g dev=%.2fppm m2 mean=%.10g dev=%.2fppm',
    [Ord(SampleMode), Run.Shunt +1, Run.Samples, Run.Mean[0], Run.DevPpm[0], Run.Mean[1], Run.DevPpm[1]]);
  { the other polarity counts only when it was taken on the same shunt }
  for var P := Low(TMaccorControlMode) to High(TMaccorControlMode) do
    if (P <> SampleMode) and (Pol[P].Shunt <> Run.Shunt) then Pol[P].Valid := False;

  var Res: TRatioResult;
  if RatioResult(Res) then
    Tap('RATIO shunt=%d stdAvg=%.10g dutAvg=%.10g ratio=%.10g standard=%.10g rdut=%.10g repeat=%.2fppm',
      [Res.Shunt +1, Res.StdAvg, Res.DutAvg, Res.Ratio, Res.Standard, Res.RDut, Res.RepeatPpm]);
end;

const
  {
    the meter specification the workbook's "8508A" sheet budgets with, per DC voltage range: ppm of reading plus
    ppm of range, and the resolution it takes (8 digits). The sheet has the 0.2 V and 2 V ranges only; a
    measurement on another range gets no uncertainty here
  }
  BUDGET_RANGE: array [0..1] of Double = (0.2, 2);
  BUDGET_PPM_READING: array [0..1] of Double = (4.5, 3);
  BUDGET_PPM_RANGE: array [0..1] of Double = (0.6, 0.3);
  BUDGET_RESOLUTION = 1E-8;                   { volts }

{
  the workbook's arithmetic: Average = (Charge - Discharge) / 2 per meter, ratio = Average DUT / Average STD,
  RDUT = R standard * ratio. Repeatability as the workbook has it in column L (the mean of the two polarities'
  deviation in volts, over the root of the sample count), taken relative for each meter and combined.
  False until both polarities of the same shunt are in and one meter stands in each role
}
function TCalibrationFrame.RatioResult(out Res: TRatioResult): Boolean;

  function Repeatability(const C, D: TPolarityRun; const M: Integer; const Average: Double): Double;
  begin
    Result := 0;
    if (Average = 0) or (C.Samples < 1) then Exit;
    var Volts := (Abs(C.Mean[M]) * C.DevPpm[M] / 1E6 + Abs(D.Mean[M]) * D.DevPpm[M] / 1E6) / 2 / Sqrt(C.Samples);
    Result := Abs(Volts / Average) * 1E6;
  end;

begin
  Res := Default(TRatioResult);
  var C := Pol[cmCharge];
  var D := Pol[cmDischarge];
  var S := RoleMeter(0);
  var U := RoleMeter(1);
  Result := C.Valid and D.Valid and (C.Shunt = D.Shunt) and (C.Shunt >= 0) and (S >= 0) and (U >= 0);
  if not Result then Exit;

  Res.Shunt := C.Shunt;
  Res.StdAvg := (C.Mean[S] - D.Mean[S]) / 2;
  Res.DutAvg := (C.Mean[U] - D.Mean[U]) / 2;
  Result := Res.StdAvg <> 0;
  if not Result then Exit;

  Res.Ratio := Res.DutAvg / Res.StdAvg;
  var StdRepeat := Repeatability(C, D, S, Res.StdAvg);
  var DutRepeat := Repeatability(C, D, U, Res.DutAvg);
  Res.RepeatPpm := Sqrt(Sqr(StdRepeat) + Sqr(DutRepeat));

  if HaveSlots and Slots[Res.Shunt +1].Found then
  begin
    Res.Standard := Slots[Res.Shunt +1].Standard;
    Res.StandardUnc := Slots[Res.Shunt +1].StandardUnc;
  end;
  if Res.Standard > 0 then Res.RDut := Abs(Res.Standard * Res.Ratio);

  {
    the uncertainty, by the budget of the workbook's meter sheet ("8508A"), all at k = 2:
      each voltage    2 * root-sum-square of  (meter spec) / 2,  resolution / root 12,  repeatability
      the shunt       root-sum-square of the two voltages' and the standard's
    This is the figure the tab shows and hands to the Calibration Record. The certificate's own is worked out
    by MeterSheetU from the meter type's sheet of Configurations, cell for cell as the workbook's sheet did
  }
  var Range := TShuntPlan.MeterRange(Max(Abs(Res.StdAvg), Abs(Res.DutAvg)));
  var Spec := -1;
  for var I := Low(BUDGET_RANGE) to High(BUDGET_RANGE) do
    if SameValue(Range, BUDGET_RANGE[I], 1E-9) then Spec := I;

  if Res.RDut <= 0 then Res.UncWhy := 'no standard value'
  else if Res.StandardUnc <= 0 then Res.UncWhy := 'the standard''s uncertainty is not given'
  else if Spec < 0 then Res.UncWhy := Format('no meter specification here for %.4g V', [Max(Abs(Res.StdAvg), Abs(Res.DutAvg))])
  else
  begin
    var Volt := function(const Average, RepeatPpm: Double): Double
      begin
        var V := Abs(Average);
        var SpecPpm := BUDGET_PPM_READING[Spec] + BUDGET_PPM_RANGE[Spec] * Range / V;
        var ResPpm := BUDGET_RESOLUTION / Sqrt(12) / V * 1E6;
        Result := 2 * Sqrt(Sqr(SpecPpm / 2) + Sqr(ResPpm) + Sqr(RepeatPpm));
      end;
    Res.UncPpm := Sqrt(Sqr(Volt(Res.StdAvg, StdRepeat)) + Sqr(Volt(Res.DutAvg, DutRepeat)) + Sqr(Res.StandardUnc));
  end;
end;

{ a shunt's nominal value as the shunt list titles it: 10K, 24.9K, 0.05 }
function OhmsLabel(const Ohms: Double): String;
begin
  if Ohms >= 1000 then Result := FloatToStrF(Ohms / 1000, ffGeneral, 6, 0, TFormatSettings.Invariant) + 'K'
  else Result := FloatToStrF(Ohms, ffGeneral, 6, 0, TFormatSettings.Invariant);
end;

{ the plan into what the runs go by: per shunt the standard, its uncertainty and the current; and the list's titles }
procedure TCalibrationFrame.ApplyPlan;
begin
  Slots := Default(TRunSlots);
  var Planned := 0;
  for var I := PLAN_FIRST to PLAN_LAST do
  begin
    var R := Plan.Rows[I];
    Slots[I].Found := R.Planned;
    Slots[I].Standard := R.Standard;
    Slots[I].StandardUnc := R.StandardUnc;
    Slots[I].Command := R.Current;
    if R.Planned then Inc(Planned);

    var Title := Format('%d (%s %s)', [I, OhmsLabel(R.Nominal), OHMS]);
    if (I - PLAN_FIRST < ShuntRBG.Items.Count) and (ShuntRBG.Items[I - PLAN_FIRST] <> Title) then
    begin
      var Kept := ShuntRBG.ItemIndex;
      ShuntRBG.Items[I - PLAN_FIRST] := Title;
      ShuntRBG.ItemIndex := Kept;
    end;
  end;
  HaveSlots := True;
  Tap('PLAN %d of %d shunts planned :: %s', [Planned, PLAN_LAST - PLAN_FIRST + 1, TShuntPlan.FileName]);
  ShowStats;
end;

{ Configure Shunts: the plan's form. Not while a current runs or samples are being taken: a run goes by the plan }
procedure TCalibrationFrame.ShuntCfgBtnClick(Sender: TObject);
begin
  if Busy or Bench.Sampling then
  begin
    ErrLbl.Caption := 'The shunt plan is not changed while a run is going';
    Exit;
  end;
  if not TShuntCfgForm.Edit(Self, Plan) then Exit;

  ApplyPlan;
  TUtils.HandleEvent(etMessage, Format('Shunt plan: saved :: %s'#13#10, [TShuntPlan.FileName]));
end;

{ picking a shunt: the plan's current for it goes into an empty Current box }
procedure TCalibrationFrame.ShuntClick(Sender: TObject);
begin
  var N := ShuntRBG.ItemIndex +1;
  if HaveSlots and (N >= 1) and Slots[N].Found and (Slots[N].Command > 0) and (Trim(CurrEdit.Text) = '') then
  begin
    CurrEdit.Text := FloatToStr(Slots[N].Command);
    TUtils.HandleEvent(etMessage, Format('Shunt plan: shunt %d current %s A, standard %s %s'#13#10,
      [N, CurrEdit.Text, FloatToStr(Slots[N].Standard), OHMS]));
  end;
end;

{
  the charge and discharge runs of one shunt go to the data file (CalDataU: its "n Ref" and "n UUT" rows),
  the certificate is brought up to date with them (CertificateU), and the shunt's value goes to the Calibration
  Record tab, ready for its Write
}
procedure TCalibrationFrame.AcceptBtnClick(Sender: TObject);
var
  Res: TRatioResult;
  Std, Dut: TDataRow;                       { the Ref and the UUT row of the data file's entry (CalDataU) }
  Why: String;
begin
  ErrLbl.Caption := '';
  if not RatioResult(Res) then
  begin
    ErrLbl.Caption := 'Accept needs a finished charge run and a finished discharge run of the same shunt';
    Exit;
  end;

  var S := RoleMeter(0);
  var U := RoleMeter(1);
  var C := Pol[cmCharge];
  var D := Pol[cmDischarge];

  {
    the readings go to the data file signed, as the meters gave them: its Average is (Charge - Discharge) / 2, so
    the discharge reading must be the negative one, by the current having turned, not by a sign put on here.
    Two polarities of the same sign are no measurement (floating inputs, a current that never reversed)
  }
  if (C.Mean[S] * D.Mean[S] >= 0) or (C.Mean[U] * D.Mean[U] >= 0) then
  begin
    ErrLbl.Caption := 'Not accepted: charge and discharge readings have the same sign (the current did not reverse)';
    TUtils.HandleEvent(etMessage, Format('Calibration: not accepted, the polarities do not mirror each other :: ' +
      'standard %.6g / %.6g V, shunt %.6g / %.6g V'#13#10, [C.Mean[S], D.Mean[S], C.Mean[U], D.Mean[U]]));
    Exit;
  end;

  Std.Charge := C.Mean[S];  Std.ChargeDev := C.DevPpm[S];  Std.Discharge := D.Mean[S];  Std.DischargeDev := D.DevPpm[S];
  Dut.Charge := C.Mean[U];  Dut.ChargeDev := C.DevPpm[U];  Dut.Discharge := D.Mean[U];  Dut.DischargeDev := D.DevPpm[U];

  { the value the record held before this calibration: for the tap; the value and its uncertainty go to the record below }
  var Previous: Double := 0;
  if Assigned(OnShuntPrevious) then Previous := OnShuntPrevious(Res.Shunt);
  Tap('ACCEPT shunt=%d rdut=%.10g unc=%.3fppm (%s) previous=%.10g',
    [Res.Shunt +1, Res.RDut, Res.UncPpm, Res.UncWhy, Previous]);
  if (Res.RDut > 0) and (Res.UncPpm <= 0) then
    TUtils.HandleEvent(etMessage, Format('Calibration: no uncertainty for shunt %d (%s)'#13#10, [Res.Shunt +1, Res.UncWhy]));

  {
    the shunt's entry of the data file (CalDataU): the typed cells of the workbook's Data sheet, C and D from the
    shunt plan; the sheet's formulas are worked out there
  }
  var Entry := Default(TDataShunt);
  Entry.Shunt := Res.Shunt +1;
  Entry.Accepted := Now;
  Entry.Samples := C.Samples;
  Entry.Nominal := Plan.Rows[Res.Shunt +1].Nominal;
  Entry.Standard := Res.Standard;
  Entry.Current := Plan.Rows[Res.Shunt +1].Current;
  Entry.Ref.Charge := Std.Charge;  Entry.Ref.ChargeDev := Std.ChargeDev;
  Entry.Ref.Discharge := Std.Discharge;  Entry.Ref.DischargeDev := Std.DischargeDev;
  Entry.Uut.Charge := Dut.Charge;  Entry.Uut.ChargeDev := Dut.ChargeDev;
  Entry.Uut.Discharge := Dut.Discharge;  Entry.Uut.DischargeDev := Dut.DischargeDev;
  if TCalData.Put(Entry, Why) then
  begin
    TUtils.HandleEvent(etMessage, Format('Data: shunt %d written to %s'#13#10, [Res.Shunt +1, ExtractFileName(TAppData.FileName)]));

    {
      and the certificate with it (CertificateU): the data file's meter and certificate members are worked out
      again, this shunt with the value the record held before, the meter type the bench runs with and the
      digits of resolution it is set to (the 6 1/2 digit box overrides the type's own)
    }
    var Kind := fm8508A;
    if BenchSpecs[0].Kind = bkFluke8588A then Kind := fm8588A;
    var Digits := TFlukeMeters.SavedDigits(Kind);
    if Res6Box.Checked then Digits := 6;
    var Cert: TCertificate;
    if TCertificateData.Refresh(Cert, Why, Res.Shunt +1, Previous, FLUKE_MODEL_NAME[Kind], Digits) then
    begin
      TUtils.HandleEvent(etMessage, Format('Certificate: %s brought up to date in %s'#13#10,
        [Cert.Number, ExtractFileName(TAppData.FileName)]));
      for var Gap in Cert.Gaps do TUtils.HandleEvent(etMessage, Format('Certificate: no value :: %s'#13#10, [Gap]));
      if Length(Cert.Gaps) > 0 then ErrLbl.Caption := 'Certificate: ' + Cert.Gaps[0];
    end
    else
    begin
      ErrLbl.Caption := 'Certificate: ' + Why;
      TUtils.HandleEvent(etMessage, Format('Certificate: not written: %s'#13#10, [Why]));
    end;
  end
  else
  begin
    ErrLbl.Caption := 'Data file: ' + Why;
    TUtils.HandleEvent(etMessage, Format('Data: not written: %s'#13#10, [Why]));
  end;

  if Res.RDut > 0 then
  begin
    TUtils.HandleEvent(etMessage, Format('Calibration: shunt %d = %s %s (standard %s %s, ratio %s)'#13#10,
      [Res.Shunt +1, FloatToStr(Res.RDut), OHMS, FloatToStr(Res.Standard), OHMS, FloatToStr(Res.Ratio)]));
    if Assigned(OnShuntAccepted) then OnShuntAccepted(Res.Shunt, Res.RDut, Res.UncPpm);
  end
  else
    TUtils.HandleEvent(etMessage, Format('Calibration: the shunt plan gives no standard for shunt %d: ' +
      'the Calibration Record was not updated'#13#10, [Res.Shunt +1]));
  ShowStats;
end;

{ the selected channel is alive while its data keeps coming (the engine hands it over about twice a second) }
function TCalibrationFrame.ChannelAlive: Boolean;
begin
  Result := (GetTickCount64 - LastDataTick) < CHANNEL_SILENT_MS;
end;

{
  no waiting, no hunting for another board: the Data box just says when the selected channel has gone quiet, and
  its readings go back to dashes so nothing stale is read off it
}
procedure TCalibrationFrame.LiveTimerTimer(Sender: TObject);
begin
  var Text := ' Data ';
  if Assigned(Tester) and Tester.Online and not Tester.Preparing and not ChannelAlive then
  begin
    Text := Format(' Data  ::  channel %d: no data ', [ChanEdit.Value]);
    if not Running then ResetDisplay;
  end;
  if DataGB.Caption <> Text then DataGB.Caption := Text;
end;

{ Run Charge and Discharge: the discharge run follows the charge run by itself }
procedure TCalibrationFrame.NextTimerTimer(Sender: TObject);
begin
  NextTimer.Enabled := False;
  if SeqStep <> 2 then Exit;

  ModeCombo.ItemIndex := Ord(cmDischarge);
  StartIt;
  if not Running then
  begin
    SeqStep := 0;
    ShowRunning;
  end;
end;
{$ENDREGION}

{ the statistics grid: header row and the two name columns (0 and 3) in the form's face, values in Consolas }
procedure TCalibrationFrame.StatGridDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
begin
  if (ACol < 0) or (ARow < 0) then Exit;

  with TStringGrid(Sender) do
  begin
    var CellStr := Trim(Cells[ACol, ARow]);
    var IsName := (ACol mod 3) = 0;
    var Flags: Cardinal := DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS;

    if (ARow = 0) or IsName then
    begin
      Canvas.Brush.Color := clBtnFace;
      Canvas.Font.Name := 'Segoe UI';
    end
    else
    begin
      Canvas.Brush.Color := clInactiveBorder;
      Canvas.Font.Name := 'Consolas';
    end;
    Canvas.Font.Color := clWindowText;

    { names read from the left, numbers and headers sit in the middle }
    if IsName and (ARow > 0) then Flags := Flags or DT_LEFT
    else Flags := Flags or DT_CENTER;

    Canvas.FillRect(Rect);
    InflateRect(Rect, -4, 0);
    DrawText(Canvas.Handle, PChar(CellStr), Length(CellStr), Rect, Flags);
  end;
end;

procedure TCalibrationFrame.GridDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
begin
  if (ACol < 0) or (ARow < 0) then Exit;

  with TStringGrid(Sender) do
  begin
    var CellStr := Trim(Cells[ACol, ARow]);
    if (ACol mod 2) <> 0 then
    begin
      Canvas.Brush.Color := clInactiveBorder;
      Canvas.Font.Name := 'Consolas';
    end
    else
    begin
      Canvas.Brush.Color := clBtnFace;
      Canvas.Font.Name := 'Segoe UI';
    end;

    Canvas.FillRect(Rect);
    DrawText(Canvas.Handle, PChar(CellStr), Length(CellStr), Rect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
  end;
end;

end.
