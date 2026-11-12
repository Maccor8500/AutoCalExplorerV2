unit ConfettiU;

{
  A confetti shower over a form, for fun: a click-through, colour-keyed, non-activating window the size of the
  form's client area, with a few hundred paper bits tumbling down for a couple of seconds. It frees itself.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls;

type
  TConfetti = class
  public
    { shows the shower over the form that holds Control; nothing happens when that form is not visible }
    class procedure Celebrate(const Control: TControl); static;
  end;

implementation

const
  KEY       = $FF00FF;      { colour-keyed: anything painted in this colour is see-through }
  PIECE_COUNT    = 220;
  FRAME_MS  = 16;
  MIN_MS    = 5000;         { the shower keeps falling for 5..10 s, then the last pieces drain off the bottom }
  MAX_MS    = 10000;
  GRAVITY   = 0.18;
  PALETTE: array [0..7] of TColor = ($3C5AF5, $58D1FF, $4CC94C, $F0A835, $F5A3FF, $E0E0E0, $2DB7F7, $7A4FE8);

type
  TPiece = record
    X, Y, VX, VY, Fall, Angle, Spin, W, H: Double;   { Fall: this piece's terminal speed }
    Color: TColor;
  end;

  TConfettiForm = class(TForm)
  private
    Pieces: array [0..PIECE_COUNT -1] of TPiece;
    Timer: TTimer;
    Buffer: TBitmap;
    Started, Duration: Cardinal;
    Over: TCustomForm;
    procedure Tick(Sender: TObject);
    procedure Seed;
    { a fresh piece above the top edge; Stagger spreads the start heights so they do not fall as one curtain }
    function NewPiece(const Stagger: Double): TPiece;
    { the form's client area in screen pixels, from the OS, wherever the form is now }
    function TargetRect: TRect;
    { the overlay sits exactly on that rectangle }
    procedure Follow;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
  public
    constructor CreateOver(const Owner: TCustomForm);
    destructor Destroy; override;
  end;

{ TConfettiForm }

constructor TConfettiForm.CreateOver(const Owner: TCustomForm);
begin
  inherited CreateNew(Owner);
  Over := Owner;
  { no DPI scaling: the bounds below are screen pixels already, scaling them again on a high-DPI monitor
    would put the overlay off the form }
  Scaled := False;
  Position := poDesigned;
  BorderStyle := bsNone;
  Color := KEY;
  TransparentColor := True;
  TransparentColorValue := KEY;
  DoubleBuffered := True;

  Buffer := TBitmap.Create;
  Follow;

  Seed;
  Started := GetTickCount;
  Timer := TTimer.Create(Self);
  Timer.Interval := FRAME_MS;
  Timer.OnTimer := Tick;
end;

destructor TConfettiForm.Destroy;
begin
  Buffer.Free;
  inherited;
end;

procedure TConfettiForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  { owned popup: stays over its form only; no focus, no taskbar button, clicks go through to what is beneath }
  Params.Style := Params.Style and not WS_CHILD or WS_POPUP;
  Params.ExStyle := Params.ExStyle or WS_EX_TRANSPARENT or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW or WS_EX_LAYERED;
  Params.WndParent := Over.Handle;
  { the creation rectangle, stated outright: left to the VCL it can go out as CW_USEDEFAULT, which for a popup
    window means (0,0), the screen corner, not the form }
  var R := TargetRect;
  Params.X := R.Left;
  Params.Y := R.Top;
  Params.Width := R.Width;
  Params.Height := R.Height;
end;

function TConfettiForm.TargetRect: TRect;
begin
  { from the OS, not from the VCL's bookkeeping }
  Winapi.Windows.GetClientRect(Over.Handle, Result);
  var TL := Result.TopLeft;
  Winapi.Windows.ClientToScreen(Over.Handle, TL);
  Result := Rect(TL.X, TL.Y, TL.X + Result.Width, TL.Y + Result.Height);
end;

procedure TConfettiForm.Follow;
begin
  var Target := TargetRect;
  if HandleAllocated then
  begin
    var Have: TRect;
    GetWindowRect(Handle, Have);
    if not EqualRect(Have, Target) then
      SetWindowPos(Handle, 0, Target.Left, Target.Top, Target.Width, Target.Height, SWP_NOACTIVATE or SWP_NOZORDER or SWP_NOOWNERZORDER);
  end
  else SetBounds(Target.Left, Target.Top, Target.Width, Target.Height);

  if (Buffer.Width <> Target.Width) or (Buffer.Height <> Target.Height) then Buffer.SetSize(Target.Width, Target.Height);
end;

function TConfettiForm.NewPiece(const Stagger: Double): TPiece;
begin
  Result.X     := Random * Width;
  Result.Y     := -Random * Stagger -8;
  Result.VX    := (Random -0.5) * 2.4;
  Result.VY    := 1 + Random * 2;
  Result.Fall  := 2.5 + Random * 4;
  Result.Angle := Random * 2 * Pi;
  Result.Spin  := (Random -0.5) * 0.3;
  Result.W     := 5 + Random * 7;
  Result.H     := 3 + Random * 4;
  Result.Color := PALETTE[Random(Length(PALETTE))];
end;

procedure TConfettiForm.Seed;
begin
  Duration := MIN_MS + Cardinal(Random(MAX_MS - MIN_MS + 1));
  { spread over more than a screen height so the first pieces trickle in rather than arrive as a curtain }
  for var I := 0 to PIECE_COUNT -1 do Pieces[I] := NewPiece(Height * 1.5);
end;

procedure TConfettiForm.Tick(Sender: TObject);
begin
  if not Over.Visible or IsIconic(Over.Handle) then begin Timer.Enabled := False; Release; Exit; end;
  Follow;
  var Raining := GetTickCount - Started < Duration;   { while it lasts, a piece off the bottom comes back at the top }
  var Alive := False;
  for var I := 0 to PIECE_COUNT -1 do
  begin
    var P := Pieces[I];
    if P.VY < P.Fall then P.VY := P.VY + GRAVITY;    { air drag: each piece settles at its own speed }
    P.VX := P.VX * 0.995 + Sin(P.Angle) * 0.08;      { a little flutter }
    P.X := P.X + P.VX;
    P.Y := P.Y + P.VY;
    P.Angle := P.Angle + P.Spin;
    { a piece off the bottom re-enters anywhere up to a screen height above the top, so re-entries are spread
      out in time instead of arriving together as a wave }
    if (P.Y >= Height + 12) and Raining then P := NewPiece(Height);
    Pieces[I] := P;
    if P.Y < Height + 12 then Alive := True;
  end;
  if not Alive then begin Timer.Enabled := False; Release; Exit; end;
  Invalidate;
end;

procedure TConfettiForm.Paint;
begin
  var C := Buffer.Canvas;
  C.Brush.Color := KEY;
  C.FillRect(Rect(0, 0, Width, Height));
  C.Pen.Style := psClear;

  for var I := 0 to PIECE_COUNT -1 do
  begin
    var P := Pieces[I];
    if (P.Y < -12) or (P.Y > Height + 12) then Continue;
    { a rectangle rotated about its centre: the tumble is the apparent width changing with the angle }
    var CA := Cos(P.Angle);
    var SA := Sin(P.Angle);
    var HW := P.W /2;
    var HH := P.H /2 *Abs(Cos(P.Angle *1.7));      { the sheet turns edge-on and back }
    var Pts: array [0..3] of TPoint;
    Pts[0] := Point(Round(P.X +(-HW *CA - -HH *SA)), Round(P.Y + (-HW *SA + -HH *CA)));
    Pts[1] := Point(Round(P.X +( HW *CA - -HH *SA)), Round(P.Y + ( HW *SA + -HH *CA)));
    Pts[2] := Point(Round(P.X +( HW *CA -HH *SA)), Round(P.Y + ( HW *SA +HH *CA)));
    Pts[3] := Point(Round(P.X +(-HW *CA -HH *SA)), Round(P.Y + (-HW *SA +HH *CA)));
    C.Brush.Color := P.Color;
    C.Polygon(Pts);
  end;

  Canvas.Draw(0, 0, Buffer);
end;

{ TConfetti }

class procedure TConfetti.Celebrate(const Control: TControl);
begin
  var Form := GetParentForm(Control);
  if not Assigned(Form) then Form := Application.MainForm;
  if not Assigned(Form) or not Form.Visible or IsIconic(Form.Handle) then Exit;
  var Shower := TConfettiForm.CreateOver(Form);
  Shower.Follow;   { the handle exists now: re-apply the bounds in case window creation moved them }
  ShowWindow(Shower.Handle, SW_SHOWNOACTIVATE);
  Shower.Visible := True;
  Shower.Follow;
end;

initialization
  Randomize;

end.
