object CertificateFrame: TCertificateFrame
  Left = 0
  Top = 0
  Width = 720
  Height = 644
  DoubleBuffered = True
  ParentDoubleBuffered = False
  TabOrder = 0
  object OwnerLbl: TLabel
    Left = 10
    Top = 8
    Width = 330
    Height = 15
    AutoSize = False
    Caption = 'Owner'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object OwnerNameLbl: TLabel
    Left = 10
    Top = 32
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Name'
  end
  object OwnerAddr1Lbl: TLabel
    Left = 10
    Top = 59
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Address'
  end
  object OwnerAddr2Lbl: TLabel
    Left = 10
    Top = 86
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'City, state, zip'
  end
  object InstrumentLbl: TLabel
    Left = 370
    Top = 8
    Width = 330
    Height = 15
    AutoSize = False
    Caption = 'Instrument'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object MfrLbl: TLabel
    Left = 370
    Top = 32
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Manufacturer'
  end
  object DescLbl: TLabel
    Left = 370
    Top = 59
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Description'
  end
  object ModelLbl: TLabel
    Left = 370
    Top = 86
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Model'
  end
  object SerialLbl: TLabel
    Left = 370
    Top = 113
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Serial'
  end
  object InfoTitleLbl: TLabel
    Left = 10
    Top = 142
    Width = 330
    Height = 15
    AutoSize = False
    Caption = 'Certificate information'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object Proc1Lbl: TLabel
    Left = 10
    Top = 166
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Procedure'
  end
  object Proc2Lbl: TLabel
    Left = 10
    Top = 193
    Width = 92
    Height = 15
    AutoSize = False
    Caption = '(second line)'
  end
  object TechLbl: TLabel
    Left = 10
    Top = 220
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Technician'
  end
  object RemarksLbl: TLabel
    Left = 10
    Top = 247
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Remarks'
  end
  object CondLbl: TLabel
    Left = 370
    Top = 142
    Width = 330
    Height = 15
    AutoSize = False
    Caption = 'Conditions, previous calibration, form'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object TempLbl: TLabel
    Left = 370
    Top = 166
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Temp. ('#176'C)'
  end
  object HumLbl: TLabel
    Left = 548
    Top = 166
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Humidity (%RH)'
  end
  object PrevLbl: TLabel
    Left = 370
    Top = 193
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Prev. cal. date'
  end
  object FormNoLbl: TLabel
    Left = 370
    Top = 220
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Form No.'
  end
  object RevLbl: TLabel
    Left = 576
    Top = 220
    Width = 30
    Height = 15
    AutoSize = False
    Caption = 'Rev.'
  end
  object RevDateLbl: TLabel
    Left = 370
    Top = 247
    Width = 92
    Height = 15
    AutoSize = False
    Caption = 'Rev. date'
  end
  object NotesLbl: TLabel
    Left = 10
    Top = 278
    Width = 700
    Height = 15
    AutoSize = False
    Caption = 'Notes'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object StdLbl: TLabel
    Left = 10
    Top = 330
    Width = 700
    Height = 15
    AutoSize = False
    Caption = 
      'Standards used  ::  meters (grey) are set on their Fluke sheets ' +
      ' ::  an Ohm Labs line prints only when a shunt used it'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object CommentsLbl: TLabel
    Left = 10
    Top = 496
    Width = 700
    Height = 15
    AutoSize = False
    Caption = 'Comments'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object InfoLbl: TLabel
    Left = 10
    Top = 590
    Width = 700
    Height = 15
    AutoSize = False
    Caption = '-'
    EllipsisPosition = epPathEllipsis
  end
  object OwnerNameEdit: TEdit
    Left = 106
    Top = 28
    Width = 244
    Height = 23
    TabOrder = 0
  end
  object OwnerAddr1Edit: TEdit
    Left = 106
    Top = 55
    Width = 244
    Height = 23
    TabOrder = 1
  end
  object OwnerAddr2Edit: TEdit
    Left = 106
    Top = 82
    Width = 244
    Height = 23
    TabOrder = 2
  end
  object MfrEdit: TEdit
    Left = 466
    Top = 28
    Width = 244
    Height = 23
    TabOrder = 3
  end
  object DescEdit: TEdit
    Left = 466
    Top = 55
    Width = 244
    Height = 23
    TabOrder = 4
  end
  object ModelEdit: TEdit
    Left = 466
    Top = 82
    Width = 244
    Height = 23
    TabOrder = 5
  end
  object SerialEdit: TEdit
    Left = 466
    Top = 109
    Width = 244
    Height = 23
    TabOrder = 6
  end
  object Proc1Edit: TEdit
    Left = 106
    Top = 162
    Width = 244
    Height = 23
    TabOrder = 7
  end
  object Proc2Edit: TEdit
    Left = 106
    Top = 189
    Width = 244
    Height = 23
    TabOrder = 8
  end
  object TechEdit: TEdit
    Left = 106
    Top = 216
    Width = 244
    Height = 23
    TabOrder = 9
  end
  object RemarksEdit: TEdit
    Left = 106
    Top = 243
    Width = 244
    Height = 23
    TabOrder = 10
  end
  object TempEdit: TEdit
    Left = 466
    Top = 162
    Width = 70
    Height = 23
    TabOrder = 11
  end
  object HumEdit: TEdit
    Left = 640
    Top = 162
    Width = 70
    Height = 23
    TabOrder = 12
  end
  object PrevPick: TDateTimePicker
    Left = 466
    Top = 189
    Width = 110
    Height = 23
    Date = 46337.000000000000000000
    Time = 46337.000000000000000000
    ShowCheckbox = True
    Checked = False
    TabOrder = 13
  end
  object FormNoEdit: TEdit
    Left = 466
    Top = 216
    Width = 100
    Height = 23
    TabOrder = 14
  end
  object RevEdit: TEdit
    Left = 610
    Top = 216
    Width = 100
    Height = 23
    TabOrder = 15
  end
  object RevDateEdit: TEdit
    Left = 466
    Top = 243
    Width = 100
    Height = 23
    TabOrder = 16
  end
  object NotesEdit: TEdit
    Left = 10
    Top = 298
    Width = 700
    Height = 23
    TabOrder = 17
  end
  object StdGrid: TStringGrid
    Left = 10
    Top = 350
    Width = 700
    Height = 138
    ColCount = 4
    DefaultRowHeight = 21
    FixedCols = 0
    RowCount = 6
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goEditing, goTabs]
    ScrollBars = ssVertical
    TabOrder = 18
    StyleName = 'Iceberg Classico'
    OnDrawCell = StdGridDrawCell
    OnSelectCell = StdGridSelectCell
    ColWidths = (
      170
      180
      170
      170)
  end
  object CommentsMemo: TMemo
    Left = 10
    Top = 516
    Width = 700
    Height = 68
    ScrollBars = ssVertical
    TabOrder = 19
  end
  object DefaultsBtn: TButton
    Left = 10
    Top = 612
    Width = 90
    Height = 26
    Hint = 'Show the text of the LDF-78 workbook'#39's Certificate sheet'
    ParentShowHint = False
    ShowHint = True
    Caption = 'Defaults'
    TabOrder = 20
    OnClick = DefaultsBtnClick
  end
  object ReloadBtn: TButton
    Left = 106
    Top = 612
    Width = 90
    Height = 26
    Hint = 'Drop the edits and show what is saved'
    ParentShowHint = False
    ShowHint = True
    Caption = 'Reload'
    TabOrder = 21
    OnClick = ReloadBtnClick
  end
  object PreviewBtn: TButton
    Left = 396
    Top = 612
    Width = 100
    Height = 26
    Hint = 'Save, then show the certificate; Print is on the preview'
    ParentShowHint = False
    ShowHint = True
    Caption = 'Preview...'
    TabOrder = 22
    OnClick = PreviewBtnClick
  end
  object ExportBtn: TButton
    Left = 502
    Top = 612
    Width = 110
    Height = 26
    Hint = 'Save, then write the certificate to a PDF file'
    ParentShowHint = False
    ShowHint = True
    Caption = 'Export PDF...'
    TabOrder = 23
    OnClick = ExportBtnClick
  end
  object SaveBtn: TButton
    Left = 620
    Top = 612
    Width = 90
    Height = 26
    Caption = 'Save'
    TabOrder = 24
    OnClick = SaveBtnClick
  end
end
