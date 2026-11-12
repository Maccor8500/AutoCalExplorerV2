unit DigitalMultiMeterU;

interface
uses
  Classes, SysUtils, Windows, CommonsU, Math, DateUtils, Threading, Diagnostics;

type
  { FL8508A, FL8588A :: GPIB meters behind a gateway <TGpibGateway>. appended, so the ordinals saved in
    settings and used as combo indexes do not move; deliberately absent from METER_TYPES / METER_TYPES_STR }
  TMeterType = (ManualMeter, AG34410A, KS34465A, KS34470A, FL8508A, FL8588A);
  TMeterMode = (mmVoltageDC, mmVoltageAC, mmCurrentDC, mmCurrentAC);
  TMeterReadMode = (rmManual, rmAutomatic);
  TMeterTrigger = (mtImmediate, mtExternal, mtBus, mtInternal);
  TMeterAutoHiZ = (miUnknown, miAutoOFF, miAutoON);
  TMeterStatMode= (smStatOFF, smStatON, smStatFuncAvgON, smStatFuncAvgOFF);
  TMeterNPLC = (nplcUNSET, nplcVOLT, nplcCURR, nplcTEMP);
  TCalcUncertUnits = (uuUnitUNSET, uuNanoVolt, uuMicroVolt, uuMilliVolt, uuVolt);

type
  TMeterTypes = Set of TMeterType;

const
  THERMAL_EMF_INSTRUCTIONS =
    'Thermal EMF measurement:'#13#10 +
    '  1. Short the meter leads together at the tester connection point (same leads as a verify).'#13#10 +
    '  2. Keep hands off the leads and wait 1 minute for the junctions to settle.'#13#10 +
    '  3. Then start the measurement (DCV 100 mV, NPLC 10; E = largest |reading|).';
  { a real loop EMF is microvolts; millivolts means the leads are not shorted }
  THERMAL_EMF_SHORT_LIMIT_VOLTS = 1E-3;
  { DCV input resistance with auto impedance OFF <all ranges>; tolerance lives with the budget }
  METER_INPUT_10M_OHMS = 10E6;

  KS_CMD_BEEP         = 'SYST:BEEP';
  KS_CMD_RST          = '*RST';
  KS_CMD_CLR          = '*CLS';
  KS_CMD_IDN          = '*IDN?';      { IEEE 488.2 :: asked only of the meters in IDN_METERS }
  KS_CMD_DISP         = 'DISP:TEXT';
  KS_CMD_DISP_GET     = 'DISP:TEXT?';
  KS_CMD_DISP_CLR     = 'DISP:TEXT:CLE';
  KS_CMD_ACAL         = '*CAL?';

  KS_CMD_VOLT_DC      = 'CONF:VOLT:DC DEF, DEF';
  KS_CMD_VOLT_AC      = 'CONF:VOLT:AC DEF, DEF';
  KS_CMD_CURR_DC      = 'CONF:CURR:DC DEF, DEF';
  KS_CMD_CURR_AC      = 'CONF:CURR:AC DEF, DEF';
  KS_CMD_NPLC         = 'VOLT:DC:NPLC';
  KS_CMD_HiZ_ON       = 'VOLT:IMP:AUTO ON';
  KS_CMD_HiZ_OFF      = 'VOLT:IMP:AUTO OFF';
  KS_CMD_HiZ_GET      = 'VOLT:IMP:AUTO?';

  AG_CMD_VOLT_DC      = 'CONF:SCAL:VOLT:DC DEF, DEF';
  AG_CMD_VOLT_AC      = 'CONF:SCAL:VOLT:AC DEF, DEF';
  AG_CMD_CURR_DC      = 'CONF:SCAL:CURR:DC DEF, DEF';
  AG_CMD_CURR_AC      = 'CONF:SCAL:CURR:AC DEF, DEF';

  KS_CMD_DATE_GET     = 'SYST:DATE?';
  KS_CMD_TIME_GET     = 'SYST:TIME?';
  KS_CMD_DATE_SET     = 'SYST:DATE';
  KS_CMD_TIME_SET     = 'SYST:TIME';

  KS_CMD_TEMP_GET     = 'SYST:ACAL:TEMP?';
  KS_CMD_ACAL_DATE    = 'SYST:ACAL:DATE?';
  KS_CMD_ACAL_TIME    = 'SYST:ACAL:TIME?';
  KS_CMD_CAL_GET      = 'CAL:DATE?';
  KS_CMD_READ         = 'READ?';
  KS_CMD_READN        = 'R?';
  KS_CMD_INIT         = 'INIT';
  KS_CMD_INIT_IMM     = 'INIT:IMM';
  KS_CMD_READ_SD      = 'CALC:AVER:AVER?;SDEV?';
  KS_CMD_READ_ALL     = ':CALCulate:AVERage:ALL?';
  KS_CMD_GET_CNT      = 'CALC:AVER:COUN?';
  KS_CMD_AVG_STAT_ON  = 'CALC:FUNC AVER; STAT ON';
  KS_CMD_AVG_STAT_OFF = 'CALC:FUNC AVER; STAT OFF';
  KS_CMD_STAT_GET     = 'CALCulate:STATe?';
  KS_CMD_STAT_ON      = 'CALC:STAT ON';
  KS_CMD_STAT_OFF     = 'CALC:STAT OFF';
  KS_CMD_CLR_IMM      = 'CALC:AVER:CLE:IMM';
  KS_CMD_LOCAL        = 'SYST:LOC';
  KS_CMD_REMOTE       = 'SYST:REM';
  KS_CMD_SOURCE       = 'ROUT:TERM?';
  KS_CMD_GET_NAME     = 'LXI:MDNS:SNAMe:RESolved?';
  KS_CMD_SET_NAME     = 'LXI:MDNS:SNAMe:DESired';
  KS_CMD_LAN_RST      = 'LXI:RESTart';

  AG_CMD_STAT_CLR     = 'CALCulate:AVERage:CLEar';
  AG_CMD_STAT_GET     = 'CALCulate:FUNCtion??';
  AG_CMD_STAT_SET     = 'CALCulate:FUNCtion AVERage';

  KS_CMD_TRIG_IMM     = 'TRIGger:SOURce IMMediate';
  KS_CMD_TRIG_EXT     = 'TRIGger:SOURce EXTernal';
  KS_CMD_TRIG_BUS     = 'TRIGger:SOURce BUS';
  KS_CMD_TRIG_INT     = 'TRIGger:SOURce INTernal';

  KS_CMD_SET_RCNT     = 'SAMPle:COUNt';
  KS_CMD_GET_RCNT     = 'SAMPle:COUNt?';

  KS_CMD_GET_NPLC_V   = 'VOLTage:DC:NPLCycles?';
  KS_CMD_SET_NPLC_V   = 'VOLTage:DC:NPLCycles';
  KS_CMD_GET_NPLC_I   = 'CURRent:DC:NPLCycles?';
  KS_CMD_SET_NPLC_I   = 'CURRent:DC:NPLCycles';

  KS_CMD_SET_RANG_V   = 'VOLTage:DC:RANGe';    { RANG <v> :: lowest span accommodating <v> }
  KS_CMD_GET_RANG_V   = 'VOLTage:DC:RANGe?';
  KS_CMD_GET_RANG_AUTO= 'VOLTage:DC:RANGe:AUTO?';
  KS_CMD_GET_AZ_V     = 'VOLTage:DC:ZERO:AUTO?';
  KS_CMD_SET_AZ_V     = 'VOLTage:DC:ZERO:AUTO';

  KS_CMD_ERROR       = 'SYSTem:ERRor:NEXT?';
  KS_CMD_SET_TIME    = 'SYSTem:TIME';      {:SYSTem:TIME 12,12,55}
  KS_CMD_SET_DATE    = 'SYSTem:DATE';      {:SYSTem:DATE 2024,4,26}

  AG_CMD_DISP_SET    = 'DISP:WIND:TEXT:DATA';
  AG_CMD_DISP_CLR    = 'DISPlay:WINDow1:TEXT:CLE';
  AG_CMD_DISP_GET    = 'DISPlay:WINDow1:TEXT:DATA?';

  AG_CMD_AVG_ON      = 'CALCulate:FUNCtion AVERage';
  AG_CMD_AVG_OFF     = 'CALCulate:FUNCtion NULL';

  AG_CMD_GET_VNPLC   = 'SENSe:VOLTage:DC:NPLCycles?';
  AG_CMD_SET_VNPLC   = 'SENSe:VOLTage:DC:NPLCycles';
  AG_CMD_GET_INPLC   = 'SENSe:CURRage:DC:NPLCycles?';
  AG_CMD_SET_INPLC   = 'SENSe:CURRage:DC:NPLCycles';
  AG_CMD_GET_TNPLC   = 'SENSe:TEMPerature:NPLCycles?';
  AG_CMD_SET_TNPLC   = 'SENSe:TEMPerature:NPLCycles';

  AG_CMD_HiZ_ON      = 'SENSe:VOLTage:DC:IMPedance:AUTO ON';
  AG_CMD_HiZ_OFF     = 'SENSe:VOLTage:DC:IMPedance:AUTO OFF';
  AG_CMD_HiZ_GET     = 'SENSe:VOLTage:DC:IMPedance:AUTO?';

  { Fluke 8508A command set <users manual, chapter 4>; the 8588A answers to it in its 8508A emulation.
    *RST, *CLS and *IDN? are the IEEE 488.2 ones above }
  FL_CMD_VOLT_DC      = 'DCV AUTO,FILT_OFF,RESL7,FAST_OFF,TWO_WR';
  FL_CMD_VOLT_AC      = 'ACV AUTO';
  FL_CMD_CURR_DC      = 'DCI AUTO,FILT_OFF,RESL7,FAST_OFF';
  FL_CMD_CURR_AC      = 'ACI AUTO';
  FL_CMD_RANG_V       = 'DCV';            { DCV <v> :: the range holding <v>, cancels autorange }
  FL_CMD_TRIG_EXT     = 'TRG_SRCE EXT';   { no free-running triggers :: a reading is taken when asked }
  FL_CMD_READ         = 'X?';             { = *TRG;RDG? }
  FL_CMD_RECALL       = 'RDG?';           { the reading of the last trigger <TGpibGateway.Trigger> }
  FL_READ_TIMEOUT_MS  = 30000;            { a high-resolution conversion takes seconds }

  CharSet1 = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'E', '-', '+', '.'];
  CharSet2 = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'E', '-', '.'];

  METER_TYPES: TMeterTypes = [ManualMeter, AG34410A, KS34465A, KS34470A];
  METER_TYPES_STR: Array [0..3] of String = ('None: MANUAL', 'Agilent - AG34410A', 'KeySight - KS34465A', 'KeySight - KS34470A');
  METER_READ_TERMINATIONS: Array [0..3] of ShortString = ('\r', '\n', '\r\n', '\n\r');
  DEFAULT_READ_PRECISION = 6;

  { Discrete NPLC values the meters accept. NPLC is fractional (not integer), so it is
    stored/handled as Single and the settings UI offers exactly these choices. }
  METER_NPLC_VALUES: Array [0..4] of Single = (0.02, 0.2, 1, 10, 100);

{ nearest allowed NPLC index for a value; and a bounds-safe value lookup by index }
function NPLCIndex(const Value: Single): Integer;
function NPLCValue(const Index: Integer): Single;

type
  PMeterResolutionFactor = ^TMeterResolutionFactor;
  TMeterResolutionFactor = record
    mv100, V1, V10, V100, V1K: Array [0..1] of
    Single;
  end;

type
  PRelativeUncertainties = ^TRelativeUncertainties;
  TRelativeUncertainties = record
    PercentRead, PercentRange: record
      Voltage: record
        mV100, V1, V10, V100,
        V1000: Double;
      end;

      Current: record
        uA1, uA10, uA100,
        mA1, mA10, mA100,
        A1, A3: Double;
      end;
    end;

    ResFactor: TMeterResolutionFactor;
  end;

type
  PCalculatedUncertainties = ^TCalculatedUncertainties;
  TCalculatedUncertainties = record
    mV100, V1, V10, V100,
    V1000: Double;

    Raw: record
      mV100, V1, V10, V100, V1000: record
        Value: Array [0..24] of AnsiChar; {25}
        Scale: TCalcUncertUnits; {05}
      end;
    end;
  end;

type
  PMeterRelativeUncertainties = ^TMeterRelativeUncertainties;
  TMeterRelativeUncertainties = record
    AG_34410A, KS_34465A, KS_34470A: TRelativeUncertainties;
  end;

type
  PMeterUncertainties = ^TMeterUncertainties;
  TMeterUncertainties = record
    Relative: TRelativeUncertainties;
    Calculated: TCalculatedUncertainties;
  end;

type
  PMeterCalculatedUncertainties = ^TMeterCalculatedUncertainties;
  TMeterCalculatedUncertainties = record
    AG_34410A, KS_34465A, KS_34470A: TCalculatedUncertainties;
  end;

type
  PMeterSettings = ^TMeterSettings;
  TMeterSettings = packed record
    Identity: TMeterType;
    Serial: ShortString;
    InitMsg: ShortString;
    Socket: packed record
      Kind: TSocketType;
      Addr: TIPAddress;
      Online: Boolean;
    end;

    Calibration: packed record
      LastCal: TDateTime;
      NextCal: TDateTime;
      Due: Boolean;
    end;

    NPLC: Byte;  { legacy integer NPLC -- retained for layout/back-compat; NPLCReal is authoritative }
    LocalOnExit: Boolean;
    ACALExpiryTime: Cardinal;
    ReadPrecision: Cardinal;
    ReadTermination: ShortString;
    HiImpedance: Boolean;
    Samples: Byte;
    ReadMode: TMeterReadMode;
    Uncertainties: TMeterUncertainties;
    {
      NPLC is a fractional quantity (e.g. 0.02, 0.2). Stored here as Single, carved from
      Spare so the record's byte layout and size are unchanged (old blobs read 0 here and
      are migrated from the legacy NPLC byte on load). See "consume from here" below.
    }
    NPLCReal: Single;
    ThermalEMFVolts: Single;
    ThermalEMFDate: TDateTime;
    AutoZeroOnce: Boolean;
    Rounding: Boolean;
    { consume from here :: subtract new usage from _1KB }
    Spare: Array [0..(_1KB
      {Uncertainties}-SizeOf(TRelativeUncertainties) -2
      {NPCReal}-SizeOf(Single)
      {ThermalEMFVolts} -SizeOf(Single)
      {ThermalEMFDate} -SizeOf(TDateTime)
      {AutoZeroOnce} -SizeOf(Boolean))
      {Rounding} -SizeOf(Byte)] of Byte;
  end;

