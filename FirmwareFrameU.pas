unit FirmwareFrameU;

{
  Firmware tab, in the order the board is brought up:
    1. Bootloader: Ariadne hex programmed over ISP with the Atmel-ICE (TAvrFlasher). Erases the application.
    2. Application: firmware.bin pushed over TFTP through that bootloader (TAutoCalBoard.Update).
    3. Direct: firmware.hex (and by default the bootloader hex of group 1) written over ISP as one image. No network.
  Only one job runs at a time: an ISP flash wipes what a TFTP push is writing, so each locks the others out.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.UITypes, System.StrUtils, System.IOUtils,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, CommonsU,
  AutoCalProtocolU, AutoCalBoardU, AvrFlasherU, ConfettiU;

type
  TFirmwareFrame = class(TFrame)
    LoaderGB: TGroupBox;
    HexPanel: TPanel;
    HexFileEdit: TEdit;
    HexBrowseBtn: TSpeedButton;
    FusePanel: TPanel;
    ExtLabel: TLabel;
    HighLabel: TLabel;
    LowLabel: TLabel;
    ExtEdit: TEdit;
    HighEdit: TEdit;
    LowEdit: TEdit;
    FuseBox: TCheckBox;
    FuseNote: TLabel;
    LockLabel: TLabel;
    LockEdit: TEdit;
    LockBox: TCheckBox;
    LoaderPanel: TPanel;
    IceLabel: TLabel;
    FlashBtn: TSpeedButton;
    FlashCancelBtn: TSpeedButton;
    AppGB: TGroupBox;
    BinPanel: TPanel;
    BinFileEdit: TEdit;
    BinBrowseBtn: TSpeedButton;
    AppPanel: TPanel;
    AppNote: TLabel;
    UpdateBtn: TSpeedButton;
    UpdateCancelBtn: TSpeedButton;
    BootloaderBtn: TSpeedButton;
    DirectGB: TGroupBox;
    AppHexPanel: TPanel;
    AppHexEdit: TEdit;
    AppHexBrowseBtn: TSpeedButton;
    DirectPanel: TPanel;
    DirectNote: TLabel;
    IncludeBootBox: TCheckBox;
    EraseBox: TCheckBox;
    VerifyBox: TCheckBox;
    DirectBtn: TSpeedButton;
    DirectCancelBtn: TSpeedButton;
    HexOpen: TFileOpenDialog;
    BinOpen: TFileOpenDialog;
    AppHexOpen: TFileOpenDialog;
    procedure HexBrowseBtnClick(Sender: TObject);
    procedure AppHexBrowseBtnClick(Sender: TObject);
    procedure DirectBtnClick(Sender: TObject);
    procedure DirectCancelBtnClick(Sender: TObject);
    procedure FuseEditChange(Sender: TObject);
    procedure FlashBtnClick(Sender: TObject);
    procedure FlashCancelBtnClick(Sender: TObject);
    procedure BinBrowseBtnClick(Sender: TObject);
    procedure UpdateBtnClick(Sender: TObject);
    procedure UpdateCancelBtnClick(Sender: TObject);
    procedure BootloaderBtnClick(Sender: TObject);

  private
    FBoard: TAutoCalBoard;
    HexFile, BinFile, AppHexFile: String;
    Fuses: TFuseSet;
    Lock: Integer;
    Flasher: TAvrFlasher;
    DirectRun: Boolean;                           { the running flash was started from group 3 }
    IceLast: String;                              { last status shown, so repeats are dropped }
    IceNotify: HDEVNOTIFY;                        { nil while the tab is hidden }
    AvrdudeChecked: Boolean;                      { avrdude resolved (installed, or unpacked from the avr_dude resource) on first show }
    LastWord: String;                             { first word of the in-place progress line }

    procedure SetBoard(const Value: TAutoCalBoard);
    procedure EnableButtons;
    function Options(const Erase, Verify: Boolean): TIspOptions;
    procedure ICEService(const Removed: Boolean = False);
    procedure CMShowingChanged(var Msg: TMessage); message CM_SHOWINGCHANGED;
    procedure WMDeviceChange(var Msg: TMessage); message WM_DEVICECHANGE;
    procedure Log(const S: String);

  public
    { the main form's in-place memo line: key, text }
    ProgressLine: TProc<String, String>;
    { a flash or update started or finished: other tabs re-check what they may touch }
    OnBusyChanged: TProc;

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Flashing: Boolean;
    { a TFTP push is running (not "Updating": TComponent has a virtual one) }
    function Uploading: Boolean;
    procedure CancelFlash;
    property Board: TAutoCalBoard read FBoard write SetBoard;
  end;

implementation

{$R *.dfm}

const
  DBT_DEVICEARRIVAL          = $8000;
  DBT_DEVICEREMOVECOMPLETE   = $8004;
  DBT_DEVTYP_DEVICEINTERFACE = 5;
  GUID_DEVINTERFACE_USB_DEVICE: TGUID = '{A5DCBF10-6530-11D2-901F-00C04FB951ED}';
  { relative to the exe: test\Delphi\Win32\Debug }
  DEFAULT_HEX = '..\..\..\..\ariadne_bootloader\AUTOCAL_528LB_BTLDR_RevE.hex';
  DEFAULT_BIN = '..\..\..\..\.pio\build\megaatmega2560\firmware.bin';
  DEFAULT_APP_HEX = '..\..\..\..\.pio\build\megaatmega2560\firmware.hex';
  BACKUP_DIR = 'backup';
  FLASH_KEY = 'avrdude';
  UPDATE_KEY = 'firmware';

constructor TFirmwareFrame.Create(AOwner: TComponent);
begin
  inherited;
  Flasher := TAvrFlasher.Create(ExtractFilePath(ParamStr(0)) + BACKUP_DIR);

  HexFile := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), DEFAULT_HEX));
  HexFileEdit.Text := AbbreviateFilePath(HexFile, 4);
  BinFile := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), DEFAULT_BIN));
  BinFileEdit.Text := AbbreviateFilePath(BinFile, 4);
  AppHexFile := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), DEFAULT_APP_HEX));
  AppHexEdit.Text := AbbreviateFilePath(AppHexFile, 4);

  { DEFAULT_FUSE / DEFAULT_LOCK seed the edits and the handler fills Fuses / Lock from them: one parse path }
  for var Edit in [ExtEdit, HighEdit, LowEdit] do
  begin
    Edit.Text := Format('0x%.2X', [DEFAULT_FUSE[Edit.Tag]]);
    FuseEditChange(Edit);
  end;
  LockEdit.Text := Format('0x%.2X', [DEFAULT_LOCK]);
  FuseEditChange(LockEdit);

  { everything below arrives on the flash task: hand it to the main thread }
  Flasher.OnSay :=
    procedure(S: String)
    begin
      TThread.Queue(nil, procedure begin LastWord := ''; Log(S); end);
    end;

  Flasher.OnProgress :=
    procedure(S: String)
    begin
      TThread.Queue(nil,
        procedure
        begin
          var W := Copy(S, 1, Pos(' ', S + ' ') -1);
          if W.EndsWith(':') then W := Copy(W, 1, Length(W) -1);   // "Reading:" (ours) and "Reading" (avrdude's bar) are one phase
          { a sign of life never takes over a line that is showing a bar }
          if (W = 'working...') and (LastWord <> '') and (LastWord <> W) then Exit;
          LastWord := W;
          if Assigned(ProgressLine) then ProgressLine(FLASH_KEY + W, S);
        end);
    end;

  Flasher.OnAsk :=
    function(Q: String): Boolean
    var
      Yes: Boolean;
    begin
      Yes := False;
      TThread.Synchronize(nil,
        procedure
        begin
          Yes := ShowDialog(TForm(GetParentForm(Self)), dtWarning, Q, [mbYes, mbNo], '', mbNo) = mrYes;
        end);
      Result := Yes;
    end;

  Flasher.OnCancelable :=
    procedure(B: Boolean)
    begin
      TThread.Queue(nil,
        procedure
        begin
          FlashCancelBtn.Enabled := B and not DirectRun;
          DirectCancelBtn.Enabled := B and DirectRun;
        end);
    end;

  Flasher.OnFinished :=
    procedure(Ok: Boolean)
    begin
      TThread.Queue(nil,
        procedure
        begin
          EnableButtons;
          if Ok then TConfetti.Celebrate(Self);
        end);
    end;

  EnableButtons;
