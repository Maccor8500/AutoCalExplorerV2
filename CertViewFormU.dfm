object CertViewForm: TCertViewForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu, biMaximize]
  Caption = 'Certificate preview'
  ClientHeight = 900
  ClientWidth = 660
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  StyleName = 'Windows'
  OnCreate = FormCreate
  TextHeight = 15
  object BottomPanel: TPanel
    Left = 0
    Top = 864
    Width = 660
    Height = 36
    Align = alBottom
    BevelOuter = bvNone
    ShowCaption = False
    TabOrder = 0
    StyleName = 'Windows'
    object InfoLbl: TLabel
      AlignWithMargins = True
      Left = 205
      Top = 10
      Width = 359
      Height = 23
      Margins.Left = 10
      Margins.Top = 10
      Align = alClient
      AutoSize = False
      Caption = '-'
      EllipsisPosition = epPathEllipsis
    end
    object PrintBtn: TButton
      AlignWithMargins = True
      Left = 6
      Top = 5
      Width = 80
      Height = 26
      Margins.Left = 6
      Margins.Top = 5
      Margins.Bottom = 5
      Align = alLeft
      Caption = 'Print...'
      TabOrder = 0
      OnClick = PrintBtnClick
    end
    object SaveBtn: TButton
      AlignWithMargins = True
      Left = 92
      Top = 5
      Width = 100
      Height = 26
      Margins.Top = 5
      Margins.Bottom = 5
      Align = alLeft
      Caption = 'Save PDF As...'
      TabOrder = 1
      OnClick = SaveBtnClick
    end
    object CloseBtn: TButton
      AlignWithMargins = True
      Left = 574
      Top = 5
      Width = 80
      Height = 26
      Margins.Top = 5
      Margins.Right = 6
      Margins.Bottom = 5
      Align = alRight
      Cancel = True
      Caption = 'Close'
      TabOrder = 2
      OnClick = CloseBtnClick
    end
  end
end