{$IF SizeOf(TMeterSettings) <> 2064}
  {$MESSAGE 'TMeterSettings size has changed! Update Spare or adjust fields.'}
  {$MESSAGE FATAL 'TMeterSettings size has changed! Update Spare or adjust fields.'}
{$IFEND}

type
  PACALStatus = ^TACALStatus;
  TACALStatus = record
    Temp: Single;
    LastCal: TDateTime;
    Ready, Busy, Expired, OK: Boolean;
    Timeout: Integer;
    ExpiryTime: UInt64;
    TimeToExpiry: ShortString;
  end;

type
  PMeterReadConfig = ^TMeterReadConfig;
  TMeterReadConfig = record
    Mode: TMeterMode;
    Stat: TMeterStatMode;
    HiZ: TMeterAutoHiZ;
    NPLC: Single;      { fractional NPLC (0.02, 0.2, 1, 10, 100) }
    Samples: Integer;
    RangeV: Single;    { VDC span ceiling <volts, shunt VoltDrop> :: 0 = autorange }
    Rounding: Boolean;
  end;

{ operational NPLC: prefer the fractional NPLCReal, fall back to the legacy byte, else 1.
  Migration-safe -- returns a sensible value even if a stored blob predates NPLCReal. }
function EffectiveNPLC(const Settings: TMeterSettings): Single;

type
  TMeterUtils = class
    const
      DEFAULT_PORT = 5025;
      DEFAULT_ADDR = '192.168.127.215';
      GPIB_PORT = 1234;                 { Prologix GPIB-ETHERNET }
      GPIB_METERS = [FL8508A, FL8588A];
      ACALMETERS = [KS34465A, KS34470A];
      IDN_METERS = [KS34465A, KS34470A];

    class var
      UncertaintiesLoaded: Boolean;
      RelativeUncertainties: TMeterRelativeUncertainties;
      ACALStat: PACALStatus;
      DefaultRelativeUncertainties: TRelativeUncertainties;
      DefaultCalculatedUncertainties: TCalculatedUncertainties;
      CalculatedUncertainties: TMeterCalculatedUncertainties;

    private
      class procedure PackUncertainties(ForceRefresh: Boolean = False); static;
      class procedure UpdateStatus(const ACALStat: PACALStatus); static;

    public
      class procedure GetSupportedMeters(Meters: TStrings); static;
      class function GetMeterTypeStr(const Id: TMeterType): String;
      class function FormatTermination(const Index: Integer): ShortString; static;
      class function ModeToStr(const Mode: TMeterMode): String; static;
      class function ParseIdentity(const Idn: String; out Model, Serial: String): Boolean; static;
      class function GetReadTerminationIndex(const ReadTermination: ShortString): Byte; static;

      class procedure GetRelativeUncertainties(const Meter: TMeterType; var Uncertainties: TRelativeUncertainties; ForceRefresh: Boolean = False); static;
      class procedure GetDefaultCalcUncertainties(var Uncertainties: PCalculatedUncertainties); static;
      class procedure SeedCalculatedUncertainties(const Meter: TMeterType; var Uncertainties: TCalculatedUncertainties; const Replace: Boolean = False); static;
      //class procedure GetDefaultRelaUncertainties(var Uncertainties: PRelativeUncertainties); static;
  end;

