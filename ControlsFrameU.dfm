object ControlsFrame: TControlsFrame
  Left = 0
  Top = 0
  Width = 740
  Height = 690
  DoubleBuffered = True
  ParentDoubleBuffered = False
  TabOrder = 0
  object TopPanel: TPanel
    AlignWithMargins = True
    Left = 6
    Top = 6
    Width = 728
    Height = 29
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Align = alTop
    BevelOuter = bvNone
    ShowCaption = False
    TabOrder = 0
    StyleName = 'Windows'
    object StatusBtn: TSpeedButton
      AlignWithMargins = True
      Left = 625
      Top = 3
      Width = 100
      Height = 23
      Align = alRight
      Caption = 'Firmware info'
      Enabled = False
      OnClick = StatusBtnClick
    end
  end
  object VChanRBG: TRadioGroup
    Tag = 1
    AlignWithMargins = True
    Left = 6
    Top = 41
    Width = 728
    Height = 50
    Margins.Left = 6
    Margins.Right = 6
    Align = alTop
    Caption = ' Maccor channel voltage sense (CHVS1..8, M1..M8) '
    Columns = 9
    Items.Strings = (
      '1'
      '2'
      '3'
      '4'
      '5'
      '6'
      '7'
      '8'
      'Off')
    TabOrder = 1
    OnClick = RelayRBGClick
  end
  object IChanRBG: TRadioGroup
    Tag = 2
    AlignWithMargins = True
    Left = 6
    Top = 97
    Width = 728
    Height = 50
    Margins.Left = 6
    Margins.Right = 6
    Align = alTop
    Caption = ' Maccor channel current (CHI1..8, M1..M8) '
    Columns = 9
    Items.Strings = (
      '1'
      '2'
      '3'
      '4'
      '5'
      '6'
      '7'
      '8'
      'Off')
    TabOrder = 2
    OnClick = RelayRBGClick
  end
  object VShuntRBG: TRadioGroup
    Tag = 3
    AlignWithMargins = True
    Left = 6
    Top = 153
    Width = 728
    Height = 50
    Margins.Left = 6
    Margins.Right = 6
    Align = alTop
    Caption = ' Voltage sense shunt (RNGV1..8, R1..R8) '
    Columns = 9
    Items.Strings = (
      '1'
      '2'
      '3'
      '4'
      '5'
      '6'
      '7'
      '8'
      'Off')
    TabOrder = 3
    OnClick = RelayRBGClick
  end
  object IShuntRBG: TRadioGroup
    Tag = 4
    AlignWithMargins = True
    Left = 6
    Top = 209
    Width = 728
    Height = 50
    Margins.Left = 6
    Margins.Right = 6
    Align = alTop
    Caption = ' Current shunt (RNGI1..8, R1..R8) '
    Columns = 9
    Items.Strings = (
      '1'
      '2'
      '3'
      '4'
      '5'
      '6'
      '7'
      '8'
      'Off')
    TabOrder = 4
    OnClick = RelayRBGClick
  end
  object LowerPanel: TPanel
    AlignWithMargins = True
    Left = 6
    Top = 265
    Width = 728
    Height = 70
    Margins.Left = 6
    Margins.Right = 6
    Align = alTop
    BevelOuter = bvNone
    ShowCaption = False
    TabOrder = 5
    StyleName = 'Windows'
    object SupplyGB: TGroupBox
      AlignWithMargins = True
      Left = 0
      Top = 0
      Width = 360
      Height = 70
      Margins.Left = 0
      Margins.Top = 0
      Margins.Bottom = 0
      Align = alLeft
      Caption = ' Supplies (checked = ON) '
      TabOrder = 0
      object FanBox: TCheckBox
        Tag = 5
        Left = 16
        Top = 30
        Width = 80
        Height = 19
        Caption = 'Fan'
        TabOrder = 0
        OnClick = SupplyBoxClick
      end
      object VSrcBox: TCheckBox
        Tag = 6
        Left = 89
        Top = 30
        Width = 110
        Height = 19
        Caption = 'Voltage source'
        TabOrder = 1
        OnClick = SupplyBoxClick
      end
      object DPSBox: TCheckBox
        Tag = 7
        Left = 200
        Top = 30
        Width = 120
        Height = 19
        Caption = 'Discharge supply'
        TabOrder = 2
        OnClick = SupplyBoxClick
      end
    end
    object ResetGB: TGroupBox
      AlignWithMargins = True
      Left = 366
      Top = 0
      Width = 362
      Height = 70
      Margins.Top = 0
      Margins.Right = 0
      Margins.Bottom = 0
      Align = alClient
      Caption = ' Reset '
      TabOrder = 1
      object ResetChansBtn: TSpeedButton
        Left = 12
        Top = 26
        Width = 80
        Height = 25
        Caption = 'Channels'
        OnClick = ResetBtnClick
      end
      object ResetShuntsBtn: TSpeedButton
        Tag = 1
        Left = 98
        Top = 26
        Width = 80
        Height = 25
        Caption = 'Shunts'
        OnClick = ResetBtnClick
      end
      object ResetAllBtn: TSpeedButton
        Tag = 3
        Left = 184
        Top = 26
        Width = 80
        Height = 25
        Caption = 'All'
        OnClick = ResetBtnClick
      end
      object RestartBtn: TSpeedButton
        Tag = 4
        Left = 270
        Top = 26
        Width = 80
        Height = 25
        Caption = 'Restart FW'
        OnClick = ResetBtnClick
      end
    end
  end
  object StateGB: TGroupBox
    AlignWithMargins = True
    Left = 6
    Top = 341
    Width = 728
    Height = 343
    Margins.Left = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Align = alClient
    Caption = 
      ' Board state (as last commanded from here; the board is not poll' +
      'ed) '
    TabOrder = 6
    object StateList: TListView
      AlignWithMargins = True
      Left = 5
      Top = 20
      Width = 718
      Height = 299
      Align = alClient
      Columns = <
        item
          Caption = 'Item'
          Width = 190
        end
        item
          Caption = 'Value'
          Width = -2
          WidthType = (
            -2)
        end>
      ColumnClick = False
      FlatScrollBars = True
      GridLines = True
      StyleName = 'Iceberg Classico'
      ReadOnly = True
      RowSelect = True
      TabOrder = 0
      ViewStyle = vsReport
      ExplicitHeight = 301
    end
  end
end
