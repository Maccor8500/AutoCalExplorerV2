object MainForm: TMainForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu, biMinimize]
  Caption = 'AutoCalibrator 528LB (Rev E) Test Application'
  ClientHeight = 937
  ClientWidth = 756
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  StyleName = 'Windows'
  OnCanResize = FormCanResize
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  TextHeight = 15
  object Splitter: TSplitter
    AlignWithMargins = True
    Left = 3
    Top = 802
    Width = 750
    Height = 3
    Cursor = crVSplit
    Align = alBottom
    Beveled = True
    StyleName = 'Windows'
    ExplicitLeft = 8
    ExplicitTop = 657
    ExplicitWidth = 756
  end
  object Pages: TPageControl
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 750
    Height = 790
    Margins.Bottom = 6
    ActivePage = ControlsTab
    Align = alClient
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    TabOrder = 0
    OnChanging = PagesChanging
    ExplicitHeight = 747
    object ControlsTab: TTabSheet
      Caption = ' Controls '
    end
    object CalibrationTab: TTabSheet
      Caption = ' Calibration '
      ImageIndex = 1
    end
    object FirmwareTab: TTabSheet
      Caption = ' Firmware && Bootloader '
      ImageIndex = 2
    end
    object RecordTab: TTabSheet
      Caption = ' Calibration Record '
      ImageIndex = 3
    end
    object ConfigTab: TTabSheet
      Caption = ' Configurations '
      ImageIndex = 4
      object ConfigPages: TPageControl
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 736
        Height = 754
        ActivePage = OhmLabsTab
        Align = alClient
        TabOrder = 0
        ExplicitHeight = 682
        object OhmLabsTab: TTabSheet
          Caption = ' Ohm Labs '
        end
        object Fluke8508Tab: TTabSheet
          Caption = ' Fluke 8508A '
          ImageIndex = 1
        end
        object Fluke8588Tab: TTabSheet
          Caption = ' Fluke 8588A '
          ImageIndex = 2
        end
        object CertificateTab: TTabSheet
          Caption = ' Certificate '
          ImageIndex = 3
        end
      end
    end
  end
  object Memo: TRichEdit
    AlignWithMargins = True
    Left = 6
    Top = 811
    Width = 744
    Height = 92
    Margins.Left = 6
    Margins.Right = 6
    Align = alBottom
    Color = clInactiveBorder
    Font.Charset = ANSI_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ScrollBars = ssVertical
    TabOrder = 1
    ExplicitTop = 813
  end
  object BottomPanel: TPanel
    Left = 0
    Top = 906
    Width = 756
    Height = 31
    Align = alBottom
    BevelOuter = bvNone
    ShowCaption = False
    TabOrder = 2
    StyleName = 'Windows'
    ExplicitTop = 863
    object StartBtn: TSpeedButton
      AlignWithMargins = True
      Left = 157
      Top = 3
      Width = 80
      Height = 25
      Align = alLeft
      Caption = 'Start'
      OnClick = StartBtnClick
      ExplicitLeft = 259
    end
    object CopyBtn: TButton
      AlignWithMargins = True
      Left = 707
      Top = 3
      Width = 42
      Height = 25
      Hint = 'Copy to clipboard'
      Margins.Left = 1
      Margins.Right = 7
      Align = alRight
      Caption = 'C'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 0
      OnClick = CopyBtnClick
    end
    object ClearBtn: TButton
      AlignWithMargins = True
      Left = 645
      Top = 3
      Width = 60
      Height = 25
      Margins.Left = 1
      Margins.Right = 1
      Align = alRight
      Caption = 'Clear'
      TabOrder = 1
      OnClick = ClearBtnClick
    end
    object AddrEdit: TEdit
      AlignWithMargins = True
      Left = 3
      Top = 3
      Width = 148
      Height = 25
      Align = alLeft
      Alignment = taCenter
      TabOrder = 2
      Text = '192.168.126.214'
      ExplicitHeight = 23
    end
  end
end
