unit ControlsFrameU;

{ Controls tab: owns the board connection, drives its relays and supplies, reset. UI only: every action is a
  TAutoCalBoard call. The address box and the Start/Stop button live on the main form, which calls Connect /
  Disconnect and mirrors the state it gets back through OnBoardChanged }

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.CommCtrl, System.SysUtils, System.Classes, System.UITypes, Vcl.Graphics, Vcl.Controls,
  Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, Vcl.ComCtrls, CommonsU, AutoCalProtocolU, AutoCalBoardU;

type
  TBoardChanged = reference to procedure(const Board: TAutoCalBoard);

  { the state list is sized to hold every row: no scrollbar, ever (the no-scroll style also stops the horizontal one) }
  TListView = class(Vcl.ComCtrls.TListView)
    protected
      procedure CreateParams(var Params: TCreateParams); override;
  end;

  TControlsFrame = class(TFrame)
    TopPanel: TPanel;
    StatusBtn: TSpeedButton;
    VChanRBG: TRadioGroup;
    IChanRBG: TRadioGroup;
    VShuntRBG: TRadioGroup;
    IShuntRBG: TRadioGroup;
    LowerPanel: TPanel;
    SupplyGB: TGroupBox;
    FanBox: TCheckBox;
    VSrcBox: TCheckBox;
    DPSBox: TCheckBox;
    ResetGB: TGroupBox;
    ResetChansBtn: TSpeedButton;
    ResetShuntsBtn: TSpeedButton;
    ResetAllBtn: TSpeedButton;
    RestartBtn: TSpeedButton;
    StateGB: TGroupBox;
    StateList: TListView;
    procedure RelayRBGClick(Sender: TObject);
    procedure SupplyBoxClick(Sender: TObject);
    procedure ResetBtnClick(Sender: TObject);
    procedure StatusBtnClick(Sender: TObject);

  private
    FBoard: TAutoCalBoard;
    Guard: Boolean;                          { True while the code itself changes a control }
    FW: TFirmwareInfo;                       { what the board last reported; HaveFW = it has reported }
    HaveFW: Boolean;

    procedure SetConnected(const Connected: Boolean);
    function GetConnected: Boolean;
    procedure ReadFirmware;
    procedure RefreshState;
    procedure ClearGroup(const RBG: TRadioGroup);
    procedure ClearChannels;
    procedure ClearShunts;
    procedure ClearSupplies(const IncludingFan: Boolean);

  public
    OnBoardChanged: TBoardChanged;           { the main form hands the board to the other tabs and shows the link state }

    constructor Create(AOwner: TComponent); override;
    { False (with the reason logged) when Addr is not an IP address; a no-op when already connected }
    function Connect(const Addr: String): Boolean;
    procedure Disconnect;
    property Board: TAutoCalBoard read FBoard;
    property Connected: Boolean read GetConnected;
  end;

implementation

{$R *.dfm}

{ TListView }

procedure TListView.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := Params.Style or LVS_NOSCROLL;
end;

constructor TControlsFrame.Create(AOwner: TComponent);
begin
  inherited;
  for var RBG in [VChanRBG, IChanRBG, VShuntRBG, IShuntRBG] do
  begin
    RBG.Items.Clear;
    { the two shunt groups name each relay by the shunt behind it, as the Calibration tab does }
    var Shunts := (RBG = VShuntRBG) or (RBG = IShuntRBG);
    for var I := 1 to CHANS do
      if Shunts then RBG.Items.Add(Format('%d (%s %s)', [I, SHUNT_OHMS[I], OHMS]))
      else RBG.Items.Add(IntToStr(I));
    RBG.Items.Add('Off');
    RBG.ItemIndex := -1;
  end;
  SetConnected(False);
end;

