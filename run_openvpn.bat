@echo off
setlocal enabledelayedexpansion
title OpenVPN Auto Installer and IP Rotator

:: ========================================================
:: 1. Administrative Privileges Check & Elevation
:: ========================================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ========================================================
    echo  Requesting Administrator Privileges...
    echo ========================================================
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo ========================================================
echo        OpenVPN Auto-Installer ^& IP Rotator System
echo ========================================================
echo.

:: ========================================================
:: 2. Read Credentials and Settings from .env File
:: ========================================================
if not exist ".env" (
    echo [ERROR] .env file not found!
    echo Creating default .env template...
    (
        echo VPN_USER=your_username
        echo VPN_PASS=your_password
        echo ROTATE_INTERVAL_SECONDS=300
    ) > .env
    echo Please update the credentials in .env file and run this script again.
    pause
    exit /b
)

echo [1/5] Loading configuration from .env...
for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
    set "KEY=%%A"
    set "VAL=%%B"
    if /i "!KEY!"=="VPN_USER" set "VPN_USER=!VAL!"
    if /i "!KEY!"=="VPN_PASS" set "VPN_PASS=!VAL!"
    if /i "!KEY!"=="ROTATE_INTERVAL_SECONDS" set "ROTATE_INTERVAL_SECONDS=!VAL!"
)

if "%ROTATE_INTERVAL_SECONDS%"=="" set "ROTATE_INTERVAL_SECONDS=300"

if "%VPN_USER%"=="" (
    echo [WARNING] VPN_USER is empty in .env file!
)
if "%VPN_USER%"=="your_username" (
    echo [WARNING] Please update VPN_USER in .env file!
)

:: ========================================================
:: 3. OpenVPN Detection ^& Automatic Synchronous Installation
:: ========================================================
set "OPENVPN_EXE=C:\Program Files\OpenVPN\bin\openvpn.exe"
if not exist "!OPENVPN_EXE!" set "OPENVPN_EXE=C:\Program Files (x86)\OpenVPN\bin\openvpn.exe"
if not exist "!OPENVPN_EXE!" set "OPENVPN_EXE=C:\Program Files\OpenVPN\openvpn.exe"
if not exist "!OPENVPN_EXE!" set "OPENVPN_EXE=C:\Program Files (x86)\OpenVPN\openvpn.exe"
if not exist "!OPENVPN_EXE!" (
    for /f "delims=" %%P in ('where openvpn.exe 2^>nul') do set "OPENVPN_EXE=%%P"
)

if not exist "!OPENVPN_EXE!" (
    echo [2/5] OpenVPN binary not found. Starting automatic installer download...
    set "INSTALLER_PATH=%TEMP%\openvpn_installer.msi"
    
    powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://swupdate.openvpn.org/community/releases/OpenVPN-2.6.12-I001-amd64.msi' -OutFile '%TEMP%\openvpn_installer.msi' -UseBasicParsing"
    
    if exist "%TEMP%\openvpn_installer.msi" (
        echo [2/5] Installing OpenVPN silently in background...
        powershell -Command "Start-Process msiexec.exe -ArgumentList '/i \"%TEMP%\openvpn_installer.msi\" /qn /norestart' -Wait"
        
        echo [2/5] Waiting for OpenVPN files to complete installation...
        set "OPENVPN_EXE="
        for /l %%I in (1,1,20) do (
            if "!OPENVPN_EXE!"=="" (
                if exist "C:\Program Files\OpenVPN\bin\openvpn.exe" set "OPENVPN_EXE=C:\Program Files\OpenVPN\bin\openvpn.exe"
                if exist "C:\Program Files (x86)\OpenVPN\bin\openvpn.exe" set "OPENVPN_EXE=C:\Program Files (x86)\OpenVPN\bin\openvpn.exe"
                if exist "C:\Program Files\OpenVPN\openvpn.exe" set "OPENVPN_EXE=C:\Program Files\OpenVPN\openvpn.exe"
                if exist "C:\Program Files (x86)\OpenVPN\openvpn.exe" set "OPENVPN_EXE=C:\Program Files (x86)\OpenVPN\openvpn.exe"
                if "!OPENVPN_EXE!"=="" (
                    for /f "delims=" %%P in ('where openvpn.exe 2^>nul') do set "OPENVPN_EXE=%%P"
                )
                if "!OPENVPN_EXE!"=="" timeout /t 2 /nobreak >nul
            )
        )
        
        if exist "%TEMP%\openvpn_installer.msi" del /f /q "%TEMP%\openvpn_installer.msi" >nul 2>&1
    ) else (
        echo [ERROR] Failed to download OpenVPN installer. Please check internet connection.
        pause
        exit /b
    )
    
    if "!OPENVPN_EXE!"=="" (
        echo [ERROR] OpenVPN installation completed, but openvpn.exe was not found.
        echo If OpenVPN was installed to a custom directory, please check Program Files.
        pause
        exit /b
    )
    echo [2/5] OpenVPN successfully installed!
) else (
    echo [2/5] OpenVPN is already installed.
)

