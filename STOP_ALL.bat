@echo off
title FinWise - Stop All Services
color 0C

echo =======================================================
echo             DUNG TOAN BO HE THONG FINWISE
echo =======================================================
echo.

echo [*] Giai phong Port 8000 (AI Microservice)...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr :8000') do (
    taskkill /f /pid %%a >nul 2>&1
)

echo [*] Giai phong Port 5000 (Backend Node.js)...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr :5000') do (
    taskkill /f /pid %%a >nul 2>&1
)

echo [*] Tat tien trinh Flutter Dart...
taskkill /f /im dart.exe >nul 2>&1

echo.
echo =======================================================
echo  [+] Da giai phong cac cong (ports) thanh cong!
echo =======================================================
echo.
pause
