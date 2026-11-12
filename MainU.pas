unit MainU;

{
  AutoCalibrator 528LB test application: hosts the tabs (Controls, Calibration, Firmware, Calibration Record,
  Configurations with its sub-sheets),
  the one shared log, and the board address with its Start/Stop button. The frames are created here at
  runtime; the board object is owned by the Controls tab (Connect / Disconnect) and handed to the other two
  through OnBoardChanged, which also keeps the Start/Stop button and the address box in step.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Buttons, CommonsU,
  AutoCalBoardU, ControlsFrameU, CalibrationFrameU, FirmwareFrameU, RecordFrameU, OhmLabsFrameU, FlukeMetersU,
  FlukeFrameU, CertificateFrameU, DebugTapU;

type
  TMainForm = class(TForm)
    Pages: TPageControl;
    ControlsTab: TTabSheet;
    CalibrationTab: TTabSheet;
    FirmwareTab: TTabSheet;
    RecordTab: TTabSheet;
    ConfigTab: TTabSheet;
    ConfigPages: TPageControl;
    OhmLabsTab: TTabSheet;
    Fluke8508Tab: TTabSheet;
    Fluke8588Tab: TTabSheet;
    CertificateTab: TTabSheet;
    Memo: TRichEdit;
    BottomPanel: TPanel;
    CopyBtn: TButton;
    ClearBtn: TButton;
    Splitter: TSplitter;
    StartBtn: TSpeedButton;
    AddrEdit: TEdit;
    procedure FormCreate(Sender: TObject);
    procedure FormCanResize(Sender: TObject; var NewWidth, NewHeight: Integer; var Resize: Boolean);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure CopyBtnClick(Sender: TObject);
    procedure ClearBtnClick(Sender: TObject);
    procedure StartBtnClick(Sender: TObject);
    procedure PagesChange(Sender: TObject);
    procedure PagesChanging(Sender: TObject; var AllowChange: Boolean);

  private
    ControlsFrame: TControlsFrame;
    CalibrationFrame: TCalibrationFrame;
    FirmwareFrame: TFirmwareFrame;
    RecordFrame: TRecordFrame;
    OhmLabsFrame: TOhmLabsFrame;               { Configurations > Ohm Labs }
    FlukeFrames: array [TFlukeModel] of TFlukeFrame;    { Configurations > Fluke 8508A, Fluke 8588A }
    CertificateFrame: TCertificateFrame;       { Configurations > Certificate }
    Announce: TAnnounceListener;
    ProgPos, ProgLen: Integer;          { the one in-place progress line of the memo; ProgPos = -1 until it exists }
    ProgKey: String;

    procedure OnEvent(const E: PAppEvent);
    { one coloured run at the end of the log }
    procedure Put(const S: String; const Color: TColor; const Bold: Boolean = False);
    { a '>> address' / '<< address' block from the board: coloured header, coloured JSON, blank line after }
    procedure PutExchange(const Msg: String);
    { JSON text token by token: keys, strings, numbers, true/false/null and punctuation each in their colour }
    procedure PutJson(const S: String);
    procedure ProgressLine(const Key, Text: String);
    procedure OnBoardChanged(const Board: TAutoCalBoard);
    { Start/Stop caption and colour, address box locked while connected }
    procedure ShowLink(const Connected: Boolean);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

const
  { log colours, TColor is $00BBGGRR }
  CLR_SEND    = TColor($00A04000);    { '>> address' header, blue }
  CLR_RECV    = TColor($00107020);    { '<< address' header, green }
  CLR_KEY     = TColor($00A55104);    { "member": }
  CLR_STRING  = TColor($001515A3);    { "value" }
  CLR_NUMBER  = TColor($00589809);
  CLR_KEYWORD = TColor($00FF0000);    { true false null }
  CLR_PUNCT   = TColor($00606060);    { braces, brackets, colons, commas }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  { global event router: every unit logs through TUtils.HandleEvent }
  TUtils.SetEventHandler(OnEvent);
  FormatJuliusMemo(Memo);
  Memo.ReadOnly := False;
  Memo.Clear;
  ProgPos := -1;

  ControlsFrame := TControlsFrame.Create(Self);
  ControlsFrame.Parent := ControlsTab;
  ControlsFrame.Align := alClient;
  ControlsFrame.OnBoardChanged := OnBoardChanged;

  CalibrationFrame := TCalibrationFrame.Create(Self);
  CalibrationFrame.Parent := CalibrationTab;
  CalibrationFrame.Align := alClient;
  { wired here, not in the dfm: the IDE dropped OnChange from the dfm on a re-save and the tab went dead }
  Pages.OnChange := PagesChange;
  Pages.OnChanging := PagesChanging;

  FirmwareFrame := TFirmwareFrame.Create(Self);
  FirmwareFrame.Parent := FirmwareTab;
  FirmwareFrame.Align := alClient;
  FirmwareFrame.ProgressLine := procedure(Key, Text: String) begin ProgressLine(Key, Text); end;

  RecordFrame := TRecordFrame.Create(Self);
  RecordFrame.Parent := RecordTab;
  RecordFrame.Align := alClient;
  FirmwareFrame.OnBusyChanged := procedure begin RecordFrame.EnableButtons; end;
  { a shunt measured and accepted on the Calibration tab lands in the record, ready for its Write }
  CalibrationFrame.OnShuntAccepted := procedure(const Index: Integer; const Ohms, UncPpm: Double)
    begin
      RecordFrame.AcceptShunt(Index, Ohms, UncPpm);
    end;
  { and the value the record held before, for the certificate's Prev. Value }
  CalibrationFrame.OnShuntPrevious := function(const Index: Integer): Double
    begin
      Result := RecordFrame.PreviousOf(Index);
    end;

  { Configurations: one sub-sheet per kind of reference data, each its own frame over the one config file }
  OhmLabsFrame := TOhmLabsFrame.Create(Self);
  OhmLabsFrame.Parent := OhmLabsTab;
  OhmLabsFrame.Align := alClient;

  { one frame class, a sheet per meter type: created unowned and named apart before the form takes them over }
  for var Model := Low(TFlukeModel) to High(TFlukeModel) do
  begin
    var Frame := TFlukeFrame.Create(nil);
    Frame.Name := 'FlukeFrame' + FLUKE_MODEL_NAME[Model];
    InsertComponent(Frame);
    if Model = fm8508A then Frame.Parent := Fluke8508Tab else Frame.Parent := Fluke8588Tab;
    Frame.Align := alClient;
    Frame.Open(Model);
    FlukeFrames[Model] := Frame;
  end;
  CertificateFrame := TCertificateFrame.Create(Self);
  CertificateFrame.Parent := CertificateTab;
  CertificateFrame.Align := alClient;
  ConfigPages.ActivePage := OhmLabsTab;

  Pages.ActivePage := ControlsTab;
  Constraints.MinHeight := Height;
  Announce := TAnnounceListener.Create;
  ShowLink(False);
end;

procedure TMainForm.OnBoardChanged(const Board: TAutoCalBoard);
begin
  { first: a run still going is stopped and its relays released while the board is still there }
  CalibrationFrame.Board := Board;
  FirmwareFrame.Board := Board;
  RecordFrame.Board := Board;
  ShowLink(Assigned(Board));
end;

procedure TMainForm.ShowLink(const Connected: Boolean);
begin
  AddrEdit.Enabled := not Connected;
  if Connected then
  begin
    StartBtn.Caption := 'Stop';
    StartBtn.Font.Color := clRed;
  end
  else
  begin
    StartBtn.Caption := 'Start';
    StartBtn.Font.Color := clWindowText;
  end;
end;

procedure TMainForm.StartBtnClick(Sender: TObject);
begin
  { the board carries the current path of a run: it stays until the run is stopped }
  if ControlsFrame.Connected and CalibrationFrame.Busy then
  begin
    CalibrationFrame.Notice('A current is running: Stop it before disconnecting the board');
    Exit;
  end;

  if ControlsFrame.Connected then ControlsFrame.Disconnect
  else
  begin
    ControlsFrame.Connect(AddrEdit.Text);
    CalibrationFrame.ErrLbl.Caption := '';
  end;
end;

{ the tester engine runs only while the Calibration tab is the open one: started on entering, stopped on leaving }
procedure TMainForm.PagesChange(Sender: TObject);
begin
  if Pages.ActivePage = CalibrationTab then CalibrationFrame.Activate
  else CalibrationFrame.Shutdown;

end;

{ a running current keeps the operator on the Calibration tab until Stop }
procedure TMainForm.PagesChanging(Sender: TObject; var AllowChange: Boolean);
begin
  AllowChange := not CalibrationFrame.Busy;
  if not AllowChange then CalibrationFrame.Notice('A current is running: Stop it before leaving this tab');
end;

procedure TMainForm.OnEvent(const E: PAppEvent);
begin
  { a message that arrives while the form is being torn down has no log left to go to }
  if E = nil then Exit;
  Tap(E^.Msg);                                { the debug tap gets every line, shown or not }
  if csDestroying in ComponentState then Exit;
  ProgPos := -1;                             // a normal line ends any in-place progress line
  Memo.SelStart := Memo.GetTextLen;
  if E^.Msg.StartsWith('>> ') or E^.Msg.StartsWith('<< ') then PutExchange(E^.Msg)
  else Put(E^.Msg, clWindowText);
  Memo.Perform(EM_SCROLLCARET, 0, 0);
end;

procedure TMainForm.Put(const S: String; const Color: TColor; const Bold: Boolean);
begin
  Memo.SelAttributes.Color := Color;
  if Bold then Memo.SelAttributes.Style := [fsBold]
  else Memo.SelAttributes.Style := [];
  Memo.SelText := S;
end;

{ TAutoCalBoard logs a request as '>> address'#13#10 + JSON + #13#10 and a reply as '<< address' likewise;
  the trailing blank line keeps each request and each reply apart from whatever follows }
procedure TMainForm.PutExchange(const Msg: String);
var
  Header, Body: String;
begin
  var P := Pos(#13#10, Msg);
  if P = 0 then
  begin
    Header := Msg;
    Body := '';
  end
  else
  begin
    Header := Copy(Msg, 1, P +1);
    Body := Copy(Msg, P +2, MaxInt);
  end;

  Memo.Perform(WM_SETREDRAW, 0, 0);
  try
    if Header.StartsWith('>>') then Put(Header, CLR_SEND, True)
    else Put(Header, CLR_RECV, True);
    PutJson(Body);
    if not Body.EndsWith(#13#10) then Put(#13#10, clWindowText);
    Put(#13#10, clWindowText);
  finally
    Memo.Perform(WM_SETREDRAW, 1, 0);
  end;
  Memo.Invalidate;
end;

procedure TMainForm.PutJson(const S: String);
var
  I, N, Start: Integer;
  Run, Ident: String;
  RunClr: TColor;

  procedure Flush;
  begin
    if Run <> '' then Put(Run, RunClr);
    Run := '';
  end;

  { consecutive tokens of one colour go out as one run }
  procedure Add(const T: String; const Clr: TColor);
  begin
    if Clr <> RunClr then
    begin
      Flush;
      RunClr := Clr;
    end;
    Run := Run + T;
  end;

  { a string followed by ':' names a member }
  function IsKey(From: Integer): Boolean;
  begin
    while (From <= N) and (S[From] <= ' ') do Inc(From);
    Result := (From <= N) and (S[From] = ':');
  end;

begin
  N := Length(S);
  I := 1;
  Run := '';
  RunClr := CLR_PUNCT;

  while I <= N do
  begin
    Start := I;
    case S[I] of
      '"':
      begin
        Inc(I);
        while (I <= N) and (S[I] <> '"') do
        begin
          if S[I] = '\' then Inc(I);
          Inc(I);
        end;
        if I <= N then Inc(I);                { closing quote }
        if IsKey(I) then Add(Copy(S, Start, I -Start), CLR_KEY)
        else Add(Copy(S, Start, I -Start), CLR_STRING);
      end;

      '0'..'9', '-':
      begin
        while (I <= N) and CharInSet(S[I], ['0'..'9', '-', '+', '.', 'e', 'E']) do Inc(I);
        Add(Copy(S, Start, I -Start), CLR_NUMBER);
      end;

      'a'..'z', 'A'..'Z', '_':
      begin
        while (I <= N) and CharInSet(S[I], ['a'..'z', 'A'..'Z', '0'..'9', '_']) do Inc(I);
        Ident := Copy(S, Start, I -Start);
        if (Ident = 'true') or (Ident = 'false') or (Ident = 'null') then Add(Ident, CLR_KEYWORD)
        else Add(Ident, clWindowText);        { not JSON after all (a raw reply that did not parse) }
      end;
    else
      Inc(I);
      Add(S[Start], CLR_PUNCT);
    end;
  end;

  Flush;
end;

{ one line that is rewritten in place while Key stays the same; a different key or any normal line starts a new one }
procedure TMainForm.ProgressLine(const Key, Text: String);
begin
  Memo.Perform(WM_SETREDRAW, 0, 0);
  try
    if (ProgPos < 0) or (Key <> ProgKey) then
    begin
      Memo.SelStart := Memo.GetTextLen;
      ProgPos := Memo.SelStart;
      ProgKey := Key;
      Put(Text + #13#10, clWindowText);
    end
    else
    begin
      Memo.SelStart := ProgPos;
      Memo.SelLength := ProgLen;
      Memo.SelText := Text;
    end;

    ProgLen := Length(Text);
    Memo.SelStart := Memo.GetTextLen;
  finally
    Memo.Perform(WM_SETREDRAW, 1, 0);
  end;

  Memo.Perform(EM_SCROLLCARET, 0, 0);
  Memo.Invalidate;
end;

procedure TMainForm.CopyBtnClick(Sender: TObject);
begin
  CopyToClipBrd(Memo.Text);
end;

procedure TMainForm.ClearBtnClick(Sender: TObject);
begin
  Memo.Clear;
  ProgPos := -1;
end;

procedure TMainForm.FormCanResize(Sender: TObject; var NewWidth, NewHeight: Integer; var Resize: Boolean);
begin
  if not Visible then Exit;
  Resize := (NewHeight <> Height) and (Width = NewWidth);
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  { never close mid-flash: ask it to stop, and close once it has }
  if FirmwareFrame.Flashing then
  begin
    FirmwareFrame.CancelFlash;
    TUtils.HandleEvent(etMessage, 'Flash in progress: cancelling, close again when it has stopped'#13#10);
    CanClose := False;
    Exit;
  end;

  { no exit under current: the operator ends the run with Stop }
  if CalibrationFrame.Busy then
  begin
    Pages.ActivePage := CalibrationTab;
    CalibrationFrame.Notice('A current is running: Stop it before closing the application');
    CanClose := False;
    Exit;
  end;

  { relays released before the board goes, then the tester engine is stopped }
  CalibrationFrame.Shutdown;
  CalibrationFrame.CloseMeters;
  ControlsFrame.Disconnect;
  FreeAndNil(Announce);
  CanClose := True;
end;

Initialization
  ReportMemoryLeak;

end.
