@echo off
::chcp 1251 > nul
cls
echo.
echo --- COLLECTING DATA ---
echo.

REM ====== Џ…ђ…Њ…ЌЌ›… „‹џ •Ћ‘’Ћ‚ ======
set NS_HOST=facebook.com
set PING_HOST=ya.ru
REM ===================================

PROMPT > %TEMP%\prompt.tmp
PROMPT $

powershell -Command "$net=((Get-NetIPConfiguration|Where-Object{$_.NetAdapter.Status -eq 'Up'}|Out-String).Trim() -split '\r\n')|Where-Object{$_ -ne ''}; $nsl=((nslookup $env:NS_HOST 2>&1|Out-String).Trim() -split '\r\n')|Where-Object{$_ -ne ''}; $ping=((ping $env:PING_HOST -n 1 2>&1|Out-String).Trim() -split '\r\n')|Where-Object{$_ -ne ''}; $out=$net+''+$nsl+''+$ping; $res=@(); foreach($line in $out){$res+=$line; if($line -match 'DNSServer'){$res+=''}}; $res -join \"`r`n\""

PROMPT < %TEMP%\prompt.tmp
del %TEMP%\prompt.tmp

pause
