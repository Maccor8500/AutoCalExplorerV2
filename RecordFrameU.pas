unit RecordFrameU;

{
  Calibration Record tab: the calibration record (system_info_t) that the box holds. The tab changes only when
  one of its buttons is pressed; nothing repaints it behind the user's back.

    Read     downloads what the board has in its EEPROM and paints it, as it is. Whatever of it does not match
             the local copy (identity, conditions, comments, shunts, standards) is then put where it belongs
             in the configuration and data files, with a warning that says what (RecordSummaryU.KeepReadLocal):
             an Import afterwards paints what was read. A shunt that has been accepted keeps its measurement
    Import   brings in what the configuration and data files have (RecordSummaryU) and paints it: identity,
             dates, conditions, comments, the shunts the certificate has a value for and the standards used.
             The data file's own record of the box goes in first; where the files hold none, what they do
             not cover stays as it is painted
    Write    writes what is painted: a push to the hardware. The board's current record is read first and
             compared with it: where they differ the differences are listed and the write waits for a yes,
             so a stale read (painted a while ago, the board changed since) is not written back unnoticed.
             After the write the record is read back. On the board as written: a successful write, and the
             one case where Write touches the data file, whose record of the box is brought up to date with
             what was written, with a notice in the log. Not as written (the firmware cut a digit): a warning
             that says where, the tab shows what the board really holds, and the data file is left alone

  Every field is editable except the firmware section, which only the board fills. A small grey dot beside a
  measured value marks a shunt that came from the files and is not what the board last gave.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.DateUtils, System.Math, System.Classes, System.UITypes, Vcl.Graphics,
  System.Threading, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, Vcl.Grids,
  Vcl.ComCtrls, CommonsU, AutoCalProtocolU, AutoCalBoardU, SystemInfoImportU, ConfettiU, AppConfigU, RecordSummaryU;

type
  TRecordFrame = class(TFrame)
    RecordGB: TGroupBox;
    IdentityPanel: TPanel;
    SerialLabel: TLabel;
    ModelLabel: TLabel;
    CertLabel: TLabel;
    ManufLabel: TLabel;
    OwnerLabel: TLabel;
    TechLabel: TLabel;
    CalDateLabel: TLabel;
    CalPrevLabel: TLabel;
    CalDueLabel: TLabel;
    TempLabel: TLabel;
    HumdLabel: TLabel;
    SerialEdit: TEdit;
    ModelEdit: TEdit;
    CertEdit: TEdit;
    ManufEdit: TEdit;
    OwnerEdit: TEdit;
    TechEdit: TEdit;
    CalDatePicker: TDateTimePicker;
    CalPrevPicker: TDateTimePicker;
    CalDuePicker: TDateTimePicker;
    TempEdit: TEdit;
    HumdEdit: TEdit;
    FirmwareGB: TGroupBox;
    FwDeviceLabel: TLabel;
    FwVersionLabel: TLabel;
    FwBuiltLabel: TLabel;
    FwNotesLabel: TLabel;
    FwDeviceEdit: TEdit;
    FwVersionEdit: TEdit;
    FwBuiltEdit: TEdit;
    GridsPanel: TPanel;
    ShuntGrid: TStringGrid;
    TraceGrid: TStringGrid;
    CommentsMemo: TMemo;
    fwNotesMemo: TEdit;
    ButtonPanel: TPanel;
    ImportBtn: TSpeedButton;
    ReadBtn: TSpeedButton;
    WriteBtn: TSpeedButton;
    StateBtn: TSpeedButton;
    SourceLabel: TLabel;
    CommitBox: TCheckBox;
    Label1: TLabel;
    CommentsLabel: TLabel;
    procedure ImportBtnClick(Sender: TObject);
    procedure CommentsMemoChange(Sender: TObject);
    procedure ReadBtnClick(Sender: TObject);
    procedure WriteBtnClick(Sender: TObject);
    procedure StateBtnClick(Sender: TObject);
    procedure CalDatePickerChange(Sender: TObject);
    procedure GridDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);

  private
    FBoard: TAutoCalBoard;
    Info: TSystemInfo;                       { what is painted, as last painted or gathered from the fields }
    {
      what the board last gave (a Read) or took (a Write): the reference for the grey dots and for the value a
      shunt held before it is calibrated again. Not what is painted
    }
    LastRead: TSystemInfo;
    HasRead: Boolean;
    Loading: Boolean;   { Paint is filling the pickers: the due date follows the record, not the cal date }
    { a read or a write runs on its own task (one of each at a time): the buttons stay disabled until it is done }
    WriteTask, ReadTask: ITask;
    { a small grey dot at the right of a measured value: imported from the files and not what the board last gave }
    Measured: array [0..CHANS -1] of Boolean;

    procedure SetBoard(const Value: TAutoCalBoard);
    { Info into the fields; Source goes beside the buttons, Detail ('' = Source) is its hint }
    procedure Paint(const Source: String; const Detail: String = '');
    { an unset date shows as an unticked picker }
    procedure ShowDate(const Picker: TDateTimePicker; const Date: TCalDate);
    { collects the edited fields back into Info; False (with every bad field logged) if a date or number does not parse }
    function GatherInfo: Boolean;
    procedure ClearGrids;
    { the tab before anything is read or imported: the house defaults and the nominal shunts }
    procedure ApplyDefaults;
    procedure Log(const S: String);
    {
      on the main thread, between the board's answer and the write: True = go ahead. Got = the board's current
      record was read; where it differs from ToWrite the differences are listed and the user decides
    }
    function ConfirmWrite(const ToWrite, Current: TSystemInfo; const Got: Boolean): Boolean;
    {
      on the main thread, after the write and its read back (GotBack = it answered): paints what the board
      holds, and either brings the data file's record up to date with a notice (written as sent) or warns
    }
    procedure WriteDone(const Written, Back: TSystemInfo; const GotBack, Commit: Boolean; const Address: String);
    function Writing: Boolean;
    function Reading: Boolean;

  public
    { a Read wrote to the configuration file (the standards): whoever shows that file should load it again }
    OnConfigChanged: TProc;

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { the record is not touched while a firmware update runs: the Firmware tab calls this when that changes }
    procedure EnableButtons;
    {
      a shunt (0-based) accepted on the Calibration tab: by then it is in the data file and the certificate.
      The tab is not repainted; this only says that Import brings it in. Ohms and UncPpm are the Calibration
      tab's own figures, for the log
    }
    procedure AcceptShunt(const Index: Integer; const Ohms: Double; const UncPpm: Double = 0);
    {
      the value the box holds for a shunt (0-based) before this calibration: the board's, when it has been read;
      else what is painted (for a shunt imported from the files: the previous value that came with it). 0 = none
    }
    function PreviousOf(const Index: Integer): Double;
    property Board: TAutoCalBoard read FBoard write SetBoard;

  end;