:: ========================================================
:: 4. Generate Auth File from Credentials
:: ========================================================
echo [3/5] Preparing authentication file...
(
    echo %VPN_USER%
    echo %VPN_PASS%
) > auth.txt

:: ========================================================
:: 5. Check Configs Directory for .ovpn files
:: ========================================================
if not exist "configs" mkdir "configs"

dir /b "configs\*.ovpn" >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo [WARNING] No .ovpn configuration files found in 'configs\' directory!
    echo Please place your .ovpn profile files in: %~dp0configs\
    echo.
    pause
    exit /b
)

echo [4/5] OpenVPN setup complete.
echo [5/5] Starting automatic IP rotation (Interval: %ROTATE_INTERVAL_SECONDS% seconds)...
echo Press Ctrl+C to stop the rotator.
echo.

:: ========================================================
:: 6. IP Rotation Loop (Random Shuffle Cycle)
:: ========================================================
:ROTATION_LOOP
set "COUNT=0"
for %%F in ("configs\*.ovpn") do (
    set /a COUNT+=1
    set "FILE_!COUNT!=%%~fF"
    set "NAME_!COUNT!=%%~nxF"
)

if !COUNT! equ 0 (
    echo [WARNING] No .ovpn configuration files found in 'configs\' directory!
    timeout /t 5 /nobreak >nul
    goto ROTATION_LOOP
)

:: Initialize shuffle index array
for /l %%I in (1,1,!COUNT!) do set "SHUFFLE_%%I=%%I"

:: Fisher-Yates Shuffle algorithm for true non-repeating random order
for /l %%I in (!COUNT!,-1,2) do (
    set /a "RAND_R=(!RANDOM! %% %%I) + 1"
    for %%J in (!RAND_R!) do (
        set "TEMP=!SHUFFLE_%%I!"
        set "SHUFFLE_%%I=!SHUFFLE_%%J!"
        set "SHUFFLE_%%J=!TEMP!"
    )
)

:: Loop through all shuffled profiles in this cycle
for /l %%S in (1,1,!COUNT!) do (
    for %%D in (!SHUFFLE_%%S!) do (
        set "SELECTED_FILE=!FILE_%%D!"
        set "SELECTED_NAME=!NAME_%%D!"
    )

    echo --------------------------------------------------------
    echo [CONNECTING] Server Profile [%%S/!COUNT!]: !SELECTED_NAME!
    echo [TIMESTAMP]  !date! !time!
    echo --------------------------------------------------------
    
    :: Terminate previous connection
    taskkill /f /im openvpn.exe >nul 2>&1
    timeout /t 2 /nobreak >nul
    
    :: Launch OpenVPN connection in background
    start /b "" "%OPENVPN_EXE%" --config "!SELECTED_FILE!" --auth-user-pass auth.txt
    
    echo IP connection initialized. Waiting %ROTATE_INTERVAL_SECONDS% seconds before next rotation...
    timeout /t %ROTATE_INTERVAL_SECONDS% /nobreak
    echo.
)

echo [INFO] Completed one full random cycle of !COUNT! server profiles. Re-shuffling for next cycle...
goto ROTATION_LOOP
