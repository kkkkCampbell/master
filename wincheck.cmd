@echo off
echo.

echo --- COLLECTING DATA ---
echo.

REM Сохраняем текущее приглашение во временный файл
PROMPT > %TEMP%\prompt.tmp

REM Делаем приглашение пустым
PROMPT $

REM Ваши основные команды
powershell.exe -Command "Get-NetIPConfiguration | Where-Object {$_.NetAdapter.Status -eq 'Up'}" | findstr /v "^$"
echo.
nslookup facebook.com
ping ya.ru -n 1

REM Возвращаем исходное приглашение обратно
PROMPT < %TEMP%\prompt.tmp

REM Удаляем временный файл
del %TEMP%\prompt.tmp
echo.

pause
