@echo off
setlocal EnableDelayedExpansion

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ========================================================
    echo  Requesting Administrator Privileges...
    echo ========================================================
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set "ENV_FILE=%~dp0.env"
if not exist "%ENV_FILE%" (
    echo ERROR: .env file not found at %ENV_FILE%
    pause
    exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in ("%ENV_FILE%") do (
    set "_key=%%A"
    set "_val=%%B"
    if not "!_key:~0,1!"=="#" (
        if defined _val (
            set "!_key!=!_val!"
        )
    )
)

if not defined CONNECTED_DURATION_MINUTES (
    set "CONNECTED_DURATION_MINUTES=10"
)
if not defined RECONNECT_DELAY_SECONDS (
    set "RECONNECT_DELAY_SECONDS=10"
)

set /a "CONNECTED_DURATION_SECONDS=CONNECTED_DURATION_MINUTES*60"

echo [CONFIG] Connected duration : %CONNECTED_DURATION_MINUTES% minute(s) (%CONNECTED_DURATION_SECONDS% seconds)
echo [CONFIG] Reconnect delay    : %RECONNECT_DELAY_SECONDS% second(s)
echo.

set "URL=https://control.kochava.com/v1/cpi/click?campaign_id=kohotspot-shield-2oo5a11d43d86192b9&network_id=5798&device_id=device_id&site_id=1&aftr_source=%%2Fvpn%%2F"
set "DOWNLOAD_FOLDER=%USERPROFILE%\Downloads"
set "HOTSPOT_EXE="
set "FRESH_INSTALL=0"
set "PS_HELPER=%TEMP%\hs_helper.ps1"

:: Build a carriage-return character for flicker-free inline timer
for /f %%A in ('copy /z "%~f0" nul') do set "CR=%%A"

call :WriteHelper

call :FindHotspotExe
if defined HOTSPOT_EXE (
    echo [OK] Hotspot Shield already installed. Skipping download and install.
    goto :Phase3_Launch
)

echo Cleaning old Hotspot Shield installers...
del /f /q "%DOWNLOAD_FOLDER%\*Hotspot*.exe" >nul 2>&1

set "INSTALLER=%DOWNLOAD_FOLDER%\HotspotShield_Setup.exe"

echo Downloading Hotspot Shield silently...
curl.exe -sL -o "%INSTALLER%" "%URL%"
if not exist "%INSTALLER%" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $u = [System.Environment]::GetEnvironmentVariable('URL'); Invoke-WebRequest -Uri $u -OutFile '%INSTALLER%' -UseBasicParsing"
)
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: Download failed.
    goto :Cleanup
)

call :CheckFileSize "%INSTALLER%"
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: Downloaded file is too small or corrupt.
    goto :Cleanup
)

echo Downloaded: %INSTALLER%

echo Starting installation...

for /f "tokens=1" %%P in ('tasklist /fo csv /nh 2^>nul ^| findstr /i "Hotspot hssvpn"') do (
    set "_P=%%~P"
    set "_P=!_P:"=!"
    taskkill /im "!_P!" /f >nul 2>&1
)
timeout /t 2 /nobreak >nul 2>&1

set "INSTALLED=0"
for %%S in ("/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" "/S" "/silent" "/quiet") do (
    if !INSTALLED! EQU 0 (
        start /wait "" "%INSTALLER%" %%~S
        if !ERRORLEVEL! EQU 0 (
            echo Silent install succeeded with: %%S
            set "INSTALLED=1"
        )
    )
)

if !INSTALLED! EQU 0 (
    echo [ERROR] Silent install failed.
    goto :Cleanup
)

echo [OK] Hotspot Shield installed successfully.
timeout /t 5 /nobreak >nul

call :FindHotspotExe
if not defined HOTSPOT_EXE (
    echo ERROR: hsscp.exe not found after install.
    goto :Cleanup
)
set "FRESH_INSTALL=1"

