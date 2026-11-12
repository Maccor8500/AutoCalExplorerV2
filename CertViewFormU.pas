unit CertViewFormU;

{
  The certificate's preview: a PDF shown by PDFium's own control (PdfiumCtrl.TPdfControl, fitted to the
  window's width), with Print and Save PDF As under it.

  Print goes through PdfiumCtrl's printer class with the print dialog; the printer is set to A4 before the
  dialog opens (it can still be changed there). Save PDF As copies the file that is shown.

  The control is created in code, as MacUniModCal's preview does: PdfiumCore loads pdfium.dll on first use, not
  at start-up, so the application runs without the dll until a certificate is previewed.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Math, System.IOUtils, System.UITypes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Printers, PdfiumCore, PdfiumCtrl;

type
  TCertViewForm = class(TForm)
    BottomPanel: TPanel;
    PrintBtn: TButton;
    SaveBtn: TButton;
    CloseBtn: TButton;
    InfoLbl: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure PrintBtnClick(Sender: TObject);
    procedure SaveBtnClick(Sender: TObject);
    procedure CloseBtnClick(Sender: TObject);

  private
    View: TPdfControl;
    PdfPath: String;                          { the file shown }
    SaveName: String;                         { the name Save PDF As proposes }

    procedure Say(const Text: String; const Bad: Boolean = False);
  public
    { shows PdfFile modally; SuggestedName is what Save PDF As proposes (no folder, no extension needed) }
    class procedure Preview(const AOwner: TComponent; const PdfFile, SuggestedName: String);
  end;

implementation

{$R *.dfm}

uses
  CertificatePdfU;

{ the selected printer's paper to A4; a printer that will not take it, or no printer at all, is left as it is }
procedure PaperA4;
var
  Device, Driver, Port: array [0..511] of Char;
  Mode: THandle;
begin
  try
    if Printer.Printers.Count = 0 then Exit;
    { the VCL marks this pair deprecated and offers nothing else that reaches the printer's DEVMODE }
    {$WARN SYMBOL_DEPRECATED OFF}
    Printer.GetPrinter(Device, Driver, Port, Mode);
    if Mode = 0 then Exit;
    var Dev: PDeviceMode := GlobalLock(Mode);
    if Dev = nil then Exit;
    try
      Dev^.dmFields := Dev^.dmFields or DM_PAPERSIZE or DM_ORIENTATION;
      Dev^.dmPaperSize := DMPAPER_A4;
      Dev^.dmOrientation := DMORIENT_PORTRAIT;
    finally
      GlobalUnlock(Mode);
    end;
    Printer.SetPrinter(Device, Driver, Port, Mode);
    {$WARN SYMBOL_DEPRECATED ON}
  except
    { the print dialog still opens, on the printer's own paper }
  end;
end;

class procedure TCertViewForm.Preview(const AOwner: TComponent; const PdfFile, SuggestedName: String);
begin
  var Form := TCertViewForm.Create(AOwner);
  try
    Form.PdfPath := PdfFile;
    Form.SaveName := SuggestedName;
    try
      Form.View.LoadFromFile(PdfFile);
      Form.Say('A4  ::  ' + SuggestedName);
    except
      on E: Exception do Form.Say(E.Message, True);
    end;
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

procedure TCertViewForm.FormCreate(Sender: TObject);
begin
  UsePdfium;
  View := TPdfControl.Create(Self);
  View.Parent := Self;
  View.Align := alClient;
  View.AlignWithMargins := True;
  View.ScaleMode := smFitWidth;
  View.Color := clWhite;
  View.ChangePageOnMouseScrolling := True;
  View.SmoothScroll := True;
  { as tall as the screen allows: an A4 page at this width wants about 1.41 times it }
  Height := Min(Round(ClientWidth * 1.41) + BottomPanel.Height + 60, Screen.WorkAreaHeight - 40);
end;

procedure TCertViewForm.Say(const Text: String; const Bad: Boolean);
begin
  InfoLbl.Caption := Text;
  if Bad then InfoLbl.Font.Color := clRed else InfoLbl.Font.Color := clWindowText;
end;

procedure TCertViewForm.PrintBtnClick(Sender: TObject);
begin
  if (View.Document = nil) or not View.Document.Active then Exit;
  if Printer.Printers.Count = 0 then
  begin
    Say('No printer is installed on this machine', True);
    Exit;
  end;
  PaperA4;
  try
    if TPdfDocumentVclPrinter.PrintDocument(View.Document, 'Certificate ' + SaveName, True, False, Handle) then
      Say('Sent to the printer  ::  ' + Printer.Printers[Printer.PrinterIndex])
    else
      Say('Not printed');
  except
    on E: Exception do Say('Not printed: ' + E.Message, True);
  end;
end;

procedure TCertViewForm.SaveBtnClick(Sender: TObject);
begin
  var Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title := 'Save certificate';
    Dlg.Filter := 'PDF (*.pdf)|*.pdf';
    Dlg.DefaultExt := 'pdf';
    Dlg.FileName := SaveName + '.pdf';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt, ofPathMustExist];
    if not Dlg.Execute then Exit;
    try
      TFile.Copy(PdfPath, Dlg.FileName, True);
      Say('Saved  ::  ' + Dlg.FileName);
    except
      on E: Exception do Say('Not saved: ' + E.Message, True);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TCertViewForm.CloseBtnClick(Sender: TObject);
begin
  Close;
end;

end.
