program Segtimer;

uses
  SysUtils, Classes, Windows, Messages, Controls, StdCtrls, Dialogs, Forms, ShellAPI, MMSystem;

{$R *.res}

type
  TTimerAction = (ScrollLock, BeepBeep, Dialog);
  TTimerActions = set of TTimerAction;

var
  Interval: Integer;
  TimerAction: TTimerActions;

procedure ProcessMessages;
var
  m: tagMSG;
begin
  while PeekMessage(m, 0, 0, 0, PM_REMOVE) do begin
    TranslateMessage(m);
    DispatchMessage(m);
  end;
end;

procedure TimerTriggered;
var
  F: TForm;
  procedure OpenDialog;
  begin
    F := TForm.Create(nil);
    with F do begin
      F.Caption := 'Segtimer alert!';
      F.BorderStyle := bsDialog;
      F.ClientWidth := 400;
      F.ClientHeight := 120;
      F.Position := poScreenCenter;
      F.Show;
    end;
    with TLabel.Create(F) do begin
      Parent := F;
      Align := alClient;
      Font.Size := 48;
      Alignment := taCenter;
      Layout := tlCenter;
      Caption := 'Segtimer!';
    end;
  end;
  procedure CloseDialog;
  begin
    // Free checks Self<>nil so we don't bother
    FreeAndNil(F);
  end;
  procedure ShakeDialog;
  var
    R: TRect;
  begin
    GetWindowRect(F.Handle, R);
    R.Left := R.Left + 8 * (Random(2)*2 - 1);
    R.Top := R.Top + 8 * (Random(2)*2 - 1);
    SetWindowPos(F.Handle, HWND_TOPMOST, R.Left, R.Top, 0, 0, SWP_NOSIZE);
  end;
  procedure PressScrollLock;
  begin
    keybd_event(VK_SCROLL, 0, 0, 0);
    keybd_event(VK_SCROLL, 0, KEYEVENTF_KEYUP, 0);
  end;
  var
    wf: TPCMWaveFormat;
    wh: TWaveHdr;
    buff: array of Byte;
    wo: HWAVEOUT;
  procedure OpenBeeper(BeepLen: Cardinal; OnDone: THandle);
  begin
    wf.wf.wFormatTag := WAVE_FORMAT_1M08;
    wf.wf.nChannels := 1;
    wf.wf.nSamplesPerSec := 11025;
    wf.wf.nAvgBytesPerSec := 11025;
    wf.wf.nBlockAlign := 1;
    wf.wBitsPerSample := 8;
    if waveOutOpen(@wo, WAVE_MAPPER, @wf, OnDone, 0, CALLBACK_EVENT) <> MMSYSERR_NOERROR then
      raise EOSError.Create('Beep [waveOutOpen()] failed');
    SetLength(buff, (wf.wf.nSamplesPerSec * BeepLen) div 1000);
    FillChar(wh, SizeOf(wh), 0);
    wh.lpData := @buff[0];
    wh.dwBufferLength := Length(buff);
    wh.dwFlags := WHDR_BEGINLOOP or WHDR_ENDLOOP;
    wh.dwLoops := 0;
    if waveOutPrepareHeader(wo, @wh, SizeOf(wh)) <> MMSYSERR_NOERROR then
      raise EOSError.Create('Beep [waveOutPrepareHeader()] failed');
  end;
  procedure CloseBeeper;
  begin
    if wo <> 0 then begin
      if (wh.dwFlags and WHDR_PREPARED) <> 0 then
        waveOutUnprepareHeader(wo, @wh, SizeOf(wh));
      waveOutClose(wo);
    end;
  end;
  procedure PlayBeep(freq: Cardinal);
  var
    I: Integer;
  begin
    for I := 0 to Length(buff) - 1 do
      buff[I] := Trunc(128 + 127*Sin(2*PI*freq*I/wf.wf.nSamplesPerSec));
    if waveOutWrite(wo, @wh, SizeOf(wh)) <> MMSYSERR_NOERROR then
      raise EOSError.Create('Beep [waveOutWrite()] failed');
  end;
var
  I: Integer;
  tevt: THandle;
const
  Delay = 30;
  NumLoops = 40;
begin
  F := nil;
  wo := 0;
  wh.dwFlags := 0;
  tevt := CreateEvent(nil, False, False, nil);
  if BeepBeep in TimerAction then
    OpenBeeper(Delay, tevt);
  if Dialog in TimerAction then
    OpenDialog;
  for I := 1 to NumLoops do begin { Must be multiple of 2 to preserve scroll lock state }
    ResetEvent(tevt);
    // Flash scroll lock
    if (ScrollLock in TimerAction) and Odd(I) then
      PressScrollLock;
    // Dialog
    if (Dialog in TimerAction) then
      ShakeDialog;
    // Beep (sets event on completion) - set a timer if we aren't beeping
    if BeepBeep in TimerAction then
      PlayBeep(250 + ((1000 div (NumLoops div 4)) * (I mod (NumLoops div 4))))
    else
      timeSetEvent(Delay, 10, Pointer(tevt), 202, TIME_ONESHOT or TIME_CALLBACK_EVENT_SET);
    // Delay (wait for timer or for beep)
    while MsgWaitForMultipleObjects(1, tevt, False, INFINITE, QS_ALLEVENTS) <> WAIT_OBJECT_0 do
      ProcessMessages;
  end;
  CloseHandle(tevt);
  CloseDialog;
  CloseBeeper;
