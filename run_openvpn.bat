@echo off
setlocal enabledelayedexpansion
title OpenVPN Auto-Installer and IP Rotator

:: ========================================================
:: 1. Check for Admin Privileges and Auto-Elevate
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
echo        OpenVPN Auto-Installer and IP Rotator System
echo ========================================================
echo.

:: ========================================================
:: 2. Read Credentials and Settings from .env File
:: ========================================================
if not exist ".env" (
    echo [ERROR] .env file not found!
    echo Creating default .env template...
    (
        echo VPN_USER=
        echo VPN_PASS=
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
    if defined VAL (
        if "!VAL:~0,1!"=="""" set "VAL=!VAL:~1,-1!"
    )
    if /i "!KEY!"=="VPN_USER" set "VPN_USER=!VAL!"
    if /i "!KEY!"=="VPN_PASS" set "VPN_PASS=!VAL!"
    if /i "!KEY!"=="SURFSHARK_USER" set "VPN_USER=!VAL!"
    if /i "!KEY!"=="SURFSHARK_PASS" set "VPN_PASS=!VAL!"
    if /i "!KEY!"=="ROTATE_INTERVAL_SECONDS" set "ROTATE_INTERVAL_SECONDS=!VAL!"
)

if "%ROTATE_INTERVAL_SECONDS%"=="" set "ROTATE_INTERVAL_SECONDS=300"

if "!VPN_USER!"=="" (
    echo [WARNING] VPN_USER is empty in .env file!
    echo Please add your VPN Username in .env.
    pause
    exit /b
)
if "!VPN_PASS!"=="" (
    echo [WARNING] VPN_PASS is empty in .env file!
    echo Please add your VPN Password in .env.
    pause
    exit /b
)

:: ========================================================
:: 3. OpenVPN Detection and Automatic Synchronous Installation
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
    
    set /a OVPN_TRY=1
    :RETRY_OPENVPN_DOWNLOAD
    echo [2/5] Downloading OpenVPN installer (Attempt !OVPN_TRY!/5)...
    curl.exe -sL -k -o "%TEMP%\openvpn_installer.msi" "https://swupdate.openvpn.net/community/releases/OpenVPN-2.6.12-I001-amd64.msi"
    if not exist "%TEMP%\openvpn_installer.msi" (
        powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -Uri 'https://swupdate.openvpn.net/community/releases/OpenVPN-2.6.12-I001-amd64.msi' -OutFile '%TEMP%\openvpn_installer.msi' -UseBasicParsing } catch {}"
    )
    
    if not exist "%TEMP%\openvpn_installer.msi" (
        set /a OVPN_TRY+=1
        if !OVPN_TRY! leq 5 (
            echo [WARNING] OpenVPN download failed. Flushing DNS and retrying in 4 seconds...
            ipconfig /flushdns >nul 2>&1
            timeout /t 4 /nobreak >nul
            goto RETRY_OPENVPN_DOWNLOAD
        )
    )
    
    if exist "%TEMP%\openvpn_installer.msi" (
        echo [2/5] Installing OpenVPN silently in background...
        powershell -NoProfile -Command "Start-Process msiexec.exe -ArgumentList '/i \"%TEMP%\openvpn_installer.msi\" /qn /norestart' -Wait"
        
        echo [2/5] Waiting for OpenVPN files to complete installation...
        set "OPENVPN_EXE="
        for /l %%I in (1,1,25) do (
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
set "AUTH_FILE=%~dp0auth.txt"
(
    echo %VPN_USER%
    echo %VPN_PASS%
) > "%AUTH_FILE%"

:: ========================================================
:: 5. Check / Auto-download Configs Directory (With Auto-Retry)
:: ========================================================
set "CONFIG_DIR=%~dp0configs"
if not exist "%CONFIG_DIR%" (
    if exist "%~dp0surfshark_configs" (
        set "CONFIG_DIR=%~dp0surfshark_configs"
    ) else (
        mkdir "%CONFIG_DIR%"
    )
)

set "CONFIG_COUNT=0"
for %%F in ("%CONFIG_DIR%\*.ovpn") do set /a CONFIG_COUNT+=1

if %CONFIG_COUNT% equ 0 (
    if exist "%~dp0surfshark_configs\*.ovpn" (
        set "CONFIG_DIR=%~dp0surfshark_configs"
        for %%F in ("%CONFIG_DIR%\*.ovpn") do set /a CONFIG_COUNT+=1
    )
)

if %CONFIG_COUNT% equ 0 (
    echo [4/5] No .ovpn files found in '%CONFIG_DIR%\'.
    set /a ATTEMPT=1
    set MAX_RETRIES=15

    :RETRY_CONFIGS_LOOP
    echo [4/5] Attempt [!ATTEMPT!/!MAX_RETRIES!]: Downloading server configurations...
    
    set "ZIP_TEMP=%TEMP%\ovpn_configs.zip"
    if exist "!ZIP_TEMP!" del /f /q "!ZIP_TEMP!" >nul 2>&1

    powershell -NoProfile -Command ^
        "$ProgressPreference='SilentlyContinue'; " ^
        "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; " ^
        "$urls = @('https://api.surfshark.com/v1/server/configurations', 'https://account.surfshark.com/api/v1/server/configurations', 'https://my.surfshark.com/api/v1/server/configurations'); " ^
        "$downloaded = $false; " ^
        "foreach ($u in $urls) { " ^
        "    try { (New-Object System.Net.WebClient).DownloadFile($u, '%TEMP%\ovpn_configs.zip'); if ((Test-Path '%TEMP%\ovpn_configs.zip') -and ((Get-Item '%TEMP%\ovpn_configs.zip').Length -gt 1000)) { $downloaded = $true; break; } } catch {} " ^
        "    if (-not $downloaded) { try { Invoke-WebRequest -Uri $u -OutFile '%TEMP%\ovpn_configs.zip' -TimeoutSec 15 -UseBasicParsing; if ((Test-Path '%TEMP%\ovpn_configs.zip') -and ((Get-Item '%TEMP%\ovpn_configs.zip').Length -gt 1000)) { $downloaded = $true; break; } } catch {} } " ^
        "} " ^
        "if ($downloaded) { exit 0 } else { exit 1 }"

    if not exist "%TEMP%\ovpn_configs.zip" (
        curl.exe -sL -k --connect-timeout 10 -m 30 -o "%TEMP%\ovpn_configs.zip" "https://api.surfshark.com/v1/server/configurations" >nul 2>&1
    )

    if exist "%TEMP%\ovpn_configs.zip" (
        powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; Expand-Archive -Path '%TEMP%\ovpn_configs.zip' -DestinationPath '%CONFIG_DIR%' -Force"
        del /f /q "%TEMP%\ovpn_configs.zip" >nul 2>&1
        for %%F in ("%CONFIG_DIR%\*.ovpn") do set /a CONFIG_COUNT+=1
        if !CONFIG_COUNT! gtr 0 (
            echo [4/5] Successfully downloaded and extracted !CONFIG_COUNT! configurations!
            goto CONFIGS_READY
        )
    )

    echo [WARNING] Download attempt !ATTEMPT! failed! Flushing DNS and retrying in 5 seconds...
    ipconfig /flushdns >nul 2>&1
    set /a ATTEMPT+=1
    if !ATTEMPT! leq !MAX_RETRIES! (
        timeout /t 5 /nobreak >nul
        goto RETRY_CONFIGS_LOOP
    ) else (
        echo.
        echo [WARNING] No .ovpn configuration files found in '%CONFIG_DIR%' directory!
        pause
        exit /b
    )
)

:CONFIGS_READY
echo [4/5] Loaded %CONFIG_COUNT% server configuration profiles.
echo [5/5] Starting automatic IP rotation (Interval: %ROTATE_INTERVAL_SECONDS% seconds)...
echo Press Ctrl+C to stop the rotator.
echo.

:: ========================================================
:: 6. IP Rotation Loop (Fisher-Yates Shuffle)
:: ========================================================
:ROTATION_LOOP
set "COUNT=0"
for %%F in ("%CONFIG_DIR%\*.ovpn") do (
    set /a COUNT+=1
    set "FILE_!COUNT!=%%~fF"
    set "NAME_!COUNT!=%%~nxF"
)

if !COUNT! equ 0 (
    echo [WARNING] No .ovpn configuration files found in '%CONFIG_DIR%' directory!
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
    start /b "" "%OPENVPN_EXE%" --config "!SELECTED_FILE!" --auth-user-pass "%AUTH_FILE%" --auth-retry nointeract
    
    echo Waiting for connection to establish...
    timeout /t 6 /nobreak >nul
    
    :: Query and show live connected IP & Country
    powershell -NoProfile -Command "try { $ipInfo = Invoke-RestMethod -Uri 'http://ip-api.com/json/?fields=status,message,country,city,query,isp' -TimeoutSec 5; if ($ipInfo.status -eq 'success') { Write-Host ('[CONNECTED IP] ' + $ipInfo.query + ' | Country: ' + $ipInfo.country + ' | City: ' + $ipInfo.city + ' | ISP: ' + $ipInfo.isp) -ForegroundColor Green } else { Write-Host ('[CONNECTED IP] ' + $ipInfo.query) -ForegroundColor Green } } catch { Write-Host '[STATUS] Connected' -ForegroundColor Yellow }"
    
    echo.
    echo IP connection active. Waiting %ROTATE_INTERVAL_SECONDS% seconds before next rotation...
    timeout /t %ROTATE_INTERVAL_SECONDS% /nobreak
    echo.
)

echo [INFO] Completed one full random cycle of !COUNT! server profiles. Re-shuffling for next cycle...
goto ROTATION_LOOP