implementation

{$R *.dfm}

const
  { differences shown in the Write warning before "and N more" }
  SHOWN_DIFFERENCES = 14;

constructor TRecordFrame.Create(AOwner: TComponent);
begin
  inherited;
  ShuntGrid.Cells[0, 0] := '#';
  ShuntGrid.Cells[1, 0] := 'Measured ' + OHMS;
  ShuntGrid.Cells[2, 0] := 'Previous ' + OHMS;
  ShuntGrid.Cells[3, 0] := 'Diff %';
  ShuntGrid.Cells[4, 0] := 'Unc ' + #$00B5 + OHMS + '/' + OHMS;
  ShuntGrid.ColWidths[0] := 24;
  ShuntGrid.ColWidths[1] := 90;
  ShuntGrid.ColWidths[2] := 90;
  ShuntGrid.ColWidths[3] := 66;
  ShuntGrid.ColWidths[4] := 72;

  TraceGrid.Cells[0, 0] := '#';
  TraceGrid.Cells[1, 0] := 'Serial #';
  TraceGrid.Cells[2, 0] := 'Mfr.';
  TraceGrid.Cells[3, 0] := 'Model';
  TraceGrid.Cells[4, 0] := 'Cal. due';
  TraceGrid.ColWidths[0] := 20;
  TraceGrid.ColWidths[1] := 85;
  TraceGrid.ColWidths[2] := 105;
  TraceGrid.ColWidths[3] := 65;
  TraceGrid.ColWidths[4] := 75;

  { set here, not in the dfm: the IDE saves its own copy of the form over a caption changed on disk }
  ImportBtn.Caption := 'Import';
  ImportBtn.Hint := 'Bring in what the configuration and data files have (' + ExtractFileName(TAppConfig.FileName) + ', '
    + ExtractFileName(TAppData.FileName) + ') and paint it';
  ReadBtn.Hint := 'Download what the board has in its EEPROM and paint it';
  WriteBtn.Hint := 'Write what is painted to the board; its current record is compared first';
  ImportBtn.ShowHint := True;
  ReadBtn.ShowHint := True;
  WriteBtn.ShowHint := True;
  SourceLabel.ShowHint := True;

  { the firmware refuses a comments text of CAP_COMMENTS bytes or more (field_text: strlen >= sizeof); the memo
    stops at the last byte that fits, and the header counts down to it }
  CommentsMemo.MaxLength := CAP_COMMENTS -1;
  CommentsMemoChange(nil);

  ClearGrids;
  Info.Clear;
  ApplyDefaults;
  Paint('Nothing read or imported yet');

  EnableButtons;