end;

procedure GetParams_Validate(OkBtn: TButton; Sender: TObject);
var
  I: Integer;
  ActionSelected: Boolean;
  TextValid: Boolean;
  Form: TForm;
begin
  Form := OkBtn.Owner as TForm;
  ActionSelected := False;
  TextValid := True;
  for I := 0 to Form.ControlCount - 1 do begin
    if Form.Controls[I] is TCheckBox then
      ActionSelected := ActionSelected or (Form.Controls[I] as TCheckBox).Checked;
    if Form.Controls[I] is TEdit then
      TextValid := TextValid and (StrToIntDef((Form.Controls[I] as TEdit).Text, 0) > 0);
  end;

  OkBtn.Enabled := TextValid and ActionSelected;    
end; 

var
  ParamsWindow: HWND;
  
function GetParams: Boolean;
var
  F: TForm;
  C1, C2, C3: TCheckBox;
  E: TEdit;
  B: TButton;
  M: TMethod;
begin
  if (ParamsWindow <> 0) and IsWindow(ParamsWindow) then begin
    BringWindowToTop(ParamsWindow);
    SetFocus(ParamsWindow);
    Result := False;
    Exit;
  end;
  F := TForm.Create(nil);
  with F do begin
    Caption := 'Segtimer - configure';
    BorderStyle := bsDialog;
    ClientWidth := 230;
    ClientHeight := 133;
    Position := poScreenCenter;
  end;
  try
    E := TEdit.Create(F);
    with E do begin
      Parent := F;
      Left := 128;
      Top := 8;
      Width := 64;
      if Interval > 0 then
        Text := IntToStr(Interval)
      else
        Text := '20';
    end;
    with TLabel.Create(F) do begin
      Parent := F;
      Top := 12;
      Left := 8;
      Width := 120;
      Alignment := taRightJustify;
      Caption := 'Timer &interval (minutes): ';
      FocusControl := E;
    end;
    {with TLabel.Create(F) do begin
      Parent := F;
      Top := 32;
      Left := 8;
      Width := 120;
      Alignment := taRightJustify;
      Caption := 'Alarm notifications: ';
    end;}
    C1 := TCheckBox.Create(F);
    with C1 do begin
      Parent := F;
      Top := 32;
      Left := 128;
      Checked := (ScrollLock in TimerAction) or (TimerAction = []);
      Caption := '&Flash scrollock';
    end;
    C2 := TCheckBox.Create(F);
    with C2 do begin
      Parent := F;
      Top := 52;
      Left := 128;
      Checked := (BeepBeep in TimerAction) or (TimerAction = []);
      Caption := '&Beep';
    end;
    C3 := TCheckBox.Create(F);
    with C3 do begin
      Parent := F;
      Top := 72;
      Left := 128;
      Checked := (Dialog in TimerAction) or (TimerAction = []);
      Caption := '&Popup message';
    end;
    B := TButton.Create(F);
    with B do begin
      Parent := F;
      Top := 100;
      Left := 64;
      Default := True;
      Caption := 'Ok';
      ModalResult := mrOk;
    end;
    with TButton.Create(F) do begin
      Parent := F;
      Top := 100;
      Left := 147;
      Cancel := True;
      Caption := 'Cancel';
      ModalResult := mrCancel;
    end;
    M.Code := @GetParams_Validate;
    M.Data := B;
    E.OnChange := TNotifyEvent(M);
    C1.OnClick := TNotifyEvent(M);
    C2.OnClick := TNotifyEvent(M);
    C3.OnClick := TNotifyEvent(M);
    //Validate
    TNotifyEvent(M)(nil);
    //Run
    ParamsWindow := F.Handle;
    Result := F.ShowModal = mrOk;
    ParamsWindow := 0;
    if Result then begin
      Interval := StrToInt(E.Text);
      TimerAction := [];
      if C1.Checked then Include(TimerAction, ScrollLock);
      if C2.Checked then Include(TimerAction, BeepBeep);
      if C3.Checked then Include(TimerAction, Dialog);
    end;
  finally
    F.Free;
  end;
end;

function ParseParams: Boolean;
var
  s: string;
