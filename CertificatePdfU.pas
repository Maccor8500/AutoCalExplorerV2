unit CertificatePdfU;

{
  GenerateCertificate: the certificate member of the data file (CertificateU) as a one-page A4 PDF, laid out
  as the LDF-78 workbook's "Certificate" sheet prints.

  The PDF is built with PDFium's own page-object calls (PdfiumLib: text, path and image objects on a new
  page), nothing else; pdfium.dll sits beside the exe. The layout is the sheet's grid: 32 columns of equal
  width between the margins and the sheet's row heights, every text in the cell it has there, in the sheet's
  font (Calibri: 12 pt for the certificate number, 11 pt, 10 pt in the measurement rows, 8 pt for the section
  titles, notes and comments) and with its borders (thin, and medium under the two table headings). The page
  footer is the sheet's: form number left, revision centred, revision date right. From the notes down the rows
  flow, so a longer note, more standards or a longer comment push what follows instead of running over it.

  The header picture is the RCDATA resource 'header_image' (a PNG); a build without it takes HeaderImage.png
  beside the exe. Calibri is embedded whole (PDFium does not subset), which is what makes the file about 1.7 MB.
}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Math, System.IOUtils, Vcl.Graphics, Vcl.Imaging.pngimage,
  PdfiumCore, PdfiumLib, CertificateU;

const
  HEADER_RESOURCE = 'header_image';
  HEADER_FILE = 'HeaderImage.png';

{ points PdfiumCore at the pdfium.dll beside the exe; called by everything here that uses it }
procedure UsePdfium;
{ the certificate member as the data file has it. False, with the reason in Why, when there is none or the file cannot be written }
function GenerateCertificate(const FileName: String; out Why: String): Boolean; overload;
function GenerateCertificate(const Cert: TCertificate; const FileName: String; out Why: String): Boolean; overload;

implementation

