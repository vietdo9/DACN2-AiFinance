@echo off
title FinWise - Start All Services
color 0A

echo =======================================================
echo            FINWISE - KHOI DONG HE THONG
echo =======================================================
echo.

set ROOT=%~dp0

echo [1/3] Khoi dong AI Service (Port 8000)...
start "AI Service :8000" cmd /k "cd /d "%ROOT%ai_service" && .\venv\Scripts\python.exe app.py"

timeout /t 2 /nobreak >nul

echo [2/3] Khoi dong Backend Gateway (Port 5000)...
start "Backend Gateway :5000" cmd /k "cd /d "%ROOT%backend" && npm start"

timeout /t 2 /nobreak >nul

echo [3/3] Khoi dong Flutter Web App (Chrome)...
start "Flutter Web Client" cmd /k "cd /d "%ROOT%finwise_mobile" && flutter run -d chrome"

echo.
echo =======================================================
echo [+] Da khoi dong ca 3 phan he thanh cong!
echo - AI Service:   http://localhost:8000/docs
echo - Backend API:  http://localhost:5000
echo - Flutter Web:  Tu dong mo tren Google Chrome
echo =======================================================
echo.
pause