end;

destructor TFirmwareFrame.Destroy;
begin
  if IceNotify <> nil then UnregisterDeviceNotification(IceNotify);
  FreeAndNil(Flasher);
  inherited;
end;

procedure TFirmwareFrame.Log(const S: String);
begin
  TUtils.HandleEvent(etMessage, S + #13#10);
end;

function TFirmwareFrame.Flashing: Boolean;
begin
  Result := Assigned(Flasher) and Flasher.Running;
end;

function TFirmwareFrame.Uploading: Boolean;
begin
  Result := Assigned(FBoard) and FBoard.Updating;
end;

procedure TFirmwareFrame.CancelFlash;
begin
  if Flashing then Flasher.Cancel;
end;

procedure TFirmwareFrame.SetBoard(const Value: TAutoCalBoard);
begin
  FBoard := Value;
  if Assigned(FBoard) then
  begin
    FBoard.OnUpdateProgress :=
      procedure(const Percent: Integer)
      begin
        if Assigned(ProgressLine) then ProgressLine(UPDATE_KEY, Format('Firmware upload: %d%%', [Percent]));
      end;

    FBoard.OnUpdateFinished :=
      procedure(const Ok: Boolean)
      begin
        EnableButtons;
        if Ok then TConfetti.Celebrate(Self);
      end;

    { asked on the update task: the dialog must run on the main thread }
    FBoard.OnConfirm :=
      function(const Question: String): Boolean
      var
        Yes: Boolean;
      begin
        Yes := False;
        TThread.Synchronize(nil,
          procedure
          begin
            Yes := ShowDialog(TForm(GetParentForm(Self)), dtWarning, Question, [mbYes, mbNo], '', mbNo) = mrYes;
          end);
        Result := Yes;
      end;
  end;
  EnableButtons;
end;

{ one job at a time across both halves }
procedure TFirmwareFrame.EnableButtons;
begin
  var Busy := Flashing or Uploading;
  FlashBtn.Enabled := not Busy;
  FlashCancelBtn.Enabled := Flashing and not DirectRun;
  UpdateBtn.Enabled := Assigned(FBoard) and not Busy;
  UpdateCancelBtn.Enabled := Uploading;
  BootloaderBtn.Enabled := Assigned(FBoard) and not Busy;
  DirectBtn.Enabled := not Busy;
  DirectCancelBtn.Enabled := Flashing and DirectRun;
  HexBrowseBtn.Enabled := not Flashing;
  AppHexBrowseBtn.Enabled := not Flashing;
  IncludeBootBox.Enabled := not Flashing;
  EraseBox.Enabled := not Flashing;
  VerifyBox.Enabled := not Flashing;
  BinBrowseBtn.Enabled := not Uploading;
  FusePanel.Enabled := not Flashing;
  if Assigned(OnBusyChanged) then OnBusyChanged();
end;

function TFirmwareFrame.Options(const Erase, Verify: Boolean): TIspOptions;
begin
  Result.Fuses := Fuses;
  Result.WriteFuses := FuseBox.Checked;
  Result.Lock := Lock;
  Result.WriteLock := LockBox.Checked;
  Result.Erase := Erase;
  Result.Verify := Verify;
end;

{ ---- bootloader ---- }

procedure TFirmwareFrame.CMShowingChanged(var Msg: TMessage);
begin
  inherited;

  if Showing then
  begin
    if IceNotify = nil then
    begin
      var Filter: TBytes;
      SetLength(Filter, 32);
      PCardinal(@Filter[0])^ := 32;
      PCardinal(@Filter[4])^ := DBT_DEVTYP_DEVICEINTERFACE;
      PGUID(@Filter[12])^ := GUID_DEVINTERFACE_USB_DEVICE;
      IceNotify := RegisterDeviceNotification(Handle, @Filter[0], DEVICE_NOTIFY_WINDOW_HANDLE);
      if IceNotify = nil then Log('Atmel-ICE: live detection unavailable (' + SysErrorMessage(GetLastError) + ')');
    end;
    IceLast := '';
    ICEService;

    { avrdude: the installed copy, else unpack the bundled avr_dude resource now rather than at the first flash }
    if not AvrdudeChecked then
    begin
      AvrdudeChecked := True;
      var Why: String;
      var Exe := AvrdudePath(Why);
      if Exe = '' then Log(Why)
      else if Why <> '' then Log(Why)
      else Log('avrdude: ' + Exe);
    end;
  end

  else if IceNotify <> nil then
  begin
    UnregisterDeviceNotification(IceNotify);
    IceNotify := nil;
  end;
end;

procedure TFirmwareFrame.ICEService(const Removed: Boolean);
begin
  var Msg := 'Atmel-ICE not connected';
  { a removal event is authoritative: WMI may not have caught up yet }
  if not Removed then Msg := TAvrFlasher.IceStatus;

  if Msg <> IceLast then
  begin
    IceLast := Msg;
    IceLabel.Caption := Msg;
    Log(Msg);
  end;
end;

procedure TFirmwareFrame.WMDeviceChange(var Msg: TMessage);
begin
  inherited;
  if not Showing then Exit;
  if (Msg.WParam <> DBT_DEVICEARRIVAL) and (Msg.WParam <> DBT_DEVICEREMOVECOMPLETE) then Exit;
  { lParam -> DEV_BROADCAST_DEVICEINTERFACE: devicetype at +4, the device path at +28 }
  if (Msg.LParam = 0) or (PCardinal(Msg.LParam + 4)^ <> DBT_DEVTYP_DEVICEINTERFACE) then Exit;
  if not ContainsText(PWideChar(Msg.LParam + 28), ICE_ID) then Exit;

  var Removed := Msg.WParam = DBT_DEVICEREMOVECOMPLETE;
  TThread.ForceQueue(nil, procedure begin ICEService(Removed); end, 300);
end;

procedure TFirmwareFrame.FuseEditChange(Sender: TObject);
begin
  with TEdit(Sender) do
  begin
    var Value := TAvrFlasher.ParseFuse(Text);
    if Tag = 3 then Lock := Value
    else Fuses[Tag] := Value;
    if Value < 0 then Font.Color := clRed
    else Font.Color := clWindowText;
  end;
end;

procedure TFirmwareFrame.HexBrowseBtnClick(Sender: TObject);
begin
  HexOpen.DefaultFolder := ExtractFilePath(HexFile);
  HexOpen.FileName := '';
  if HexOpen.Execute and FileExists(HexOpen.FileName) then
  begin
    HexFile := HexOpen.FileName;
    HexFileEdit.Text := AbbreviateFilePath(HexFile, 4);
    Log('Bootloader hex: ' + HexFile);
  end;
end;

procedure TFirmwareFrame.FlashBtnClick(Sender: TObject);
begin
  if Flashing or Uploading then Exit;
  { the WMI status may lag a removal: the label is what the operator sees }
  if not IceLast.StartsWith('Atmel-ICE connected') then begin Log('Atmel-ICE not connected: nothing done'); Exit; end;

  var Refusal: String;
  if not Flasher.Start(HexFile, Options(True, True), Refusal) then
  begin
    Log(Refusal);
    Exit;
  end;

  LastWord := '';
  DirectRun := False;
  EnableButtons;
  Log('Flash started: ' + HexFile);
end;

procedure TFirmwareFrame.FlashCancelBtnClick(Sender: TObject);
begin
  if not Flashing then Exit;
  Flasher.Cancel;
  Log('Cancel requested');
end;

{ ---- direct ---- }

procedure TFirmwareFrame.AppHexBrowseBtnClick(Sender: TObject);
begin
  AppHexOpen.DefaultFolder := ExtractFilePath(AppHexFile);
  AppHexOpen.FileName := '';
  if AppHexOpen.Execute and FileExists(AppHexOpen.FileName) then
  begin
    AppHexFile := AppHexOpen.FileName;
    AppHexEdit.Text := AbbreviateFilePath(AppHexFile, 4);
    Log('Application hex: ' + AppHexFile);
  end;
end;

procedure TFirmwareFrame.DirectBtnClick(Sender: TObject);
begin
  if Flashing or Uploading then Exit;
  if not IceLast.StartsWith('Atmel-ICE connected') then begin Log('Atmel-ICE not connected: nothing done'); Exit; end;

  var Refusal: String;
  if not Flasher.StartDirect(AppHexFile, IfThen(IncludeBootBox.Checked, HexFile, ''),
    Options(EraseBox.Checked, VerifyBox.Checked), Refusal) then
  begin
    Log(Refusal);
    Exit;
  end;

  LastWord := '';
  DirectRun := True;
  EnableButtons;
  Log('Direct flash started: ' + AppHexFile + IfThen(IncludeBootBox.Checked, ' + ' + HexFile, ' (no bootloader)') +
    IfThen(EraseBox.Checked, ', erase', ', no erase') + IfThen(VerifyBox.Checked, ', verify', ', no verify'));
end;

procedure TFirmwareFrame.DirectCancelBtnClick(Sender: TObject);
begin
  FlashCancelBtnClick(Sender);
end;

{ ---- application ---- }

procedure TFirmwareFrame.BinBrowseBtnClick(Sender: TObject);
begin
  BinOpen.DefaultFolder := ExtractFilePath(BinFile);
  BinOpen.FileName := '';
  if BinOpen.Execute and FileExists(BinOpen.FileName) then
  begin
    BinFile := BinOpen.FileName;
    BinFileEdit.Text := AbbreviateFilePath(BinFile, 4);
    Log('Firmware image: ' + BinFile);
  end;
end;

procedure TFirmwareFrame.UpdateBtnClick(Sender: TObject);
begin
  if not Assigned(FBoard) or Flashing then Exit;
  if FBoard.Update(BinFile) then EnableButtons;
end;

procedure TFirmwareFrame.UpdateCancelBtnClick(Sender: TObject);
begin
  if Uploading then FBoard.CancelUpdate;
end;

procedure TFirmwareFrame.BootloaderBtnClick(Sender: TObject);
begin
  if not Assigned(FBoard) or Flashing then Exit;
  if ShowDialog(TForm(GetParentForm(Self)), dtConfirm,
    'Reboot the board into the Ariadne bootloader? It waits about 15 s for a TFTP push, then returns to the application.',
    [mbYes, mbNo], '', mbNo) <> mrYes then Exit;
  FBoard.Reset(RS_ALL);
  FBoard.Download;
end;

end.