end;

procedure TRecordFrame.ApplyDefaults;
const
  HOUSE = 'Maccor, Inc.';
  {
    the nominal shunts the tab starts with: the ohms are the fitted list every tab shows
    (AutoCalBoardU.SHUNT_VALUE: 10K, 24.9K, 1, 0.05, 0.005, 10, 500, 100), not a table of their own. The k=2 ppm
    are the design sheet's <2026-11-09>, each beside the value it was given for there (10K 8.5, 500 11.5,
    100 9.2, the rest 9); the 24.9K was not on that sheet and takes the 8.5 of the 10K and the 50K around it
  }
  NOMINAL_PPM: array [1..CHANS] of Double = (8.5, 8.5, 9, 9, 9, 9, 11.5, 9.2);
begin
  if Trim(Info.Manufacturer) = '' then Info.Manufacturer := HOUSE;
  if Trim(Info.Owner) = '' then Info.Owner := HOUSE;

  var Today := TCalDate.FromDateTime(Date);
  if not Info.CalDate.IsSet then Info.CalDate := Today;
  if not Info.CalDatePrev.IsSet then Info.CalDatePrev := Today;
  if not Info.CalDue.IsSet then
  begin
    var D: TDateTime;
    if (Info.CalDate.Year <= 9999) and TryEncodeDate(Word(Info.CalDate.Year), Info.CalDate.Month, Info.CalDate.Day, D)
      then Info.CalDue := TCalDate.FromDateTime(IncYear(D))
      else Info.CalDue := Today;
  end;

  for var I := 0 to CHANS -1 do
  begin
    var R := Default(TShuntRecord);          { no entry text: the nominal numbers show as they are }
    R.Index := I;
    R.Put(sfCurrent,     SHUNT_VALUE[I +1]);
    R.Put(sfUncertainty, NOMINAL_PPM[I +1]);
    Info.Shunts[I] := R;
  end;
end;