{
  the state list mirrors the controls: it is what this tab last asked the board to do, not a readback.
  Rebuilt on every change; connected, every state row is present (ON/off, selected channel or 'not set')
}
procedure TControlsFrame.RefreshState;

  procedure AddRow(const Name, Value: String);
  begin
    with StateList.Items.Add do
    begin
      Caption := Name;
      SubItems.Add(Value);
    end;
  end;

  function RelayText(const RBG: TRadioGroup): String;
  begin
    if RBG.ItemIndex < 0 then Exit('not set');
    if RBG.ItemIndex >= CHANS then Exit('off');
    Result := RBG.Items[RBG.ItemIndex];
  end;

  function SupplyText(const Box: TCheckBox): String;
  begin
    if Box.Checked then Result := 'ON' else Result := 'off';
  end;

  function OneLine(const S: String): String;
  begin
    Result := Trim(StringReplace(StringReplace(S, #13, '', [rfReplaceAll]), #10, ' / ', [rfReplaceAll]));
  end;

begin
  StateList.Items.BeginUpdate;
  try
    StateList.Items.Clear;
    if not Assigned(FBoard) then
    begin
      AddRow('Link', 'not connected');
      Exit;
    end;

    AddRow('Address', FBoard.Address);
    if FBoard.Online then AddRow('Link', 'online (answered the connect ping)')
    else if FBoard.Connecting then AddRow('Link', 'no reply yet: retrying while the board boots')
    else AddRow('Link', 'no reply to the connect ping: bootloader, or not there');

    if HaveFW then
    begin
      AddRow('Firmware', Trim(FW.Device + ' ' + FW.Version));
      AddRow('Built', FW.DateTime);
      AddRow('Notes', OneLine(FW.Notes));
    end
    else AddRow('Firmware', 'not reported');

    if FBoard.LastStatus = '' then AddRow('Last reply', 'none yet')
    else if FBoard.LastError <= ERR_NONE then AddRow('Last reply', FBoard.LastStatus)
    else AddRow('Last reply', Format('%s (%d: %s)', [FBoard.LastStatus, FBoard.LastError, TAutoCalProtocol.ErrorText(FBoard.LastError)]));

    AddRow('Channel voltage sense (CHVS)', RelayText(VChanRBG));
    AddRow('Channel current (CHI)',        RelayText(IChanRBG));
    AddRow('Voltage sense shunt (RNGV)',   RelayText(VShuntRBG));
    AddRow('Current shunt (RNGI)',         RelayText(IShuntRBG));
    AddRow('Fan',                          SupplyText(FanBox));
    AddRow('Voltage source',               SupplyText(VSrcBox));
    AddRow('Discharge supply',             SupplyText(DPSBox));
  finally
    StateList.Items.EndUpdate;
  end;
end;

procedure TControlsFrame.ReadFirmware;
begin
  HaveFW := Assigned(FBoard) and FBoard.Firmware(FW);
  RefreshState;
end;

procedure TControlsFrame.SetConnected(const Connected: Boolean);
begin
  Guard := True;
  try
    for var RBG in [VChanRBG, IChanRBG, VShuntRBG, IShuntRBG] do
    begin
      RBG.ItemIndex := -1;
      RBG.Enabled := Connected;
    end;
    for var Box in [FanBox, VSrcBox, DPSBox] do
    begin
      Box.Checked := False;
      Box.Enabled := Connected;
    end;
  finally
    Guard := False;
  end;

  ResetGB.Enabled := Connected;
  StatusBtn.Enabled := Connected;
  RefreshState;
end;

function TControlsFrame.GetConnected: Boolean;
begin
  Result := Assigned(FBoard);
end;

function TControlsFrame.Connect(const Addr: String): Boolean;
begin
  Result := True;
  if Assigned(FBoard) then Exit;
  var A := Trim(Addr);
  if not ValidAddress(A) then
  begin
    TUtils.HandleEvent(etMessage, Format('Invalid IP address: %s'#13#10, [A]));
    Exit(False);
  end;

  FBoard := TAutoCalBoard.Create(A);
  HaveFW := False;
  SetConnected(True);
  { a board that answered the ping tells us what it runs; one in its bootloader has no RPC to ask }
  if FBoard.Online then ReadFirmware
  else
  begin
    { not answering yet (booting, or in the bootloader's TFTP window): keep pinging on a task. Stop cancels it }
    var Board := FBoard;
    FBoard.OnConnected :=
      procedure(const Online: Boolean)
      begin
        if FBoard <> Board then Exit;          { disconnected meanwhile }
        if Online then ReadFirmware else RefreshState;
        { the other tabs see the board again, now that it answers: the record tab reads it }
        if Online and Assigned(OnBoardChanged) then OnBoardChanged(FBoard);
      end;
    FBoard.WaitOnline;
  end;
  if Assigned(OnBoardChanged) then OnBoardChanged(FBoard);
  RefreshState;
end;

procedure TControlsFrame.Disconnect;
begin
  if not Assigned(FBoard) then Exit;
  { the other tabs drop their reference first }
  if Assigned(OnBoardChanged) then OnBoardChanged(nil);
  SetConnected(False);
  FreeAndNil(FBoard);
  HaveFW := False;
  RefreshState;
end;

procedure TControlsFrame.StatusBtnClick(Sender: TObject);
begin
  ReadFirmware;
end;

{ Tag of the group = f_class; the item index = f_num (0..7, 8 = Off) }
procedure TControlsFrame.RelayRBGClick(Sender: TObject);
begin
  if Guard or not Assigned(FBoard) then Exit;
  with TRadioGroup(Sender) do
  begin
    if ItemIndex < 0 then Exit;
    if not FBoard.SelectRelay(Tag, ItemIndex) then ClearGroup(TRadioGroup(Sender));
  end;
  RefreshState;
end;

{ Tag of the box = f_class; checked = ON. A refusal (interlock) puts the box back }
procedure TControlsFrame.SupplyBoxClick(Sender: TObject);
begin
  if Guard or not Assigned(FBoard) then Exit;
  with TCheckBox(Sender) do
  begin
    if not FBoard.Supply(Tag, Checked) then
    begin
      Guard := True;
      try
        Checked := not Checked;
      finally
        Guard := False;
      end;
    end;
  end;
  RefreshState;
end;

{ Tag of the button = reset option }
procedure TControlsFrame.ResetBtnClick(Sender: TObject);
begin
  if not Assigned(FBoard) then Exit;
  var Option := TSpeedButton(Sender).Tag;

  if Option = RS_FIRMWARE then
    if ShowDialog(TForm(GetParentForm(Self)), dtConfirm, 'Restart the firmware? Every relay and the fan are released first.',
      [mbYes, mbNo], '', mbNo) <> mrYes then Exit;

  if FBoard.Reset(Option) then
    case Option of
      RS_CHANNELS: ClearChannels;
      RS_SHUNTS:   ClearShunts;
      RS_ALL:      begin ClearChannels; ClearShunts; ClearSupplies(False); end;
      RS_FIRMWARE: begin ClearChannels; ClearShunts; ClearSupplies(True); end;
    end;
  RefreshState;
end;

procedure TControlsFrame.ClearGroup(const RBG: TRadioGroup);
begin
  Guard := True;
  try
    RBG.ItemIndex := -1;
  finally
    Guard := False;
  end;
end;

procedure TControlsFrame.ClearChannels;
begin
  ClearGroup(VChanRBG);
  ClearGroup(IChanRBG);
end;

procedure TControlsFrame.ClearShunts;
begin
  ClearGroup(VShuntRBG);
  ClearGroup(IShuntRBG);
end;

procedure TControlsFrame.ClearSupplies(const IncludingFan: Boolean);
begin
  Guard := True;
  try
    VSrcBox.Checked := False;
    DPSBox.Checked := False;
    if IncludingFan then FanBox.Checked := False;
  finally
    Guard := False;
  end;
end;

end.