const
  { A4, points }
  PAGE_W = 595.276;
  PAGE_H = 841.890;
  { the sheet's page margins: 0.75 in left and right, 0.5 in top }
  MARGIN_X = 54.0;
  MARGIN_TOP = 36.0;
  COLS = 32;
  COL_W = (PAGE_W - 2 * MARGIN_X) / COLS;
  ROW_H = 15.0;                               { the sheet's default row height }
  PAD = 2.2;                                  { a cell's text from its left edge }
  THIN = 0.5;
  MEDIUM = 1.25;
  { the picture's width on the sheet against the sheet's printable width (480 pt of 504) }
  HEADER_SHARE = 480 / 504;
  FOOTER_BASE = 26.0;                         { the footer's baseline above the page's bottom edge }
  WRAP_PITCH = 10.9;                          { line to line in the wrapped 8 pt texts }
  OHM = #$03A9;
  MICRO = #$00B5;
  DEGREE = #$00B0;

type
  TAlign = (alLeft, alRight, alCentre);

  TCertPage = class(TObject)
    private
      Doc: TPdfDocument;
      Page: TPdfPage;
      Font: FPDF_FONT;
      FontBytes: TBytes;

      procedure LoadFont;
      function Width(const S: String; const Size: Double): Double;
      { baseline at Base, measured down from the page's top edge }
      procedure TextAt(const X, Base: Double; const S: String; const Size: Double; const Align: TAlign = alLeft);
      procedure Rule(const Y: Double; const ColFrom, ColTo: Integer; const Weight: Double);
      procedure Picture;
      function Wrap(const S: String; const Size, MaxWidth: Double): TArray<String>;

    public
      constructor Create;
      destructor Destroy; override;
      procedure Draw(const Cert: TCertificate);
      procedure Save(const FileName: String);
  end;

{
  pdfium.dll is expected beside the exe (the project's post-build step puts it there). A build that did not run
  that step has none: it is then fetched from the development tree's library folder, as the tester engine's
  dlls are, and when it is in neither place this says so by name (Windows' own word for it is "error 126")
}
procedure UsePdfium;
const
  LIBRARY_COPY = '..\..\..\..\..\..\Delphi\Libraries\PDFium\pdfium.dll';     { from <project>\<platform>\<config> }
begin
  var Beside := ExtractFilePath(ParamStr(0)) + 'pdfium.dll';
  if not FileExists(Beside) then
  begin
    var Source := ExpandFileName(ExtractFilePath(ParamStr(0)) + LIBRARY_COPY);
    if FileExists(Source) then
      try
        TFile.Copy(Source, Beside, False);
      except
        { a folder that cannot be written to: the message below still names what is missing }
      end;
  end;
  if not FileExists(Beside) then
    raise Exception.CreateFmt('pdfium.dll is missing: it must sit beside %s (the 64-bit pdfium.dll of Delphi\Libraries\PDFium)',
      [ExtractFileName(ParamStr(0))]);
  if PDFiumDllFileName = '' then PDFiumDllFileName := Beside;
end;

{
  PDFium's text objects lose the hyphen-minus of a font loaded this way (it comes out as a missing glyph), so
  the text is handed over with the hyphen proper, U+2010, which draws the same mark
}
function Glyphs(const S: String): String;
begin
  Result := StringReplace(S, '-', #$2010, [rfReplaceAll]);
end;

function ColX(const Col: Integer): Double;
begin
  Result := MARGIN_X + Col * COL_W;
end;

{ the sheet's row heights, rows 1 to 24: the picture, the certificate number, the titles, the measurement rows }
function RowHeight(const Row: Integer): Double;
begin
  case Row of
    1: Result := 91.5;
    2, 16: Result := 15.75;
    3: Result := 14.25;
    17..24: Result := 12.75;
  else
    Result := ROW_H;
  end;
end;

{ a row's bottom edge, down from the page's top edge }
function RowBottom(const Row: Integer): Double;
begin
  Result := MARGIN_TOP;
  for var R := 1 to Row do Result := Result + RowHeight(R);
end;

{ where a text of Size sits in a row that ends at Bottom: the sheet aligns to the bottom of the cell }
function BaseIn(const Bottom, Size: Double): Double;
begin
  Result := Bottom - 0.27 * Size - 0.8;
end;

{ TCertPage }

constructor TCertPage.Create;
begin
  inherited;
  UsePdfium;
  Doc := TPdfDocument.Create;
  if not Doc.NewDocument then raise Exception.Create('PDFium could not start a new document');
  Page := Doc.NewPage(PAGE_W, PAGE_H);
  if Page = nil then raise Exception.Create('PDFium could not add the page');
  LoadFont;
end;

destructor TCertPage.Destroy;
begin
  if (Font <> nil) and Assigned(FPDFFont_Close) then FPDFFont_Close(Font);
  FreeAndNil(Doc);                            { frees its pages }
  inherited;
end;

{ Calibri, the sheet's font; Arial where a machine has none. Loaded as a CID font so every character maps (ohm, micro, degree) }
procedure TCertPage.LoadFont;
const
  FACES: array [0..1] of String = ('calibri.ttf', 'arial.ttf');
begin
  var Dir := TPath.Combine(GetEnvironmentVariable('WINDIR'), 'Fonts');
  for var Face in FACES do
  begin
    var Path := TPath.Combine(Dir, Face);
    if not FileExists(Path) then Continue;
    FontBytes := TFile.ReadAllBytes(Path);
    Font := FPDFText_LoadFont(Doc.Handle, PByte(FontBytes), Length(FontBytes), FPDF_FONT_TRUETYPE, 1);
    if Font <> nil then Exit;
  end;
  raise Exception.CreateFmt('No font for the certificate: neither %s nor %s could be loaded from %s', [FACES[0], FACES[1], Dir]);
end;

function TCertPage.Width(const S: String; const Size: Double): Double;
var
  L, B, R, T: Single;
begin
  Result := 0;
  if S = '' then Exit;
  var Obj := FPDFPageObj_CreateTextObj(Doc.Handle, Font, Size);
  if Obj = nil then Exit;
  try
    var G := Glyphs(S);
    if (FPDFText_SetText(Obj, FPDF_WIDESTRING(PWideChar(G))) <> 0) and (FPDFPageObj_GetBounds(Obj, L, B, R, T) <> 0) then
      Result := R - L;
  finally
    FPDFPageObj_Destroy(Obj);
  end;
end;

procedure TCertPage.TextAt(const X, Base: Double; const S: String; const Size: Double; const Align: TAlign);
begin
  if S = '' then Exit;
  var Obj := FPDFPageObj_CreateTextObj(Doc.Handle, Font, Size);
  if Obj = nil then raise Exception.Create('PDFium could not make a text object');
  var G := Glyphs(S);
  if FPDFText_SetText(Obj, FPDF_WIDESTRING(PWideChar(G))) = 0 then
  begin
    FPDFPageObj_Destroy(Obj);
    raise Exception.CreateFmt('PDFium could not set the text "%s"', [S]);
  end;

  var Left := X;
  case Align of
    alRight: Left := X - Width(S, Size);
    alCentre: Left := X - Width(S, Size) / 2;
  end;
  FPDFPageObj_Transform(Obj, 1, 0, 0, 1, Left, PAGE_H - Base);
  FPDFPage_InsertObject(Page.Handle, Obj);    { the page owns it from here }
end;

{ a border: from the left edge of ColFrom to the left edge of ColTo, Y down from the page's top edge }
procedure TCertPage.Rule(const Y: Double; const ColFrom, ColTo: Integer; const Weight: Double);
begin
  var Path := FPDFPageObj_CreateNewPath(ColX(ColFrom), PAGE_H - Y);
  if Path = nil then raise Exception.Create('PDFium could not make a path object');
  FPDFPath_LineTo(Path, ColX(ColTo), PAGE_H - Y);
  FPDFPageObj_SetStrokeColor(Path, 0, 0, 0, 255);
  FPDFPageObj_SetStrokeWidth(Path, Weight);
  FPDFPath_SetDrawMode(Path, FPDF_FILLMODE_NONE, 1);
  FPDFPage_InsertObject(Page.Handle, Path);
end;

{ the header picture across the top of the first row, at the share of the width it has on the sheet }
procedure TCertPage.Picture;
var
  Source: TStream;
  Handle: FPDF_PAGE;
begin
  if FindResource(HInstance, PChar(HEADER_RESOURCE), RT_RCDATA) <> 0 then
    Source := TResourceStream.Create(HInstance, HEADER_RESOURCE, RT_RCDATA)
  else if FileExists(ExtractFilePath(ParamStr(0)) + HEADER_FILE) then
    Source := TFileStream.Create(ExtractFilePath(ParamStr(0)) + HEADER_FILE, fmOpenRead or fmShareDenyWrite)
  else
    raise Exception.CreateFmt('The header picture is missing: no "%s" resource in the exe and no %s beside it',
      [HEADER_RESOURCE, HEADER_FILE]);

  var Png := TPngImage.Create;
  var Bmp := TBitmap.Create;
  try
    Png.LoadFromStream(Source);
    { onto white: the page is white and the picture may be transparent around its artwork }
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(Png.Width, Png.Height);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, Bmp.Width, Bmp.Height));
    Bmp.Canvas.Draw(0, 0, Png);

    var Stride := Bmp.Width * 4;
    var Pixels: TBytes;
    SetLength(Pixels, Stride * Bmp.Height);
    for var Y := 0 to Bmp.Height -1 do Move(Bmp.ScanLine[Y]^, Pixels[Y * Stride], Stride);

    var Image := FPDFBitmap_CreateEx(Bmp.Width, Bmp.Height, FPDFBitmap_BGRx, @Pixels[0], Stride);
    if Image = nil then raise Exception.Create('PDFium could not take the header picture');
    try
      var Obj := FPDFPageObj_NewImageObj(Doc.Handle);
      if Obj = nil then raise Exception.Create('PDFium could not make an image object');
      Handle := Page.Handle;
      if FPDFImageObj_SetBitmap(@Handle, 1, Obj, Image) = 0 then
      begin
        FPDFPageObj_Destroy(Obj);
        raise Exception.Create('PDFium could not set the header picture');
      end;
      var W := (PAGE_W - 2 * MARGIN_X) * HEADER_SHARE;
      var H := W * Bmp.Height / Bmp.Width;
      FPDFImageObj_SetMatrix(Obj, W, 0, 0, H, MARGIN_X, PAGE_H - MARGIN_TOP - H);
      FPDFPage_InsertObject(Page.Handle, Obj);
    finally
      FPDFBitmap_Destroy(Image);
    end;
  finally
    Bmp.Free;
    Png.Free;
    Source.Free;
  end;
end;

{ S in lines no wider than MaxWidth, broken at spaces; the spaces of the text are kept as they are }
function TCertPage.Wrap(const S: String; const Size, MaxWidth: Double): TArray<String>;
begin
  Result := nil;
  var Line := '';
  for var Word in S.Split([' ']) do
  begin
    { the line as it would be drawn with this word on it: its real width, kerning and all }
    if (Line <> '') and (Word <> '') and (Width(Line + ' ' + Word, Size) > MaxWidth) then
    begin
      Result := Result + [TrimRight(Line)];
      Line := Word;
    end
    else if Line = '' then Line := Word       { a space at the start of a line is dropped }
    else Line := Line + ' ' + Word;
  end;
  if Trim(Line) <> '' then Result := Result + [TrimRight(Line)];
end;

procedure TCertPage.Draw(const Cert: TCertificate);
var
  Y: Double;                                  { the flowing part's place, down from the page's top edge }

  { a text in its cell: column Col of row Row }
  procedure Cell(const Col, Row: Integer; const S: String; const Size: Double = 11);
  begin
    TextAt(ColX(Col) + PAD, BaseIn(RowBottom(Row), Size), S, Size);
  end;

  function OneDecimal(const Text: String): String;
  var
    D: Double;
  begin
    Result := Trim(Text);
    if (Result <> '') and TryStrToFloat(Result, D, TFormatSettings.Invariant) then
      Result := FormatFloat('0.0', D, TFormatSettings.Invariant);
  end;

  { a section's title: 8 pt on a default row with a thin rule under it }
  procedure Title(const S: String);
  begin
    Y := Y + ROW_H;
    TextAt(ColX(0) + PAD, BaseIn(Y, 8), S, 8);
    Rule(Y, 0, COLS, THIN);
  end;

  { a wrapped 8 pt text under a title, in a box of at least MinHeight }
  procedure Flow(const S: String; const MinHeight: Double);
  begin
    var Lines := Wrap(S, 8, PAGE_W - 2 * MARGIN_X - 2 * PAD);
    var Top := Y;
    for var I := 0 to High(Lines) do TextAt(ColX(0) + PAD, Top + 9.2 + I * WRAP_PITCH, Lines[I], 8);
    Y := Max(Top + MinHeight, Top + 9.2 + High(Lines) * WRAP_PITCH + 4.5);
  end;

begin
  Picture;

  Cell(0, 2, 'Certificate Number:', 12);
  Cell(7, 2, Cert.Number, 12);

  Cell(0, 3, 'OWNER', 8);
  Rule(RowBottom(3), 0, 15, THIN);
  Cell(18, 3, 'INSTRUMENT', 8);
  Rule(RowBottom(3), 18, COLS, THIN);
  Cell(1, 4, Cert.Inputs.OwnerName);
  Cell(1, 5, Cert.Inputs.OwnerAddress1);
  Cell(1, 6, Cert.Inputs.OwnerAddress2);
  Cell(19, 4, 'Manufacturer:');
  Cell(25, 4, Cert.Inputs.Manufacturer);
  Cell(19, 5, 'Description:');
  Cell(25, 5, Cert.Inputs.Description);
  Cell(19, 6, 'Model:');
  Cell(25, 6, Cert.Inputs.Model);
  Cell(19, 7, 'Serial:');
  Cell(25, 7, Cert.Inputs.Serial);

  Cell(0, 8, 'CERTIFICATE INFORMATION', 8);
  Rule(RowBottom(8), 0, COLS, THIN);
  Cell(1, 9, 'Procedure:');
  Cell(5, 9, Cert.Inputs.Procedure1);
  Cell(5, 10, Cert.Inputs.Procedure2);
  Cell(1, 11, 'Technician:');
  Cell(5, 11, Cert.Inputs.Technician);
  Cell(1, 12, 'Remarks:');
  Cell(5, 12, Cert.Inputs.Remarks);
  Cell(19, 9, 'Calibration Date:');
  Cell(25, 9, CertDateText(Cert.CalDate));
  Cell(19, 10, 'Calibration Due:');
  Cell(25, 10, CertDateText(Cert.CalDue));
  Cell(19, 11, 'Temp.:');
  Cell(25, 11, OneDecimal(Cert.Inputs.Temp));
  Cell(27, 11, DEGREE + 'C');
  Cell(19, 12, 'Humidity:');
  Cell(25, 12, OneDecimal(Cert.Inputs.Humidity));
  Cell(27, 12, '%RH');

  Cell(20, 14, 'Prev. Cal. Date:');
  Cell(27, 14, CertDateText(Cert.Inputs.PrevCalDate));
  Cell(0, 15, 'MEASUREMENT DATA (AS FOUND / AS LEFT)', 8);
  Cell(20, 15, 'Days Since Last Cal.:');
  if Cert.HaveDays then TextAt(ColX(COLS) - PAD, BaseIn(RowBottom(15), 11), IntToStr(Cert.DaysSince), 11, alRight);
  Rule(RowBottom(15), 0, COLS, THIN);

  Cell(1, 16, 'Shunt');
  Cell(5, 16, 'Measured Value (' + OHM + ')');
  Cell(14, 16, 'Unc (' + MICRO + OHM + '/' + OHM + ')');
  Cell(20, 16, 'Prev. Value (' + OHM + ')');
  Cell(27, 16, 'Diff (%)');
  Rule(RowBottom(16), 0, COLS, MEDIUM);
  for var I := 1 to CERT_SHUNTS do
  begin
    var R := Cert.Shunts[I];
    var Row := 16 + I;
    Cell(1, Row, IntToStr(I), 10);
    if R.HaveMeasured then
    begin
      Cell(5, Row, CertOhmsText(R.Measured, R.Nominal), 10);
      Cell(14, Row, FormatFloat('0.00', R.Unc, TFormatSettings.Invariant), 10);
    end;
    if R.Previous > 0 then Cell(20, Row, CertOhmsText(R.Previous, R.Nominal), 10);
    if R.HaveDiff then Cell(27, Row, FormatFloat('0.00000', R.Diff, TFormatSettings.Invariant), 10);
  end;

  { from here the rows flow }
  Y := RowBottom(24);
  Title('NOTES');
  Flow(Cert.Inputs.Notes, ROW_H);

  Title('STANDARDS USED');
  Y := Y + RowHeight(16);
  TextAt(ColX(1) + PAD, BaseIn(Y, 11), 'Serial #', 11);
  TextAt(ColX(9) + PAD, BaseIn(Y, 11), 'Mfr.', 11);
  TextAt(ColX(17) + PAD, BaseIn(Y, 11), 'Model', 11);
  TextAt(ColX(25) + PAD, BaseIn(Y, 11), 'Cal. Due', 11);
  Rule(Y, 0, COLS, MEDIUM);
  for var S in Cert.Standards do
  begin
    Y := Y + ROW_H;
    TextAt(ColX(1) + PAD, BaseIn(Y, 11), S.Serial, 11);
    TextAt(ColX(9) + PAD, BaseIn(Y, 11), S.Mfr, 11);
    TextAt(ColX(17) + PAD, BaseIn(Y, 11), S.Model, 11);
    TextAt(ColX(25) + PAD, BaseIn(Y, 11), CertDateText(S.Due), 11);
  end;
  { the sheet has four lines there }
  if Length(Cert.Standards) < 4 then Y := Y + (4 - Length(Cert.Standards)) * ROW_H;

  Title('COMMENTS');
  Flow(Cert.Inputs.Comments, 7 * ROW_H);
  Rule(Y, 0, COLS, THIN);

  { three empty rows, then the signatures }
  Y := Y + 4 * ROW_H;
  TextAt(ColX(0) + PAD, BaseIn(Y, 11), 'Performed by:', 11);
  Rule(Y, 5, 15, THIN);
  TextAt(ColX(16) + PAD, BaseIn(Y, 11), 'Reviewed by:', 11);
  Rule(Y, 21, COLS, THIN);

  { the sheet's page footer }
  var Foot := PAGE_H - FOOTER_BASE;
  TextAt(MARGIN_X, Foot, 'Form No.: ' + Cert.Inputs.FormNo, 11);
  TextAt(PAGE_W / 2, Foot, Cert.Inputs.Rev, 11, alCentre);
  TextAt(PAGE_W - MARGIN_X, Foot, 'Rev. Date: ' + Cert.Inputs.RevDate, 11, alRight);

  Page.ApplyChanges;
end;

procedure TCertPage.Save(const FileName: String);
begin
  Doc.SaveToFile(FileName);
end;

function GenerateCertificate(const Cert: TCertificate; const FileName: String; out Why: String): Boolean;
begin
  Result := False;
  Why := '';
  try
    var Sheet := TCertPage.Create;
    try
      Sheet.Draw(Cert);
      Sheet.Save(FileName);
      Result := True;
    finally
      Sheet.Free;
    end;
  except
    on E: Exception do Why := E.Message;
  end;
end;

function GenerateCertificate(const FileName: String; out Why: String): Boolean;
var
  Cert: TCertificate;
begin
  Result := TCertificateData.Load(Cert, Why) and GenerateCertificate(Cert, FileName, Why);
end;

end.
