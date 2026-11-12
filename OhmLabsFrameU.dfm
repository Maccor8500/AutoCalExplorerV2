object OhmLabsFrame: TOhmLabsFrame
  Left = 0
  Top = 0
  Width = 720
  Height = 646
  DoubleBuffered = True
  ParentDoubleBuffered = False
  TabOrder = 0
  object MrsLbl: TLabel
    Left = 10
    Top = 12
    Width = 150
    Height = 15
    Caption = 'Ohm-Labs MRS'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object MrsDueLbl: TLabel
    Left = 518
    Top = 12
    Width = 80
    Height = 15
    Alignment = taRightJustify
    AutoSize = False
    Caption = 'Due'
  end
  object MrsDuePick: TDateTimePicker
    Left = 604
    Top = 8
    Width = 106
    Height = 23
    Date = 46337.000000000000000000
    Time = 46337.000000000000000000
    ShowCheckbox = True
    Checked = False
    TabOrder = 0
    OnChange = DuePickChange
  end
  object MrsGrid: TStringGrid
    Left = 10
    Top = 36
    Width = 700
    Height = 182
    ColCount = 6
    DefaultRowHeight = 21
    FixedCols = 0
    RowCount = 8
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goEditing, goTabs]
    ScrollBars = ssVertical
    TabOrder = 1
    StyleName = 'Iceberg Classico'
    OnDrawCell = GridDrawCell
    OnSelectCell = GridSelectCell
    OnSetEditText = GridSetEditText
    ColWidths = (
      110
      124
      112
      110
      124
      108)
  end
  object Mcs10Lbl: TLabel
    Left = 10
    Top = 230
    Width = 150
    Height = 15
    Caption = 'Ohm-Labs MCS 0.01'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object Mcs10DueLbl: TLabel
    Left = 518
    Top = 230
    Width = 80
    Height = 15
    Alignment = taRightJustify
    AutoSize = False
    Caption = 'Due'
  end
  object Mcs10DuePick: TDateTimePicker
    Left = 604
    Top = 226
    Width = 106
    Height = 23
    Date = 46337.000000000000000000
    Time = 46337.000000000000000000
    ShowCheckbox = True
    Checked = False
    TabOrder = 2
    OnChange = DuePickChange
  end
  object Mcs10Grid: TStringGrid
    Left = 10
    Top = 254
    Width = 700
    Height = 138
    ColCount = 6
    DefaultRowHeight = 21
    FixedCols = 0
    RowCount = 6
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goEditing, goTabs]
    ScrollBars = ssVertical
    TabOrder = 3
    StyleName = 'Iceberg Classico'
    OnDrawCell = GridDrawCell
    OnSelectCell = GridSelectCell
    OnSetEditText = GridSetEditText
    ColWidths = (
      110
      124
      112
      110
      124
      108)
  end
  object Mcs1Lbl: TLabel
    Left = 10
    Top = 404
    Width = 150
    Height = 15
    Caption = 'Ohm-Labs MCS 0.001'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object Mcs1DueLbl: TLabel
    Left = 518
    Top = 404
    Width = 80
    Height = 15
    Alignment = taRightJustify
    AutoSize = False
    Caption = 'Due'
  end
  object Mcs1DuePick: TDateTimePicker
    Left = 604
    Top = 400
    Width = 106
    Height = 23
    Date = 46337.000000000000000000
    Time = 46337.000000000000000000
    ShowCheckbox = True
    Checked = False
    TabOrder = 4
    OnChange = DuePickChange
  end
  object Mcs1Grid: TStringGrid
    Left = 10
    Top = 428
    Width = 700
    Height = 138
    ColCount = 6
    DefaultRowHeight = 21
    FixedCols = 0
    RowCount = 6
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goEditing, goTabs]
    ScrollBars = ssVertical
    TabOrder = 5
    StyleName = 'Iceberg Classico'
    OnDrawCell = GridDrawCell
    OnSelectCell = GridSelectCell
    OnSetEditText = GridSetEditText
    ColWidths = (
      110
      124
      112
      110
      124
      108)
  end
  object HintLbl: TLabel
    Left = 10
    Top = 574
    Width = 700
    Height = 15
    AutoSize = False
    Caption = 
      'All uncertainties are expressed at 95 % confidence, k = 2. Grey ' +
      'columns are worked out: stability and certificate uncertainty, RSS.'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
  end
  object InfoLbl: TLabel
    Left = 10
    Top = 593
    Width = 700
    Height = 15
    AutoSize = False
    Caption = '-'
    EllipsisPosition = epPathEllipsis
  end
  object DefaultsBtn: TButton
    Left = 10
    Top = 614
    Width = 90
    Height = 26
    Hint = 'Show the figures of the LDF-78 workbook'#39's Ohm Labs sheet'
    Caption = 'Defaults'
    ParentShowHint = False
    ShowHint = True
    TabOrder = 6
    OnClick = DefaultsBtnClick
  end
  object ReloadBtn: TButton
    Left = 106
    Top = 614
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
    Top = 614
    Width = 90
    Height = 26
    Caption = 'Save'
    TabOrder = 8
    OnClick = SaveBtnClick
  end
end
