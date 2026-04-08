@echo off
::chcp 1251 > nul
cls
echo.
echo --- COLLECTING DATA ---
echo.

REM ====== Parameters ======
set NS_HOST=facebook.com
set PING_HOST=ya.ru
set PING_COUNT=10
REM =========================

REM ----- PART 1: Network config + nslookup (with empty line after DNSServer) -----
( powershell -Command "Get-NetIPConfiguration | Where-Object {$_.NetAdapter.Status -eq 'Up'}; nslookup %NS_HOST% 2>&1" | findstr /v "^$" ) | powershell -Command "$input | ForEach-Object { $_; if ($_ -match 'DNSServer') { '' } }"

echo.
echo --- PING RESULTS ---

setlocal enabledelayedexpansion

:: Используем [ ] как якорь для первой строки и = для статистики
:: Исключаем TTL, чтобы убрать строки ответов
ping ya.ru -n 10 | findstr /r /c:"\[" /c:"=" /c:"%%" | findstr /v /i "TTL"

echo.

pause
