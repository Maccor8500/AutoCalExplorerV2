object RecordFrame: TRecordFrame
  Left = 0
  Top = 0
  Width = 740
  Height = 669
  DoubleBuffered = True
  ParentDoubleBuffered = False
  TabOrder = 0
  object RecordGB: TGroupBox
    AlignWithMargins = True
    Left = 6
    Top = 6
    Width = 728
    Height = 657
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Align = alClient
    Caption = ' Calibration record (system_info) '
    TabOrder = 0
    ExplicitHeight = 685
    object CommentsLabel: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 577
      Width = 718
      Height = 15
      Align = alTop
      Caption = 'Comments'
      ExplicitWidth = 59
    end
    object IdentityPanel: TPanel
      AlignWithMargins = True
      Left = 5
      Top = 20
      Width = 718
      Height = 154
      Align = alTop
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 0
      StyleName = 'Windows'
      object SerialLabel: TLabel
        Left = 8
        Top = 7
        Width = 90
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Serial'
      end
      object ModelLabel: TLabel
        Left = 8
        Top = 32
        Width = 90
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Model'
      end
      object CertLabel: TLabel
        Left = 8
        Top = 57
        Width = 90
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Certificate #'
      end
      object ManufLabel: TLabel
        Left = 8
        Top = 82
        Width = 90
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Manufacturer'
      end
      object OwnerLabel: TLabel
        Left = 8
        Top = 107
        Width = 90
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Owner'
      end
      object TechLabel: TLabel
        Left = 8
        Top = 132
        Width = 90
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Technician'
      end
      object CalDateLabel: TLabel
        Left = 370
        Top = 7
        Width = 100
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Calibration date'
      end
      object CalPrevLabel: TLabel
        Left = 370
        Top = 32
        Width = 100
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Previous cal.'
      end
      object CalDueLabel: TLabel
        Left = 370
        Top = 57
        Width = 100
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Calibration due'
      end
      object TempLabel: TLabel
        Left = 370
        Top = 82
        Width = 100
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Temp. '#176'C'
      end
      object HumdLabel: TLabel
        Left = 370
        Top = 107
        Width = 100
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Humidity %RH'
      end
      object SerialEdit: TEdit
        Left = 106
        Top = 3
        Width = 240
        Height = 23
        Alignment = taCenter
        BevelOuter = bvNone
        TabOrder = 0
      end
      object ModelEdit: TEdit
        Left = 106
        Top = 28
        Width = 240
        Height = 23
        Alignment = taCenter
        BevelOuter = bvNone
        TabOrder = 1
      end
      object CertEdit: TEdit
        Left = 106
        Top = 53
        Width = 240
        Height = 23
        Alignment = taCenter
        BevelOuter = bvNone
        TabOrder = 2
      end
      object ManufEdit: TEdit
        Left = 106
        Top = 78
        Width = 240
        Height = 23
        Alignment = taCenter
        BevelOuter = bvNone
        TabOrder = 3
      end
      object OwnerEdit: TEdit
        Left = 106
        Top = 103
        Width = 240
        Height = 23
        Alignment = taCenter
        BevelOuter = bvNone
        TabOrder = 4
      end
      object TechEdit: TEdit
        Left = 106
        Top = 128
        Width = 240
        Height = 23
        Alignment = taCenter
        BevelOuter = bvNone
        TabOrder = 5
      end
      object CalDatePicker: TDateTimePicker
        Left = 478
        Top = 3
        Width = 140
        Height = 23
        Date = 46023.000000000000000000
        Format = 'yyyy-MM-dd'
        Time = 46023.000000000000000000
        ShowCheckbox = True
        Checked = False
        MinDate = 36526.000000000000000000
        TabOrder = 6
        OnChange = CalDatePickerChange
      end
      object CalPrevPicker: TDateTimePicker
        Left = 478
        Top = 28
        Width = 140
        Height = 23
        Date = 46023.000000000000000000
        Format = 'yyyy-MM-dd'
        Time = 46023.000000000000000000
        ShowCheckbox = True
        Checked = False
        MinDate = 36526.000000000000000000
        TabOrder = 7
      end
      object CalDuePicker: TDateTimePicker
        Left = 478
        Top = 53
        Width = 140
        Height = 23
        Date = 46023.000000000000000000
        Format = 'yyyy-MM-dd'
        Time = 46023.000000000000000000
        ShowCheckbox = True
        Checked = False
        MinDate = 36526.000000000000000000
        TabOrder = 8
      end
      object TempEdit: TEdit
        Left = 478
        Top = 78
        Width = 140
        Height = 23
        Alignment = taCenter
        BevelOuter = bvNone
        TabOrder = 9
      end
      object HumdEdit: TEdit
        Left = 478
        Top = 103
        Width = 140
        Height = 23
        Alignment = taCenter
        BevelOuter = bvNone
        TabOrder = 10
      end
    end
    object FirmwareGB: TGroupBox
      AlignWithMargins = True
      Left = 5
      Top = 180
      Width = 718
      Height = 141
      Margins.Bottom = 6
      Align = alTop
      Caption = 
        ' Firmware (firmware_t: running build reported by the board, read' +
        '-only) '
      TabOrder = 1
      object FwDeviceLabel: TLabel
        Left = 8
        Top = 33
        Width = 90
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Device'
      end
      object FwVersionLabel: TLabel
        Left = 8
        Top = 58
        Width = 90
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Version'
      end
      object FwBuiltLabel: TLabel
        Left = 8
        Top = 83
        Width = 90
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Built'
      end
      object FwNotesLabel: TLabel
        Left = 64
        Top = 107
        Width = 34
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'Notes'
      end
      object FwDeviceEdit: TEdit
        Left = 106
        Top = 29
        Width = 337
        Height = 23
        Alignment = taCenter
        BevelInner = bvNone
        BevelOuter = bvNone
        BorderStyle = bsNone
        Color = clBtnFace
        Ctl3D = True
        Enabled = False
        ParentCtl3D = False
        ReadOnly = True
        TabOrder = 0
      end
      object FwVersionEdit: TEdit
        Left = 106
        Top = 54
        Width = 337
        Height = 23
        Alignment = taCenter
        BevelInner = bvNone
        BevelOuter = bvNone
        BorderStyle = bsNone
        Color = clBtnFace
        Ctl3D = True
        Enabled = False
        ParentCtl3D = False
        ReadOnly = True
        TabOrder = 1
      end
      object FwBuiltEdit: TEdit
        Left = 106
        Top = 79
        Width = 337
        Height = 23
        Alignment = taCenter
        BevelInner = bvNone
        BevelOuter = bvNone
        BorderStyle = bsNone
        Color = clBtnFace
        Ctl3D = True
        Enabled = False
        ParentCtl3D = False
        ReadOnly = True
        TabOrder = 2
      end
      object fwNotesMemo: TEdit
        Left = 106
        Top = 104
        Width = 337
        Height = 23
        Alignment = taCenter
        BevelInner = bvNone
        BevelOuter = bvNone
        BorderStyle = bsNone
        Color = clBtnFace
        Enabled = False
        TabOrder = 3
      end
    end
    object GridsPanel: TPanel
      AlignWithMargins = True
      Left = 5
      Top = 330
      Width = 718
      Height = 241
      Align = alTop
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 3
      StyleName = 'Windows'
      object Label1: TLabel
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 409
        Height = 15
        Align = alTop
        Caption = 
          'Shunts                                                          ' +
          '                                                 Standards'
      end
      object ShuntGrid: TStringGrid
        AlignWithMargins = True
        Left = 3
        Top = 24
        Width = 350
        Height = 183
        Align = alLeft
        BevelOuter = bvNone
        DefaultRowHeight = 19
        RowCount = 9
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goEditing, goTabs]
        ScrollBars = ssNone
        TabOrder = 0
        OnDrawCell = GridDrawCell
        ExplicitHeight = 162
      end
      object TraceGrid: TStringGrid
        AlignWithMargins = True
        Left = 359
        Top = 24
        Width = 356
        Height = 183
        Align = alClient
        DefaultRowHeight = 19
        RowCount = 9
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goEditing, goTabs]
        ScrollBars = ssNone
        TabOrder = 1
        OnDrawCell = GridDrawCell
        ExplicitHeight = 162
      end
      object ButtonPanel: TPanel
        Left = 0
        Top = 210
        Width = 718
        Height = 31
        Align = alBottom
        BevelOuter = bvNone
        ShowCaption = False
        TabOrder = 2
        StyleName = 'Windows'
        ExplicitTop = 189
        object ImportBtn: TSpeedButton
          AlignWithMargins = True
          Left = 3
          Top = 3
          Width = 100
          Height = 25
          Align = alLeft
          Caption = 'Import...'
          OnClick = ImportBtnClick
        end
        object ReadBtn: TSpeedButton
          AlignWithMargins = True
          Left = 109
          Top = 3
          Width = 80
          Height = 25
          Align = alLeft
          Caption = 'Read'
          Enabled = False
          OnClick = ReadBtnClick
        end
        object WriteBtn: TSpeedButton
          AlignWithMargins = True
          Left = 195
          Top = 3
          Width = 80
          Height = 25
          Align = alLeft
          Caption = 'Write'
          Enabled = False
          OnClick = WriteBtnClick
        end
        object StateBtn: TSpeedButton
          AlignWithMargins = True
          Left = 635
          Top = 3
          Width = 80
          Height = 25
          Align = alRight
          Caption = 'State'
          Enabled = False
          OnClick = StateBtnClick
          ExplicitLeft = 641
        end
        object SourceLabel: TLabel
          AlignWithMargins = True
          Left = 626
          Top = 3
          Width = 3
          Height = 15
          Align = alClient
          Alignment = taRightJustify
          Layout = tlCenter
          StyleName = 'Iceberg Classico'
        end
        object CommitBox: TCheckBox
          AlignWithMargins = True
          Left = 284
          Top = 3
          Width = 127
          Height = 25
          Margins.Left = 6
          Align = alLeft
          Caption = 'Commit to EEPROM'
          Checked = True
          State = cbChecked
          TabOrder = 0
          StyleName = 'Iceberg Classico'
        end
      end
    end
    object CommentsMemo: TMemo
      AlignWithMargins = True
      Left = 5
      Top = 598
      Width = 718
      Height = 54
      Align = alClient
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Consolas'
      Font.Style = []
      ParentFont = False
      ScrollBars = ssVertical
      TabOrder = 2
      OnChange = CommentsMemoChange
      ExplicitHeight = 96
    end
  end
end
