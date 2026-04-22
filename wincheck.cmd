@echo off
setlocal

chcp 1251 > nul
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
::echo --- PING RESULTS ---
::echo.
chcp 866 > nul
setlocal enabledelayedexpansion

:: Используем [ ] как якорь для первой строки и = для статистики
:: Исключаем TTL, чтобы убрать строки ответов
ping ya.ru -n 10 | findstr /r /c:"\[" /c:"=" /c:"%%" | findstr /v /i "TTL"

echo.

echo ========== ПАРАМЕТРЫ СИСТЕМНОГО ПРОКСИ ==========
chcp 1251 > nul
echo.

set "PROXY_ACTIVE="

:: 1. Проверяем пользовательский прокси (Internet Settings)
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2>nul | find "0x1" >nul
if not errorlevel 1 (
    set "PROXY_ACTIVE=1"
    echo "[Включен пользовательский прокси]"
    for /f "tokens=2,*" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer 2^>nul') do echo   Сервер: %%b
    for /f "tokens=2,*" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyOverride 2^>nul') do echo   Исключения: %%b
    echo.
)

:: 2. Проверяем автообнаружение (WPAD)
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v AutoDetect 2>nul | find "0x1" >nul
if not errorlevel 1 (
    set "PROXY_ACTIVE=1"
    echo "[Включено автоматическое обнаружение прокси (WPAD)]"
    echo.
)

:: 3. Проверяем URL PAC-файла
for /f "tokens=2,*" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v AutoConfigURL 2^>nul') do (
    set "PROXY_ACTIVE=1"
    echo [Используется PAC-скрипт]
    echo   "URL: %%b"
    echo.
)

:: 4. WinHTTP прокси (исправлено)
netsh winhttp show proxy | find "прямой доступ" >nul
if errorlevel 1 (
    set "PROXY_ACTIVE=1"
    echo "[Настроен WinHTTP прокси]"
    for /f "tokens=*" %%a in ('netsh winhttp show proxy ^| findstr /v /c:"прямой доступ" ^| findstr /v "^$"') do echo "  %%a"
    echo.
)


:: 5. Если ничего не активно
if not defined PROXY_ACTIVE (
    echo "Активных прокси нет."
    echo.
)

echo ========== КОНЕЦ ==========

pause