begin
  Result := True;
  s := ParamStr(1);
  Interval := StrToIntDef(s, 0);
  Result := Result and (Interval > 0);
  s := UpperCase(ParamStr(2));
  TimerAction := [];
  if Pos('F', s) > 0 then Include(TimerAction, ScrollLock);
  if Pos('B', s) > 0 then Include(TimerAction, BeepBeep);
  if Pos('P', s) > 0 then Include(TimerAction, Dialog);
  Result := Result and (TimerAction <> []);
  if not Result then
    Result := GetParams
end;

var
  nid: _NOTIFYICONDATA;
  Timeleft: Integer;

function Run_WndProc(hwnd: HWND; msg: Cardinal; wParam, lParam: Integer): Integer; stdcall;
  procedure CreateTrayIcon;
  begin
    FillChar(nid, SizeOf(nid), 0);
    nid.cbSize := SizeOf(nid);
    nid.Wnd := hwnd;
    nid.uID := 101;
    nid.uFlags := NIF_MESSAGE or NIF_ICON or NIF_TIP;
    nid.uCallbackMessage := WM_USER;
    nid.hIcon := LoadIcon(HINSTANCE, 'TRAYICON');
    Shell_NotifyIcon(NIM_ADD, @nid);
  end;
  procedure UpdateTrayIcon;
  var
    s: string;
  begin
    s := Format(
           'Segtimer - %d minute timer (%d:%d%d)'#13#10+
           '  Left doubleclick = reset timer'#13#10+
           '  Middle click = configure'#13#10+
           '  Right doubleclick = close',
           [Interval, Timeleft div 60, (Timeleft mod 60) div 10, Timeleft mod 10]);
    StrPLCopy(@nid.szTip[0], s, Length(nid.szTip) - 1);
    Shell_NotifyIcon(NIM_MODIFY, @nid);
  end;
  procedure DestroyTrayIcon;
  begin
    Shell_NotifyIcon(NIM_DELETE, @nid);
  end;
  procedure StartTimer;
  begin
    SetTimer(hwnd, 201, MSecsPerSec, nil);
    Timeleft := interval * SecsPerMin;
  end;
  procedure StopTimer;
  begin
    KillTimer(hwnd, 201);
  end;
  procedure RestartTimer;
  begin
    StartTimer;
  end;
begin
  case msg of
    WM_CREATE: begin
      CreateTrayIcon;
      UpdateTrayIcon;
      StartTimer;
    end;
    WM_DESTROY: begin
      StopTimer;
      DestroyTrayIcon;
      PostQuitMessage(0);
    end;
    WM_CLOSE:
      PostQuitMessage(0);
    WM_USER:
      case wParam of
        101:
          case lParam of
            WM_LBUTTONDBLCLK: 
              RestartTimer;
            WM_RBUTTONDBLCLK: begin
              // Don't leak MouseUp message
              Sleep(100);
              PostQuitMessage(0);
            end;
            WM_MBUTTONUP: begin
              if GetParams then
                RestartTimer;
            end;
          end;
      end;
    WM_TIMER:
      case wParam of
        201: begin
          Dec(Timeleft);
          if Timeleft <= 0 then begin
            StopTimer;
            TimerTriggered;
            StartTimer;
          end;
          UpdateTrayIcon;
        end;
      end;
  end;
  Result := DefWindowProc(hwnd, msg, wParam, lParam);
end;

procedure Run;
const
  WndClassName = 'SegTimer_WndClass';
  WndName = 'SegTimer_Window';
var
  WC: WNDCLASS;
  W: HWND;
  // Create the window
  procedure CreateWnd;
  begin
    FillChar(WC, SizeOf(WC), 0);
    WC.lpfnWndProc := @Run_WndProc;
    WC.hInstance := HINSTANCE;
    WC.lpszClassName := WndClassName;
    if RegisterClass(WC) = 0 then
      RaiseLastOSError;
    W := CreateWindow(WndClassName, WndName, 0, 0, 0, 0, 0, 0, 0, HINSTANCE, nil);
    if W = 0 then
      RaiseLastOSError;
  end;
  // Destroy the window
  procedure DestroyWnd;
  begin
    DestroyWindow(W);
    UnRegisterClass(WndClassName, HINSTANCE);
  end;
  // Main message loop
  procedure MessageLoop;
  var
    m: tagMSG;
  begin
    while GetMessage(m, 0, 0, 0) do begin
      TranslateMessage(m);
      DispatchMessage(m);
    end;
  end;
begin
  CreateWnd;
  try
    MessageLoop;
  finally
    DestroyWnd;
  end;
end;

var
  M: THandle;

begin
  M := CreateMutex(nil, True, 'SegTimer_InstanceMutex');
  TimerAction := [ScrollLock, BeepBeep];
  if GetLastError = ERROR_ALREADY_EXISTS then begin
    ShowMessage('Segtimer is already running');
    Exit;
  end;
  if ParseParams then
    Run;
  CloseHandle(M);
end.
