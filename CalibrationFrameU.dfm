object CalibrationFrame: TCalibrationFrame
  Left = 0
  Top = 0
  Width = 721
  Height = 750
  Margins.Left = 1
  Margins.Right = 4
  DoubleBuffered = True
  ParentDoubleBuffered = False
  TabOrder = 0
  object DataGB: TGroupBox
    AlignWithMargins = True
    Left = 6
    Top = 6
    Width = 709
    Height = 140
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Align = alTop
    Caption = ' Channel Data [Live!] '
    TabOrder = 0
    object Grid: TStringGrid
      AlignWithMargins = True
      Left = 8
      Top = 20
      Width = 693
      Height = 108
      Margins.Left = 6
      Margins.Right = 6
      Margins.Bottom = 10
      Align = alClient
      BevelInner = bvNone
      BevelOuter = bvRaised
      ColCount = 4
      DefaultColWidth = 176
      DefaultRowHeight = 20
      DoubleBuffered = True
      Enabled = False
      FixedCols = 0
      FixedRows = 0
      Options = [goFixedHorzLine, goHorzLine, goFixedRowDefAlign]
      ParentDoubleBuffered = False
      ScrollBars = ssNone
      TabOrder = 0
      StyleName = 'Iceberg Classico'
      OnDrawCell = GridDrawCell
    end
  end
  object ControlGB: TGroupBox
    AlignWithMargins = True
    Left = 6
    Top = 152
    Width = 709
    Height = 569
    Margins.Left = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Align = alTop
    Caption = ' Control '
    TabOrder = 1
    object ErrLbl: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 546
      Width = 699
      Height = 18
      Align = alTop
      Alignment = taCenter
      AutoSize = False
      Caption = '...'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clRed
      Font.Height = -12
      Font.Name = 'Consolas'
      Font.Style = []
      ParentFont = False
      Layout = tlCenter
      StyleName = 'Windows'
      ExplicitLeft = 2
      ExplicitTop = 510
      ExplicitWidth = 724
      ExplicitHeight = 20
    end
    object StatGB: TGroupBox
      AlignWithMargins = True
      Left = 5
      Top = 305
      Width = 697
      Height = 235
      Margins.Top = 0
      Margins.Right = 5
      Align = alTop
      Caption = ' Statistics '
      TabOrder = 0
      ExplicitHeight = 232
      object AcceptPanel: TPanel
        Left = 2
        Top = 197
        Width = 693
        Height = 31
        Align = alTop
        BevelOuter = bvNone
        ShowCaption = False
        TabOrder = 1
        DesignSize = (
          693
          31)
        object AcceptBtn: TSpeedButton
          Left = 596
          Top = 3
          Width = 94
          Height = 25
          Anchors = [akTop, akRight]
          Caption = 'Accept'
          StyleName = 'Windows'
          OnClick = AcceptBtnClick
        end
      end
      object StatGrid: TStringGrid
        AlignWithMargins = True
        Left = 5
        Top = 20
        Width = 687
        Height = 174
        Align = alTop
        ColCount = 6
        DefaultColWidth = 112
        DefaultRowHeight = 18
        DoubleBuffered = True
        FixedCols = 0
        RowCount = 9
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine]
        ParentDoubleBuffered = False
        ScrollBars = ssVertical
        TabOrder = 0
        StyleName = 'Iceberg Classico'
        OnDrawCell = StatGridDrawCell
        ColWidths = (
          104
          112
          112
          112
          124
          112)
      end
    end
    object Panel1: TPanel
      Left = 2
      Top = 17
      Width = 705
      Height = 288
      Align = alTop
      BevelOuter = bvNone
      Caption = 'Panel1'
      ShowCaption = False
      TabOrder = 1
      object AutoCalGB: TGroupBox
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 192
        Height = 282
        Align = alLeft
        Caption = ' Autocalibrator '
        TabOrder = 0
        object ShuntCfgBtn: TSpeedButton
          AlignWithMargins = True
          Left = 5
          Top = 252
          Width = 182
          Height = 25
          Align = alBottom
          Caption = 'Configure Shunts'
          StyleName = 'Windows'
          OnClick = ShuntCfgBtnClick
          ExplicitLeft = 2
          ExplicitTop = 255
          ExplicitWidth = 188
        end
        object PosRBG: TRadioGroup
          AlignWithMargins = True
          Left = 111
          Top = 20
          Width = 76
          Height = 226
          Align = alClient
          Caption = ' Positions '
          Items.Strings = (
            '1'
            '2'
            '3'
            '4'
            '5'
            '6'
            '7'
            '8')
          TabOrder = 0
        end
        object ShuntRBG: TRadioGroup
          AlignWithMargins = True
          Left = 6
          Top = 20
          Width = 99
          Height = 226
          Margins.Left = 4
          Align = alLeft
          Caption = ' Shunts '
          Items.Strings = (
            '1'
            '2'
            '3'
            '4'
            '5'
            '6'
            '7'
            '8')
          TabOrder = 1
        end
      end
      object MeterGB: TGroupBox
        AlignWithMargins = True
        Left = 201
        Top = 1
        Width = 288
        Height = 284
        Margins.Top = 1
        Margins.Right = 4
        Align = alClient
        Caption = 'Meter(s)'
        TabOrder = 1
        object MeterPanel: TPanel
          AlignWithMargins = True
          Left = 5
          Top = 20
          Width = 278
          Height = 56
          Margins.Bottom = 0
          Align = alTop
          BevelOuter = bvNone
          ShowCaption = False
          TabOrder = 0
          object Meter1Box: TCheckBox
            Tag = 1
            Left = 8
            Top = 6
            Width = 270
            Height = 19
            Caption = 'Fluke 8508A (x2)'
            Checked = True
            State = cbChecked
            TabOrder = 0
            OnClick = MeterBoxClick
          end
          object Meter2Box: TCheckBox
            Tag = 2
            Left = 8
            Top = 31
            Width = 270
            Height = 19
            Caption = 'Fluke 8588A (x2)'
            TabOrder = 1
            OnClick = MeterBoxClick
          end
        end
        object BenchPanel: TPanel
          AlignWithMargins = True
          Left = 5
          Top = 77
          Width = 278
          Height = 202
          Margins.Top = 1
          Align = alClient
          BevelOuter = bvNone
          ParentColor = True
          ShowCaption = False
          TabOrder = 1
          object GatewayLbl: TLabel
            Left = 40
            Top = 9
            Width = 58
            Height = 15
            AutoSize = False
            Caption = 'IP Address'
          end
          object MeterBtn: TSpeedButton
            Left = 216
            Top = 5
            Width = 73
            Height = 25
            Caption = 'Connect'
            StyleName = 'Windows'
            OnClick = MeterBtnClick
          end
          object ReadBtn: TSpeedButton
            Left = 195
            Top = 172
            Width = 92
            Height = 25
            Caption = 'Read'
            Enabled = False
            StyleName = 'Windows'
            OnClick = ReadBtnClick
          end
          object SampleLbl: TLabel
            Left = 8
            Top = 153
            Width = 44
            Height = 15
            Caption = 'Samples'
          end
          object SettleLbl: TLabel
            Left = 8
            Top = 104
            Width = 97
            Height = 15
            Caption = 'Settling Time (ms)'
          end
          object IntervalLbl: TLabel
            Left = 87
            Top = 153
            Width = 39
            Height = 15
            Caption = 'Interval'
          end
          object GatewayEdit: TEdit
            Left = 104
            Top = 6
            Width = 106
            Height = 23
            Alignment = taCenter
            TabOrder = 0
            Text = '192.168.126.216'
            TextHint = 'Prologix IP'
          end
          object Use1Box: TCheckBox
            Left = 8
            Top = 39
            Width = 94
            Height = 19
            Caption = 'Meter 1'
            Checked = True
            State = cbChecked
            TabOrder = 1
          end
          object Addr1Edit: TSpinEdit
            Left = 104
            Top = 37
            Width = 46
            Height = 24
            Hint = 'GPIB address'
            MaxValue = 30
            MinValue = 0
            ParentShowHint = False
            ShowHint = True
            TabOrder = 2
            Value = 1
          end
          object Role1Combo: TComboBox
            Left = 154
            Top = 37
            Width = 135
            Height = 23
            Style = csDropDownList
            ItemIndex = 0
            TabOrder = 3
            Text = 'Shunt voltage (DCV)'
            Items.Strings = (
              'Shunt voltage (DCV)'
              'Current (DCI)')
          end
          object Use2Box: TCheckBox
            Left = 8
            Top = 67
            Width = 94
            Height = 19
            Caption = 'Meter 2'
            Checked = True
            State = cbChecked
            TabOrder = 4
          end
          object Addr2Edit: TSpinEdit
            Left = 104
            Top = 65
            Width = 46
            Height = 24
            Hint = 'GPIB address'
            MaxValue = 30
            MinValue = 0
            ParentShowHint = False
            ShowHint = True
            TabOrder = 5
            Value = 2
          end
          object Role2Combo: TComboBox
            Left = 154
            Top = 65
            Width = 135
            Height = 23
            Style = csDropDownList
            ItemIndex = 0
            TabOrder = 6
            Text = 'Shunt voltage (DCV)'
            Items.Strings = (
              'Shunt voltage (DCV)'
              'Current (DCI)')
          end
          object SampleEdit: TSpinEdit
            Left = 8
            Top = 170
            Width = 73
            Height = 24
            MaxValue = 100
            MinValue = 10
            TabOrder = 7
            Value = 50
          end
          object AutoReadBox: TCheckBox
            Left = 171
            Top = 124
            Width = 89
            Height = 17
            Caption = 'Auto Read'
            TabOrder = 8
          end
          object AutoSettleBox: TCheckBox
            Left = 87
            Top = 126
            Width = 58
            Height = 17
            Caption = 'Auto'
            Checked = True
            State = cbChecked
            TabOrder = 12
          end
          object AutoConnectBox: TCheckBox
            Left = 171
            Top = 104
            Width = 97
            Height = 17
            Caption = 'Auto Connect'
            TabOrder = 9
          end
          object FastBox: TCheckBox
            Left = 171
            Top = 144
            Width = 46
            Height = 17
            Caption = 'Fast'
            TabOrder = 13
          end
          object Res6Box: TCheckBox
            Left = 224
            Top = 144
            Width = 72
            Height = 17
            Caption = '6'#189' digits'
            TabOrder = 14
          end
          object SettleEdit: TSpinEdit
            Left = 8
            Top = 122
            Width = 73
            Height = 24
            MaxValue = 10000
            MinValue = 500
            TabOrder = 10
            Value = 1000
          end
          object IntervalEdit: TSpinEdit
            Left = 87
            Top = 170
            Width = 73
            Height = 24
            MaxValue = 1000
            MinValue = 1
            TabOrder = 11
            Value = 10
          end
        end
      end
      object TesterGB: TGroupBox
        AlignWithMargins = True
        Left = 496
        Top = 3
        Width = 204
        Height = 282
        Margins.Right = 5
        Align = alRight
        Caption = ' Tester '
        TabOrder = 2
        object ChanLbl: TLabel
          Left = 6
          Top = 74
          Width = 53
          Height = 15
          Alignment = taRightJustify
          AutoSize = False
          Caption = 'Channel'
        end
        object ModeLbl: TLabel
          Left = 18
          Top = 101
          Width = 45
          Height = 15
          Alignment = taRightJustify
          AutoSize = False
          Caption = 'Mode'
        end
        object RangeLbl: TLabel
          Left = 18
          Top = 128
          Width = 45
          Height = 15
          Alignment = taRightJustify
          AutoSize = False
          Caption = 'Range'
        end
        object CtrlLbl: TLabel
          Left = 10
          Top = 155
          Width = 53
          Height = 15
          Alignment = taRightJustify
          AutoSize = False
          Caption = 'Control'
        end
        object CurrLbl: TLabel
          Left = 15
          Top = 228
          Width = 67
          Height = 15
          AutoSize = False
          Caption = 'Current (A)'
        end
        object StartStopBtn: TSpeedButton
          Left = 95
          Top = 246
          Width = 95
          Height = 25
          Caption = 'Start'
          StyleName = 'Windows'
          OnClick = StartStopBtnClick
        end
        object DownloadBtn: TSpeedButton
          Left = 15
          Top = 24
          Width = 175
          Height = 25
          Caption = 'Download Board'
          StyleName = 'Windows'
          OnClick = DownloadBtnClick
        end
        object ChanEdit: TSpinEdit
          Left = 67
          Top = 71
          Width = 123
          Height = 24
          MaxValue = 512
          MinValue = 1
          TabOrder = 0
          Value = 1
          OnChange = ChanEditChange
        end
        object ModeCombo: TComboBox
          Left = 67
          Top = 98
          Width = 123
          Height = 23
          Style = csDropDownList
          ItemIndex = 0
          TabOrder = 1
          Text = 'Charge'
          Items.Strings = (
            'Charge'
            'Discharge')
        end
        object RangeCombo: TComboBox
          Left = 67
          Top = 125
          Width = 123
          Height = 23
          Style = csDropDownList
          ItemIndex = 0
          TabOrder = 2
          Text = 'R1'
          Items.Strings = (
            'R1'
            'R2'
            'R3'
            'R4')
        end
        object ControlCombo: TComboBox
          Left = 67
          Top = 152
          Width = 123
          Height = 23
          Style = csDropDownList
          ItemIndex = 1
          TabOrder = 3
          Text = 'Constant Current'
          Items.Strings = (
            'Constant Output'
            'Constant Current')
        end
        object CurrEdit: TEdit
          Left = 15
          Top = 247
          Width = 74
          Height = 23
          Alignment = taCenter
          TabOrder = 4
          TextHint = '0.0'
          OnKeyPress = CurrEditKeyPress
        end
        object BothBox: TCheckBox
          Left = 12
          Top = 203
          Width = 161
          Height = 19
          Caption = 'Run Charge and Discharge'
          Checked = True
          State = cbChecked
          TabOrder = 5
        end
      end
    end
  end
end