{ both grids: the data rows in alternating bands of clWindow and clInactiveBorder (the MacUniModCal grids' look);
  the fixed row and column keep the default drawing, the selected cell keeps the highlight colours }
procedure TRecordFrame.GridDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
begin
  if (ARow <= 0) or (ACol <= 0) then Exit;

  with TStringGrid(Sender) do
  begin
    if ARow mod 2 = 0 then Canvas.Brush.Color := clWindow
    else Canvas.Brush.Color := clInactiveBorder;
    Canvas.Font.Color := clWindowText;

    Canvas.FillRect(Rect);

    var Text := Cells[ACol, ARow];
    var R := Rect;
    Inc(R.Left, 2);
    DrawText(Canvas.Handle, PChar(Text), Length(Text), R, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);

    { imported and not what the board last gave: a small grey dot at the right edge of the measured value }
    if (Sender = ShuntGrid) and (ACol = 1) and (ARow -1 <= High(Measured)) and Measured[ARow -1] then
    begin
      var Mid := (Rect.Top + Rect.Bottom) div 2;
      Canvas.Brush.Color := clGrayText;
      Canvas.Pen.Color := clGrayText;
      Canvas.Ellipse(Rect.Right -10, Mid -2, Rect.Right -5, Mid +3);
    end;
  end;
end;

procedure TRecordFrame.CalDatePickerChange(Sender: TObject);
begin
  { the due date follows a new calibration date by one year; it stays editable on its own afterwards }
  if Loading or not CalDatePicker.Checked then Exit;
  CalDuePicker.Date := IncYear(CalDatePicker.Date);
  CalDuePicker.Checked := True;
end;

procedure TRecordFrame.CommentsMemoChange(Sender: TObject);
begin
  { Length(Text) is the byte count the board sees: the request goes out as single-byte ANSI and the memo's line
    breaks are CRLF, two bytes each, as strlen() counts them after the JSON unescape }
  var Max := CAP_COMMENTS -1;
  var Left := Max - Length(CommentsMemo.Text);
  if Left >= 0
    then CommentsLabel.Caption := Format('Comments  (%d of %d characters left)', [Left, Max])
    else CommentsLabel.Caption := Format('Comments  (%d characters over the board''s %d: Write will cut it)', [-Left, Max]);
end;

procedure TRecordFrame.Log(const S: String);
begin
  TUtils.HandleEvent(etMessage, S + #13#10);
end;

destructor TRecordFrame.Destroy;
begin
  { a task still talking to the board must not outlive the tab it reports to }
  if Reading then ReadTask.Wait(3000);
  if Writing then WriteTask.Wait(3000);
  inherited;
end;

procedure TRecordFrame.SetBoard(const Value: TAutoCalBoard);
begin
  { the board is freed by the Controls tab right after it takes it away: let a task that is using it finish first }
  if (Value <> FBoard) and Reading then ReadTask.Wait(3000);
  if (Value <> FBoard) and Writing then WriteTask.Wait(3000);
  { another board, or none: what the last one gave is no reference for this one }
  if Value <> FBoard then HasRead := False;
  FBoard := Value;
  EnableButtons;
  { connecting paints nothing: Read does }
end;

function TRecordFrame.PreviousOf(const Index: Integer): Double;
begin
  Result := 0;
  if (Index < 0) or (Index >= CHANS) then Exit;
  if HasRead then Result := LastRead.Shunts[Index].Current
  else if Measured[Index] then Result := Info.Shunts[Index].Previous
  else if not TCertificateParser.ParseNumber(Trim(ShuntGrid.Cells[1, Index +1]), Result) then Result := 0;
  if Result < 0 then Result := 0;
end;

procedure TRecordFrame.AcceptShunt(const Index: Integer; const Ohms: Double; const UncPpm: Double);
begin
  if (Index < 0) or (Index >= CHANS) then Exit;
  Log(Format('Shunt %d accepted (%s ohm): it is in %s :: Import on the Calibration Record tab brings it to the record',
    [Index +1, FloatToStrF(Ohms, ffGeneral, 10, 0, TFormatSettings.Invariant), ExtractFileName(TAppData.FileName)]));
end;

procedure TRecordFrame.EnableButtons;
begin
  var Connected := Assigned(FBoard);
  var Busy := Connected and FBoard.Updating;
  ReadBtn.Enabled := Connected and not Busy and not Reading and not Writing;
  WriteBtn.Enabled := Connected and not Busy and not Reading and not Writing;   { the fields can be typed in from scratch }
  StateBtn.Enabled := Connected and not Busy;
  ImportBtn.Enabled := not Reading and not Writing;                            { the files need no board }
end;

function TRecordFrame.Writing: Boolean;
begin
  Result := Assigned(WriteTask) and not (WriteTask.Status in
    [TTaskStatus.Completed, TTaskStatus.Canceled, TTaskStatus.Exception]);
end;

function TRecordFrame.Reading: Boolean;
begin
  Result := Assigned(ReadTask) and not (ReadTask.Status in
    [TTaskStatus.Completed, TTaskStatus.Canceled, TTaskStatus.Exception]);
end;

{ Read: what the board has in its EEPROM, painted as it is. On its own task, so a slow board does not freeze the tab }
procedure TRecordFrame.ReadBtnClick(Sender: TObject);
begin
  if not Assigned(FBoard) or Reading or Writing then Exit;
  var Board := FBoard;
  ReadBtn.Enabled := False;
  WriteBtn.Enabled := False;
  ImportBtn.Enabled := False;
  ReadTask := TTask.Run(procedure
  begin
    var Read: TSystemInfo;
    var Ok := Board.ReadSystemInfo(Read);
    TThread.Queue(nil, procedure
    begin
      if FBoard = Board then
      begin
        if Ok then
        begin
          Info := Read;
          LastRead := Read;
          HasRead := True;
          for var I := 0 to CHANS -1 do Measured[I] := False;
          Paint('Read from ' + Board.Address + ' at ' + FormatDateTime('hh:nn:ss', Now));

          {
            whatever of the record the local files do not have, or have differently, is put where it belongs in
            them (RecordSummaryU.KeepReadLocal), with a warning that says what: an Import then paints what was read
          }
          var Changes: TArray<String>;
          var Why: String;
          var Done := KeepReadLocal(Read, 'Read from ' + Board.Address, Changes, Why);
          if Length(Changes) > 0 then
          begin
            Log(Format('WARNING: the record read from the board did not match the local copy in %d place(s) :: the local copy was brought up to date:',
              [Length(Changes)]));
            for var C in Changes do Log('  ' + C);
            { the Configurations sheets show what they loaded: they are told to load again }
            if Assigned(OnConfigChanged) then OnConfigChanged();

            var Text := Format('The record read from the board did not match the local copy in %d place(s).', [Length(Changes)])
              + #13#10#13#10 + 'The local copy was updated to match the board:' + #13#10;
            for var I := 0 to Min(High(Changes), SHOWN_DIFFERENCES -1) do Text := Text + '  ' + Changes[I] + #13#10;
            if Length(Changes) > SHOWN_DIFFERENCES then
              Text := Text + Format('  ... and %d more (all of them are in the log)', [Length(Changes) - SHOWN_DIFFERENCES]) + #13#10;
            MessageDlg(Text, mtWarning, [mbOK], 0);
          end;
          if not Done then Log('Read: the local copy could not be brought up to date :: ' + Why);
        end
        else
        begin
          SourceLabel.Caption := 'Read failed';
          SourceLabel.Hint := 'The board did not give its record: what is painted was left as it was';
          Log('Read: the board did not give its record :: what is painted was left as it was');
        end;
      end;
      EnableButtons;
    end);
  end);
end;

{ Import: what the configuration and data files have, over what is painted }
procedure TRecordFrame.ImportBtnClick(Sender: TObject);
var
  Rows: TSummaryRows;
  Note, Why: String;
begin
  if Reading or Writing then Exit;
  { what is painted is what the files go over: a field typed a moment ago counts }
  if not GatherInfo then
  begin
    Log('Import: a field above does not read (see the lines before this one) :: nothing imported');
    Exit;
  end;

  if not ApplyFilesToRecord(Info, Rows, Note, Why) then
  begin
    SourceLabel.Caption := 'Import failed';
    SourceLabel.Hint := Why;
    Log('Import: ' + Why + ' :: what is painted was left as it was');
    Exit;
  end;

  var Waiting := 0;
  var Count := 0;
  for var I := 0 to CHANS -1 do
  begin
    { a row the files did not touch keeps the mark it had }
    if I in Rows then
    begin
      Inc(Count);
      Measured[I] := not HasRead
        or not SameValue(Info.Shunts[I].Current, LastRead.Shunts[I].Current, Abs(LastRead.Shunts[I].Current) * 1E-6);
    end;
    if Measured[I] then Inc(Waiting);
  end;

  var Files := ExtractFileName(TAppConfig.FileName) + ', ' + ExtractFileName(TAppData.FileName);
  Paint('Imported at ' + FormatDateTime('hh:nn:ss', Now),
    Format('Imported from %s :: %d shunt(s) from the certificate, %d not what the board last gave :: not in the box until Write',
      [Files, Count, Waiting]));
  Log(Format('Imported from %s :: %d shunt(s) from the certificate :: not in the box until Write', [Files, Count]));
  if Note <> '' then Log('Import: ' + Note);
end;

function TRecordFrame.ConfirmWrite(const ToWrite, Current: TSystemInfo; const Got: Boolean): Boolean;
begin
  if not Got then
  begin
    Log('Write: the board''s current record could not be read to compare with');
    Exit(MessageDlg('The board''s current record could not be read, so what is about to be written cannot be compared with it.'
      + #13#10#13#10 + 'Write what is shown anyway?', mtWarning, [mbYes, mbNo], 0, mbNo) = mrYes);
  end;

  var Diffs := RecordDifferences(ToWrite, Current);
  if Length(Diffs) = 0 then
  begin
    Log('Write: the board already holds what is shown :: written again');
    Exit(True);
  end;

  Log(Format('Write: the board''s current record differs from what is shown in %d place(s):', [Length(Diffs)]));
  for var D in Diffs do Log('  ' + D);

  var Text := Format('The board''s current record differs from what is shown in %d place(s):', [Length(Diffs)]) + #13#10#13#10;
  for var I := 0 to Min(High(Diffs), SHOWN_DIFFERENCES -1) do Text := Text + Diffs[I] + #13#10;
  if Length(Diffs) > SHOWN_DIFFERENCES then
    Text := Text + Format('... and %d more (all of them are in the log)', [Length(Diffs) - SHOWN_DIFFERENCES]) + #13#10;
  Text := Text + #13#10 + 'Writing replaces the board''s record with what is shown. Write?';
  Result := MessageDlg(Text, mtWarning, [mbYes, mbNo], 0, mbNo) = mrYes;
  if not Result then Log('Write: not written');
end;

{
  Write: what is painted goes to the board. First the board's record as it is now is read and compared (on the
  task; the question, when there is one, is asked on the main thread), then the sections go out
}
procedure TRecordFrame.WriteBtnClick(Sender: TObject);
begin
  if not Assigned(FBoard) or Writing or Reading then Exit;
  if not GatherInfo then Exit;
  var Problems := TStringList.Create;
  try
    Info.Fit(Problems);
    for var P in Problems do Log('  ' + P);
  finally
    Problems.Free;
  end;

  var Board := FBoard;
  var Snapshot := Info;
  var Commit := CommitBox.Checked;
  WriteBtn.Enabled := False;
  ReadBtn.Enabled := False;
  ImportBtn.Enabled := False;
  WriteTask := TTask.Run(procedure
  begin
    var Current: TSystemInfo;
    var Got := Board.ReadSystemInfo(Current);
    var Go := False;
    TThread.Synchronize(nil, procedure
    begin
      Go := (FBoard = Board) and ConfirmWrite(Snapshot, Current, Got);
    end);
    var Ok := Go and Board.WriteSystemInfo(Snapshot, Commit);
    { what the board holds now, to see that it is what was sent }
    var Back: TSystemInfo;
    var GotBack := Ok and Board.ReadSystemInfo(Back);
    TThread.Queue(nil, procedure
    begin
      if Go and (FBoard = Board) then
      begin
        if Ok then WriteDone(Snapshot, Back, GotBack, Commit, Board.Address)
        else
        begin
          SourceLabel.Caption := 'Write failed';
          SourceLabel.Hint := 'The board did not take the record (see the log)';
        end;
      end;
      EnableButtons;
    end);
  end);
end;

procedure TRecordFrame.WriteDone(const Written, Back: TSystemInfo; const GotBack, Commit: Boolean; const Address: String);
var
  Stored: TSystemInfo;
  Why: String;
begin
  var Where := StrTernary(Commit, 'the board''s EEPROM', 'the board (not committed)');
  var At := ' at ' + FormatDateTime('hh:nn:ss', Now);
  for var I := 0 to CHANS -1 do Measured[I] := False;
  HasRead := True;

  if not GotBack then
  begin
    { sent, and the board said yes to every section; what it holds could not be looked at }
    LastRead := Written;
    Info := Written;
    Paint('Written, not verified' + At, 'Written to ' + Where + ', but the record could not be read back to check it');
    Log('WARNING: written to ' + Where + ', but the record could not be read back: it is not known to be as written');
    MessageDlg('The record was written, but it could not be read back, so it is not known to be on the board as written.'
      + #13#10#13#10 + 'Press Read to see what the board holds.', mtWarning, [mbOK], 0);
    Exit;
  end;

  var Diffs := RecordDifferences(Written, Back, True, 'the board has', 'written');
  if Length(Diffs) > 0 then
  begin
    { the board holds something else than was sent: that is what the tab shows from here on }
    LastRead := Back;
    Info := Back;
    Paint(Format('Written, %d value(s) not as written', [Length(Diffs)]) + At,
      Format('Written to %s, but %d value(s) read back differently: the tab shows what the board holds', [Where, Length(Diffs)]));
    Log(Format('WARNING: written to %s, but the board holds %d value(s) differently from what was written:', [Where, Length(Diffs)]));
    for var D in Diffs do Log('  ' + D);
    Log(Format('  %s was not touched', [ExtractFileName(TAppData.FileName)]));

    var Text := Format('The record was written, but %d value(s) read back differently from what was written:', [Length(Diffs)]) + #13#10#13#10;
    for var I := 0 to Min(High(Diffs), SHOWN_DIFFERENCES -1) do Text := Text + Diffs[I] + #13#10;
    if Length(Diffs) > SHOWN_DIFFERENCES then
      Text := Text + Format('... and %d more (all of them are in the log)', [Length(Diffs) - SHOWN_DIFFERENCES]) + #13#10;
    Text := Text + #13#10 + 'The tab now shows what the board holds. ' + ExtractFileName(TAppData.FileName) + ' was not changed.';
    MessageDlg(Text, mtWarning, [mbOK], 0);
    Exit;
  end;

  { on the board as written: a successful write. What was typed stays on the tab, digit for digit }
  LastRead := Written;
  LastRead.Firmware := Back.Firmware;
  Info := LastRead;
  var Line := 'Written and verified' + At;
  var Detail := 'Written to ' + Where + ' and read back the same';
  Log('Written to ' + Where + ' and read back the same');

  {
    the one case where Write touches the data file: its record of the box is brought up to date with what is
    now known to be in the box. A notice, not a warning; nothing when the file already has it
  }
  var Name := ExtractFileName(TAppData.FileName);
  var Had := LoadStoredRecord(Stored, Why);
  var Changes: TArray<String> := nil;
  if Had then Changes := RecordDifferences(Written, Stored, False, 'the file had', 'written');
  if (not Had) or (Length(Changes) > 0) then
  begin
    if SaveStoredRecord(LastRead, 'Written to ' + Address, Why) then
    begin
      if Had then
      begin
        Log(Format('Notice: %s brought up to date with what was written (%d value(s)):', [Name, Length(Changes)]));
        for var C in Changes do Log('  ' + C);
        Line := Line + ' :: ' + Name + ' updated';
        Detail := Detail + Format(' :: %s brought up to date (%d value(s), listed in the log)', [Name, Length(Changes)]);
      end
      else
      begin
        Log(Format('Notice: %s had no valid record of the box :: what was written was saved to it', [Name]));
        Line := Line + ' :: ' + Name + ' updated';
        Detail := Detail + Format(' :: saved to %s, which had no valid record of the box', [Name]);
      end;
    end
    else
      Log(Format('Notice: %s could not be brought up to date with what was written :: %s', [Name, Why]));
  end;

  Paint(Line, Detail);
  TConfetti.Celebrate(Self);
end;

procedure TRecordFrame.StateBtnClick(Sender: TObject);
var
  State: TRecordState;
begin
  if Assigned(FBoard) then FBoard.ReadRecordState(State);
end;

procedure TRecordFrame.ClearGrids;
begin
  for var R := 1 to ShuntGrid.RowCount -1 do
  begin
    ShuntGrid.Cells[0, R] := IntToStr(R);
    for var C := 1 to ShuntGrid.ColCount -1 do ShuntGrid.Cells[C, R] := '';
  end;
  for var R := 1 to TraceGrid.RowCount -1 do
  begin
    TraceGrid.Cells[0, R] := IntToStr(R);
    for var C := 1 to TraceGrid.ColCount -1 do TraceGrid.Cells[C, R] := '';
  end;
end;

procedure TRecordFrame.Paint(const Source, Detail: String);
begin
  SerialEdit.Text  := Info.Serial;
  ModelEdit.Text   := Info.Model;
  CertEdit.Text    := Info.Cert;
  ManufEdit.Text   := Info.Manufacturer;
  OwnerEdit.Text   := Info.Owner;
  TechEdit.Text    := Info.Tech;
  Loading := True;
  try
    ShowDate(CalDatePicker, Info.CalDate);
    ShowDate(CalPrevPicker, Info.CalDatePrev);
    ShowDate(CalDuePicker, Info.CalDue);
  finally
    Loading := False;
  end;
  TempEdit.Text    := TAutoCalProtocol.FormatValue(Info.Temp);
  HumdEdit.Text    := TAutoCalProtocol.FormatValue(Info.Humd);
  CommentsMemo.Text := Info.Comments;

  { firmware_t: only a board read fills it (f_num 1); Import leaves it as it is, Write never sends it }
  var FW := Info.Firmware;
  FwDeviceEdit.Text  := FW.Device;
  if FW.DateTime <> '' then FwVersionEdit.Text := FW.Version else FwVersionEdit.Text := '';
  FwBuiltEdit.Text   := FW.DateTime;
  FwNotesMemo.Text   := FW.Notes;

  ClearGrids;
  for var I := 0 to CHANS -1 do
  begin
    var S := Info.Shunts[I];
    if (S.Current = 0) and (S.Previous = 0) and (S.Uncertainty = 0) then Continue;
    { the entry text where there is one, so an imported or typed value shows digit for digit }
    ShuntGrid.Cells[1, I +1] := S.Text(sfCurrent);
    ShuntGrid.Cells[2, I +1] := StrTernary(S.Previous = 0, '-', S.Text(sfPrevious));
    ShuntGrid.Cells[3, I +1] := StrTernary(S.Previous = 0, '-', S.Text(sfDifference));
    ShuntGrid.Cells[4, I +1] := S.Text(sfUncertainty);
  end;

  for var I := 0 to TRACE_COUNT -1 do
  begin
    var T := Info.Trace[I];
    if (T.Serial = '') and (T.Model = '') then Continue;
    TraceGrid.Cells[1, I +1] := T.Serial;
    TraceGrid.Cells[2, I +1] := T.Manufacturer;
    TraceGrid.Cells[3, I +1] := T.Model;
    TraceGrid.Cells[4, I +1] := T.CalDueText;          { the text as read when the firmware refused the year }
  end;
  ShuntGrid.Invalidate;

  SourceLabel.Caption := Source;
  if Detail <> '' then SourceLabel.Hint := Detail else SourceLabel.Hint := Source;
end;

procedure TRecordFrame.ShowDate(const Picker: TDateTimePicker; const Date: TCalDate);
begin
  { TDateTime cannot hold the firmware's full uint32 year: a record with such a year is shown unticked }
  Picker.Checked := False;
  if not Date.IsSet or (Date.Year > 9999) then Exit;
  var D: TDateTime;
  if not TryEncodeDate(Word(Date.Year), Date.Month, Date.Day, D) then Exit;
  { the picker's MinDate (2000-01-01, the firmware's MIN_YEAR) would raise on an earlier date: shown unticked }
  if D < Picker.MinDate then Exit;
  Picker.Date := D;
  Picker.Checked := True;
end;

function TRecordFrame.GatherInfo: Boolean;
var
  Ok: Boolean;

  function GetDate(const Picker: TDateTimePicker): TCalDate;
  begin
    if Picker.Checked then Result := TCalDate.FromDateTime(Picker.Date) else Result := TCalDate.Empty;
  end;

  function GetNumber(const Text, Name: String): Double;
  begin
    var T := Trim(Text);
    if (T = '') or (T = '-') then Exit(0);
    if TCertificateParser.ParseNumber(T, Result) then Exit;
    Log(Format('%s: "%s" is not a number', [Name, T]));
    Ok := False;
  end;

  { a shunt cell: the number, and the cell's own text kept as the entry (a blank or "-" is no entry) }
  procedure PutCell(var R: TShuntRecord; const F: TShuntField; const Cell, Name: String);
  begin
    var T := Trim(Cell);
    if T = '-' then T := '';
    R.Put(F, GetNumber(T, Name), T);
  end;

begin
  Ok := True;
  var FW := Info.Firmware;   { the board's section, never edited here }

  Info.Serial       := Trim(SerialEdit.Text);
  Info.Model        := Trim(ModelEdit.Text);
  Info.Cert         := Trim(CertEdit.Text);
  Info.Manufacturer := Trim(ManufEdit.Text);
  Info.Owner        := Trim(OwnerEdit.Text);
  Info.Tech         := Trim(TechEdit.Text);
  Info.CalDate      := GetDate(CalDatePicker);
  Info.CalDatePrev  := GetDate(CalPrevPicker);
  Info.CalDue       := GetDate(CalDuePicker);
  Info.Temp         := GetNumber(TempEdit.Text, TempLabel.Caption);
  Info.Humd         := GetNumber(HumdEdit.Text, HumdLabel.Caption);
  Info.Comments     := CommentsMemo.Text;

  for var I := 0 to CHANS -1 do
  begin
    var Row := 'Shunt ' + IntToStr(I +1);
    Info.Shunts[I].Index := I;
    PutCell(Info.Shunts[I], sfCurrent,     ShuntGrid.Cells[1, I +1], Row + ' measured');
    PutCell(Info.Shunts[I], sfPrevious,    ShuntGrid.Cells[2, I +1], Row + ' previous');
    PutCell(Info.Shunts[I], sfDifference,  ShuntGrid.Cells[3, I +1], Row + ' diff');
    PutCell(Info.Shunts[I], sfUncertainty, ShuntGrid.Cells[4, I +1], Row + ' uncertainty');
  end;

  for var I := 0 to TRACE_COUNT -1 do
  begin
    Info.Trace[I].Serial       := Trim(TraceGrid.Cells[1, I +1]);
    Info.Trace[I].Manufacturer := Trim(TraceGrid.Cells[2, I +1]);
    Info.Trace[I].Model        := Trim(TraceGrid.Cells[3, I +1]);
    var T := Trim(TraceGrid.Cells[4, I +1]);
    Info.Trace[I].CalDueStr := T;
    if T = '' then Info.Trace[I].CalDue := TCalDate.Empty
    else if not TCertificateParser.ParseDate(T, Info.Trace[I].CalDue) then
    begin
      Log(Format('Trace %d cal. due: "%s" is not a date', [I +1, T]));
      Ok := False;
    end;
  end;

  Info.Firmware := FW;
  Result := Ok;
end;

end.
