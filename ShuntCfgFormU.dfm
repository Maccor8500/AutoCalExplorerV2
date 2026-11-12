object ShuntCfgForm: TShuntCfgForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Shunt plan'
  ClientHeight = 290
  ClientWidth = 956
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  OnCreate = FormCreate
  OnMouseEnter = FormMouseEnter
  TextHeight = 15
  object InfoLbl: TLabel
    Left = 8
    Top = 232
    Width = 940
    Height = 15
    AutoSize = False
    Caption = '-'
    EllipsisPosition = epPathEllipsis
  end
  object Grid: TStringGrid
    Left = 8
    Top = 8
    Width = 940
    Height = 214
    ColCount = 9
    DefaultRowHeight = 22
    RowCount = 9
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goEditing, goTabs]
    ScrollBars = ssNone
    TabOrder = 0
    StyleName = 'Iceberg Classico'
    OnDrawCell = GridDrawCell
    OnMouseLeave = GridMouseLeave
    OnSelectCell = GridSelectCell
    OnSetEditText = GridSetEditText
  end
  object DefaultsBtn: TButton
    Left = 8
    Top = 256
    Width = 90
    Height = 26
    Caption = 'Defaults'
    TabOrder = 2
    OnClick = DefaultsBtnClick
  end
  object SaveBtn: TButton
    Left = 858
    Top = 256
    Width = 90
    Height = 26
    Caption = 'Save'
    TabOrder = 3
    OnClick = SaveBtnClick
  end
  object Panel1: TPanel
    Left = 776
    Top = 288
    Width = 185
    Height = 41
    BevelOuter = bvNone
    TabOrder = 4
  end
end
