object FirmwareFrame: TFirmwareFrame
  Left = 0
  Top = 0
  Width = 740
  Height = 511
  DoubleBuffered = True
  ParentDoubleBuffered = False
  TabOrder = 0
  object LoaderGB: TGroupBox
    AlignWithMargins = True
    Left = 6
    Top = 6
    Width = 728
    Height = 210
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Align = alTop
    Caption = 
      ' 1. Bootloader :: Ariadne over ISP (Atmel-ICE); erases the appli' +
      'cation '
    TabOrder = 0
    object HexPanel: TPanel
      AlignWithMargins = True
      Left = 5
      Top = 20
      Width = 718
      Height = 29
      Align = alTop
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 0
      StyleName = 'Windows'
      object HexBrowseBtn: TSpeedButton
        AlignWithMargins = True
        Left = 635
        Top = 3
        Width = 80
        Height = 23
        Align = alRight
        Caption = 'Browse'
        OnClick = HexBrowseBtnClick
      end
      object HexFileEdit: TEdit
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 626
        Height = 23
        Align = alClient
        Alignment = taCenter
        ReadOnly = True
        TabOrder = 0
        Text = '..\..\..\..\ariadne_bootloader\AUTOCAL_528LB_BTLDR_RevE.hex'
      end
    end
    object FusePanel: TPanel
      AlignWithMargins = True
      Left = 5
      Top = 55
      Width = 718
      Height = 115
      Align = alTop
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 1
      StyleName = 'Windows'
      object ExtLabel: TLabel
        Left = 8
        Top = 7
        Width = 97
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'FUSE EXTENDED'
      end
      object HighLabel: TLabel
        Left = 8
        Top = 33
        Width = 97
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'HIGH'
      end
      object LowLabel: TLabel
        Left = 8
        Top = 59
        Width = 97
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'LOW'
      end
      object FuseNote: TLabel
        Left = 264
        Top = 4
        Width = 448
        Height = 48
        AutoSize = False
        Caption = 
          'Stock Mega 2560 Ariadne: LOW 0xFF external crystal, HIGH 0xD8 BO' +
          'OTRST + 4096-word boot section, EXT 0xFD brown-out 2.7 V. Order:' +
          ' backup, fuses, erase, flash, verify, lock bits last (LOCK 0x0F ' +
          '= boot section protected, no ISP read lock).'
        WordWrap = True
      end
      object LockLabel: TLabel
        Left = 66
        Top = 95
        Width = 40
        Height = 15
        Alignment = taRightJustify
        AutoSize = False
        Caption = 'LOCK'
      end
      object ExtEdit: TEdit
        Left = 112
        Top = 4
        Width = 61
        Height = 23
        Alignment = taCenter
        AutoSelect = False
        AutoSize = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -15
        Font.Name = 'Consolas'
        Font.Style = []
        ParentFont = False
        TabOrder = 0
        Text = '0xFD'
        OnChange = FuseEditChange
      end
      object HighEdit: TEdit
        Tag = 1
        Left = 112
        Top = 30
        Width = 61
        Height = 23
        Alignment = taCenter
        AutoSelect = False
        AutoSize = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -15
        Font.Name = 'Consolas'
        Font.Style = []
        ParentFont = False
        TabOrder = 1
        Text = '0xD8'
        OnChange = FuseEditChange
      end
      object LowEdit: TEdit
        Tag = 2
        Left = 112
        Top = 56
        Width = 61
        Height = 23
        Alignment = taCenter
        AutoSelect = False
        AutoSize = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -15
        Font.Name = 'Consolas'
        Font.Style = []
        ParentFont = False
        TabOrder = 2
        Text = '0xFF'
        OnChange = FuseEditChange
      end
      object FuseBox: TCheckBox
        Left = 264
        Top = 72
        Width = 121
        Height = 17
        Caption = 'Program FUSE'
        TabOrder = 3
        StyleName = 'Iceberg Classico'
      end
      object LockEdit: TEdit
        Tag = 3
        Left = 112
        Top = 92
        Width = 61
        Height = 23
        Alignment = taCenter
        AutoSelect = False
        AutoSize = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -15
        Font.Name = 'Consolas'
        Font.Style = []
        ParentFont = False
        TabOrder = 4
        Text = '0x0F'
        OnChange = FuseEditChange
      end
      object LockBox: TCheckBox
        Left = 264
        Top = 95
        Width = 121
        Height = 17
        Caption = 'Program LOCK'
        TabOrder = 5
        StyleName = 'Iceberg Classico'
      end
    end
    object LoaderPanel: TPanel
      AlignWithMargins = True
      Left = 5
      Top = 176
      Width = 718
      Height = 31
      Align = alTop
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 2
      StyleName = 'Windows'
      object FlashCancelBtn: TSpeedButton
        AlignWithMargins = True
        Left = 547
        Top = 3
        Width = 86
        Height = 25
        Margins.Left = 1
        Margins.Right = 1
        Align = alRight
        Caption = 'Cancel'
        Enabled = False
        OnClick = FlashCancelBtnClick
      end
      object FlashBtn: TSpeedButton
        AlignWithMargins = True
        Left = 635
        Top = 3
        Width = 80
        Height = 25
        Margins.Left = 1
        Align = alRight
        Caption = 'Flash'
        OnClick = FlashBtnClick
      end
      object IceLabel: TLabel
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 540
        Height = 25
        Align = alClient
        Caption = 'Atmel-ICE: checking...'
        Layout = tlCenter
        ExplicitWidth = 117
        ExplicitHeight = 15
      end
    end
  end
  object AppGB: TGroupBox
    AlignWithMargins = True
    Left = 6
    Top = 222
    Width = 728
    Height = 110
    Margins.Left = 6
    Margins.Right = 6
    Align = alTop
    Caption = 
      ' 2. Application :: firmware.bin over TFTP through the bootloader' +
      '; needs a connected board '
    TabOrder = 1
    object BinPanel: TPanel
      AlignWithMargins = True
      Left = 5
      Top = 20
      Width = 718
      Height = 29
      Align = alTop
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 0
      StyleName = 'Windows'
      object BinBrowseBtn: TSpeedButton
        AlignWithMargins = True
        Left = 635
        Top = 3
        Width = 80
        Height = 23
        Align = alRight
        Caption = 'Browse'
        OnClick = BinBrowseBtnClick
      end
      object BinFileEdit: TEdit
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 626
        Height = 23
        Align = alClient
        Alignment = taCenter
        ReadOnly = True
        TabOrder = 0
        Text = '..\..\..\..\.pio\build\megaatmega2560\firmware.bin'
      end
    end
    object AppPanel: TPanel
      AlignWithMargins = True
      Left = 5
      Top = 55
      Width = 718
      Height = 42
      Align = alTop
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 1
      StyleName = 'Windows'
      object BootloaderBtn: TSpeedButton
        AlignWithMargins = True
        Left = 445
        Top = 3
        Width = 100
        Height = 36
        Margins.Left = 1
        Margins.Right = 1
        Align = alRight
        Caption = 'To bootloader'
        Enabled = False
        Visible = False
        OnClick = BootloaderBtnClick
        ExplicitHeight = 25
      end
      object UpdateCancelBtn: TSpeedButton
        AlignWithMargins = True
        Left = 631
        Top = 3
        Width = 86
        Height = 36
        Margins.Left = 1
        Margins.Right = 1
        Align = alRight
        Caption = 'Cancel'
        Enabled = False
        OnClick = UpdateCancelBtnClick
        ExplicitLeft = 547
        ExplicitHeight = 25
      end
      object UpdateBtn: TSpeedButton
        AlignWithMargins = True
        Left = 547
        Top = 3
        Width = 80
        Height = 36
        Margins.Left = 1
        Align = alRight
        Caption = 'Update'
        Enabled = False
        OnClick = UpdateBtnClick
        ExplicitLeft = 539
        ExplicitTop = 0
      end
      object AppNote: TLabel
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 438
        Height = 36
        Align = alClient
        AutoSize = False
        Caption = 
          'Update: releases relays, reboots into Ariadne, pushes the image,' +
          ' waits for the application.'
        Layout = tlCenter
        WordWrap = True
        ExplicitHeight = 35
      end
    end
  end
  object DirectGB: TGroupBox
    AlignWithMargins = True
    Left = 6
    Top = 338
    Width = 728
    Height = 110
    Margins.Left = 6
    Margins.Right = 6
    Align = alTop
    Caption = 
      ' 3. Direct :: firmware.hex over ISP (Atmel-ICE), no network; boo' +
      'tloader from group 1 merged in '
    TabOrder = 2
    object AppHexPanel: TPanel
      AlignWithMargins = True
      Left = 5
      Top = 20
      Width = 718
      Height = 29
      Align = alTop
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 0
      StyleName = 'Windows'
      object AppHexBrowseBtn: TSpeedButton
        AlignWithMargins = True
        Left = 635
        Top = 3
        Width = 80
        Height = 23
        Align = alRight
        Caption = 'Browse'
        OnClick = AppHexBrowseBtnClick
      end
      object AppHexEdit: TEdit
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 626
        Height = 23
        Align = alClient
        Alignment = taCenter
        ReadOnly = True
        TabOrder = 0
        Text = '..\..\..\..\.pio\build\megaatmega2560\firmware.hex'
      end
    end
    object DirectPanel: TPanel
      AlignWithMargins = True
      Left = 5
      Top = 55
      Width = 718
      Height = 42
      Align = alTop
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 1
      StyleName = 'Windows'
      object DirectCancelBtn: TSpeedButton
        AlignWithMargins = True
        Left = 631
        Top = 3
        Width = 86
        Height = 36
        Margins.Left = 1
        Margins.Right = 1
        Align = alRight
        Caption = 'Cancel'
        Enabled = False
        OnClick = DirectCancelBtnClick
      end
      object DirectBtn: TSpeedButton
        AlignWithMargins = True
        Left = 547
        Top = 3
        Width = 80
        Height = 36
        Margins.Left = 1
        Align = alRight
        Caption = 'Flash direct'
        OnClick = DirectBtnClick
      end
      object DirectNote: TLabel
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 262
        Height = 36
        Align = alClient
        AutoSize = False
        Caption = 'Same backup and fuse handling as group 1.'
        Layout = tlCenter
        WordWrap = True
      end
      object IncludeBootBox: TCheckBox
        AlignWithMargins = True
        Left = 271
        Top = 3
        Width = 134
        Height = 36
        Align = alRight
        Caption = 'Include bootloader'
        Color = clBtnFace
        ParentColor = False
        TabOrder = 0
        StyleName = 'Iceberg Classico'
      end
      object EraseBox: TCheckBox
        AlignWithMargins = True
        Left = 411
        Top = 3
        Width = 64
        Height = 36
        Align = alRight
        Caption = 'Erase'
        Checked = True
        Color = clBtnFace
        ParentColor = False
        State = cbChecked
        TabOrder = 1
        StyleName = 'Iceberg Classico'
      end
      object VerifyBox: TCheckBox
        AlignWithMargins = True
        Left = 481
        Top = 3
        Width = 62
        Height = 36
        Align = alRight
        Caption = 'Verify'
        Color = clBtnFace
        ParentColor = False
        TabOrder = 2
        StyleName = 'Iceberg Classico'
      end
    end
  end
  object HexOpen: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <
      item
        DisplayName = 'Intel HEX'
        FileMask = '*.hex'
      end
      item
        DisplayName = 'All files'
        FileMask = '*.*'
      end>
    Options = []
    Title = 'Bootloader image (Intel HEX)'
    Left = 648
    Top = 344
  end
  object AppHexOpen: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <
      item
        DisplayName = 'Intel HEX'
        FileMask = '*.hex'
      end
      item
        DisplayName = 'All files'
        FileMask = '*.*'
      end>
    Options = []
    Title = 'Application image (Intel HEX)'
    Left = 536
    Top = 344
  end
  object BinOpen: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <
      item
        DisplayName = 'Firmware image'
        FileMask = '*.bin'
      end
      item
        DisplayName = 'All files'
        FileMask = '*.*'
      end>
    Options = []
    Title = 'Firmware image (raw binary)'
    Left = 592
    Top = 344
  end
end