:Phase3_Launch
echo Launching Hotspot Shield...
start "" "%HOTSPOT_EXE%"

echo Waiting for window and clearing popups...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" WaitForWindow 40
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: Hotspot Shield window not found.
    goto :Cleanup
)
echo Window found.

:: Dismiss any introductory offers or popups automatically
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" DismissPopups 5 >nul 2>&1

set "LOOP_COUNT=0"

:LoopStart
set /a "LOOP_COUNT+=1"

:: Dismiss any promo, offer or back popups before connecting
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" DismissPopups 3 >nul 2>&1

echo.
echo ==================================================
echo  CYCLE #%LOOP_COUNT%
echo  Connected for  : %CONNECTED_DURATION_MINUTES% min (%CONNECTED_DURATION_SECONDS% sec)
echo  Reconnect delay: %RECONNECT_DELAY_SECONDS% sec
echo ==================================================

timeout /t 2 /nobreak >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" WaitForWindow 20
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: VPN window not found. Relaunching Hotspot Shield...
    call :FindHotspotExe
    if defined HOTSPOT_EXE (
        start "" "%HOTSPOT_EXE%"
        timeout /t 5 /nobreak >nul
    ) else (
        echo ERROR: Hotspot Shield exe not found. Retrying in %RECONNECT_DELAY_SECONDS% seconds...
    )
    call :SimpleTimer %RECONNECT_DELAY_SECONDS% "Retry in"
    goto :LoopStart
)

echo [Cycle %LOOP_COUNT%] Connecting...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" ClickButton btn_connect 20
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: Connect button not found. Retrying in %RECONNECT_DELAY_SECONDS% seconds...
    call :SimpleTimer %RECONNECT_DELAY_SECONDS% "Retry in"
    goto :LoopStart
)

echo [Cycle %LOOP_COUNT%] Verifying connection...
set "VERIFY_COUNT=0"
:VerifyLoop
set /a "VERIFY_COUNT+=1"
timeout /t 3 /nobreak >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" CheckConnected 5
if !ERRORLEVEL! EQU 0 (
    echo [Cycle %LOOP_COUNT%] Connection verified!
    goto :StartTimer
)
if !VERIFY_COUNT! LSS 6 (
    echo [Cycle %LOOP_COUNT%] Not connected yet, checking... (!VERIFY_COUNT!/6)
    goto :VerifyLoop
)
echo [Cycle %LOOP_COUNT%] WARNING: UI status not confirmed, checking IP traffic...
goto :StartTimer

:StartTimer
call :SimpleTimer %CONNECTED_DURATION_SECONDS% "Disconnecting in"
echo.
echo [Cycle %LOOP_COUNT%] Connected timer finished.

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" WaitForWindow 10
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: VPN window lost. Restarting cycle...
    goto :LoopStart
)

echo [Cycle %LOOP_COUNT%] Disconnecting...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" ClickButton btn_connect 10
timeout /t 2 /nobreak >nul
echo [Cycle %LOOP_COUNT%] Disconnected.

echo [Cycle %LOOP_COUNT%] Reconnecting in %RECONNECT_DELAY_SECONDS% seconds...
call :SimpleTimer %RECONNECT_DELAY_SECONDS% "Reconnecting in"
echo.

goto :LoopStart

:: ========================================================
:: Subroutines
:: ========================================================

:SimpleTimer
setlocal EnableDelayedExpansion
set /a "_total=%~1"
set "_label=%~2"
for /l %%i in (%_total%,-1,1) do (
    set /a "_m=%%i/60"
    set /a "_s=%%i%%60"
    if !_m! gtr 0 (
        set "_disp=  !_label!: !_m!m !_s!s remaining...   "
    ) else (
        set "_disp=  !_label!: !_s!s remaining...         "
    )
    <nul set /p "=!_disp!!CR!"
    timeout /t 1 /nobreak >nul
)
<nul set /p "=  !_label!: done.                              !CR!"
endlocal
goto :eof

