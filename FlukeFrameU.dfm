object FlukeFrame: TFlukeFrame
  Left = 0
  Top = 0
  Width = 720
  Height = 432
  DoubleBuffered = True
  ParentDoubleBuffered = False
  TabOrder = 0
  object TitleLbl: TLabel
    Left = 10
    Top = 12
    Width = 200
    Height = 15
    AutoSize = False
    Caption = 'Fluke'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object DigitsLbl: TLabel
    Left = 10
    Top = 46
    Width = 104
    Height = 15
    Caption = 'Digits of resolution'
  end
  object DigitsNoteLbl: TLabel
    Left = 204
    Top = 46
    Width = 506
    Height = 15
    AutoSize = False
    Caption = '-'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
  end
  object MetersLbl: TLabel
    Left = 10
    Top = 86
    Width = 200
    Height = 15
    AutoSize = False
    Caption = 'Meters'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object Serial1Lbl: TLabel
    Left = 10
    Top = 116
    Width = 92
    Height = 15
    Caption = 'Meter 1   Serial #'
  end
  object Due1Lbl: TLabel
    Left = 300
    Top = 116
    Width = 60
    Height = 15
    Alignment = taRightJustify
    AutoSize = False
    Caption = 'Cal. due'
  end
  object Serial2Lbl: TLabel
    Left = 10
    Top = 146
    Width = 92
    Height = 15
    Caption = 'Meter 2   Serial #'
  end
  object Due2Lbl: TLabel
    Left = 300
    Top = 146
    Width = 60
    Height = 15
    Alignment = taRightJustify
    AutoSize = False
    Caption = 'Cal. due'
  end
  object SpecLbl: TLabel
    Left = 10
    Top = 190
    Width = 200
    Height = 15
    AutoSize = False
    Caption = 'DC voltage accuracy'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object HintLbl: TLabel
    Left = 10
    Top = 358
    Width = 700
    Height = 15
    AutoSize = False
    Caption =
      'Per range, as the uncertainty budget takes it: ppm of reading + ' +
      'ppm of range, and the calibration uncertainty. A blank row is no range.'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
  end
  object InfoLbl: TLabel
    Left = 10
    Top = 378
    Width = 700
    Height = 15
    AutoSize = False
    Caption = '-'
    EllipsisPosition = epPathEllipsis
  end
  object DigitsSpin: TSpinEdit
    Left = 136
    Top = 42
    Width = 56
    Height = 24
    MaxValue = 8
    MinValue = 5
    TabOrder = 0
    Value = 7
    OnChange = DigitsSpinChange
  end
  object Serial1Edit: TEdit
    Left = 136
    Top = 112
    Width = 150
    Height = 23
    TabOrder = 1
  end
  object Due1Pick: TDateTimePicker
    Left = 366
    Top = 112
    Width = 106
    Height = 23
    Date = 46337.000000000000000000
    Time = 46337.000000000000000000
    ShowCheckbox = True
    TabOrder = 2
    OnChange = DuePickChange
  end
  object Serial2Edit: TEdit
    Left = 136
    Top = 142
    Width = 150
    Height = 23
    TabOrder = 3
  end
  object Due2Pick: TDateTimePicker
    Left = 366
    Top = 142
    Width = 106
    Height = 23
    Date = 46337.000000000000000000
    Time = 46337.000000000000000000
    ShowCheckbox = True
    TabOrder = 4
    OnChange = DuePickChange
  end
  object SpecGrid: TStringGrid
    Left = 10
    Top = 212
    Width = 616
    Height = 138
    ColCount = 4
    DefaultRowHeight = 21
    FixedCols = 0
    RowCount = 6
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goEditing, goTabs]
    ScrollBars = ssVertical
    TabOrder = 5
    StyleName = 'Iceberg Classico'
    OnDrawCell = SpecGridDrawCell
    ColWidths = (
      150
      150
      150
      150)
  end
  object DefaultsBtn: TButton
    Left = 10
    Top = 400
    Width = 90
    Height = 26
    Hint = 'Show the figures of the LDF-78 workbook'
    Caption = 'Defaults'
    ParentShowHint = False
    ShowHint = True
    TabOrder = 6
    OnClick = DefaultsBtnClick
  end
  object ReloadBtn: TButton
    Left = 106
    Top = 400
    Width = 90
    Height = 26
    Hint = 'Drop the edits and show what is saved'
    Caption = 'Reload'
    ParentShowHint = False
    ShowHint = True
    TabOrder = 7
    OnClick = ReloadBtnClick
  end
  object SaveBtn: TButton
    Left = 620
    Top = 400
    Width = 90
    Height = 26
    Caption = 'Save'
    TabOrder = 8
    OnClick = SaveBtnClick
  end
end
