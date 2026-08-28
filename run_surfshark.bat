@echo off
setlocal enabledelayedexpansion
title Surfshark VPN Auto-Installer, Config Downloader and IP Rotator

:: ========================================================
:: 1. Administrative Privileges Check and Elevation
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
echo   Surfshark VPN Auto-Installer, Downloader and IP Rotator
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
    echo Please update your Surfshark VPN_USER and VPN_PASS in .env file and run again.
    pause
    exit /b
)

echo [1/5] Loading credentials from .env...
for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
    set "KEY=%%A"
    set "VAL=%%B"
    :: Strip surrounding quotes if present
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
    echo Please enter your Surfshark Service Username in .env file.
    echo Get it from: Surfshark Dashboard - VPN - Manual Setup - OpenVPN
    echo.
    pause
    exit /b
)

if "!VPN_PASS!"=="" (
    echo [WARNING] VPN_PASS is empty in .env file!
    echo Please enter your Surfshark Service Password in .env file.
    echo.
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
        
        echo [2/5] Waiting for OpenVPN files to finalize...
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
        echo [ERROR] Failed to download OpenVPN installer after multiple attempts. Please check internet connection.
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
:: 4. Automatic Surfshark Configuration Download and Extract (With Auto-Retry)
:: ========================================================
set "CONFIG_DIR=%~dp0surfshark_configs"
if not exist "%CONFIG_DIR%" (
    if exist "%~dp0configs" (
        set "CONFIG_DIR=%~dp0configs"
    ) else (
        mkdir "%CONFIG_DIR%"
    )
)

set "OVPN_COUNT=0"
for %%F in ("%CONFIG_DIR%\*.ovpn") do set /a OVPN_COUNT+=1

:: If 0 in current CONFIG_DIR, check if other configs directory exists
if %OVPN_COUNT% equ 0 (
    if exist "%~dp0configs\*.ovpn" (
        set "CONFIG_DIR=%~dp0configs"
        for %%F in ("%CONFIG_DIR%\*.ovpn") do set /a OVPN_COUNT+=1
    )
)

if %OVPN_COUNT% equ 0 (
    echo [3/5] No Surfshark .ovpn files found in '%CONFIG_DIR%\'.
    set /a ATTEMPT=1
    set MAX_RETRIES=15

    :RETRY_CONFIG_DOWNLOAD
    echo.
    echo [3/5] Attempt [!ATTEMPT!/!MAX_RETRIES!]: Downloading official configuration package from Surfshark...
    
    set "ZIP_TEMP=%TEMP%\surfshark_configs.zip"
    if exist "!ZIP_TEMP!" del /f /q "!ZIP_TEMP!" >nul 2>&1

    powershell -NoProfile -Command ^
        "$ProgressPreference='SilentlyContinue'; " ^
        "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; " ^
        "$urls = @( " ^
        "    'https://api.surfshark.com/v1/server/configurations', " ^
        "    'https://account.surfshark.com/api/v1/server/configurations', " ^
        "    'https://my.surfshark.com/api/v1/server/configurations' " ^
        "); " ^
        "$downloaded = $false; " ^
        "foreach ($u in $urls) { " ^
        "    try { " ^
        "        (New-Object System.Net.WebClient).DownloadFile($u, '%TEMP%\surfshark_configs.zip'); " ^
        "        if ((Test-Path '%TEMP%\surfshark_configs.zip') -and ((Get-Item '%TEMP%\surfshark_configs.zip').Length -gt 1000)) { " ^
        "            $downloaded = $true; break; " ^
        "        } " ^
        "    } catch {} " ^
        "    if (-not $downloaded) { " ^
        "        try { " ^
        "            Invoke-WebRequest -Uri $u -OutFile '%TEMP%\surfshark_configs.zip' -TimeoutSec 15 -UseBasicParsing; " ^
        "            if ((Test-Path '%TEMP%\surfshark_configs.zip') -and ((Get-Item '%TEMP%\surfshark_configs.zip').Length -gt 1000)) { " ^
        "                $downloaded = $true; break; " ^
        "            } " ^
        "        } catch {} " ^
        "    } " ^
        "} " ^
        "if ($downloaded) { Write-Host '[OK] Download successful.' } else { exit 1 }"

    if not exist "%TEMP%\surfshark_configs.zip" (
        curl.exe -sL -k --connect-timeout 10 -m 30 -o "%TEMP%\surfshark_configs.zip" "https://api.surfshark.com/v1/server/configurations" >nul 2>&1
    )

    if exist "%TEMP%\surfshark_configs.zip" (
        echo       Extracting server profiles to %CONFIG_DIR%\...
        powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; Expand-Archive -Path '%TEMP%\surfshark_configs.zip' -DestinationPath '%CONFIG_DIR%' -Force"
        del /f /q "%TEMP%\surfshark_configs.zip" >nul 2>&1
        
        set "OVPN_COUNT=0"
        for %%F in ("%CONFIG_DIR%\*.ovpn") do set /a OVPN_COUNT+=1
        if !OVPN_COUNT! gtr 0 (
            echo [3/5] Successfully downloaded and extracted !OVPN_COUNT! Surfshark server configurations!
            goto CONFIG_DOWNLOAD_DONE
        )
    )

    echo [WARNING] Download/Extraction attempt !ATTEMPT! failed!
    echo [INFO] Flushing DNS cache and waiting 5 seconds before retrying...
    ipconfig /flushdns >nul 2>&1
    
    set /a ATTEMPT+=1
    if !ATTEMPT! leq !MAX_RETRIES! (
        timeout /t 5 /nobreak >nul
        goto RETRY_CONFIG_DOWNLOAD
    ) else (
        echo.
        echo [ERROR] Could not download Surfshark .ovpn files automatically after !MAX_RETRIES! attempts.
        echo Please manually place your .ovpn files into: %CONFIG_DIR%
        pause
        exit /b
    )
)

:CONFIG_DOWNLOAD_DONE
if %OVPN_COUNT% gtr 0 (
    echo [3/5] Found %OVPN_COUNT% Surfshark server configurations.
)

:: ========================================================
:: 5. Generate Auth File
:: ========================================================
set "AUTH_FILE=%~dp0surfshark_auth.txt"
(
    echo %VPN_USER%
    echo %VPN_PASS%
) > "%AUTH_FILE%"

echo [4/5] Authentication file prepared.
echo [5/5] Ready! Starting Surfshark IP Rotation (Interval: %ROTATE_INTERVAL_SECONDS%s)...
echo Press Ctrl+C at any time to stop.
echo.

:: ========================================================
:: 6. IP Rotation Loop (Fisher-Yates Non-Repeating Shuffle)
:: ========================================================
:ROTATION_LOOP
set "TOTAL_SERVERS=0"
for %%F in ("%CONFIG_DIR%\*.ovpn") do (
    set /a TOTAL_SERVERS+=1
    set "SERVER_FILE_!TOTAL_SERVERS!=%%~fF"
    set "SERVER_NAME_!TOTAL_SERVERS!=%%~nxF"
)

if !TOTAL_SERVERS! equ 0 (
    echo [ERROR] No .ovpn files available in '%CONFIG_DIR%'.
    timeout /t 5 /nobreak >nul
    goto ROTATION_LOOP
)

:: Initialize shuffle index array
for /l %%I in (1,1,!TOTAL_SERVERS!) do set "SHUFFLE_%%I=%%I"

:: Fisher-Yates Shuffle algorithm
for /l %%I in (!TOTAL_SERVERS!,-1,2) do (
    set /a "RAND_R=(!RANDOM! %% %%I) + 1"
    for %%J in (!RAND_R!) do (
        set "TEMP=!SHUFFLE_%%I!"
        set "SHUFFLE_%%I=!SHUFFLE_%%J!"
        set "SHUFFLE_%%J=!TEMP!"
    )
)

:: Iterate through each randomized server profile in this cycle
for /l %%S in (1,1,!TOTAL_SERVERS!) do (
    for %%D in (!SHUFFLE_%%S!) do (
        set "ACTIVE_FILE=!SERVER_FILE_%%D!"
        set "ACTIVE_NAME=!SERVER_NAME_%%D!"
    )

    echo ========================================================
    echo [CONNECTING] Server [%%S/!TOTAL_SERVERS!]: !ACTIVE_NAME!
    echo [TIME]       !date! !time!
    echo ========================================================
    
    :: Terminate previous OpenVPN session cleanly
    taskkill /f /im openvpn.exe >nul 2>&1
    timeout /t 2 /nobreak >nul
    
    :: Connect OpenVPN in background
    start /b "" "%OPENVPN_EXE%" --config "!ACTIVE_FILE!" --auth-user-pass "%AUTH_FILE%" --auth-retry nointeract
    
    :: Wait for VPN handshake to complete
    echo Waiting for connection to establish...
    timeout /t 6 /nobreak >nul
    
    :: Fetch and display current Public IP and Location details
    powershell -NoProfile -Command "try { $ipInfo = Invoke-RestMethod -Uri 'http://ip-api.com/json/?fields=status,message,country,city,query,isp' -TimeoutSec 5; if ($ipInfo.status -eq 'success') { Write-Host ('[CONNECTED IP] ' + $ipInfo.query + ' | Country: ' + $ipInfo.country + ' | City: ' + $ipInfo.city + ' | ISP: ' + $ipInfo.isp) -ForegroundColor Green } else { Write-Host ('[CONNECTED IP] ' + $ipInfo.query) -ForegroundColor Green } } catch { Write-Host '[STATUS] Connected (IP query timed out)' -ForegroundColor Yellow }"
    
    echo.
    echo Staying connected for %ROTATE_INTERVAL_SECONDS% seconds before next rotation...
    timeout /t %ROTATE_INTERVAL_SECONDS% /nobreak
    echo.
)

echo.
echo [CYCLE COMPLETE] Finished all !TOTAL_SERVERS! servers. Re-shuffling for next round...
echo.
goto ROTATION_LOOP