:FindHotspotExe
set "HOTSPOT_EXE="
for %%B in (
    "C:\Program Files (x86)\Hotspot Shield"
    "C:\Program Files\Hotspot Shield"
    "%LOCALAPPDATA%\Hotspot Shield"
    "%ProgramFiles%\Hotspot Shield"
) do (
    if exist %%B (
        for /f "delims=" %%E in ('dir /b /s %%B\hsscp.exe 2^>nul') do (
            if not defined HOTSPOT_EXE set "HOTSPOT_EXE=%%E"
        )
    )
)
goto :eof

:CheckFileSize
for %%A in ("%~1") do set "_SZ=%%~zA"
if not defined _SZ exit /b 1
if !_SZ! GEQ 1048576 exit /b 0
exit /b 1

:WriteHelper
set "F=%PS_HELPER%"
(
echo Add-Type -AssemblyName UIAutomationClient
echo Add-Type -AssemblyName UIAutomationTypes
echo Add-Type -AssemblyName Microsoft.VisualBasic
echo.
echo ^$csCode = @"
echo using System;
echo using System.Runtime.InteropServices;
echo public class MC {
echo     [DllImport("user32.dll"^)] public static extern bool SetCursorPos(int x, int y^);
echo     [DllImport("user32.dll"^)] public static extern void mouse_event(int f, int x, int y, int b, int e^);
echo     [DllImport("user32.dll"^)] public static extern bool SetForegroundWindow(IntPtr hWnd^);
echo     public const int LD = 2, LU = 4;
echo     public static void Click(int x, int y^) {
echo         SetCursorPos(x, y^);
echo         mouse_event(LD, x, y, 0, 0^);
echo         System.Threading.Thread.Sleep(120^);
echo         mouse_event(LU, x, y, 0, 0^);
echo     }
echo }
echo "@
echo Add-Type -Language CSharp -TypeDefinition ^$csCode
echo.
echo ^$root = [System.Windows.Automation.AutomationElement]::RootElement
echo.
echo function Restore-HSWindow {
echo     ^$procs = Get-Process -ErrorAction SilentlyContinue ^| Where-Object { ^$_.Name -match 'hsscp' }
echo     foreach (^$p in ^$procs^) {
echo         try {
echo             [Microsoft.VisualBasic.Interaction]::AppActivate(^$p.Id^)
echo             [MC]::SetForegroundWindow(^$p.MainWindowHandle^)
echo         } catch {}
echo     }
echo }
echo.
echo function Dismiss-Popups {
echo     try {
echo         ^$allWins = ^$root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition^)
echo         foreach (^$w in ^$allWins^) {
echo             ^$wName = ^$w.Current.Name
echo             if (^$wName -match '(?i^)(Optional Offer^|Offer^|Yahoo^|Welcome^|Premium^|Promotion^|Notice^|Survey^)'^) {
echo                 ^$btns = ^$w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition^)
echo                 foreach (^$b in ^$btns^) {
echo                     ^$bName = ^$b.Current.Name
echo                     ^$bAid = ^$b.Current.AutomationId
echo                     if (^$bName -match '(?i^)^^(Decline^|Skip^|Close^|Back^|No thanks^|Cancel^|Dismiss^|Maybe later^|Continue with basic^)$' -or ^$bAid -match '(?i^)(decline^|skip^|close^|back^|cancel^|dismiss^|btn_decline^|btn_skip^|btn_back^|btn_close^)'^) {
echo                         try {
echo                             ^$b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern^).Invoke(^)
echo                             Start-Sleep -Milliseconds 400
echo                         } catch {
echo                             ^$r = ^$b.Current.BoundingRectangle
echo                             if (^$r.Width -gt 0^) {
echo                                 [MC]::Click([int](^$r.Left + ^$r.Width/2^), [int](^$r.Top + ^$r.Height/2^)^)
echo                                 Start-Sleep -Milliseconds 400
echo                             }
echo                         }
echo                     }
echo                 }
echo             }
echo         }
echo     } catch {}
echo     try {
echo         ^$win = Find-HSWindow 1
echo         if (^$win -ne ^$null^) {
echo             ^$btns = ^$win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition^)
echo             foreach (^$b in ^$btns^) {
echo                 ^$bName = ^$b.Current.Name
echo                 ^$bAid = ^$b.Current.AutomationId
echo                 if (^$bName -match '(?i^)^^(Decline^|Skip^|Back^|Close^|No thanks^|Cancel^|Dismiss^|Maybe later^|Continue with basic^)$' -or ^$bAid -match '(?i^)(btn_decline^|btn_skip^|btn_back^|btn_close^|btn_dismiss^|btn_header_back^)'^) {
echo                     try {
echo                         ^$b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern^).Invoke(^)
echo                         Start-Sleep -Milliseconds 300
echo                     } catch {
echo                         ^$r = ^$b.Current.BoundingRectangle
echo                         if (^$r.Width -gt 0 -and ^$r.Height -gt 0^) {
echo                             [MC]::Click([int](^$r.Left + ^$r.Width/2^), [int](^$r.Top + ^$r.Height/2^)^)
echo                             Start-Sleep -Milliseconds 300
echo                         }
echo                     }
echo                 }
echo             }
echo         }
echo     } catch {}
echo }
echo.
echo function Find-HSWindow([int]^$timeoutSec^) {
echo     ^$deadline = (Get-Date^).AddSeconds(^$timeoutSec^)
echo     while ((Get-Date^) -lt ^$deadline^) {
echo         Restore-HSWindow
echo         Start-Sleep -Milliseconds 300
echo         ^$allWins = ^$root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition^)
echo         foreach (^$win in ^$allWins^) {
echo             ^$n = ^$win.Current.Name
echo             ^$p = ^$win.Current.ProcessId
echo             if (^$n -match 'Hotspot Shield^|HotspotShield^|Hotspot' -or (^$p -gt 0 -and (Get-Process -Id ^$p -ErrorAction SilentlyContinue^).ProcessName -match 'hsscp'^)^) {
echo                 if (^$n -notmatch '(?i^)(Optional Offer^|Offer^|Setup^)'^) {
echo                     return ^$win
echo                 }
echo             }
echo         }
echo         Start-Sleep -Milliseconds 400
echo     }
echo     return ^$null
echo }
echo.
echo ^$action  = ^$args[0]
echo ^$btnId   = ^$args[1]
echo ^$timeout = if (^$args[2]^) { [int]^$args[2] } else { [int]^$args[1] }
echo.
echo if (^$action -eq 'DismissPopups'^) {
echo     Dismiss-Popups
echo     exit 0
echo }
echo.
echo if (^$action -eq 'WaitForWindow'^) {
echo     Dismiss-Popups
echo     ^$win = Find-HSWindow ^$timeout
echo     if (^$win -eq ^$null^) { exit 1 }
echo     exit 0
echo }
echo.
echo if (^$action -eq 'CheckConnected'^) {
echo     Dismiss-Popups
echo     ^$win = Find-HSWindow ^$timeout
echo     if (^$win -ne ^$null^) {
echo         ^$all = ^$win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition^)
echo         foreach (^$el in ^$all^) {
echo             ^$name = ^$el.Current.Name
echo             ^$aid = ^$el.Current.AutomationId
echo             if (^$name -match '(?i^)(Connected^|Disconnect^|Stop^|Protection is on^|VPN ON^)' -or (^$aid -eq 'lbl_ip' -and ^$name -ne ''^) -or (^$aid -match '(?i^)(disconnect^|connected^)'^)^) {
echo                 exit 0
echo             }
echo         }
echo     }
echo     try {
echo         ^$hssNics = Get-NetAdapter -ErrorAction SilentlyContinue ^| Where-Object { (^$_.InterfaceDescription -match 'Hotspot Shield^|Anchorfree^|HSS' -or ^$_.Name -match 'Hotspot'^) -and ^$_.Status -eq 'Up' }
echo         if (^$hssNics -ne ^$null -and ^$hssNics.Count -gt 0^) { exit 0 }
echo     } catch {}
echo     exit 1
echo }
echo.
echo if (^$action -eq 'ClickButton'^) {
echo     Dismiss-Popups
echo     Start-Sleep -Milliseconds 400
echo     Dismiss-Popups
echo.
echo     ^$win = Find-HSWindow ^$timeout
echo     if (^$win -eq ^$null^) { exit 1 }
echo.
echo     ^$deadline = (Get-Date^).AddSeconds(^$timeout^)
echo     while ((Get-Date^) -lt ^$deadline^) {
echo         ^$all = ^$win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition^)
echo         ^$clicked = ^$false
echo.
echo         foreach (^$el in ^$all^) {
echo             ^$aid = ^$el.Current.AutomationId
echo             ^$name = ^$el.Current.Name
echo             ^$match = ^$false
echo.
echo             if (^$btnId -match 'btn_connect'^) {
echo                 if (^$aid -match '(?i^)^^(btn_connect^|connect^|btn_power^|button_connect^|btn_main_action^|btn_start^)$' -or ^$name -match '(?i^)^^(Connect^|Disconnect^|Stop^|Start^)$'^) {
echo                     ^$match = ^$true
echo                 }
echo             } elseif (^$btnId -match 'btn_back'^) {
echo                 if (^$aid -match '(?i^)(back^|btn_back^|btn_header_back^)' -or ^$name -match '(?i^)^^(Back^|<^)$'^) {
echo                     ^$match = ^$true
echo                 }
echo             } elseif (^$btnId -match 'btn_skip'^) {
echo                 if (^$aid -match '(?i^)(skip^|btn_skip^)' -or ^$name -match '(?i^)^^(Skip^|Skip for now^)$'^) {
echo                     ^$match = ^$true
echo                 }
echo             } elseif (^$btnId -match 'btn_ok'^) {
echo                 if (^$aid -match '(?i^)(ok^|btn_ok^|agree^)' -or ^$name -match '(?i^)^^(OK^|Agree^|Continue^)$'^) {
echo                     ^$match = ^$true
echo                 }
echo             } else {
echo                 if (^$aid -eq ^$btnId -or ^$name -eq ^$btnId^) {
echo                     ^$match = ^$true
echo                 }
echo             }
echo.
echo             if (^$match^) {
echo                 try {
echo                     ^$el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern^).Invoke(^)
echo                     ^$clicked = ^$true
echo                     break
echo                 } catch {
echo                     ^$r = ^$el.Current.BoundingRectangle
echo                     if (^$r.Width -gt 0 -and ^$r.Height -gt 0^) {
echo                         [MC]::Click([int](^$r.Left + ^$r.Width/2^), [int](^$r.Top + ^$r.Height/2^)^)
echo                         ^$clicked = ^$true
echo                         break
echo                     }
echo                 }
echo             }
echo         }
echo.
echo         if (^$clicked^) { exit 0 }
echo.
echo         if (^$btnId -match 'btn_connect'^) {
echo             ^$r = ^$win.Current.BoundingRectangle
echo             if (^$r.Width -gt 100 -and ^$r.Height -gt 100^) {
echo                 ^$cx = [int](^$r.Left + ^$r.Width / 2^)
echo                 ^$cy = [int](^$r.Top + (^$r.Height * 0.52^)^)
echo                 [MC]::Click(^$cx, ^$cy^)
echo                 exit 0
echo             }
echo         }
echo.
echo         Dismiss-Popups
echo         Start-Sleep -Milliseconds 600
echo     }
echo     exit 1
echo }
) > "%F%"
goto :eof

:Cleanup
del /f /q "%PS_HELPER%" >nul 2>&1
exit /b 0
