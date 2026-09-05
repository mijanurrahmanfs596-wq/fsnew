@echo off
setlocal EnableDelayedExpansion

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
    echo ERROR: CONNECTED_DURATION_MINUTES not set in .env
    pause & exit /b 1
)
if not defined RECONNECT_DELAY_SECONDS (
    echo ERROR: RECONNECT_DELAY_SECONDS not set in .env
    pause & exit /b 1
)

set /a "CONNECTED_DURATION_SECONDS=CONNECTED_DURATION_MINUTES*60"

echo [CONFIG] Connected duration : %CONNECTED_DURATION_MINUTES% minute(s) ^(%CONNECTED_DURATION_SECONDS% seconds^)
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
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%URL%' -OutFile '%INSTALLER%' -UseBasicParsing"
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
timeout /t 2 /nobreak >nul

set "INSTALLED=0"
for %%S in ("/S" "/silent" "/quiet") do (
    if !INSTALLED! EQU 0 (
        "%INSTALLER%" %%S >nul 2>&1
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

echo Waiting for window...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" WaitForWindow 40
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: Hotspot Shield window not found.
    goto :Cleanup
)
echo Window found.

if %FRESH_INSTALL% EQU 1 (

    echo Waiting for OK button...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" ClickButton btn_ok 20
    if !ERRORLEVEL! EQU 0 (
        echo Clicked OK.
        timeout /t 2 /nobreak >nul
    ) else (
        echo OK button not found, skipping...
    )

    echo Waiting for Skip button...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" ClickButton btn_skip 20
    if !ERRORLEVEL! EQU 0 (
        echo Clicked Skip.
        timeout /t 3 /nobreak >nul
    ) else (
        echo Skip button not found, skipping...
    )

    echo Waiting for Back button...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" ClickButton btn_back 20
    if !ERRORLEVEL! EQU 0 (
        echo Clicked Back.
        timeout /t 3 /nobreak >nul
    ) else (
        echo ERROR: Back button not found.
        goto :Cleanup
    )
)

set "LOOP_COUNT=0"

:LoopStart
set /a "LOOP_COUNT+=1"

:: Premium/Basic popup আসলে Back button দিয়ে dismiss করো
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" ClickButton btn_back 3 >nul 2>&1

echo.
echo ==================================================
echo  CYCLE #%LOOP_COUNT%
echo  Connected for  : %CONNECTED_DURATION_MINUTES% min ^(%CONNECTED_DURATION_SECONDS% sec^)
echo  Reconnect delay: %RECONNECT_DELAY_SECONDS% sec
echo ==================================================

timeout /t 3 /nobreak >nul
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
if !VERIFY_COUNT! LSS 5 (
    echo [Cycle %LOOP_COUNT%] Not connected yet, retrying... ^(!VERIFY_COUNT!/5^)
    goto :VerifyLoop
)
echo [Cycle %LOOP_COUNT%] ERROR: Connection failed after 5 attempts. Retrying cycle...
call :SimpleTimer %RECONNECT_DELAY_SECONDS% "Retry in"
goto :LoopStart

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

:: -------------------------------------------------------
:: Flicker-free countdown timer using carriage-return trick
:: Usage: call :SimpleTimer <seconds> "Label"
:: Prints a single line that updates in-place — no cls, no flicker
:: -------------------------------------------------------
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
> "%F%" echo Add-Type -AssemblyName UIAutomationClient
>> "%F%" echo Add-Type -AssemblyName UIAutomationTypes
>> "%F%" echo Add-Type -AssemblyName Microsoft.VisualBasic
>> "%F%" echo.
>> "%F%" echo $csCode = 'using System; using System.Runtime.InteropServices; public class MC { [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y); [DllImport("user32.dll")] public static extern void mouse_event(int f,int x,int y,int b,int e); public const int LD=2,LU=4; public static void Click(int x,int y){SetCursorPos(x,y);mouse_event(LD,x,y,0,0);System.Threading.Thread.Sleep(100);mouse_event(LU,x,y,0,0);}}'
>> "%F%" echo Add-Type -Language CSharp -TypeDefinition $csCode
>> "%F%" echo.
>> "%F%" echo $windowNames = @('Hotspot Shield','Hotspot Shield Basic','HotspotShield','Hotspot Shield VPN','Hotspot Shield Free')
>> "%F%" echo $root = [System.Windows.Automation.AutomationElement]::RootElement
>> "%F%" echo.
>> "%F%" echo function Restore-HSWindow {
>> "%F%" echo     $procs = Get-Process -ErrorAction SilentlyContinue ^| Where-Object { $_.Name -match 'hsscp' }
>> "%F%" echo     foreach ($p in $procs) {
>> "%F%" echo         try { [Microsoft.VisualBasic.Interaction]::AppActivate($p.Id) } catch {}
>> "%F%" echo     }
>> "%F%" echo }
>> "%F%" echo.
>> "%F%" echo function Find-HSWindow([int]$timeoutSec) {
>> "%F%" echo     $deadline = (Get-Date).AddSeconds($timeoutSec)
>> "%F%" echo     while ((Get-Date) -lt $deadline) {
>> "%F%" echo         Restore-HSWindow
>> "%F%" echo         Start-Sleep -Milliseconds 400
>> "%F%" echo         foreach ($name in $windowNames) {
>> "%F%" echo             $cond = New-Object System.Windows.Automation.PropertyCondition(
>> "%F%" echo                 [System.Windows.Automation.AutomationElement]::NameProperty, $name)
>> "%F%" echo             $win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
>> "%F%" echo             if ($win -ne $null) { return $win }
>> "%F%" echo         }
>> "%F%" echo         Start-Sleep -Milliseconds 500
>> "%F%" echo     }
>> "%F%" echo     return $null
>> "%F%" echo }
>> "%F%" echo.
>> "%F%" echo $action  = $args[0]
>> "%F%" echo $btnId   = $args[1]
>> "%F%" echo $timeout = if ($args[2]) { [int]$args[2] } else { [int]$args[1] }
>> "%F%" echo.
>> "%F%" echo if ($action -eq 'WaitForWindow') {
>> "%F%" echo     $win = Find-HSWindow $timeout
>> "%F%" echo     if ($win -eq $null) { exit 1 }
>> "%F%" echo     exit 0
>> "%F%" echo }
>> "%F%" echo.
>> "%F%" echo if ($action -eq 'CheckConnected') {
>> "%F%" echo     $win = Find-HSWindow $timeout
>> "%F%" echo     if ($win -eq $null) { exit 1 }
>> "%F%" echo     $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
>> "%F%" echo         [System.Windows.Automation.Condition]::TrueCondition)
>> "%F%" echo     foreach ($el in $all) {
>> "%F%" echo         if ($el.Current.Name -eq 'Connected') { exit 0 }
>> "%F%" echo         if ($el.Current.AutomationId -eq 'lbl_ip' -and $el.Current.Name -ne '') { exit 0 }
>> "%F%" echo     }
>> "%F%" echo     exit 1
>> "%F%" echo }
>> "%F%" echo.
>> "%F%" echo if ($action -eq 'ClickButton') {
>> "%F%" echo     $win = Find-HSWindow $timeout
>> "%F%" echo     if ($win -eq $null) { exit 1 }
>> "%F%" echo     $deadline = (Get-Date).AddSeconds($timeout)
>> "%F%" echo     while ((Get-Date) -lt $deadline) {
>> "%F%" echo         $cond = New-Object System.Windows.Automation.PropertyCondition(
>> "%F%" echo             [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $btnId)
>> "%F%" echo         $btn = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
>> "%F%" echo         if ($btn -ne $null) {
>> "%F%" echo             try { $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
>> "%F%" echo             catch {
>> "%F%" echo                 $r = $btn.Current.BoundingRectangle
>> "%F%" echo                 [MC]::Click([int]($r.Left + $r.Width/2), [int]($r.Top + $r.Height/2))
>> "%F%" echo             }
>> "%F%" echo             exit 0
>> "%F%" echo         }
>> "%F%" echo         Start-Sleep -Milliseconds 500
>> "%F%" echo     }
>> "%F%" echo     exit 1
>> "%F%" echo }
goto :eof

:Cleanup
del /f /q "%PS_HELPER%" >nul 2>&1
exit /b 0