{
  one Prologix GPIB-ETHERNET controller: one TCP connection, shared by every meter on its bus. A meter is
  addressed <++addr N> before each exchange; Write and Query hold one lock, so meters on the same gateway
  may be driven from different threads. Created by the caller and handed to each TMultiMeter, or created
  and owned by a single TMultiMeter <see its constructors>.
}
type
  PGpibGateway = ^TGpibGateway;
  TGpibGateway = class(TObject)
    private
      FAddr: String;
      FPort: Word;
      Client: TTCPClientEx;
      EventHandler: TAppEventCallback;
      Lock, RxLock: TRTLCriticalSection;
      RxEvent: THandle;                 { signaled while RxBuf holds a complete line }
      RxBuf: AnsiString;
      LastAddr: Integer;                { the address the controller was last told; -1 = none }

      procedure Alert(const Evt: TAppEventType; const Msg: String);
      procedure OnDataRecvd(const Payload: PSocketPayload);
      procedure DropClient;
      procedure ResetRx;
      function Send(const Line: AnsiString): Boolean;
      function Select(const GpibAddr: Byte): Boolean;
      function WaitLine(out Line: String; const TimeoutMs: Integer): Boolean;

    public
      constructor Create(const Addr: String; const Port: Word = TMeterUtils.GPIB_PORT; OnEvent: TAppEventCallback = nil);
      destructor Destroy; override;

      function Connect: Boolean;
      procedure Disconnect;
      function Connected: Boolean;
      { a command with no reply }
      function Write(const GpibAddr: Byte; const Cmd: AnsiString): Boolean;
      { a command and its one-line reply; TimeoutMs covers the instrument's conversion time }
      function Query(const GpibAddr: Byte; const Cmd: AnsiString; out Reply: String; const TimeoutMs: Integer = 3000): Boolean;
      { front panel back to the operator }
      procedure Local(const GpibAddr: Byte);
      { one Group Execute Trigger to every listed instrument at once :: they start converting together.
        each reading is then fetched with its own Query <FL_CMD_RECALL> }
      function Trigger(const GpibAddrs: array of Byte): Boolean;

      property Address: String read FAddr;
  end;

type
  PMultiMeter = ^TMultiMeter;
  TMultiMeter = class(TObject)
    private
      Config: TMeterSettings;
      Mode: TMeterMode;
      EventHandler: TAppEventCallback;
      Socket: TSocketHandle;
      DataRcvd: Boolean;
      Response: TBufferEx;
      AddrStr, Delimiter: String;
      Event: TAppEvent;
      LastRdCnt: Integer;

      ACALCtrl: record
        Cancel: Boolean;
        LastCall: UInt64;
        Time: Byte;
      end;

      ACALStatus: TACALStatus;
      //Uncertianties: TMeterUncertainties;

      Status: record
        Connected,
        Online,
        Terminate,
        Terminated,
        Working: Boolean;
        ReadBusyLastCall: UInt64;
        ReadTimeout: Integer;
      end;

      DebugShunt: Single;
      MaccorMode: TMaccorRunMode;
      ReadConfig: TMeterReadConfig;
      PingHandle: TThread;
      { armed by SendCommand, signaled by OnTcpDataRecvd :: exact wake, no poll tick }
      RxEvent: THandle;

      { GPIB meters <TMeterUtils.GPIB_METERS> only :: nil / 0 for every LAN meter }
      Bus: TGpibGateway;
      OwnBus: Boolean;                  { the gateway was created here and is freed here }
      GpibAddr: Byte;
      GpibSamples: Integer;             { readings per statistic <ConfigureRead> }

      function IsGpib: Boolean;
      function ConnectGpib: Boolean;
      function GpibWrite(const Cmd: AnsiString): Boolean;
      function ReadGpib(var FltData: Double; Timeout: Single): Boolean;
      function ReadGpibArray(var Data: TArray<Double>; Count: Integer; Timeout: Single): Boolean;
      function ReadGpibStats(Count: Integer; Timeout: Single; out Avg, Dev: Double; Lo: PDouble = nil; Hi: PDouble = nil): Boolean;

      procedure InitMeter;
      procedure MeterPing;
      procedure TerminatePing;
      procedure InitUDPSocket;
      procedure InitTCPSocket;
      procedure HandleExceptionEvent(const E: Exception);
      procedure AlertEvent(const Evt: TAppEventType; const Msg: String; UseLastLine: Boolean = False; Code: Integer = 0);
      procedure OnUdpDataRecvd(const Packet: PSocketPayload);
      procedure OnTcpDataRecvd(const Payload: PSocketPayload);
      procedure CheckACALStatus;
      procedure CheckIdentity;

      procedure ACALInProgress;
      procedure ReadInProgress;

      procedure SocketCleanup;
      procedure SendCommand(const Cmd: AnsiString);
      procedure ParseTemperature(const TempStr: String);
      function ParseMeterRead(const TempStr: String; var FltData: TArray<Double>; FmtResponse: Boolean = False): Boolean; overload;
      function ParseMeterRead(const TempStr: String; var FltData: Double): Boolean; overload;
      function ParseMeterRead(const TempStr: String; var FltData, StdDev: Double; MinMax: ITuple<Double, Double> = nil): Boolean; overload;
      procedure LogReadConfig;

    public
      constructor Create(var Config: PMeterSettings; OnEvent: TAppEventCallback = nil); overload;
      { a GPIB meter on its own :: creates and owns its gateway, whose address is Config.Socket.Addr <port 0 = TMeterUtils.GPIB_PORT> }
      constructor Create(var Config: PMeterSettings; const GpibAddr: Byte; OnEvent: TAppEventCallback = nil); overload;
      { a GPIB meter on a gateway the caller owns :: any number of meters may share one }
      constructor Create(var Config: PMeterSettings; const Bus: TGpibGateway; const GpibAddr: Byte; OnEvent: TAppEventCallback = nil); overload;
      destructor Destroy; override;

      function Connect: Boolean;
      function Connected: Boolean;
      function Disconnect: Boolean;
      function Online: Boolean;
      function SetMode(const Mode: TMeterMode): boolean;
      function GetMode: TMeterMode;

      function Read(var FltData: Double; Timeout: Single = 1.0): Boolean; overload;
      function Read(var FltData: String; Timeout: Single = 1.0): Boolean; overload;
      function Read(var FltData, StdDev: Double; Timeout: Single = 5.0): Boolean; overload;
      function Read(var FltData, StdDev, MinValue, MaxValue: Double; Timeout: Single = 5.0): Boolean; overload;
      function Read(var FltData: TArray<Double>; Cnt: SmallInt; Timeout: Single = 3.0): Boolean; overload;
      function Read(var FltData: TArray<Double>; var Avg, Dev: Single; Cnt: SmallInt; Timeout: Single = 5.0): Boolean; overload;

      function ReadEx(var FltData, StdDev: Double; const Count: Byte; Interval: Integer = 10{ms}): Boolean; overload;
      function ReadEx(var FltData: TArray<Double>; var StdDev: Double; const Count: Byte; Interval: Integer = 10{ms}): Boolean; overload;
      function ReadEx(var FltData: TArray<Double>; var Avg, StdDev: Single; const Count: Byte; Interval: Integer = 10{ms}): Boolean; overload;

      procedure ReadAsync(FltData, StdDev: PDouble; ReadOK: PBoolean = nil; Timeout: Single = 5.0); overload;
      procedure ReadAsync(FltData, StdDev, MinValue, MaxValue: PDouble; ReadOK: PBoolean = nil; Timeout: Single = 5.0); overload;

      procedure ConfigureRead(const Mode: TMeterMode; const Stat: TMeterStatMode; const HiZ: TMeterAutoHiZ; const NPLC: Single; const Samples: Integer; const RangeV: Single = 0); overload;
      procedure ConfigureRead(const Config: TMeterReadConfig); overload;
      function GetReadCount: Integer;
      procedure SetReadCount(const Cnt: Byte);

      procedure EnableRoundingPrecision(Enable: Boolean = True);
      procedure SetReadPrecision(const Precision: Byte);
      procedure SetTriggerSource(const Trigger: TMeterTrigger);
      procedure SetAutoImpedance(const HiZ: TMeterAutoHiZ);
      function GetAutoImpedanceMode: TMeterAutoHiZ;
      procedure GetNPLC(var Value: Single; const NPLC: TMeterNPLC);
      procedure SetNPLC(const Value: Single; NPLC: TMeterNPLC = nplcVOLT);
      procedure SetStatMode(const Mode: TMeterStatMode);
      function GetStatMode: TMeterStatMode;
      procedure Beep;

      procedure PerformACAL(Timeout: Integer = 30; Forced: Boolean = False);
      procedure CancelACAL;
      procedure SetCtrlLocal;
      procedure SetCtrlRemote;
      function DisplayInitMessage: Boolean;
      procedure SetReadTermination(TermChar: String = '\n');
      procedure ClearDisplay;
      procedure Reset;
      function Busy: Boolean;
      function GetACALStatus: TACALStatus;
      function GetMeterIdentity(out Model, Serial: String): Boolean;
      procedure EnabledRuntimeDebug(const ShuntValue: Single; const Mode: TMaccorRunMode);
      function MeasureThermalEMF(out E: Double; const Count: Byte = 10): Boolean;
      procedure SetAutoZero(const Enabled: Boolean; const Once: Boolean = False);
      procedure InvalidateReadConfig;

  end;

implementation

var
  NoACAL: TACALStatus;  { all-False fallback so TMeterUtils.ACALStat is never nil/dangling }

function NPLCIndex(const Value: Single): Integer;
var
  i: Integer;
  Best, D: Double;
begin
  Result := 0;
  Best := Abs(Value -METER_NPLC_VALUES[Low(METER_NPLC_VALUES)]);
  for i := Low(METER_NPLC_VALUES) +1 to High(METER_NPLC_VALUES) do
  begin
    D := Abs(Value -METER_NPLC_VALUES[i]);
    if D < Best then
    begin
      Best := D;
      Result := i;
    end;
  end;
end;

function NPLCValue(const Index: Integer): Single;
begin
  if (Index >= Low(METER_NPLC_VALUES)) and (Index <= High(METER_NPLC_VALUES)) then
    Result := METER_NPLC_VALUES[Index]
  else
    Result := 1;  { safe default: 1 NPLC }
end;

function EffectiveNPLC(const Settings: TMeterSettings): Single;
begin
  if Settings.NPLCReal > 0 then  Result := Settings.NPLCReal
  else if Settings.NPLC > 0 then Result := Settings.NPLC
  else Result := 1;
end;

{$REGION ' METER-UTILS '}

class function TMeterUtils.GetMeterTypeStr(const Id: TMeterType): String;
begin
  case Id of
    ManualMeter: Result := 'None: Manual';
    AG34410A: Result := 'AG34410A';
    KS34465A: Result := 'KS34465A';
    KS34470A: Result := 'KS34470A';
    FL8508A: Result := 'FL8508A';
    FL8588A: Result := 'FL8588A';

    else Exit('');
  end;
end;

{ <manufacturer>,<model>,<serial>,<firmware> :: Model and Serial are only set when the reply has them }
class function TMeterUtils.ParseIdentity(const Idn: String; out Model, Serial: String): Boolean;
var
  Parts: TArray<string>;
begin
  Model := '';
  Serial := '';
  SplitStr(Idn, ',', Parts);
  Result := (Length(Parts) >= 3) and (Trim(Parts[1]) <> '') and (Trim(Parts[2]) <> '');
  if Result then
  begin
    Model := Trim(Parts[1]);
    Serial := Trim(Parts[2]);
  end;
end;

class procedure TMeterUtils.GetSupportedMeters(Meters: TStrings);
var
  M: String;
begin
  Meters.Clear;
  for M in METER_TYPES_STR do Meters.Append(M);
end;

class function TMeterUtils.ModeToStr(const Mode: TMeterMode): String;
begin
  case Mode of
    mmVoltageDC: Result := 'Voltage::DC';
    mmVoltageAC: Result := 'Voltage::AC';
    mmCurrentDC: Result := 'Current::DC';
    mmCurrentAC: Result := 'Current::AC';
    else Result := 'invalid mode!';
  end;
end;

class function TMeterUtils.GetReadTerminationIndex(const ReadTermination: ShortString): Byte;
var
  i: Byte;
begin
  Result := 1;
  if Trim(String(ReadTermination)) = '' then Exit;

  for i := Low(METER_READ_TERMINATIONS) to High(METER_READ_TERMINATIONS) do
  begin
    if (METER_READ_TERMINATIONS[i] <> ReadTermination) then continue;
    Result := 1;
    break;
  end;
end;

class function TMeterUtils.FormatTermination(const Index: Integer): ShortString;
begin
  if Index in [0..3] then Result := METER_READ_TERMINATIONS[Index]
  else Result := METER_READ_TERMINATIONS[1];
end;

class procedure TMeterUtils.GetDefaultCalcUncertainties(var Uncertainties: PCalculatedUncertainties);
begin
  if not UncertaintiesLoaded then PackUncertainties;
  Uncertainties := @DefaultCalculatedUncertainties;
end;

class procedure TMeterUtils.UpdateStatus(const ACALStat: PACALStatus);
begin
  TMeterUtils.ACALStat := ACALStat;
end;

class procedure TMeterUtils.GetRelativeUncertainties(const Meter: TMeterType; var Uncertainties: TRelativeUncertainties; ForceRefresh: Boolean);
begin
  PackUncertainties(ForceRefresh);

  case Meter of
    AG34410A: Uncertainties := RelativeUncertainties.AG_34410A;
    KS34465A: Uncertainties := RelativeUncertainties.KS_34465A;
    KS34470A: Uncertainties := RelativeUncertainties.KS_34470A;

    else Uncertainties := DefaultRelativeUncertainties;
  end;
end;

class procedure TMeterUtils.SeedCalculatedUncertainties(const Meter: TMeterType;
  var Uncertainties: TCalculatedUncertainties; const Replace: Boolean);
var
  Row: PCalculatedUncertainties;

  function Blank(const Cert: TCalculatedUncertainties): Boolean;
  begin
    Result := (AnsiCharsToStr(Cert.Raw.mV100.Value) = '') and
              (AnsiCharsToStr(Cert.Raw.V1.Value) = '') and
              (AnsiCharsToStr(Cert.Raw.V10.Value) = '') and
              (AnsiCharsToStr(Cert.Raw.V100.Value) = '') and
              (AnsiCharsToStr(Cert.Raw.V1000.Value) = '');
  end;

begin
  PackUncertainties;

  case Meter of
    AG34410A: Row := @CalculatedUncertainties.AG_34410A;
    KS34465A: Row := @CalculatedUncertainties.KS_34465A;
    KS34470A: Row := @CalculatedUncertainties.KS_34470A;

    else Exit;
  end;

  { never displace real data with nothing :: the table carries figures under DEBUG
    only, so outside it this returns here at every call site. }
  if Blank(Row^) then Exit;

  { all-or-nothing :: a partly transcribed certificate is left alone rather than merged
    with table values, which would put real and nominal figures in one budget. Replace is
    the deliberate model change, where the prior unit's certificate no longer applies. }
  if (not Replace) and (not Blank(Uncertainties)) then Exit;

  Uncertainties := Row^;
end;

class procedure TMeterUtils.PackUncertainties(ForceRefresh: Boolean);
var
  Ptr: PRelativeUncertainties;

{$IFDEF DEBUG}
  { both halves must land :: ISO multiplies the Double by the Raw Scale, and the
    settings form rejects a value entered without a unit. }
  procedure Seed(var Value: Double; var Chars: Array of AnsiChar;
    var Scale: TCalcUncertUnits; const MicroVolts: Double);
  begin
    Value := MicroVolts;
    Scale := uuMicroVolt;
    UnpackAnsiStr(AnsiString(FloatToStr(MicroVolts, TFormatSettings.Invariant)), Chars);
  end;
{$ENDIF}

begin
  if (UncertaintiesLoaded and (not ForceRefresh)) then Exit;

  { dummies... }
  DefaultRelativeUncertainties := Default(TRelativeUncertainties);
  DefaultCalculatedUncertainties := Default(TCalculatedUncertainties);
  CalculatedUncertainties := Default(TMeterCalculatedUncertainties);

  try
    { start with agilent-34410A :: Keysight 5989-3738EN p.6 <1 yr, Tcal +/-5 C>, p.7 <ppm of range at 1 / 10 PLC>;
      no 1 uA / 10 uA current ranges on this meter }
    Ptr := @RelativeUncertainties.AG_34410A;
    { pack it }
    with Ptr^ do
    begin
      with PercentRead.Voltage do
      begin
        mV100 := 0.0050;
        V1 := 0.0035;
        V10 := 0.0030;
        V100 := 0.0040;
        V1000 := 0.0040;
      end;

      with PercentRange.Voltage do
      begin
        mV100 := 0.0035;
        V1 := 0.0007;
        V10 := 0.0005;
        V100 := 0.0006;
        V1000 := 0.0006;
      end;

      with PercentRead.Current do
      begin
        uA100 := 0.05;
        mA1 := 0.05;
        mA10 := 0.05;
        mA100 := 0.05;
        A1 := 0.1;
        A3 := 0.15;
      end;

      with PercentRange.Current do
      begin
        uA100 := 0.025;
        mA1 := 0.006;
        mA10 := 0.02;
        mA100 := 0.005;
        A1 := 0.01;
        A3 := 0.02;
      end;

      with ResFactor do
      begin
        mv100[0] := 3E-8; mv100[1] := 1E-8;
           V1[0] := 3E-7;    V1[1] := 1E-7;
          V10[0] := 3E-6;   V10[1] := 1E-6;
         V100[0] := 3E-5;  V100[1] := 1E-5;
          V1K[0] := 3E-4;   V1K[1] := 1E-4;
      end;
    end;

    { ...then keysight-KS34465A }
    Ptr := @RelativeUncertainties.KS_34465A;
    { pack it }
    with Ptr^ do
    begin
      with PercentRead.Voltage do
      begin
        mV100 := 0.0050;
        V1 := 0.0035;
        V10 := 0.0030;
        V100 := 0.0040;
        V1000 := 0.0040;
      end;

      with PercentRange.Voltage do
      begin
        mV100 := 0.0035;
        V1 := 0.0004;
        V10 := 0.0004;
        V100 := 0.0006;
        V1000 := 0.0006;
      end;

      with PercentRead.Current do
      begin
        uA1 := 0.05;
        uA10 := 0.05;
        uA100 := 0.05;
        mA1 := 0.05;
        mA10 := 0.05;
        mA100 := 0.05;
        A1 := 0.08;
        A3 := 0.2;
      end;

      with PercentRange.Current do
      begin
        uA1 := 0.005;
        uA10 := 0.002;
        uA100 := 0.001;
        mA1 := 0.005;
        mA10 := 0.02;
        mA100 := 0.005;
        A1 := 0.01;
        A3 := 0.02;
      end;

      with ResFactor do
      begin
        mv100[0] := 3E-8; mv100[1] := 1E-8;
           V1[0] := 3E-7;    V1[1] := 1E-7;
          V10[0] := 3E-6;   V10[1] := 1E-6;
         V100[0] := 3E-5;  V100[1] := 1E-5;
          V1K[0] := 3E-4;   V1K[1] := 1E-4;
      end;
    end;

    { ...and finally keysight-KS34470A }
    Ptr := @RelativeUncertainties.KS_34470A;
    { pack it }
    with Ptr^ do
    begin
      with PercentRead.Voltage  do
      begin
        mV100 := 0.0040;
        V1 := 0.0020;
        V10 := 0.0016;
        V100 := 0.0038;
        V1000 := 0.0038;
      end;

      with PercentRange.Voltage do
      begin
        mV100 := 0.0035;
        V1 := 0.0004;
        V10 := 0.0002;
        V100 := 0.0006;
        V1000 := 0.0006;
      end;

      with PercentRead.Current do
      begin
        uA1 := 0.05;
        uA10 := 0.05;
        uA100 := 0.05;
        mA1 := 0.05;
        mA10 := 0.05;
        mA100 := 0.005;
        A1 := 0.08;
        A3 := 0.02;
      end;

      with PercentRange.Current do
      begin
        uA1 := 0.005;
        uA10 := 0.002;
        uA100 := 0.001;
        mA1 := 0.005;
        mA10 := 0.02;
        mA100 := 0.005;
        A1 := 0.01;
        A3 := 0.02;
      end;

      with ResFactor do
      begin
        mv100[0] := 1E-8; mv100[1] := 3E-9;
           V1[0] := 1E-7;    V1[1] := 3E-8;
          V10[0] := 1E-6;   V10[1] := 3E-7;
         V100[0] := 1E-5;  V100[1] := 3E-6;
          V1K[0] := 1E-4;   V1K[1] := 3E-5;
      end;
    end;

{$IFDEF DEBUG}
    { bench convenience only :: saves re-typing five certificate values per fresh
      workspace. outside DEBUG this table stays zeroed and SeedCalculatedUncertainties
      is inert -- a K=2 certificate is per-serial and cannot come from a model table.
      AG34410A is left zeroed: its relative block is zeroed too, so a certificate there
      would put an unanchored term in the budget. microvolts throughout. }

    { keysight-KS34465A :: the KS34470A figures scaled by the ratio of the two spec
      windows packed above -- arithmetic, not a certificate. }
    with CalculatedUncertainties.KS_34465A do
    begin
      Seed(mV100, Raw.mV100.Value, Raw.mV100.Scale, 2.0);
      Seed(V1,    Raw.V1.Value,    Raw.V1.Scale,    11);
      Seed(V10,   Raw.V10.Value,   Raw.V10.Scale,   77);
      Seed(V100,  Raw.V100.Value,  Raw.V100.Scale,  620);
      Seed(V1000, Raw.V1000.Value, Raw.V1000.Scale, 8400);
    end;

    { keysight-KS34470A :: transcribed from an accredited certificate <2026-08-27> }
    with CalculatedUncertainties.KS_34470A do
    begin
      Seed(mV100, Raw.mV100.Value, Raw.mV100.Scale, 1.8);
      Seed(V1,    Raw.V1.Value,    Raw.V1.Scale,    6.5);
      Seed(V10,   Raw.V10.Value,   Raw.V10.Scale,   41);
      Seed(V100,  Raw.V100.Value,  Raw.V100.Scale,  590);
      Seed(V1000, Raw.V1000.Value, Raw.V1000.Scale, 8000);
    end;
{$ENDIF}
  finally
    UncertaintiesLoaded := True;
  end;
end;

{$ENDREGION}

{ TMultiMeter }

{$REGION ' GPIB-GATEWAY <Prologix GPIB-ETHERNET> '}
constructor TGpibGateway.Create(const Addr: String; const Port: Word; OnEvent: TAppEventCallback);
begin
  inherited Create;
  FAddr := Addr;
  FPort := Port;
  if FPort = 0 then FPort := TMeterUtils.GPIB_PORT;
  EventHandler := OnEvent;
  LastAddr := -1;
  InitializeCriticalSection(Lock);
  InitializeCriticalSection(RxLock);
  RxEvent := CreateEvent(nil, True{manual-reset}, False, nil);
end;

destructor TGpibGateway.Destroy;
begin
  Disconnect;
  if RxEvent <> 0 then CloseHandle(RxEvent);
  DeleteCriticalSection(RxLock);
  DeleteCriticalSection(Lock);
  inherited;
end;

procedure TGpibGateway.Alert(const Evt: TAppEventType; const Msg: String);
var
  Event: TAppEvent;
begin
  if not Assigned(EventHandler) then Exit;
  Event := Default(TAppEvent);
  Event.TimeStamp := Now;
  Event.Reason := Evt;
  Event.Msg := Msg;
  EventHandler(@Event);
end;

{ the client's own thread :: bytes are only collected here, lines are taken by WaitLine }
procedure TGpibGateway.OnDataRecvd(const Payload: PSocketPayload);
var
  Chunk: AnsiString;
begin
  if (Payload = nil) or (Payload^.Size <= 0) then Exit;
  SetString(Chunk, PAnsiChar(@Payload^.AsBytes[0]), Min(Payload^.Size, Length(Payload^.AsBytes)));

  EnterCriticalSection(RxLock);
  try
    RxBuf := RxBuf + Chunk;
    if Pos(AnsiString(#10), RxBuf) > 0 then SetEvent(RxEvent);
  finally
    LeaveCriticalSection(RxLock);
  end;
end;

procedure TGpibGateway.ResetRx;
begin
  EnterCriticalSection(RxLock);
  try
    RxBuf := '';
    ResetEvent(RxEvent);
  finally
    LeaveCriticalSection(RxLock);
  end;
end;

{ the next complete line, without its terminator }
function TGpibGateway.WaitLine(out Line: String; const TimeoutMs: Integer): Boolean;
var
  P: Integer;
begin
  Line := '';
  Result := WaitForSingleObject(RxEvent, Max(TimeoutMs, 1)) = WAIT_OBJECT_0;
  if not Result then Exit;

  EnterCriticalSection(RxLock);
  try
    P := Pos(AnsiString(#10), RxBuf);
    Result := P > 0;
    if Result then
    begin
      Line := Trim(String(Copy(RxBuf, 1, P -1)));
      Delete(RxBuf, 1, P);
    end;
    if Pos(AnsiString(#10), RxBuf) = 0 then ResetEvent(RxEvent);
  finally
    LeaveCriticalSection(RxLock);
  end;
end;

procedure TGpibGateway.DropClient;
begin
  if Client = nil then Exit;
  try
    if Client.Connected then Client.Disconnect;
    Client.Terminate;
    Client.WaitFor;
  finally
    FreeAndNil(Client);
  end;
end;

function TGpibGateway.Connected: Boolean;
begin
  Result := (Client <> nil) and Client.Connected;
end;

{ every line to the controller ends in LF :: '++' lines are its own, the rest goes to the addressed instrument }
function TGpibGateway.Send(const Line: AnsiString): Boolean;
begin
  Result := Connected and Client.SendData(Line +#10);
end;

function TGpibGateway.Select(const GpibAddr: Byte): Boolean;
begin
  Result := True;
  if LastAddr = GpibAddr then Exit;
  Result := Send(AnsiString(format('++addr %d', [GpibAddr])));
  if Result then LastAddr := GpibAddr;
end;

function TGpibGateway.Connect: Boolean;
var
  Version: String;
begin
  EnterCriticalSection(Lock);
  try
    if Connected then Exit(True);

    { reconnect over a stale client :: never orphan it }
    DropClient;
    Client := TTCPClientEx.Create(FAddr, FPort, OnDataRecvd);
    Client.Connect(3000{ms});
    Result := Client.Connected;
    if not Result then
    begin
      Alert(etAppError, format('gpib gateway %s:%d failed to connect!'#13#10, [FAddr, FPort]));
      Exit;
    end;

    LastAddr := -1;
    ResetRx;
    {
      controller mode; no read-after-write <a reply is asked for with ++read, see Query>; LF appended to
      what goes onto the bus, with EOI on its last byte <the 8508A accepts either>; the longest wait the
      controller offers for the instrument to start talking
    }
    Send('++mode 1');
    Send('++auto 0');
    Send('++eos 2');
    Send('++eoi 1');
    Send('++read_tmo_ms 3000');

    Send('++ver');
    if WaitLine(Version, 1000) then Alert(etMessage, format('gpib gateway %s:%d connected :: %s'#13#10, [FAddr, FPort, Version]))
    else Alert(etMessage, format('gpib gateway %s:%d connected <no version reply>'#13#10, [FAddr, FPort]));
  finally
    LeaveCriticalSection(Lock);
  end;
end;

procedure TGpibGateway.Disconnect;
begin
  EnterCriticalSection(Lock);
  try
    DropClient;
    LastAddr := -1;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TGpibGateway.Write(const GpibAddr: Byte; const Cmd: AnsiString): Boolean;
begin
  EnterCriticalSection(Lock);
  try
    Result := Select(GpibAddr) and Send(Cmd);
  finally
    LeaveCriticalSection(Lock);
  end;
end;

{
  the controller gives up on a read after its own timeout <3 s at most> when the instrument has not begun
  to answer; the instrument keeps its reply, so the read is simply asked again until TimeoutMs is spent
}
function TGpibGateway.Query(const GpibAddr: Byte; const Cmd: AnsiString; out Reply: String; const TimeoutMs: Integer): Boolean;
var
  Started: UInt64;
  Left: Int64;
begin
  Reply := '';
  Result := False;

  EnterCriticalSection(Lock);
  try
    ResetRx;
    if not (Select(GpibAddr) and Send(Cmd)) then Exit;

    Started := GetTickCount64;
    repeat
      if not Send('++read eoi') then Exit;
      Left := Int64(TimeoutMs) -Int64(GetTickCount64 -Started);
      if WaitLine(Reply, Integer(Min(Max(Left, 1), 3500))) then Exit(True);
    until Int64(GetTickCount64 -Started) >= TimeoutMs;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TGpibGateway.Trigger(const GpibAddrs: array of Byte): Boolean;
var
  Line: AnsiString;
  A: Byte;
begin
  Result := False;
  if Length(GpibAddrs) = 0 then Exit;

  Line := '++trg';
  for A in GpibAddrs do Line := Line +AnsiString(format(' %d', [A]));

  EnterCriticalSection(Lock);
  try
    Result := Send(Line);
  finally
    LeaveCriticalSection(Lock);
  end;
end;

procedure TGpibGateway.Local(const GpibAddr: Byte);
begin
  EnterCriticalSection(Lock);
  try
    if Select(GpibAddr) then Send('++loc');
  finally
    LeaveCriticalSection(Lock);
  end;
end;
{$ENDREGION}

constructor TMultiMeter.Create(var Config: PMeterSettings; OnEvent: TAppEventCallback);
begin
  try
    EventHandler:= OnEvent;
    AlertEvent(etMessage, format('initializing meter [%s]!'#13#10, [TMeterUtils.GetMeterTypeStr(Config^.Identity)]));

    Self.Config := Config^;
    ACALStatus.ExpiryTime := Config^.ACALExpiryTime;
    if ACALStatus.ExpiryTime = 0 then
      ACALStatus.ExpiryTime := 72{ hours };
    if Self.Config.ReadPrecision <= 0 then
      Self.Config.ReadPrecision := DEFAULT_READ_PRECISION;

    AlertEvent(etMessage, 'Meter: Initialization complete!'#13#10);
    TMeterUtils.UpdateStatus(@ACALStatus);
    RxEvent := CreateEvent(nil, True{manual-reset}, False, nil);
    DebugShunt := 0.000000000000;
    TMeterUtils.GetRelativeUncertainties(Config^.Identity, Config.Uncertainties.Relative);
    TMeterUtils.SeedCalculatedUncertainties(Config^.Identity, Config.Uncertainties.Calculated);
  except
    On E: Exception do
      AlertEvent(etAppException, format('Meter: Initialization failed! %s'#13#10'%s'#13#10,
        [E.Message, E.StackTrace]));
  end;
end;

constructor TMultiMeter.Create(var Config: PMeterSettings; const GpibAddr: Byte; OnEvent: TAppEventCallback);
var
  Addr: String;
  Port: Word;
begin
  Create(Config, OnEvent);
  AddrToStr(Self.Config.Socket.Addr.AsIPv4Addr.AsRAW, Addr);
  Port := Self.Config.Socket.Addr.Port;
  if Port = 0 then Port := TMeterUtils.GPIB_PORT;

  Self.Bus := TGpibGateway.Create(Addr, Port, OnEvent);
  Self.GpibAddr := GpibAddr;
  OwnBus := True;
end;

constructor TMultiMeter.Create(var Config: PMeterSettings; const Bus: TGpibGateway; const GpibAddr: Byte; OnEvent: TAppEventCallback);
begin
  Create(Config, OnEvent);
  Self.Bus := Bus;
  Self.GpibAddr := GpibAddr;
  OwnBus := False;
end;

destructor TMultiMeter.Destroy;
begin
  if TMeterUtils.ACALStat = @ACALStatus then TMeterUtils.ACALStat := @NoACAL;
  if Config.LocalOnExit then SetCtrlLocal;

  TerminatePing;
  SocketCleanup;
  if OwnBus then FreeAndNil(Bus);
  if RxEvent <> 0 then CloseHandle(RxEvent);
  inherited;
end;

procedure TMultiMeter.ConfigureRead(const Mode: TMeterMode; const Stat: TMeterStatMode; const HiZ: TMeterAutoHiZ; const NPLC: Single; const Samples: Integer; const RangeV: Single = 0);
begin
  { 8508A :: mode, then the range; resolution and filter are in the mode command, statistics are host-side }
  if IsGpib then
  begin
    SetMode(Mode);
    if (Mode = mmVoltageDC) and (RangeV > 0) then
      GpibWrite(AnsiString(format('%s %s', [FL_CMD_RANG_V, FloatToStr(RangeV, TFormatSettings.Invariant)])));
    GpibSamples := Samples;
    Exit;
  end;

  SetMode(Mode);

  { pin the VDC span AFTER the CONF <CONF resets to autorange> :: RANG <v>
    selects the lowest span accommodating <v>; 0 keeps autorange }
  if (Config.Identity in [KS34465A, KS34470A]) and (Mode = mmVoltageDC) and (RangeV > 0) then
  begin
    SendCommand(AnsiString(format('%s %s', [KS_CMD_SET_RANG_V, FloatToStr(RangeV, TFormatSettings.Invariant)])));
    AwaitResponse(@DataRcvd, 0.2);
  end;

  SetStatMode(Stat);
  SetNPLC(NPLC, TMeterNPLC(IntTernary(Mode = mmVoltageDC, Ord(nplcVOLT), Ord(nplcCURR))));
  SetReadCount(Byte(Samples));
  SetAutoImpedance(HiZ);
end;

procedure TMultiMeter.ConfigureRead(const Config: TMeterReadConfig);
begin
  { don't if matching! }
  if CompareMem(@Config, @ReadConfig, SizeOf(TMeterReadConfig)) then Exit;
  ConfigureRead(Config.Mode, Config.Stat, Config.HiZ, Config.NPLC, Config.Samples, Config.RangeV);
  ReadConfig := Config;
  LogReadConfig;
end;

{ journal the EFFECTIVE read config <device readback, not intent> :: method traceability }
procedure TMultiMeter.LogReadConfig;
var
  NPLC: Single;
  AZ, Rang, Auto: String;
begin
  if not (Config.Identity in [KS34465A, KS34470A]) then Exit;

  GetNPLC(NPLC, TMeterNPLC(IntTernary(Mode = mmVoltageDC, Ord(nplcVOLT), Ord(nplcCURR))));

  AZ := '?'; Rang := '?'; Auto := '?';
  if(Mode = mmVoltageDC) then
  begin
    SendCommand(KS_CMD_GET_AZ_V); AwaitResponse(@DataRcvd, 0.2);
    if DataRcvd then AZ := Trim(Response.AsString);
    SendCommand(KS_CMD_GET_RANG_V); AwaitResponse(@DataRcvd, 0.2);
    if DataRcvd then Rang := Trim(Response.AsString);
    { AUTO 1 :: RANG is merely the floating selection, not a pin }
    SendCommand(KS_CMD_GET_RANG_AUTO); AwaitResponse(@DataRcvd, 0.2);
    if DataRcvd then Auto := Trim(Response.AsString);
  end;

  AlertEvent(etMessage, format('meter read-config :: %s | NPLC %s | AZ %s | RANG %s | AUTO %s'#13#10,
    [TMeterUtils.ModeToStr(Mode), FloatToStr(NPLC, TFormatSettings.Invariant), AZ, Rang, Auto]), False, TUtils.GRAY);
end;

function TMultiMeter.Connect: Boolean;
begin
  Result := False;
  if IsGpib then Exit(ConnectGpib);

  case Config.Socket.Kind of
    stSockTCP:
    begin
      InitMeter;
      if not Assigned(Socket.AsTcpClientSockPtr) then
        Exit;

      AlertEvent(etMessage, 'connecting to meter... '#13#10);
      Socket.AsTcpClientSockPtr^.Connect(3000{ms});
      Result := Socket.AsTcpClientSockPtr^.Connected;
    end;

    stSockUDP:
    begin
      if Socket.AsUdpSockPtr = nil then
        Exit;

      Result := Ping(Config.Socket.Addr.AsIPv4Addr.AsRAW, 150);
    end;
  end;

  if Result then
  begin
    Reset;
    DisplayInitMessage;
    CheckIdentity;
    CheckACALStatus;
    MeterPing;
    //ConfigureRead(TMeterMode.mmVoltageDC, TMeterStatMode.smStatOFF, TMeterAutoHiZ.miAutoON, Config.NPLC, Config.Samples);
  end;

  AlertEvent(TAppEventType(IntTernary(Result, 0, 1)), StrTernary(Result, 'meter connected!', 'meter failed to connect!')+#13#10, False, IntTernary(Result, 1, 0));
  Status.Connected := Result;
  if Result then AvoidBusyWait(QTR_SEC);
end;

function TMultiMeter.Disconnect: Boolean;
begin
  AlertEvent(etMessage, 'meter attempting disconnect!'#13#10);

  { this is a must! }
  ReadConfig := Default(TMeterReadConfig);

  { a shared gateway stays up for the other meters on it }
  if IsGpib then
  begin
    if Status.Connected then SetCtrlLocal;
    Status.Connected := False;
    if OwnBus and Assigned(Bus) then Bus.Disconnect;
    AlertEvent(etMessage, 'meter disconnected!'#13#10);
    Exit(True);
  end;

  try
  case Config.Socket.Kind of
      stSockUDP: Status.Connected := False;

      stSockTCP:
      begin
        if Assigned(Socket.AsTcpClientSockPtr) then
        begin
          try
            if Socket.AsTcpClientSockPtr^ <> nil then
              if Socket.AsTcpClientSockPtr^.Connected then
              begin
                SetCtrlLocal;
                Socket.AsTcpClientSockPtr^.Disconnect;
              end;

            Status.Connected := Socket.AsTcpClientSockPtr^.Connected;
          finally
            SocketCleanup;
          end;
        end;
      end;
    end;
  finally
    Result := (not Status.Connected);
  end;

  if Result then AlertEvent(etMessage, 'meter disconnected!'#13#10);
end;

function TMultiMeter.Connected: Boolean;
begin
  Result := False;
  if IsGpib then Exit(Status.Connected and Assigned(Bus) and Bus.Connected);

  case Config.Socket.Kind of
    stSockUDP: Result := Status.Connected and Status.Online;
    stSockTCP:
    begin
      begin
        if Assigned(Socket.AsTcpClientSockPtr) then
          if (Socket.AsTcpClientSockPtr^ <> nil) then
            Result := Socket.AsTcpClientSockPtr^.Connected;
      end;
    end;
  end;
end;

procedure TMultiMeter.SetReadTermination(TermChar: String = '\n');
var
  CMDSTR: AnsiString;
begin
  CMDSTR := AnsiString(format('INVOKE SetReadTerminator with terminator = "%s"', [TermChar]));
  SendCommand(CMDSTR);
end;

function TMultiMeter.DisplayInitMessage: Boolean;
begin
  AlertEvent(etMessage, 'meter sending init. message'#13#10);
  Result := False;

  case Config.Identity of
    AG34410A:
    begin
      SendCommand(KS_CMD_BEEP); AwaitResponse(@DataRcvd, 0.3);
      SendCommand(KS_CMD_BEEP); AwaitResponse(@DataRcvd, 0.2);
      SendCommand(AnsiString(format('%s '#39'%s'#39, [AG_CMD_DISP_SET, Config.InitMsg])));
      AwaitResponse(@DataRcvd, 1);

      { read back! }
      SendCommand(AG_CMD_DISP_GET);
      AwaitResponse(@DataRcvd);
      { check! }
      if DataRcvd then
      begin
        Result := True;
        AwaitResponse(@DataRcvd, 0.2);
        if DataRcvd then
        begin
          SendCommand(AG_CMD_DISP_CLR);
          AlertEvent(etMessage, 'meter: init. messsage sent & confirmed'#13#10);
        end;
        if Config.Socket.Kind = stSockUDP then Status.Connected := True;
      end;
    end;

    KS34465A, KS34470A:
    begin
      SendCommand(KS_CMD_BEEP); AwaitResponse(@DataRcvd, 0.3);
      SendCommand(KS_CMD_BEEP); AwaitResponse(@DataRcvd, 0.2);
      SendCommand(KS_CMD_RST);  AwaitResponse(@DataRcvd, 0.2);
      SendCommand(KS_CMD_CLR);  AwaitResponse(@DataRcvd, 0.2);
      SendCommand(AnsiString(format('%s '#39'%s'#39, [KS_CMD_DISP, Config.InitMsg])));
      AwaitResponse(@DataRcvd, 1);

      { read back! }
      SendCommand(KS_CMD_DISP_GET);
      AwaitResponse(@DataRcvd);
      { check! }
      if DataRcvd then
      begin
        Result := True;
        AwaitResponse(@DataRcvd, 0.2);
        if DataRcvd then
        begin
          SendCommand(KS_CMD_DISP_CLR);
          AlertEvent(etMessage, 'meter: init. messsage sent & confirmed'#13#10);
        end;
        if Config.Socket.Kind = stSockUDP then Status.Connected := True;
      end;
    end;
  end;

  AvoidBusyWait(WAIT_100MS);
end;

procedure TMultiMeter.EnabledRuntimeDebug(const ShuntValue: Single; const Mode: TMaccorRunMode);
begin
  DebugShunt := Shuntvalue;
  MaccorMode := Mode;
end;

{
  thermal EMF of the measurement loop: leads shorted at the connection point, settled by the operator.
  E = largest |reading| on DCV 100 mV at NPLC 10. invalidates the cached read config so the next
  ConfigureRead(Config) re-applies the task's own range.
}
function TMultiMeter.MeasureThermalEMF(out E: Double; const Count: Byte = 10): Boolean;
var
  Values: TArray<Double>;
begin
  E := 0.0;
  AlertEvent(etMessage, THERMAL_EMF_INSTRUCTIONS +#13#10);
  ConfigureRead(mmVoltageDC, smStatOFF, miAutoON, 10, Count, 0.1);
  ReadConfig := Default(TMeterReadConfig);
  Result := Read(Values, Count, 5.0) and (Length(Values) = Count);
  if Result then
    for var V in Values do E := Max(E, Abs(V));

  if Result and (E > THERMAL_EMF_SHORT_LIMIT_VOLTS) then
  begin
    AlertEvent(etMessage, format('thermal EMF: %.3f mV read - the leads are not shorted. Short them at the ' +
      'connection point and measure again.'#13#10, [E *1E3]));
    Result := False;
  end;
end;

{ DCV autozero; a CONF (SetMode) restores the meter default <ON>. ONCE zeroes now and leaves it OFF }
procedure TMultiMeter.SetAutoZero(const Enabled: Boolean; const Once: Boolean = False);
begin
  if not (Config.Identity in [KS34465A, KS34470A]) then Exit;
  SendCommand(AnsiString(format('%s %s', [KS_CMD_SET_AZ_V,
    StrTernary(Once, 'ONCE', StrTernary(Enabled, 'ON', 'OFF'))])));
  AwaitResponse(@DataRcvd, 0.2);
end;

{ forget the cached read config so the next ConfigureRead(Config) re-applies it in full <after direct overrides> }
procedure TMultiMeter.InvalidateReadConfig;
begin
  ReadConfig := Default(TMeterReadConfig);
end;

procedure TMultiMeter.Beep;
begin
  if not Connected then Exit;

  case Config.Identity of
    AG34410A, KS34465A, KS34470A:
    begin
      SendCommand(KS_CMD_BEEP);
      AwaitResponse(@DataRcvd, 0.3);
    end;
  end;
end;

function TMultiMeter.Busy: Boolean;
begin
  Result := Status.Working;
end;

procedure TMultiMeter.ClearDisplay;
begin
  if not Connected then Exit;

  case Config.Identity of
    AG34410A: ;
    KS34465A, KS34470A:
    begin
      SendCommand(KS_CMD_DISP_CLR);
      AwaitResponse(@DataRcvd, 0.3);
    end;
  end;
end;

function TMultiMeter.GetMode: TMeterMode;
begin
  Result := Mode;
end;

procedure TMultiMeter.InitMeter;
begin
  try
    case Config.Socket.Kind of
      stSockUDP:
      begin
        InitUDPSocket;
        if Assigned(Socket.AsUdpSockPtr) and (Socket.AsUdpSockPtr^ <> nil) then
          AlertEvent(etMessage, 'meter com. socket initialization complete.'#13#10);
      end;

      stSockTCP:
      begin
        InitTCPSocket;
        if Assigned(Socket.AsTcpClientSockPtr) and (Socket.AsTcpClientSockPtr^ <> nil) then
          AlertEvent(etMessage, 'meter com. socket initialization complete.'#13#10);
      end;
    end;
  except
    On E: Exception do
      AlertEvent(etAppException, format('meter socket initialization failed! %s'#13#10'%s'#13#10,
        [E.Message, E.StackTrace]));
  end;
end;

procedure TMultiMeter.InitTCPSocket;
begin
  try
    { reconnect over a stale client :: never orphan it }
    if Assigned(Socket.AsTcpClientSockPtr) then SocketCleanup;
    New(Socket.AsTcpClientSockPtr);

    if Assigned(Socket.AsTcpClientSockPtr) then
    begin
      AddrToStr(Config.Socket.Addr.AsIPv4Addr.AsRAW, AddrStr);
      { initialize it }
      Socket.AsTcpClientSockPtr^ := TTCPClientEx.Create(AddrStr, Config.Socket.Addr.Port, OnTcpDataRecvd);
    end;
  except
    On E: Exception do
      HandleExceptionEvent(E);
  end;
end;

procedure TMultiMeter.InitUDPSocket;
var
  Addr: String;
begin
  try
    { reconnect over a stale client :: never orphan it }
    if (Socket.AsUdpSockPtr <> nil) then SocketCleanup;
    New(Socket.AsUdpSockPtr);

    if Assigned(Socket.AsUdpSockPtr) then
    begin
      AddrToStr(Config.Socket.Addr.AsIPv4Addr.AsRAW, Addr);
      { initialize it }
      Socket.AsUdpSockPtr^ := TUdpSocketEx.Create(0{auto}, OnUdpDataRecvd);
      { set static address }
      Socket.AsUdpSockPtr^.SetRemoteAddr(Addr, Config.Socket.Addr.Port);
    end;
  except
    On E: Exception do
      HandleExceptionEvent(E);
  end;
end;

{
  ping address, update online status every second
}
procedure TMultiMeter.MeterPing;
begin
  if Assigned(PingHandle) then Exit;

  PingHandle := TThread.CreateAnonymousThread(procedure
  var
    PingTmr: UInt64;
    CheckACAL: Boolean;
    ExpiryTime, LastACAL: TDateTime;
  begin
    { now in hours:: default = 72 Hrs }
    PingTmr := 0;
    ExpiryTime := Now;
    LastACAL := Now;
    CheckACAL := Config.Identity in TMeterUtils.ACALMETERS;

    repeat
      AvoidBusyWait(1);
      if Status.Terminate then break;

      { every 2secs }
      if (GetTickCountEx < PingTmr) then continue;

      { update timer }
      PingTmr := GetTickCountEx(TWO_SEC);

      { validate address before ping! }
      if ValidAddress(AddrStr) then
        Status.Online := Ping(AnsiString(AddrStr), 250);

      { dont bother until online }
      if not Status.Online then continue;

      { why not do other things here }
      if CheckACAL and (not ACALStatus.Busy) then
      begin
        if LastACAL <> ACALStatus.LastCal then
        begin
          LastACAL := ACALStatus.LastCal;
          ExpiryTime := IncHour(ACALStatus.LastCal, Config.ACALExpiryTime);
        end;

        ACALStatus.Expired := (Now >= ExpiryTime);
        ACALStatus.Ready := not ACALStatus.Expired;
        { update global-copy TMeterUtils }
        TMeterUtils.UpdateStatus(@ACALStatus);

        if ACALStatus.Ready then ACALStatus.TimeToExpiry := DateTimeToCountdown(TDateTime(ExpiryTime -Now))
        else ACALStatus.TimeToExpiry := 'ACAL expired!';
      end;
    until Status.Terminate;

    Status.Terminated := True;
  end);

  PingHandle.FreeOnTerminate := False;
  PingHandle.Start;
  AlertEvent(etMessage, 'meter ping process started ok!'#13#10);
end;

{ terminate ping thread, give it a timeout of 3 seconds }
procedure TMultiMeter.TerminatePing;
var
  T: UInt64;
begin
  try
    AlertEvent(etMessage, 'meter terminating ping process...'#13#10);
    Status.Terminate := True;
    T := GetTickCountEx(TWO_SEC);

    repeat
      ProcessMsgs(QTR_SEC);
    until (GetTickCountEx >= T) or (Status.Terminated);

    if Status.Terminated then AlertEvent(etMessage, 'meter ping process termination complete!'#13#10);
  finally
    FreeAndNil(PingHandle);
  end;
end;

procedure TMultiMeter.SendCommand(const Cmd: AnsiString);
var
  Data: AnsiString;
begin
  DataRcvd := False;
  if RxEvent <> 0 then ResetEvent(RxEvent);
  ZeroMemory(@Response.Data.AsBytes[0], Sizeof(TBufferData));

  { GPIB meters go through their gateway <GpibWrite, Bus.Query>, never this socket }
  if IsGpib then Exit;

  case Config.Socket.Kind of
    stSockUDP: ;
    stSockTCP:
    begin
      if Socket.AsTcpClientSockPtr <> nil then
      begin
        if Socket.AsTcpClientSockPtr^ <> nil then
        begin
          if Socket.AsTcpClientSockPtr^.Connected then
          begin
            Data := CMD +#10;
            Socket.AsTcpClientSockPtr^.SendData(Data);
          end;
        end;
      end;
    end;
  end;
end;

procedure TMultiMeter.SetAutoImpedance(const HiZ: TMeterAutoHiZ);
begin
  if HiZ = miUnknown then Exit;

  case Config.Identity of
    AG34410A:
    begin
      case HiZ of
        miAutoON: SendCommand(AG_CMD_HiZ_ON);
        miAutoOFF: SendCommand(AG_CMD_HiZ_OFF);
      end;
    end;

    KS34465A, KS34470A:
    begin
      case HiZ of
        miAutoON: SendCommand(KS_CMD_HiZ_ON);
        miAutoOFF: SendCommand(KS_CMD_HiZ_OFF);
      end;
    end;
  end;

  AwaitResponse(@DataRcvd);
end;

function TMultiMeter.GetMeterIdentity(out Model, Serial: String): Boolean;
var
  Idn: String;
begin
  Model := '';
  Serial := '';
  if IsGpib then
    Exit(Assigned(Bus) and Bus.Query(GpibAddr, KS_CMD_IDN, Idn) and TMeterUtils.ParseIdentity(Idn, Model, Serial));

  SendCommand(KS_CMD_IDN);
  AwaitResponse(@DataRcvd, 0.5);
  Result := DataRcvd and TMeterUtils.ParseIdentity(Response.AsString, Model, Serial);
end;

{ warning only, and only for the meters known to answer :: anything else is never asked }
procedure TMultiMeter.CheckIdentity;
var
  Model, Serial, Want, Kind: String;
begin
  if (Config.Socket.Kind <> stSockTCP) or (not Connected) then Exit;
  if not (Config.Identity in TMeterUtils.IDN_METERS) then Exit;

  if not GetMeterIdentity(Model, Serial) then
  begin
    AlertEvent(etMessage, 'meter identity unavailable'#13#10);
    Exit;
  end;

  { the typed serial may carry a prefix or be empty }
  Kind := UpperCase(TMeterUtils.GetMeterTypeStr(Config.Identity));
  Want := UpperCase(Trim(String(Config.Serial)));

  if (Pos(UpperCase(Model), Kind) = 0)
    or ((Want <> '') and (Pos(Want, UpperCase(Serial)) = 0) and (Pos(UpperCase(Serial), Want) = 0)) then
    AlertEvent(etMessage, format('meter identity differs: configured %s %s, instrument reports %s %s'#13#10,
      [TMeterUtils.GetMeterTypeStr(Config.Identity), Trim(String(Config.Serial)), Model, Serial]));
end;

function TMultiMeter.GetACALStatus: TACALStatus;
begin
  Result := ACALStatus;
end;

function TMultiMeter.GetAutoImpedanceMode: TMeterAutoHiZ;
begin
  Result := miUnknown;

  case Config.Identity of
    AG34410A: SendCommand(AG_CMD_HiZ_GET);
    KS34465A, KS34470A: SendCommand(KS_CMD_HiZ_GET);
    else DataRcvd := False;
  end;

  AwaitResponse(@DataRcvd, 1);
  if DataRcvd then Result := TMeterAutoHiZ(Response.AsInteger +1);
end;

procedure TMultiMeter.SetCtrlLocal;
begin
  if IsGpib then
  begin
    if Assigned(Bus) then Bus.Local(GpibAddr);
    Exit;
  end;

  AlertEvent(etMessage, 'meter setting local control'#13#10);
  case Config.Identity of
    AG34410A: AlertEvent(etAppError, 'meter command is not available'#13#10);
    KS34465A, KS34470A: SendCommand(KS_CMD_LOCAL);
  end;

  if not(Config.Identity in [AG34410A]) then
  begin
    AwaitResponse(@DataRcvd, 0.5);
    if DataRcvd then AlertEvent(etMessage, 'meter control <Local> complete'#13#10);
  end;
end;

procedure TMultiMeter.SetCtrlRemote;
begin
  case Config.Identity of
    AG34410A, KS34465A, KS34470A: DisplayInitMessage;
  end;
end;

function TMultiMeter.SetMode(const Mode: TMeterMode): Boolean;
begin
  AlertEvent(etMessage, format('meter setting mode to %s... ', [TMeterUtils.ModeToStr(Mode)]));
  if Ord(Mode) > Ord(mmCurrentAC) then
  begin
    AlertEvent(etAppError, ' fail!'#13#10);
    Exit(False);
  end;

  { 8508A :: no acknowledgement to wait for, the write either left or it did not }
  if IsGpib then
  begin
    Result := False;
    case Mode of
      mmVoltageDC: Result := GpibWrite(FL_CMD_VOLT_DC);
      mmVoltageAC: Result := GpibWrite(FL_CMD_VOLT_AC);
      mmCurrentDC: Result := GpibWrite(FL_CMD_CURR_DC);
      mmCurrentAC: Result := GpibWrite(FL_CMD_CURR_AC);
    end;

    if Result then Self.Mode := Mode;
    AlertEvent(TAppEventType(IntTernary(Result, 0, 1)),
      format('%s'#13#10, [StrTernary(Result, 'ok!', 'failed!')]));
    Exit;
  end;

  case Config.Identity of
    AG34410A:
    begin
      case Mode of
        mmVoltageDC: SendCommand(AG_CMD_VOLT_DC);
        mmVoltageAC: SendCommand(AG_CMD_VOLT_AC);
        mmCurrentDC: SendCommand(AG_CMD_CURR_DC);
        mmCurrentAC: SendCommand(AG_CMD_CURR_DC);
      end;

      AwaitResponse(@DataRcvd, 0.25);
      SendCommand(AG_CMD_DISP_GET);
      AwaitResponse(@DataRcvd, 0.25);
    end;

    KS34465A, KS34470A:
    begin
      case Mode of
        mmVoltageDC:
        begin
          SendCommand(KS_CMD_VOLT_DC); AwaitResponse(@DataRcvd, 0.5);
          //SendCommand(format('%s %d', [KS_CMD_NPLC, Config.NPLC])); AwaitResponse(@DataRcvd, 0.2);
          //SendCommand(KS_CMD_HiZ_ON); AwaitResponse(@DataRcvd, 0.2);
        end;

        mmVoltageAC: SendCommand(KS_CMD_VOLT_AC);
        mmCurrentDC: SendCommand(KS_CMD_CURR_DC);
        mmCurrentAC: SendCommand(KS_CMD_CURR_AC);
      end;
    end;
  end;

  AwaitResponse(@DataRcvd);
  if DataRcvd then Self.Mode := Mode;
  Result := (Mode = Self.Mode);
  AlertEvent(TAppEventType(IntTernary(Result, 0, 1)),
    format('%s'#13#10, [StrTernary(Result, 'ok!', 'failed!')]));
end;

procedure TMultiMeter.SetNPLC(const Value: Single; NPLC: TMeterNPLC);
var
  FromDevice: Single;
  ValStr: String;
begin
  case Config.Identity of
    AG34410A, KS34465A, KS34470A:
    begin
      { get current }
      GetNPLC(FromDevice, NPLC);

      { BUGFIX: write whenever the value differs. The old guard also required
        (FromDevice > 0), so a failed/zero read silently blocked every write.
        Format with an invariant locale so the decimal separator is always '.'. }
      if not SameValue(FromDevice, Value, 1E-4) then
      begin
        ValStr := FloatToStr(Value, TFormatSettings.Invariant);
        case Config.Identity of
          AG34410A:
          begin
            case NPLC of
              nplcVOLT: SendCommand(AnsiString(format('%s %s'#13#10, [AG_CMD_SET_VNPLC, ValStr])));
              nplcCURR: SendCommand(AnsiString(format('%s %s'#13#10, [AG_CMD_SET_INPLC, ValStr])));
              nplcTEMP: SendCommand(AnsiString(format('%s %s'#13#10, [AG_CMD_SET_TNPLC, ValStr])));
            end;
          end

          else SendCommand(AnsiString(format('%s %s'#13#10, [StrTernary(NPLC = nplcVOLT, KS_CMD_SET_NPLC_V, KS_CMD_SET_NPLC_I), ValStr])));
        end;
      end;
    end;
  end;
end;

procedure TMultiMeter.GetNPLC(var Value: Single; const NPLC: TMeterNPLC);
begin
  Value := -1;

  case Config.Identity of
    AG34410A:
    begin
      case NPLC of
        nplcVOLT: SendCommand(AG_CMD_GET_VNPLC);
        nplcCURR: SendCommand(AG_CMD_GET_INPLC);
        nplcTEMP: SendCommand(AG_CMD_GET_TNPLC);

        else Exit;
      end;
    end;

    KS34465A, KS34470A: SendCommand(
      AnsiString(
        StrTernary(NPLC = nplcVOLT, KS_CMD_GET_NPLC_V, KS_CMD_GET_NPLC_I))
      );
    else Exit;
  end;

  AwaitResponse(@DataRcvd);
  { NPLC comes back as a float in scientific notation (e.g. '+1.00000000E+01').
    Parse locale-invariant so a comma-decimal system does not fail the parse; leave the
    -1 sentinel on failure. }
  if DataRcvd then
  begin
    var Parsed: Single;
    if TryStrToFloat(Trim(Response.AsString), Parsed, TFormatSettings.Invariant) then
      Value := Parsed;
  end;
end;

procedure TMultiMeter.SetStatMode(const Mode: TMeterStatMode);
begin
  case Config.Identity of
    AG34410A:
    begin
      case Mode of
        smStatON, smStatFuncAvgON: SendCommand(AG_CMD_STAT_SET);
        smStatOFF, smStatFuncAvgOFF: SendCommand(AG_CMD_STAT_CLR);
//        smStatFuncAvgON: SendCommand(AG_CMD_AVG_ON);
//        smStatFuncAvgOFF: SendCommand(AG_CMD_AVG_OFF);
      end;
    end;

    KS34465A, KS34470A:
    begin
      { get current }
      case Mode of
        smStatON: SendCommand(KS_CMD_STAT_ON);
        smStatOFF: SendCommand(KS_CMD_STAT_OFF);
        smStatFuncAvgON: SendCommand(KS_CMD_AVG_STAT_ON);
        smStatFuncAvgOFF: SendCommand(KS_CMD_AVG_STAT_OFF);
      end;

      AwaitResponse(@DataRcvd, 0.25);
    end;
  end;
end;

function TMultiMeter.GetStatMode: TMeterStatMode;
begin
  Result := TMeterStatMode(0);
  case Config.Identity of
    AG34410A, KS34465A, KS34470A: SendCommand(KS_CMD_STAT_GET);
    else DataRcvd := False;
  end;

  AwaitResponse(@DataRcvd, 1);
  if DataRcvd then
    Result := TMeterStatMode(Response.AsInteger);
end;

function TMultiMeter.GetReadCount: Integer;
begin
  Result := 0;

  case Config.Identity of
    AG34410A, KS34465A, KS34470A:
    begin
      { get current }
      SendCommand(KS_CMD_GET_RCNT); AwaitResponse(@DataRcvd, 3);
      { update res ult }
      if DataRcvd then Result := Response.AsInteger;
    end;
  end;
end;

procedure TMultiMeter.SetReadCount(const Cnt: Byte);
var
  RCnt: SmallInt;
begin
  case Config.Identity of
    AG34410A, KS34465A, KS34470A:
    begin
      if (LastRdCnt = Cnt) then Exit;

      RCnt := GetReadCount;
      if RCnt <= 0 then Exit;   { no answer :: ask again on the next read }

      if RCnt <> Cnt then
      begin
        SendCommand(AnsiString(format('%s %d'#13#10, [KS_CMD_SET_RCNT, Cnt])));
        AwaitResponse(@DataRcvd, 0.2);
      end;
      LastRdCnt := Cnt;
    end;
  end;
end;

procedure TMultiMeter.SetReadPrecision(const Precision: Byte);
begin
  Config.ReadPrecision := Precision;
end;

procedure TMultiMeter.EnableRoundingPrecision(Enable: Boolean);
begin
  Config.Rounding := Enable;
end;

procedure TMultiMeter.SetTriggerSource(const Trigger: TMeterTrigger);
begin
  case Config.Identity of
    AG34410A:;
    KS34465A, KS34470A:
    begin
      case Trigger of
        mtImmediate: SendCommand(KS_CMD_TRIG_IMM);
        mtExternal: SendCommand(KS_CMD_TRIG_EXT);
        mtBus: SendCommand(KS_CMD_TRIG_BUS);
        mtInternal: SendCommand(KS_CMD_TRIG_INT);
      end;
    end;
  end;
end;

procedure TMultiMeter.SocketCleanup;
begin
  case Config.Socket.Kind of
    stSockUDP:
    begin
      if (Socket.AsUdpSockPtr <> nil) then
      begin
        try
          Socket.AsUdpSockPtr^.Terminate;
          Socket.AsUdpSockPtr^.WaitFor;
          Socket.AsUdpSockPtr^.Free;
          Socket.AsUdpSockPtr^ := nil;
        finally
          Dispose(Socket.AsUdpSockPtr);
        end;
      end;
    end;

    stSockTCP:
    begin
      if Assigned(Socket.AsTcpClientSockPtr) then
      begin
        try
          if (Socket.AsTcpClientSockPtr^ <> nil) then
          begin
            if Socket.AsTcpClientSockPtr^.Connected then
              Socket.AsTcpClientSockPtr^.Disconnect;

            Socket.AsTcpClientSockPtr^.Terminate;
            Socket.AsTcpClientSockPtr^.WaitFor;
            Socket.AsTcpClientSockPtr^.Free;
            Socket.AsTcpClientSockPtr^ := nil;
          end;
        finally
          Dispose(Socket.AsTcpClientSockPtr);
          Socket.AsTcpClientSockPtr := nil;
        end;
      end;
    end;
  end;
end;

procedure TMultiMeter.PerformACAL(Timeout: Integer; Forced: Boolean);
var
  StrData: String;
begin
  if (ACALStatus.Busy or Status.Working) or (not Connected) then
    Exit;

  CheckACALStatus;
  if (not ACALStatus.Expired) and (not Forced) then
  begin
    TUtils.HandleEvent(etMessage, 'meter ACAL ok! Expires: ', TUtils.GRAY);
    TUtils.HandleEvent(etMessage, format('%s'#13#10, [String(GetACALStatus.TimeToExpiry)]),
      TUtils.UpdateLine(ulPartial, TUtils.SILVER));
    Exit;
  end;

  case Config.Identity of
    AG34410A: AlertEvent(etAppError, 'ACAL command is not available for this meter!'#13#10);
    KS34465A, KS34470A:
    begin
      ACALStatus.Busy := True;
      Status.Working := True;
      ACALStatus.Ready := False;
      ACALCtrl.Cancel := False;
      ACALStatus.OK := False;
      ACALStatus.Timeout := IntTernary(ACALStatus.Timeout <= 0, 1000, ACALStatus.Timeout);
      AlertEvent(etMessage, 'meter ACAL in progress... please wait!'#13#10);

      { detach! }
      TThread.CreateAnonymousThread(
      procedure
      begin
        try
          ACALCtrl.Time := Timeout;
          SendCommand(KS_CMD_ACAL);
          AwaitResponse(@DataRcvd, ACALInProgress, Timeout, @ACALCtrl.Cancel);

          if DataRcvd and (not ACALCtrl.Cancel) then
          begin
            ACALStatus.Ready := (Response.AsString = '+0');
            if ACALStatus.Ready then ACALStatus.LastCal := Now;

            { get new meter temp }
            AlertEvent(etMessage, 'meter getting temperature'#13#10);
            SendCommand(KS_CMD_TEMP_GET);
            AwaitResponse(@DataRcvd, 1);
            if DataRcvd then
            begin
              StrData := Trim(Response.AsString);
              ParseTemperature(StrData);
              AlertEvent(etMessage, format('meter reported temperature = %.2f %sC'#13#10, [ACALStatus.Temp, DEGREE]));
            end;

            if ACALStatus.OK then
            begin
              AlertEvent(etMessage, 'meter ACAL completed successfully!'#13#10);
              AlertEvent(etMessage, format('meter ACAL will expire after %d hours!'#13#10, [ACALStatus.ExpiryTime]));
              ACALStatus.LastCal := Now;
            end
            else AlertEvent(etAppError, 'meter ACAL failed!'#13#10);
          end
          else
          begin
            if ACALCtrl.Cancel then AlertEvent(etAppError, 'meter ACAL cancelled by user!'#13#10)
            else AlertEvent(etMessage, 'meter ACAL timeout. try again or do it manually'#13#10);
          end;
        finally
          ACALStatus.Busy := False;
          Status.Working := False;
          TMeterUtils.UpdateStatus(@ACALStatus);
        end;
      end).Start;
    end;
  end;
end;

procedure TMultiMeter.CancelACAL;
begin
  if ACALStatus.Busy then
    ACALCtrl.Cancel := True;
end;

procedure TMultiMeter.CheckACALStatus;
var
  DateParts, TimeParts: TArray<string>;
  ISO: String; Y, M, D: Integer;
  H, N: Integer;
  SecText: String;
begin
  if not Connected then Exit;
  if not (Config.Identity in TMeterUtils.ACALMETERS) then Exit;

  AlertEvent(etMessage, 'meter: checking last ACAL date... ');

  { get meter date&time... if wrong would screw all }
  SendCommand(KS_CMD_DATE_GET);
  AwaitResponse(@DataRcvd, QTR_SEC);
  if not DataRcvd then Exit;
  SplitStr(Response.AsString, ',', DateParts);

  SendCommand(KS_CMD_TIME_GET);
  AwaitResponse(@DataRcvd, QTR_SEC);
  if not DataRcvd then Exit;
  SplitStr(Response.AsString, ',', TimeParts);

  ISO := Format('%4d-%2.2d-%2.2dT%2.2d:%2.2d:%s',
    [StrToInt(DateParts[0]), StrToInt(DateParts[1]), StrToInt(DateParts[2]),
      StrToInt(TimeParts[0]), StrToInt(TimeParts[1]), TimeParts[2]]);
  ISO := StringReplace(ISO, '+', '', [rfReplaceAll, rfIgnoreCase]);

  { datetime parse }
  try
    var DT: TDateTime := ISO8601ToDate(ISO, True);

    if SecondsBetween(DT, Now) >= 120 {2mins} then
    begin
      var Today: TDateTimeParts := Now;
      var Parts: TDateIntRec := Today.DateRec.AsInt;
      AlertEvent(etMessage, 'FROG!'#13#10);
      AvoidBusyWait(WAIT_50MS);

      AlertEvent(etAppError,
        format('meter has invalid date &\ time <%s>. attempting fix...!'#13#10,
          [DateTimeToStr(DT)]));

      { update date&time }
      SendCommand(AnsiString(format('%s %d,%d,%d', [KS_CMD_DATE_SET, Parts.Year, Parts.Month, Parts.Day])));
      AvoidBusyWait(QTR_SEC);
      SendCommand(AnsiString(format('%s %d,%d,%d', [KS_CMD_TIME_SET, Parts.Hour, Parts.Minutes, Parts.Seconds])));
      AlertEvent(etMessage, 'Invalid meter date & time corrected! '#13#10);
      Exit;
    end;
  except
    On E: Exception do
      AlertEvent(etAppException, format('Invalid ACAL date/time: %s <%s>'#13#10'%s'#13#10,
        [ISO, E.Message, E.StackTrace]));
  end;

  try
    try
      SendCommand(KS_CMD_ACAL_DATE);
      AwaitResponse(@DataRcvd, QTR_SEC);
      if not DataRcvd then Exit;

      SplitStr(Response.AsString, ',', DateParts);
      if Length(DateParts) <> 3 then Exit;

      if not TryStrToInt(Trim(DateParts[0]), Y) then Exit;
      if not TryStrToInt(Trim(DateParts[1]), M) then Exit;
      if not TryStrToInt(Trim(DateParts[2]), D) then Exit;

      SendCommand(KS_CMD_ACAL_TIME);
      AwaitResponse(@DataRcvd, QTR_SEC);
      if not DataRcvd then Exit;

      SplitStr(Response.AsString, ',', TimeParts);
      if Length(TimeParts) <> 3 then Exit;

      if not TryStrToInt(Trim(TimeParts[0]), H) then Exit;
      if not TryStrToInt(Trim(TimeParts[1]), N) then Exit;

      SecText := Trim(TimeParts[2]);
      SecText := StringReplace(SecText, '+', '', [rfReplaceAll]);

      { Pad seconds if instrument returns 9.000 instead of 09.000 }
      if (Length(SecText) > 0) and (Pos('.', SecText) > 0) and (Pos('.', SecText) = 2) then
        SecText := '0' +SecText
      else if Length(SecText) = 1 then
        SecText := '0' +SecText;

      ISO := Format('%.4d-%.2d-%.2dT%.2d:%.2d:%s', [Y, M, D, H, N, SecText]);

      try
        ACALStatus.LastCal := ISO8601ToDate(ISO, True);
        if (ACALStatus.Expired) then TUtils.HandleEvent(etMessage, 'meter ACAL expired!'#13#10, TUtils.RED)
        else
        begin
          TUtils.HandleEvent(etMessage, 'meter ACAL expires: ', TUtils.SILVER);
          TUtils.HandleEvent(etMessage, format('%s'#13#10,
            [DateTimeToStr(ACALStatus.LastCal)]), TUtils.UpdateLine(ulPartial, TUtils.GRAY));
        end;
      except
        on E: Exception do
          AlertEvent(etAppException, format('Invalid ACAL date/time: %s <%s>'#13#10'%s'#13#10,
            [ISO, E.Message, E.StackTrace]));
      end;
    except
      on E: Exception do
        AlertEvent(etAppException, format('ACAL date/time retrieval failed: %s'#13#10'%s'#13#10,
          [E.Message, E.StackTrace]));
    end;
  finally
    AlertEvent(etMessage, format('%s'#13#10, [StrTernary(DataRcvd, 'ok | ' +DateTimeToStr(ACALStatus.LastCal), 'failed!')]));
  end;
end;

function TMultiMeter.ParseMeterRead(const TempStr: String; var FltData: TArray<Double>; FmtResponse: Boolean = False): Boolean;
var
  S: String;
  SArr: TArray<String>;
  L, H, i, NveSign, PveSign, Sign: Integer;
begin
  Result := False;
  S := Trim(TempStr);
  if (S = '') or (Length(S) < 5) then Exit;

  { #279?...: for some reason }
  SplitStr(S, Delimiter, SArr);

  { cleanup arr[0] }
  L := Length(SArr);

  if L <> 0 then
  begin
    { correct|fix data in arr[0] }
    if S[1] = '#' then
    begin
      { check -ve }
      NveSign := FindDelimiter('-', SArr[0]);
      PveSign := FindDelimiter('+', SArr[0]);
      { check +ve }
      if (NveSign > 0) and (PveSign > 0) then
        Sign := Min(NveSign, PveSign)
      else Sign := IntTernary(PveSign > 0, PveSign, NveSign);

      if Sign <= 0 then Exit;
      Delete(SArr[0], 1, Sign -1);
    end;

    SetLength(FltData, L);

    for i := Low(SArr) to High(SArr) do
    begin
      Result := TryStrToFloat(SArr[i], FltData[i]);
      if not Result then break;

      if Config.Rounding then FltData[i] := RoundTo(FltData[i], -Config.ReadPrecision);
    end;

    if FmtResponse then
    begin
      Response.Clear;
      H := High(FltData);
      for i := Low(FltData) to H do
      begin
        if i >= H then S := format('%.3E', [FltData[i]])
        else S := format('%.3E, ', [FltData[i]]);
        Response.Append(S);
      end;
    end;
  end;
end;

function TMultiMeter.ParseMeterRead(const TempStr: String; var FltData: Double): Boolean;
var
  i: Integer;
  S: String;
  SArr: TArray<String>;
  FltVal, EVal: Double;
begin
  Result := False;
  if (TempStr = '') or (not TempStr.Contains('.')) then
  begin
    AlertEvent(etAppError, 'meter invalid or empty response received!'#13#10);
    Exit;
  end;

  S := '';
  FltData := 0.0;

  for i := 1 to Length(TempStr) do
  begin
    { check for annoying LF }
    if TempStr[i] = Char(#$A) then break;
    { otherwise, }
    if (CharInSet(TempStr[i], CharSet2)) then
      S := S + TempStr[i];
  end;

  { check for the annoying exp at end of string, delete it! }
  if (S[Length(S)] = 'E') then Delete(S, Length(S), Length(S));

  SplitStr(S, 'E', SArr);
  if Length(SArr) > 1 then
  begin
    { E notation to float }
    if TryStrToFloat(SArr[0], FltVal) then
    begin
      if TryStrToFloat(SArr[1], EVal) then
      begin
        FltVal := FltVal *Power(10, EVal);
        Result := True;
      end;
    end;

    if not Result then Exit;

    { precison | Rounding should be optional, for different reasons than calibration }
    if Config.Rounding then
      FltData := RoundTo(FltVal, -IntTernary(Config.ReadPrecision <> 0,
        Config.ReadPrecision, DEFAULT_READ_PRECISION))
    else FltData := FltVal;
  end;
end;

function TMultiMeter.ParseMeterRead(const TempStr: String; var FltData, StdDev: Double; MinMax: ITuple<Double, Double>): Boolean;
var
  S: String;
  FltVal: Double;    { '+1.20339622E+01;+1.24525158E-05' }
  SArr: TArray<String>;
begin
  Result := False;
  if (TempStr = '') or (not TempStr.Contains('.')) then
  begin
    AlertEvent(etAppError,
      format('Meter Recieved: %s: TempStr'#13#10,
        [StrTernary(TempStr <> EmptyString, TempStr, 'Emptpy Value')]));
    Exit;
  end;

  try
    FltData := 0;
    StdDev := 0;
    S := Trim(TempStr);

    SplitStr(S, Delimiter, SArr);
    if Length(SArr) < 2 then Exit;

    { parse data & sd }
    Result := TryStrToFloat(SArr[0], FltVal);
    if not Result then Exit;

    if Config.Rounding then FltData := RoundTo(FltVal, -Config.ReadPrecision)
    else FltData := FltVal;

    Result := TryStrToFloat(SArr[1], FltVal);
    if not Result then Exit;
    if Config.Rounding then StdDev := RoundTo(FltVal, -Config.ReadPrecision)
    else StdDev := FltVal;

    { more...? }
    if (Delimiter = ';') and (MinMax = nil) and (Length(SArr) < 4) then Exit;

    Result := TryStrToFloat(SArr[2], FltVal);
    if not Result then Exit;
    if Config.Rounding then MinMax.{Min}First := RoundTo(FltVal, -Config.ReadPrecision)
    else MinMax.First := FltVal;

    Result := TryStrToFloat(SArr[3], FltVal);
    if not Result then Exit;
    if Config.Rounding then MinMax.{Max}Second := RoundTo(FltVal, -Config.ReadPrecision)
    else MinMax.Second := FltVal;
  except
    on E: Exception do
      TUtils.HandleEvent(etAppException, format('ParseMeterRead: %s'#13#10'%s'#13#10,
        [E.Message, E.StackTrace]));
  end;
end;

procedure TMultiMeter.ParseTemperature(const TempStr: String);
var
  StrVal: String;
  StrArr : TArray<String>;
  EValue : Integer;
  FValue : Single;
begin
  if (not TempStr.Contains('.')) or (TempStr = '') then
    Exit;

  StrVal := '';

  { check first char }
  if TempStr[1] = '+' then StrVal := Copy(TempStr, 2, Length(TempStr) -1)
  else StrVal := TempStr;

  if Length(StrVal) > 0 then
  begin
    SplitStr(StrVal, 'E', StrArr);

    if Length(StrArr) >= 2 then
    begin
      if TryStrToInt(StrArr[1], EValue) then
      begin
        if TryStrToFloat(StrArr[0], FValue) then
        begin
          FValue := FValue *Power(10, EValue);
          ACALStatus.Temp := FValue;

          ACALStatus.OK := True;
        end;
      end;
    end;
  end;
end;

function TMultiMeter.Read(var FltData: Double; Timeout: single): Boolean;
var
  Watch: TStopwatch;  { caller-experienced read time :: SetReadCount + READ + response }
begin
  AlertEvent(etMessage, 'meter reading in progress... ', False, TUtils.GRAY);
  Result := False;
  FltData := 0.0;
  Status.Working := True;
  Status.ReadTimeout := Round(Timeout) +1;
  Watch := TStopwatch.StartNew;

  try
    case Config.Identity of
      AG34410A, KS34465A, KS34470A:
      begin
        SetReadCount(1);
        SendCommand(KS_CMD_READ);
        WaitForSingleObject(RxEvent, Round(Timeout *1000));
        Watch.Stop;

        if DataRcvd then
        begin
          Result := ParseMeterRead(Response.AsString, FltData);

          { live sample :: debug and release alike <the operator's live readout> }
          case MaccorMode of
            rmCurrent:
            begin
              if RoundFloat(DebugShunt, -12) <> 0 then
                AlertEvent(etMessage, format('%s %s %s (%s) [%06.1fms]'#13#10,
                  [Response.AsString, APPROX, FormatFloat('0.000000', Abs(FltData /DebugShunt)),
                    StrTernary(MaccorMode = rmCurrent, 'A', 'V'), Watch.Elapsed.TotalMilliseconds]), False, TUtils.SILVER)
              else AlertEvent(etMessage, format('%s [%06.1fms]'#13#10, [Response.AsString, Watch.Elapsed.TotalMilliseconds]), False, TUtils.SILVER);
            end;

            rmVoltage: AlertEvent(etMessage, format('%s [%06.1fms]'#13#10, [FormatFloat('0.000000 V', FltData), Watch.Elapsed.TotalMilliseconds]), False, TUtils.SILVER);
          end;
        end

        { handle events }
        else AlertEvent(etAppError, format('meter <READ> operation timed-out! [%06.1fms]'#13#10, [Watch.Elapsed.TotalMilliseconds]));
      end;

      FL8508A, FL8588A:
      begin
        Result := ReadGpib(FltData, Timeout);
        Watch.Stop;
        if Result then
          AlertEvent(etMessage, format('%s [%06.1fms]'#13#10, [FloatToStr(FltData, TFormatSettings.Invariant),
            Watch.Elapsed.TotalMilliseconds]), False, TUtils.SILVER)
        else AlertEvent(etAppError, format('meter <READ> operation timed-out! [%06.1fms]'#13#10, [Watch.Elapsed.TotalMilliseconds]));
      end;
    end;
  finally
    Status.Working := False;
  end;
end;

function TMultiMeter.Read(var FltData: TArray<Double>; Cnt: SmallInt; Timeout: Single): Boolean;
begin
  Result := False;
  if Status.Working then Exit;
  Status.Working := True;

  try
    if IsGpib then Exit(ReadGpibArray(FltData, Max(Cnt, 1), Timeout));

    if Cnt <= 0 then
    begin
      SetLength(FltData, 1);
      Result := Read(FltData[0], Timeout);
    end

    else
    begin
      AlertEvent(etMessage, 'meter reading in progress...'#13#10);
      if Timeout < 3 then Timeout := 3;
      Status.ReadTimeout := Round(Timeout);

      { update read count }
      SetReadCount(Cnt);

      { init. read operation : no-response! awful!!! }
      SendCommand(KS_CMD_INIT); AvoidBusyWait(Timeout +(Cnt /5));
      SendCommand(AnsiString(format('%s %d', [KS_CMD_READN, Cnt])));
      AwaitResponse(@DataRcvd, Timeout);

      if DataRcvd then
      begin
        Delimiter := ',';
        Result := ParseMeterRead(Response.AsString, FltData);
        AlertEvent(etMessage, format('meter <READ> completed. [%s]'#13#10, [Response.AsString]), True);
      end;
    end;
  finally
    Status.Working := False;
  end;
end;

function  TMultiMeter.Read(var FltData: TArray<Double>; var Avg, Dev: Single; Cnt: SmallInt; Timeout: Single = 5.0): Boolean;
var
  L: Integer;
begin
  Result := False;
  Status.Working := True;

  try
    if IsGpib then
    begin
      Result := ReadGpibArray(FltData, Max(Cnt, 1), Timeout);
      if Result then
      begin
        Avg := Mean(FltData);
        if Length(FltData) > 1 then Dev := StdDev(FltData) else Dev := 0;
      end;
      Exit;
    end;

    if Cnt <= 0 then
    begin
      SetLength(FltData, 1);
      Result := Read(FltData[0], Timeout);
      Avg := FltData[0];
      Dev := 0;
    end

    else
    begin
      AlertEvent(etMessage, 'meter reading in progress...'#13#10);

      { mandate! Assert! }
      if Timeout < 5 then Timeout := 5;
      { update read count }
      SetReadCount(Cnt);

      { init. read operation }
      SendCommand(KS_CMD_INIT); AvoidBusyWait(Timeout +(Cnt /2));
      SendCommand(AnsiString(format('%s %d', [KS_CMD_READN, Cnt])));
      AwaitResponse(@DataRcvd, Timeout);

      Delimiter := ',';

      if DataRcvd then
      begin
        Result := ParseMeterRead(Response.AsString, FltData, True);

        L := Length(FltData);
        if Result and (L > 1) then
        begin
          Avg := Sum(FltData) /L;
          Dev := StdDev(FltData);
          AlertEvent(etMessage, format('meter <READ> completed. [%s]'#13#10, [Response.AsString]), True);
        end
        else
          AlertEvent(etAppError, format('meter <READ> partial fail. [%s]'#13#10, [Response.AsString]));
      end;
    end;
  finally
    Status.Working := False;
  end;
end;

procedure TMultiMeter.ReadAsync(FltData, StdDev: PDouble; ReadOK: PBoolean;
  Timeout: single);
begin
  Status.Working := True;

  TTask.Create(
    procedure
    var
      OK: Boolean;
    begin
      FltData^ := 0.0;
      StdDev^ := 0.0;
      ReadOK^ := False;
      if Timeout < 3 then Timeout := 3;

      try
        case Config.Identity of
          AG34410A: ;
          KS34465A, KS34470A:
          begin
            Delimiter := ';';

            { init. read operation }
            SendCommand(KS_CMD_INIT); AwaitResponse(@DataRcvd, Timeout);
            { send read command }
            SendCommand(KS_CMD_READ_SD); AwaitResponse(@DataRcvd, Timeout);
            { if response! parse received data }
            if DataRcvd then
            begin
              OK := ParseMeterRead(Response.AsString, FltData^, StdDev^);
              if ReadOK <> nil then ReadOK^ := OK;
            end
            else
                AlertEvent(etAppError, 'meter: <READ> operation timed-out!'#13#10);
          end;

          FL8508A, FL8588A:
          begin
            OK := ReadGpibStats(0, Timeout, FltData^, StdDev^);
            if ReadOK <> nil then ReadOK^ := OK;
          end;
        end;
      finally
        Status.Working := False;
      end;
    end
  ).Start;
end;

procedure TMultiMeter.ReadAsync(FltData, StdDev, MinValue, MaxValue: PDouble;  ReadOK: PBoolean; Timeout: Single);
begin
  TTask.Create(
    procedure
    var
      MinMax: ITuple<Double, Double>;
      OK: Boolean;
    begin
      Status.Working := True;
      FltData^ := 0.0;
      StdDev^ := 0.0;
      MaxValue^:= 0.0;
      MinValue^ := 0.0;
      if Timeout < 3 then Timeout := 3;

      try
        case Config.Identity of
          AG34410A: ;
          KS34465A, KS34470A:
          begin
            Delimiter := ',';

            SendCommand(KS_CMD_INIT); AwaitResponse(@DataRcvd, Timeout);
            { send read command }
            SendCommand(KS_CMD_READ_ALL); AwaitResponse(@DataRcvd, Timeout);
            { if response! parse received data }
            if DataRcvd then
            begin
              MinMax := TTuple<Double, Double>.Create(0.0, 0.0);
              OK := ParseMeterRead(Response.AsString, FltData^, StdDev^, MinMax);

              MinValue^ := MinMax.First;
              MaxValue^ := MinMax.Second;
              if ReadOK <> nil then ReadOK^ := OK;
            end

            else
              { handle events }
                AlertEvent(etAppError, 'meter <READ> operation timed-out!'#13#10);
          end;

          FL8508A, FL8588A:
          begin
            OK := ReadGpibStats(0, Timeout, FltData^, StdDev^, MinValue, MaxValue);
            if ReadOK <> nil then ReadOK^ := OK;
          end;
        end;
      finally
        Status.Working := False;
      end;
    end
  ).Start;
end;

function TMultiMeter.ReadEx(var FltData: TArray<Double>; var Avg, StdDev: Single; const Count: Byte; Interval: Integer): Boolean;
var
  Data: Double;
begin
  Avg := 0;
  Result := ReadEx(FltData, Data, Count);
  if Result then
  begin
    Avg := Sum(FltData)/ Count;
    StdDev := Single(Data);
  end;
end;

function TMultiMeter.ReadEx(var FltData: TArray<Double>; var StdDev: Double;
  const Count: Byte; Interval: Integer): Boolean;
var
  Data: Double;
  i, x: Integer;
begin
  x := 0;
  StdDev := 0;
  SetLength(FltData, Count);

  for i := 0 to Count -1 do
  begin
    if Read(Data) then
    begin
      FltData[i] := Data;
      Inc(x);
    end;
    TThread.Sleep(Interval);
  end;

  Result := (Count = x);

  if Result then
  begin
    if Count > 1 then StdDev := Math.StdDev(FltData)
    else StdDev := 0;
  end;
end;

function TMultiMeter.ReadEx(var FltData, StdDev: Double; const Count: Byte;
  Interval: Integer): Boolean;
var
  i, x: Integer;
  Data: TArray<Double>;
begin
  x := 0;
  SetLength(Data, Count);

  for i := 0 to Count -1 do
  begin
    if Read(FltData) then
    begin
      Data[i] := FltData;
      Inc(x);
    end;
    TThread.Sleep(Interval);
  end;

  Result := (Count =  x);
  if Result then
  begin
    FltData := Sum(Data) /Count;
    if Count > 1 then StdDev := Math.StdDev(Data)
    else StdDev := 0;
  end;
end;

procedure TMultiMeter.Reset;
begin
  if IsGpib then
  begin
    GpibWrite(KS_CMD_RST);
    AvoidBusyWait(ONE_SEC);
    GpibWrite(KS_CMD_CLR);
    GpibWrite(FL_CMD_TRIG_EXT);
    Exit;
  end;

  AvoidBusyWait(WAIT_50MS *3);
  SendCommand(KS_CMD_RST); AwaitResponse(@DataRcvd, 0.05);
  SendCommand(KS_CMD_CLR); AwaitResponse(@DataRcvd);
end;

function TMultiMeter.Read(var FltData: String; Timeout: single): Boolean;
var
  FltVal: Double;
begin
  Status.Working := True;
  try
    FltData := '';
    Result := Read(FltVal, Timeout);
    if Result then
      FltData := FormatFloat('0', FltVal);
  finally
    Status.Working := False;
  end;
end;

function TMultiMeter.Read(var FltData, StdDev: Double; Timeout: single): Boolean;
begin
  Status.Working := True;
  Result := False;
  FltData := 0.0;
  StdDev := 0.0;
  if Timeout < 3 then Timeout := 3;
  Status.ReadTimeout := Round(Timeout) +1;

  try
    case Config.Identity of
      AG34410A:
        Result := ReadEx(FltData, StdDev, Min(LastRdCnt, 5));

      KS34465A, KS34470A:
      begin
        Delimiter := ';';
        AlertEvent(etMessage, 'meter reading in progress...'#13#10);

        { init. read operation }
        SendCommand(KS_CMD_INIT); AwaitResponse(@DataRcvd, Timeout);
        { send read command }
        SendCommand(KS_CMD_READ_SD); AwaitResponse(@DataRcvd, Timeout);
        { if response! parse received data }
        if DataRcvd then
        begin
          Result := ParseMeterRead(Response.AsString, FltData, StdDev);
          AlertEvent(etMessage, format('meter <READ> completed. [%.6f, %.6f]'#13#10, [FltData, StdDev]), True);
        end

        else { handle events }
          AlertEvent(etAppError, 'meter: <READ> operation timed-out!'#13#10);
      end;

      FL8508A, FL8588A: Result := ReadGpibStats(0, Timeout, FltData, StdDev);
    end;
  finally
    Status.Working := False;
  end;
end;

function TMultiMeter.Read(var FltData, StdDev, MinValue, MaxValue: Double; Timeout: Single): Boolean;
var
  MinMax: ITuple<Double, Double>;
begin
  Status.Working := True;
  Result := False;
  FltData := 0.0;
  StdDev := 0.0;
  if Timeout < 3 then Timeout := 3;
  Status.ReadTimeout := Round(Timeout) +1;

  try
    case Config.Identity of
      AG34410A: AlertEvent(etAppError, 'meter command is not available!'#13#10);
      KS34465A, KS34470A:
      begin
        Delimiter := ',';

        SendCommand(KS_CMD_INIT); AwaitResponse(@DataRcvd, Timeout);
        { send read command }
        SendCommand(KS_CMD_READ_ALL); AwaitResponse(@DataRcvd, ReadInProgress, Timeout);
        { if response! parse received data }
        if DataRcvd then
        begin
          MinMax := TTuple<Double, Double>.Create(0.0, 0.0);
          Result := ParseMeterRead(Response.AsString, FltData, StdDev, MinMax);
          MinValue := MinMax.First;
          MaxValue := MinMax.Second;
        end

        else { handle events }
          AlertEvent(etAppError, 'meter <READ> operation timed-out!'#13#10);
      end;

      FL8508A, FL8588A: Result := ReadGpibStats(0, Timeout, FltData, StdDev, @MinValue, @MaxValue);
    end;
  finally
    Status.Working := False;
  end;
end;

{$REGION ' GPIB METERS <Fluke 8508A, 8588A in 8508A emulation> '}
function TMultiMeter.IsGpib: Boolean;
begin
  Result := Config.Identity in TMeterUtils.GPIB_METERS;
end;

function TMultiMeter.GpibWrite(const Cmd: AnsiString): Boolean;
begin
  Result := Assigned(Bus) and Bus.Write(GpibAddr, Cmd);
end;

function TMultiMeter.ConnectGpib: Boolean;
var
  Model, Serial: String;
begin
  Result := False;
  if not Assigned(Bus) then
  begin
    AlertEvent(etAppError, 'meter has no gpib gateway :: create it with a gpib address'#13#10);
    Exit;
  end;

  AlertEvent(etMessage, format('connecting to meter at gpib address %d... '#13#10, [GpibAddr]));
  if Bus.Connect then
  begin
    AddrStr := Bus.Address;               { the ping thread watches the gateway }
    Reset;
    Result := GetMeterIdentity(Model, Serial);
    if Result then AlertEvent(etMessage, format('meter identity: %s %s'#13#10, [Model, Serial]))
    else AlertEvent(etAppError, format('no reply from gpib address %d'#13#10, [GpibAddr]));
    if Result then MeterPing;
  end;

  AlertEvent(TAppEventType(IntTernary(Result, 0, 1)), StrTernary(Result, 'meter connected!', 'meter failed to connect!')+#13#10, False, IntTernary(Result, 1, 0));
  Status.Connected := Result;
end;

{ one triggered reading <X?>; the wait is never shorter than a high-resolution conversion needs }
function TMultiMeter.ReadGpib(var FltData: Double; Timeout: Single): Boolean;
var
  Reply: String;
begin
  Result := Assigned(Bus)
    and Bus.Query(GpibAddr, FL_CMD_READ, Reply, Max(Round(Timeout *1000), FL_READ_TIMEOUT_MS))
    and TryStrToFloat(Trim(Reply), FltData, TFormatSettings.Invariant);
end;

function TMultiMeter.ReadGpibArray(var Data: TArray<Double>; Count: Integer; Timeout: Single): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Count <= 0 then Count := 1;
  SetLength(Data, Count);

  for I := 0 to Count -1 do
    if not ReadGpib(Data[I], Timeout) then
    begin
      AlertEvent(etAppError, format('meter <READ> %d of %d failed!'#13#10, [I +1, Count]));
      Exit;
    end;

  Result := True;
end;

{ the 8508A keeps no statistics :: Count readings <0 = the count of the last ConfigureRead>, reduced here }
function TMultiMeter.ReadGpibStats(Count: Integer; Timeout: Single; out Avg, Dev: Double; Lo, Hi: PDouble): Boolean;
var
  Data: TArray<Double>;
begin
  Avg := 0;
  Dev := 0;
  if Count <= 0 then Count := Max(GpibSamples, 1);

  Result := ReadGpibArray(Data, Count, Timeout);
  if not Result then Exit;

  Avg := Mean(Data);
  if Count > 1 then Dev := Math.StdDev(Data);
  if Lo <> nil then Lo^ := Math.MinValue(Data);
  if Hi <> nil then Hi^ := Math.MaxValue(Data);
end;
{$ENDREGION}

{$REGION ' PSEUDO-EVENTS '}
procedure TMultiMeter.ACALInProgress;
begin
  if (GetTickCount64 -ACALCtrl.LastCall) >= ONE_SEC then
  begin
    AlertEvent(etMessage, format('meter ACAL busy... [%d seconds] to timeout'#13#10, [ACALCtrl.Time]), True);
    if ACALCtrl.Time > 0 then Dec(ACALCtrl.Time);
    ACALCtrl.LastCall := GetTickCount64;
  end;
end;

procedure TMultiMeter.ReadInProgress;
begin
  if (GetTickCount64 -Status.ReadBusyLastCall) >= ONE_SEC then
  begin
    AlertEvent(etMessage, format('meter reading... [%d seconds] to timeout'#13#10, [Status.ReadTimeout]), True);
    if Status.ReadTimeout > 0 then Dec(Status.ReadTimeout);
    Status.ReadBusyLastCall := GetTickCount64;
  end;
end;
{$ENDREGION}
{$REGION' EVENTS <MESSAGES & NETWORK!> '}
procedure TMultiMeter.HandleExceptionEvent(const E: Exception);
begin
  if not Assigned(EventHandler) then Exit;
  ZeroMemory(@Event, SizeOf(TAppEvent));
  try
    Event.TimeStamp := Now;
    Event.Reason := etAppException;
    Event.Code := GetLastError;
    Event.Msg := format('%s'#13#10'%s'#13#10, [E.Message, E.StackTrace]);
    EventHandler(@Event);
  finally
    Event.Msg := '';
  end;
end;

procedure TMultiMeter.AlertEvent(const Evt: TAppEventType; const Msg: String; UseLastLine: Boolean; Code: Integer);
begin
  if not Assigned(EventHandler) then Exit;
  Event := Default(TAppEvent);

  try
    Event.TimeStamp := Now;
    Event.Code := Code;
    Event.Reason := Evt;
    Event.Msg := Msg;
    Event.Overwrite := UseLastLine;
    EventHandler(@Event);
  finally
    Event.Msg := '';
  end;
end;

function TMultiMeter.Online: Boolean;
begin
  Result := Status.Online;
end;

{$REGION ' SOCKET-DATA '}

procedure TMultiMeter.OnTcpDataRecvd(const Payload: PSocketPayload);
begin
  { get recv'd data }
  Response.Data.AsBytes := Payload^.AsBytes;
  { clear trailing garbage! }
  Response.Strip(Payload^.Size);

  if Payload^.Size > Length(Response.Data.AsBytes) then
    AlertEvent(etMessage, format('receive buffer overflow by %d bytes'#13#10,
      [Payload^.Size -Length(Response.Data.AsBytes)]));

  DataRcvd := (Payload^.Size > 0);
  if DataRcvd and (RxEvent <> 0) then SetEvent(RxEvent);
end;

procedure TMultiMeter.OnUdpDataRecvd(const Packet: PSocketPayload);
begin

end;
{$ENDREGION}
{$ENDREGION}

initialization
  TMeterUtils.ACALStat := @NoACAL;

end.
