@echo off
title FinWise - Khoi Dong He Thong
color 0A

echo =======================================================
echo            FINWISE - KHOI DONG HE THONG
echo =======================================================
echo.

set ROOT=%~dp0
set ADB="C:\Users\admin\AppData\Local\Android\Sdk\platform-tools\adb.exe"

echo [1/2] Khoi dong AI Microservice (Port 8000)...
start "AI Service :8000" cmd /k "cd /d "%ROOT%ai_service" && .\venv\Scripts\python.exe app.py"

timeout /t 2 /nobreak >nul

echo [2/2] Khoi dong Backend Gateway (Port 5000)...
start "Backend Gateway :5000" cmd /k "cd /d "%ROOT%backend" && npm start"

timeout /t 2 /nobreak >nul

echo.
echo =======================================================
echo  [+] AI Service & Backend Gateway da chay thanh cong!
echo =======================================================
echo.
echo Ban muon mo giao dien FinWise theo cach nao?
echo.
echo   [1] Mo tren Google Chrome (Web - Nhan Enter de chon)
echo   [2] Chay len Dien thoai Android (Cam cap USB)
echo   [3] Xuat file cai dat Android (.apk cho dien thoai)
echo   [4] Chi chay Server (Khong mo Client)
echo.

set /p CHOICE="Nhap lua chon (1-4) [Mac dinh: 1]: "
if "%CHOICE%"=="" set CHOICE=1

if "%CHOICE%"=="1" goto CHROME
if "%CHOICE%"=="2" goto PHONE
if "%CHOICE%"=="3" goto BUILD_APK
if "%CHOICE%"=="4" goto SERVER_ONLY
goto CHROME

:CHROME
echo.
echo [*] Dang khoi chay tren Google Chrome...
start "Flutter Web Client" cmd /k "cd /d "%ROOT%finwise_mobile" && flutter run -d chrome"
goto END

:PHONE
echo.
echo [*] Kiem tra ket noi dien thoai Android qua USB...
if exist %ADB% (
    %ADB% devices
    %ADB% reverse tcp:5000 tcp:5000 >nul 2>&1
    %ADB% reverse tcp:8000 tcp:8000 >nul 2>&1
    echo [+] Da tao chuyen tiep cong: Dien thoai ket noi truc tiep duoc Backend!
)
echo [*] Dang cai dat va chay ung dung len dien thoai...
start "Flutter Android Client" cmd /k "cd /d "%ROOT%finwise_mobile" && flutter run"
goto END

:BUILD_APK
echo.
echo [*] Dang dong goi file APK Release cho dien thoai...
cd /d "%ROOT%finwise_mobile"
call flutter build apk --release
echo.
echo =======================================================
echo [+] File APK da duoc tao thanh cong tai:
echo %ROOT%finwise_mobile\build\app\outputs\flutter-apk\app-release.apk
echo =======================================================
echo.
pause
goto END

:SERVER_ONLY
echo.
echo [*] He thong Server dang hoat dong:
echo - AI Service:   http://localhost:8000/docs
echo - Backend API:  http://localhost:5000
echo =======================================================
pause
goto END

:END
