unit SystemInfoImportU;

{
  Calibration certificate import: a Word (.docx / .doc) or RTF document becomes plain text, and the text is
  parsed into the firmware's calibration record (TSystemInfo). Table cells arrive as tab separated fields and
  rows as lines, which is what the parser prefers; a flat text run is handled too.
  No VCL. Word's own format (.doc) needs Word installed: it is converted to RTF through automation.
}

interface

uses
  System.SysUtils, System.Classes, System.StrUtils, System.Math, System.Zip, System.RegularExpressions, System.IOUtils,
  System.Variants, System.Generics.Collections, System.Win.ComObj, Winapi.ActiveX, AutoCalProtocolU;

type
  TDocumentText = record
    { .docx, .rtf, .doc or .txt to text; raises on an unreadable file }
    class function Extract(const FileName: String): String; static;
    class function FromDocx(const FileName: String): String; static;
    class function FromRtf(const FileName: String): String; static;
    class function FromDoc(const FileName: String): String; static;    { Word automation -> RTF }
    class function RtfToText(const Rtf: AnsiString): String; static;
    class function DocxXmlToText(const Xml: String): String; static;
    { &lt; &amp; &#NNN; &#xHH; -> characters }
    class function DecodeEntities(const S: String): String; static;
  end;

  TCertificateParser = record
    { fills Info from the certificate text; Warnings (may be nil) gets every field not found or cut.
      True when at least the serial or the certificate number was found }
    class function Parse(const Text: String; var Info: TSystemInfo; const Warnings: TStrings = nil): Boolean; static;
    { "9/15/2026", "2026-09-15" or "15.09.2026" }
    class function ParseDate(const S: String; out Date: TCalDate): Boolean; static;
    { the same shapes as "YYYY-MM-DD" whatever the year; '' when S is not a date }
    class function DateText(const S: String): String; static;
    { "100.064 33" -> 100.06433; "22.2 °C" -> 22.2; "4.42E-3" -> 0.00442 }
    class function ParseNumber(const S: String; out V: Double): Boolean; static;
  end;

implementation

{ TDocumentText }

class function TDocumentText.Extract(const FileName: String): String;
begin
  var Ext := LowerCase(ExtractFileExt(FileName));
  if Ext = '.docx' then Result := FromDocx(FileName)
  else if Ext = '.rtf' then Result := FromRtf(FileName)
  else if Ext = '.doc' then Result := FromDoc(FileName)
  else if Ext = '.txt' then Result := TFile.ReadAllText(FileName)
  else raise Exception.Create('Unsupported document type: ' + Ext);
end;

{ the package opened for shared reading: a document still open in Word is readable all the same }
function OpenShared(const FileName: String): TFileStream;
begin
  Result := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
end;

class function TDocumentText.FromDocx(const FileName: String): String;
begin
  var Stream := OpenShared(FileName);
  var Zip := TZipFile.Create;
  try
    Zip.Open(Stream, zmRead);
    var Bytes: TBytes;
    Zip.Read('word/document.xml', Bytes);
    Result := DocxXmlToText(TEncoding.UTF8.GetString(Bytes));
  finally
    Zip.Free;
    Stream.Free;
  end;
end;

{ paragraphs -> lines, table cells -> tabs, then every tag is dropped and entities decoded }
class function TDocumentText.DocxXmlToText(const Xml: String): String;
begin
  var S := Xml;
  S := TRegEx.Replace(S, '<w:tab\s*/>', #9);
  S := TRegEx.Replace(S, '<w:(br|cr)\s*/>', #10);
  S := TRegEx.Replace(S, '</w:tc>', #9);
  S := TRegEx.Replace(S, '</w:tr>', #10);
  S := TRegEx.Replace(S, '</w:p>|<w:p\s*/>', #10);
  { instruction text of fields (page numbers, merge fields) is not content }
  S := TRegEx.Replace(S, '<w:instrText[^>]*>.*?</w:instrText>', '', [roSingleLine]);
  S := TRegEx.Replace(S, '<[^>]+>', '');
  S := DecodeEntities(S);
  { a cell's own paragraph break would split the row: keep rows on one line }
  S := StringReplace(S, #10#9, #9, [rfReplaceAll]);
  Result := S;
end;

class function TDocumentText.DecodeEntities(const S: String): String;
begin
  var T := S;
  T := StringReplace(T, '&lt;',   '<', [rfReplaceAll]);
  T := StringReplace(T, '&gt;',   '>', [rfReplaceAll]);
  T := StringReplace(T, '&quot;', '"', [rfReplaceAll]);
  T := StringReplace(T, '&apos;', '''', [rfReplaceAll]);
  { numeric entities, hex and decimal; the matches are walked back to front so the indexes stay valid }
  var Matches := TRegEx.Matches(T, '&#(x[0-9A-Fa-f]+|\d+);');
  for var I := Matches.Count -1 downto 0 do
  begin
    var M := Matches[I];
    var Num := M.Groups[1].Value;
    if Num.StartsWith('x') then Num := '$' + Num.Substring(1);
    var Code := StrToIntDef(Num, 32);
    if (Code < 0) or (Code > $FFFF) then Code := 32;
    T := Copy(T, 1, M.Index -1) + Char(Code) + Copy(T, M.Index + M.Length, MaxInt);
  end;
  Result := StringReplace(T, '&amp;', '&', [rfReplaceAll]);
end;

class function TDocumentText.FromRtf(const FileName: String): String;
begin
  var Bytes := TFile.ReadAllBytes(FileName);
  var Raw: AnsiString;
  SetString(Raw, PAnsiChar(@Bytes[0]), Length(Bytes));
  Result := RtfToText(Raw);
end;

{ minimal RTF reader: text, \par \line \tab \cell \row, \'hh, \uN, skips the non-content destinations }
class function TDocumentText.RtfToText(const Rtf: AnsiString): String;
const
  SKIP: array [0..19] of AnsiString = ('fonttbl', 'colortbl', 'stylesheet', 'info', 'header', 'footer', 'headerl', 'headerr',
    'footerl', 'footerr', 'pict', 'object', 'fldinst', 'themedata', 'colorschememapping', 'datastore', 'latentstyles',
    'listtable', 'listoverridetable', 'rsidtbl');
type
  TState = record Uc: Integer; Skip: Boolean; end;
var
  Stack: array of TState;
  Cur: TState;
  Sb: TStringBuilder;
  I, N: Integer;
  SkipNext: Integer;        { bytes to drop after \uN }
begin
  Sb := TStringBuilder.Create;
  try
    Cur.Uc := 1;
    Cur.Skip := False;
    SkipNext := 0;
    N := Length(Rtf);
    I := 1;

    while I <= N do
    begin
      var C := Rtf[I];
      case C of
        '{':
          begin
            SetLength(Stack, Length(Stack) +1);
            Stack[High(Stack)] := Cur;
            Inc(I);
            { a destination group: "{\*\..." or "{\fonttbl" }
            if (I <= N) and (Rtf[I] = '\') then
            begin
              var J := I +1;
              var Star := (J <= N) and (Rtf[J] = '*');
              if Star then
              begin
                Cur.Skip := True;
              end
              else
              begin
                var W: AnsiString := '';
                while (J <= N) and CharInSet(Rtf[J], ['a'..'z']) do begin W := W + Rtf[J]; Inc(J); end;
                for var K := 0 to High(SKIP) do
                  if W = SKIP[K] then begin Cur.Skip := True; Break; end;
              end;
            end;
          end;

        '}':
          begin
            if Length(Stack) > 0 then
            begin
              Cur := Stack[High(Stack)];
              SetLength(Stack, Length(Stack) -1);
            end;
            Inc(I);
          end;

        '\':
          begin
            Inc(I);
            if I > N then Break;
            var D := Rtf[I];

            if D = '''' then                                   { \'hh }
            begin
              var Hex := AnsiString(Copy(Rtf, I +1, 2));
              Inc(I, 3);
              if SkipNext > 0 then begin Dec(SkipNext); Continue; end;
              if not Cur.Skip then
              begin
                var B: Byte := StrToIntDef('$' + String(Hex), 32);
                var A: AnsiString := AnsiChar(B);
                Sb.Append(String(A));                            { ANSI code page -> Unicode }
              end;
            end

            else if CharInSet(D, ['a'..'z', 'A'..'Z']) then       { control word }
            begin
              var W: AnsiString := '';
              while (I <= N) and CharInSet(Rtf[I], ['a'..'z', 'A'..'Z']) do begin W := W + Rtf[I]; Inc(I); end;
              var Num: AnsiString := '';
              while (I <= N) and CharInSet(Rtf[I], ['0'..'9', '-']) do begin Num := Num + Rtf[I]; Inc(I); end;
              if (I <= N) and (Rtf[I] = ' ') then Inc(I);          { the delimiter space belongs to the word }

              if not Cur.Skip then
              begin
                if (W = 'par') or (W = 'line') or (W = 'row') then Sb.Append(#10)
                else if (W = 'tab') or (W = 'cell') then Sb.Append(#9)
                else if W = 'uc' then Cur.Uc := StrToIntDef(String(Num), 1)
                else if W = 'u' then
                begin
                  var Code := StrToIntDef(String(Num), 63);
                  if Code < 0 then Code := Code +65536;
                  Sb.Append(Char(Code));
                  SkipNext := Cur.Uc;
                end
                else if W = 'emdash' then Sb.Append('-')
                else if W = 'endash' then Sb.Append('-')
                else if W = 'bullet' then Sb.Append('*')
                else if (W = 'lquote') or (W = 'rquote') then Sb.Append('''')
                else if (W = 'ldblquote') or (W = 'rdblquote') then Sb.Append('"');
              end;
            end

            else                                                 // escaped backslash and braces, \~ \_ \- \* and the rest
            begin
              Inc(I);
              if Cur.Skip then Continue;
              case D of
                '\', '{', '}': Sb.Append(Char(D));
                '~': Sb.Append(' ');
                '_': Sb.Append('-');
                #13, #10: ;
              end;
            end;
          end;

        #13, #10: Inc(I);

        else
          begin
            Inc(I);
            if SkipNext > 0 then begin Dec(SkipNext); Continue; end;
            if not Cur.Skip then Sb.Append(Char(C));
          end;
      end;
    end;

    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

class function TDocumentText.FromDoc(const FileName: String): String;
const
  wdFormatRTF = 6;
  wdDoNotSaveChanges = 0;
begin
  var Temp := TPath.Combine(TPath.GetTempPath, TPath.GetGUIDFileName + '.rtf');
  CoInitialize(nil);
  try
    var Word: OleVariant := CreateOleObject('Word.Application');
    try
      Word.Visible := False;
      Word.DisplayAlerts := 0;
      var Doc: OleVariant := Word.Documents.Open(FileName, False, True);     { ConfirmConversions, ReadOnly }
      try
        Doc.SaveAs2(Temp, wdFormatRTF);
      finally
        Doc.Close(wdDoNotSaveChanges);
      end;
    finally
      Word.Quit(wdDoNotSaveChanges);
    end;

    Result := FromRtf(Temp);
  finally
    CoUninitialize;
    if FileExists(Temp) then TFile.Delete(Temp);
  end;
end;

{ TCertificateParser }

class function TCertificateParser.DateText(const S: String): String;
begin
  var T := Trim(S);
  var M := TRegEx.Match(T, '^(\d{1,2})/(\d{1,2})/(\d{4})');                 { M/D/YYYY }
  if M.Success then
    Exit(Format('%s-%.2d-%.2d', [M.Groups[3].Value, StrToInt(M.Groups[1].Value), StrToInt(M.Groups[2].Value)]));

  M := TRegEx.Match(T, '^(\d{4})-(\d{2})-(\d{2})');                          { ISO }
  if M.Success then Exit(M.Value);

  M := TRegEx.Match(T, '^(\d{1,2})\.(\d{1,2})\.(\d{4})');                    { D.M.YYYY }
  if M.Success then
    Exit(Format('%s-%.2d-%.2d', [M.Groups[3].Value, StrToInt(M.Groups[2].Value), StrToInt(M.Groups[1].Value)]));

  Result := '';
end;

class function TCertificateParser.ParseDate(const S: String; out Date: TCalDate): Boolean;
begin
  Date := TCalDate.Empty;
  var T := DateText(S);
  Result := (T <> '') and TCalDate.Parse(T, Date);
end;

class function TCertificateParser.ParseNumber(const S: String; out V: Double): Boolean;
begin
  V := 0;
  { the leading number, digit groups after the point may be spaced: "0.050 009 86"; an exponent may follow }
  var M := TRegEx.Match(Trim(S), '^-?\d+(?:[.,]\d+(?:\s\d+)*)?(?:[eE][-+]?\d+)?');
  if not M.Success then Exit(False);
  var T := StringReplace(M.Value, ' ', '', [rfReplaceAll]);
  T := StringReplace(T, ',', '.', [rfReplaceAll]);
  Result := TryStrToFloat(T, V, TFormatSettings.Invariant);
end;

class function TCertificateParser.Parse(const Text: String; var Info: TSystemInfo; const Warnings: TStrings): Boolean;
const
  { every label that may share a line with another: a value ends where the next label starts }
  LABELS: array [0..15] of String = ('Certificate Number', 'Manufacturer', 'Description', 'Model', 'Serial',
    'Cal. Method', 'Procedure', 'Technician', 'Remarks', 'Calibration Date', 'Calibration Due', 'Temp.', 'Humidity',
    'Prev. Cal. Date', 'Days Since Last Cal.', 'Accreditation #');
  NUM = '(-?\d+(?:[.,]\d+(?:\s\d+)*)?)';
  { the shapes ParseDate reads; a value of this shape that ParseDate still refuses has a year the firmware rejects }
  DATE_SHAPE = '^\s*(\d{1,2}/\d{1,2}/\d{4}|\d{4}-\d{2}-\d{2}|\d{1,2}\.\d{1,2}\.\d{4})\s*$';
var
  Lines: TArray<String>;

  procedure Warn(const S: String);
  begin
    if Assigned(Warnings) then Warnings.Add(S);
  end;

  procedure WarnDate(const Name, V: String);
  begin
    if TRegEx.IsMatch(V, DATE_SHAPE) then
      Warn(Format('%s: "%s" refused, the firmware takes years from %d', [Name, V, MIN_YEAR]))
    else
      Warn(Format('%s: "%s" is not a date', [Name, V]));
  end;

  { the text after "Label:" on the first line that has it; cut at a tab or at the next known label }
  function ValueOf(const Lbl: String; const Found: PBoolean = nil): String;
  begin
    Result := '';
    if Found <> nil then Found^ := False;
    var Rx := TRegEx.Create('(?i)' + TRegEx.Escape(Lbl) + '\s*:\s*');

    for var L in Lines do
    begin
      var M := Rx.Match(L);
      if not M.Success then Continue;

      var V := Copy(L, M.Index + M.Length, MaxInt);
      { tab = next cell; an empty value means the value sits in the next cell }
      var Cells := V.Split([#9]);
      V := '';
      for var Cell in Cells do
        if Trim(Cell) <> '' then begin V := Trim(Cell); Break; end;

      { an empty value followed by another label (e.g. "Remarks:" next to "Humidity:") is empty, not that label's text }
      for var Other in LABELS do
      begin
        if SameText(Other, Lbl) then Continue;
        var P := Pos(LowerCase(Other), LowerCase(V));
        if P = 1 then V := ''
        else if P > 1 then V := Trim(Copy(V, 1, P -1));
      end;

      Result := V;
      if Found <> nil then Found^ := True;
      Exit;
    end;
  end;

  function LineIndex(const Needle: String; const From: Integer = 0): Integer;
  begin
    for var I := From to High(Lines) do
      if ContainsText(Lines[I], Needle) then Exit(I);
    Result := -1;
  end;

  { table cells: tab separated from a document, or two or more spaces in a flat text rendering }
  function Cells(const L: String): TArray<String>;
  begin
    Result := [];
    for var C in TRegEx.Split(L, '\t|\s{2,}') do
      if Trim(C) <> '' then Result := Result + [Trim(C)];
  end;

  function TextOf(const Lbl: String; const Cap: Integer; const Name: String): String;
  var
    Found: Boolean;
  begin
    Result := ValueOf(Lbl, @Found);
    if not Found then Warn(Name + ': not found');
    Result := TAutoCalProtocol.FitText(Result, Cap);
  end;

  function DateOf(const Lbl, Name: String): TCalDate;
  var
    Found: Boolean;
  begin
    var V := ValueOf(Lbl, @Found);
    if not Found then Warn(Name + ': not found')
    else if not ParseDate(V, Result) then WarnDate(Name, V);
  end;

  function NumberOf(const Lbl, Name: String): Double;
  var
    Found: Boolean;
  begin
    var V := ValueOf(Lbl, @Found);
    if not Found then Warn(Name + ': not found')
    else if not ParseNumber(V, Result) then Warn(Format('%s: "%s" is not a number', [Name, V]));
  end;

begin
  Info.Clear;
  Lines := StringReplace(Text, #13, '', [rfReplaceAll]).Split([#10]);
  for var I := 0 to High(Lines) do Lines[I] := Lines[I].TrimRight;

  { identity }
  Info.Cert         := TextOf('Certificate Number', CAP_CERT,         'certificate number');
  Info.Manufacturer := TextOf('Manufacturer',       CAP_MANUFACTURER, 'manufacturer');
  Info.Model        := TextOf('Model',              CAP_MODEL,        'model');
  Info.Serial       := TextOf('Serial',             CAP_SERIAL,       'serial');
  Info.Tech         := TextOf('Technician',         CAP_TECH,         'technician');
  Info.CalDate      := DateOf('Calibration Date',   'calibration date');
  Info.CalDue       := DateOf('Calibration Due',    'calibration due');
  Info.CalDatePrev  := DateOf('Prev. Cal. Date',    'previous calibration date');
  Info.Temp         := NumberOf('Temp.',            'temperature');
  Info.Humd         := NumberOf('Humidity',         'humidity');

  { owner: the first cell of the first non-empty line after the OWNER heading }
  var Idx := -1;
  for var I := 0 to High(Lines) do
    if TRegEx.IsMatch(Lines[I], '^\s*OWNER\b') then begin Idx := I; Break; end;
  if Idx < 0 then Warn('owner: not found')
  else
  begin
    for var I := Idx +1 to High(Lines) do
    begin
      var C := Cells(Lines[I]);
      if Length(C) = 0 then Continue;
      Info.Owner := TAutoCalProtocol.FitText(C[0], CAP_OWNER);
      Break;
    end;
  end;

  { comments: method, remarks, notes }
  var Comments := '';
  var Method := ValueOf('Cal. Method');
  if Method = '' then Method := ValueOf('Procedure');                   { the worksheet's name for it }
  if Method <> '' then Comments := 'Method: ' + Method;
  var Remarks := ValueOf('Remarks');
  if Remarks <> '' then Comments := Comments + IfThen(Comments <> '', '; ') + 'Remarks: ' + Remarks;
  Idx := LineIndex('NOTES');
  if Idx >= 0 then
    for var I := Idx +1 to High(Lines) do
    begin
      var L := Trim(Lines[I]);
      if L = '' then Continue;
      if ContainsText(L, 'STANDARDS USED') then Break;
      Comments := Comments + IfThen(Comments <> '', '; ') + 'Notes: ' + L;
      Break;
    end;
  if Length(Comments) >= CAP_COMMENTS then Warn('comments cut to 255 characters');
  Info.Comments := TAutoCalProtocol.FitText(Comments, CAP_COMMENTS);

  { shunt rows: "N  measured  unc  previous  diff" by cells, or by the spaced-number pattern }
  var Found := 0;
  var ShuntRx := TRegEx.Create('^\s*([1-8])\s+' + NUM + '\s+' + NUM + '\s+' + NUM + '\s+' + NUM + '\s*$');
  var First := LineIndex('MEASUREMENT DATA');
  var Last := LineIndex('NOTES', IfThen(First < 0, 0, First));
  if First < 0 then First := 0;
  if Last < 0 then Last := High(Lines);

  for var I := First to Last do
  begin
    var L := Lines[I];
    var Vals: TArray<String> := [];
    var C := Cells(L);
    if (Length(C) = 5) and TRegEx.IsMatch(C[0], '^[1-8]$') then Vals := C
    else
    begin
      var M := ShuntRx.Match(StringReplace(L, #9, ' ', [rfReplaceAll]));
      if M.Success then
        for var G := 1 to 5 do Vals := Vals + [M.Groups[G].Value];
    end;
    if Length(Vals) <> 5 then Continue;

    var N := StrToIntDef(Vals[0], 0) -1;
    if (N < 0) or (N >= CHANS) then Continue;
    var Rec := Default(TShuntRecord);
    Rec.Index := N;
    var Cur, Unc, Prev, Diff: Double;
    if not (ParseNumber(Vals[1], Cur) and ParseNumber(Vals[2], Unc) and
            ParseNumber(Vals[3], Prev) and ParseNumber(Vals[4], Diff)) then
    begin
      Warn(Format('shunt %d: a value is not a number: %s', [N +1, L]));
      Continue;
    end;
    { the entry saved and shown is the document's text as printed ("0.999 915 6"); the number is parsed from
      that same text, so what the user sees is what goes to the board }
    Rec.Put(sfCurrent,     Cur,  Vals[1]);
    Rec.Put(sfUncertainty, Unc,  Vals[2]);
    Rec.Put(sfPrevious,    Prev, Vals[3]);
    Rec.Put(sfDifference,  Diff, Vals[4]);
    Info.Shunts[N] := Rec;
    Inc(Found);
  end;
  if Found = 0 then Warn('shunt table: no rows found');

  { standards used: "serial  mfr  model  cal due" }
  Found := 0;
  First := LineIndex('STANDARDS USED');
  if First < 0 then Warn('standards table: not found')
  else
  begin
    Last := LineIndex('COMMENTS', First);
    if Last < 0 then Last := High(Lines);
    var TraceRx := TRegEx.Create('^\s*(\S+)\s+(.+?)\s+(\S+)\s+(\d{1,2}/\d{1,2}/\d{4}|\d{4}-\d{2}-\d{2})\s*$');

    for var I := First +1 to Last do
    begin
      if Found >= TRACE_COUNT then Break;
      var L := Lines[I];
      if ContainsText(L, 'Serial #') then Continue;              { the header row }
      var Vals: TArray<String> := [];
      var C := Cells(L);
      if Length(C) = 4 then Vals := C
      else
      begin
        var M := TraceRx.Match(StringReplace(L, #9, ' ', [rfReplaceAll]));
        if M.Success then
          for var G := 1 to 4 do Vals := Vals + [M.Groups[G].Value];
      end;
      if Length(Vals) <> 4 then Continue;

      var Rec := Default(TTraceRecord);
      if not TRegEx.IsMatch(Vals[3], DATE_SHAPE) then Continue;   { not a data row }
      { a due date the firmware refuses still leaves the standard on record, its date kept as text }
      Rec.CalDueStr := DateText(Vals[3]);
      if not ParseDate(Vals[3], Rec.CalDue) then WarnDate(Format('standard %d cal due', [Found +1]), Vals[3]);
      Rec.Serial       := TAutoCalProtocol.FitText(Vals[0], CAP_TRACE_SERIAL);
      Rec.Manufacturer := TAutoCalProtocol.FitText(Vals[1], CAP_TRACE_MANUF);
      Rec.Model        := TAutoCalProtocol.FitText(Vals[2], CAP_TRACE_MODEL);
      if (Length(Vals[0]) >= CAP_TRACE_SERIAL) or (Length(Vals[1]) >= CAP_TRACE_MANUF) or (Length(Vals[2]) >= CAP_TRACE_MODEL) then
        Warn(Format('standard %d: a text was cut to fit', [Found +1]));
      Info.Trace[Found] := Rec;
      Inc(Found);
    end;
    if Found = 0 then Warn('standards table: no rows found');
  end;

  Result := (Info.Serial <> '') or (Info.Cert <> '');
end;

end.
