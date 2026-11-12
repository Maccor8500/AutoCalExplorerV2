unit RecordSummaryU;

{
  The calibration record as the configuration and data files have it: what goes into the box, at a glance.
  It is what the Calibration Record tab's Import button brings in, and RecordDifferences is what its Write
  button compares with before it writes.

  ApplyFilesToRecord takes a record (what the tab has painted) and lays over it everything the two
  JSON files say about the box. The certificate is worked out afresh from them (CertificateU, nothing is
  written), so a sheet of Configurations saved a moment ago already counts:

    record (system_info_t)        from
    serial, model, manufacturer   the Certificate sheet's instrument
    owner, technician             the Certificate sheet
    certificate number            the certificate's formula (once a shunt has been accepted)
    calibration date, due date    the certificate (the day of the latest accepted shunt; the sheet's due formula)
    previous calibration date     the Certificate sheet
    temperature, humidity         the Certificate sheet
    comments                      "Method: <procedure>; Remarks: <remarks>; Notes: <notes>", as a certificate
                                  import composes them; the certificate's long comment paragraph is print only,
                                  the board's field holds 255 characters
    shunts 1 to 8                 the certificate's row: measured value, previous value, difference, uncertainty,
                                  each as the certificate prints it. A shunt that has no value there keeps the
                                  record's own line
    standards                     the certificate's "Standards used": the meters, then the typed lines

  A text or date the files leave empty does not blank the record's. The board trims what is too long for a
  field when the record is written; nothing is trimmed here.

  The Certificate sheet counts only once it has been saved. Until then its fields would be the workbook's
  defaults (its serial, its technician, its standards), and those must not replace what a board holds: the
  typed part (identity, technician, conditions, comments, certificate number, standards) is then left as the
  record has it and Note says so. The shunt rows and the calibration dates come from the measurements and are
  laid over either way.

  No VCL.
}

interface

uses
  System.SysUtils, System.Classes, System.Math, System.StrUtils, AutoCalProtocolU, AppConfigU, CertificateU;

type
  TSummaryRows = set of 0..CHANS -1;

{
  Rows: the shunts (0-based) whose line now comes from the certificate. Note: '' or what was held back and
  why. False, with the reason in Why, when the files cannot be used: Info is then as it was
}
function ApplyFilesToRecord(var Info: TSystemInfo; out Rows: TSummaryRows; out Note, Why: String): Boolean;

{
  where a record about to be written differs from the one the board holds now, one line each ("Serial: the
  board has "A", to write "B""); none = the same. The firmware section is not compared: it is never written.
  Numbers count as the same within a part in a million: the board keeps them as 32-bit floats, so a value
  read back is not bit for bit the one that was sent
}
function RecordDifferences(const ToWrite, OnBoard: TSystemInfo): TArray<String>;

implementation

{ a number as the certificate prints it ("100.006 67") back to the number that text states }
function Stated(const Text: String; const Fallback: Double): Double;
begin
  if not TryStrToFloat(StringReplace(Text, ' ', '', [rfReplaceAll]), Result, TFormatSettings.Invariant) then Result := Fallback;
end;

function RecordDifferences(const ToWrite, OnBoard: TSystemInfo): TArray<String>;
const
  SHUNT_FIELD: array [TShuntField] of String = ('measured', 'previous', 'diff', 'uncertainty');
var
  List: TArray<String>;

  function Short(const S: String): String;
  begin
    Result := S.Replace(#13#10, ' ').Replace(#10, ' ');
    if Length(Result) > 40 then Result := Copy(Result, 1, 37) + '...';
  end;

  procedure Text(const Name, Mine, Theirs: String);
  begin
    if Trim(Mine) <> Trim(Theirs) then
      List := List + [Format('%s: the board has "%s", to write "%s"', [Name, Short(Trim(Theirs)), Short(Trim(Mine))])];
  end;

  procedure Date(const Name: String; const Mine, Theirs: TCalDate);
  begin
    if (Mine.Year <> Theirs.Year) or (Mine.Month <> Theirs.Month) or (Mine.Day <> Theirs.Day) then
      List := List + [Format('%s: the board has %s, to write %s', [Name, Theirs.ToDisplay, Mine.ToDisplay])];
  end;

  procedure Number(const Name: String; const Mine, Theirs: Double);
  begin
    if not SameValue(Mine, Theirs, Max(Abs(Mine), Abs(Theirs)) * 1E-6) then
      List := List + [Format('%s: the board has %s, to write %s',
        [Name, TAutoCalProtocol.FormatValue(Theirs), TAutoCalProtocol.FormatValue(Mine)])];
  end;

begin
  List := nil;
  Text('Serial', ToWrite.Serial, OnBoard.Serial);
  Text('Model', ToWrite.Model, OnBoard.Model);
  Text('Certificate #', ToWrite.Cert, OnBoard.Cert);
  Text('Manufacturer', ToWrite.Manufacturer, OnBoard.Manufacturer);
  Text('Owner', ToWrite.Owner, OnBoard.Owner);
  Text('Technician', ToWrite.Tech, OnBoard.Tech);
  Date('Calibration date', ToWrite.CalDate, OnBoard.CalDate);
  Date('Previous cal.', ToWrite.CalDatePrev, OnBoard.CalDatePrev);
  Date('Calibration due', ToWrite.CalDue, OnBoard.CalDue);
  Number('Temp.', ToWrite.Temp, OnBoard.Temp);
  Number('Humidity', ToWrite.Humd, OnBoard.Humd);
  for var I := 0 to CHANS -1 do
    for var F := Low(TShuntField) to High(TShuntField) do
      Number(Format('Shunt %d %s', [I +1, SHUNT_FIELD[F]]), ToWrite.Shunts[I].Value(F), OnBoard.Shunts[I].Value(F));
  for var I := 0 to TRACE_COUNT -1 do
  begin
    var Name := Format('Standard %d', [I +1]);
    Text(Name + ' serial', ToWrite.Trace[I].Serial, OnBoard.Trace[I].Serial);
    Text(Name + ' mfr.', ToWrite.Trace[I].Manufacturer, OnBoard.Trace[I].Manufacturer);
    Text(Name + ' model', ToWrite.Trace[I].Model, OnBoard.Trace[I].Model);
    Date(Name + ' cal. due', ToWrite.Trace[I].CalDue, OnBoard.Trace[I].CalDue);
  end;
  Text('Comments', ToWrite.Comments, OnBoard.Comments);
  Result := List;
end;

function ApplyFilesToRecord(var Info: TSystemInfo; out Rows: TSummaryRows; out Note, Why: String): Boolean;
var
  Cert: TCertificate;
  Saved: TCertInputs;
  Ignore: String;
  D: Double;

  procedure Take(var Field: String; const Value: String);
  begin
    if Trim(Value) <> '' then Field := Trim(Value);
  end;

  procedure TakeDate(var Field: TCalDate; const Value: TDate);
  begin
    if Value <> 0 then Field := TCalDate.FromDateTime(Value);
  end;

begin
  Rows := [];
  Note := '';
  { worked out from the files as they stand; not stored: looking at the record changes nothing }
  Result := TCertificateData.Refresh(Cert, Why, 0, 0, '', 0, False);
  if not Result then Exit;

  { the measurements' part: the dates, and further down the shunt rows }
  TakeDate(Info.CalDate, Cert.CalDate);
  TakeDate(Info.CalDue, Cert.CalDue);

  var Typed := TCertInputs.Load(Saved, Ignore);
  if not Typed then
    Note := 'the Certificate sheet of Configurations has not been saved: identity, technician, conditions, comments, ' +
      'certificate number and standards are left as the record has them';

  var I := Cert.Inputs;
  if Typed then
  begin
  Take(Info.Serial, I.Serial);
  Take(Info.Model, I.Model);
  Take(Info.Manufacturer, I.Manufacturer);
  Take(Info.Owner, I.OwnerName);
  Take(Info.Tech, I.Technician);
  { the number is serial + month and year + initials: without a calibration date it is not one yet }
  if Cert.CalDate <> 0 then Take(Info.Cert, Cert.Number);
  TakeDate(Info.CalDatePrev, I.PrevCalDate);
  if TryStrToFloat(Trim(I.Temp), D, TFormatSettings.Invariant) then Info.Temp := D;
  if TryStrToFloat(Trim(I.Humidity), D, TFormatSettings.Invariant) then Info.Humd := D;

  var Comments := '';
  var Method := Trim(Trim(I.Procedure1) + ' ' + Trim(I.Procedure2));
  if Method <> '' then Comments := 'Method: ' + Method;
  if Trim(I.Remarks) <> '' then Comments := Comments + IfThen(Comments <> '', '; ') + 'Remarks: ' + Trim(I.Remarks);
  if Trim(I.Notes) <> '' then Comments := Comments + IfThen(Comments <> '', '; ') + 'Notes: ' + Trim(I.Notes);
  Take(Info.Comments, Comments);
  end;

  for var N := 1 to Min(CERT_SHUNTS, CHANS) do
  begin
    var S := Cert.Shunts[N];
    if not S.HaveMeasured then Continue;
    var R := Default(TShuntRecord);
    R.Index := N -1;
    var Text := CertOhmsText(S.Measured, S.Nominal);
    R.Put(sfCurrent, Stated(Text, S.Measured), Text);
    Text := FormatFloat('0.00', S.Unc, TFormatSettings.Invariant);
    R.Put(sfUncertainty, Stated(Text, S.Unc), Text);
    if S.Previous > 0 then
    begin
      Text := CertOhmsText(S.Previous, S.Nominal);
      R.Put(sfPrevious, Stated(Text, S.Previous), Text);
    end;
    if S.HaveDiff then
    begin
      Text := FormatFloat('0.00000', S.Diff, TFormatSettings.Invariant);
      R.Put(sfDifference, Stated(Text, S.Diff), Text);
    end;
    Info.Shunts[N -1] := R;
    Include(Rows, N -1);
  end;

  { the certificate's table in place of the record's, when it has one }
  if Typed and (Length(Cert.Standards) > 0) then
    for var N := 0 to TRACE_COUNT -1 do
    begin
      var T := Default(TTraceRecord);
      if N <= High(Cert.Standards) then
      begin
        T.Serial := Cert.Standards[N].Serial;
        T.Manufacturer := Cert.Standards[N].Mfr;
        T.Model := Cert.Standards[N].Model;
        if Cert.Standards[N].Due <> 0 then
        begin
          T.CalDue := TCalDate.FromDateTime(Cert.Standards[N].Due);
          T.CalDueStr := CfgDate(Cert.Standards[N].Due);
        end;
      end;
      Info.Trace[N] := T;
    end;
end;

end.
