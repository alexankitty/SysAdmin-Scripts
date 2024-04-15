@echo off

::Get todays date and split in to day,month and year vars
for /f "tokens=2 delims==" %%G in ('wmic os get localdatetime /value') do set currdate=%%G
set currday=%currdate:~6,2%
set currmonth=%currdate:~4,2%
set curryear=%currdate:~0,4%

:: Get users password expirey date and split in to day,month and year vars
for /f "tokens=3,4 delims= " %%f in ('net user %username% /domain ^| find /I "Password expires"') do set expire=%%f %%g
set "expireDate=%expire: =" & set "dummy=%"
for /f "tokens=1,2,3 delims=/" %%f in ('echo %expireDate%') do set expmonth=%%f& set expday=%%g& set expyear=%%h
IF "%expmonth%" == "Never" GOTO :EOF

:: Work out the time between todays date and the expiry dat
call :diffdays "%curryear%-%currmonth%-%currday%" "%expyear%-%expmonth%-%expday%"
set daydiff=%diff_day_of_year%

:: Show 1 day / x day's
if /i "%daydiff%" EQU "0" goto :DAYDIFF
if /i "%daydiff%" EQU "1" goto :1DAYDIFF
if /i "%daydiff%" GEQ "2" goto :DAYDIFF

:1DAYDIFF
:: Show formatted data to user in a readable format
set dayText="%daydiff% day"
goto :Display

:DAYDIFF
:: Show formatted data to user in a readable format
set dayText="%daydiff% days"
goto :Display

:Display
if /i "%daydiff%" GEQ exit
powershell -executionpolicy bypass -Command .\ShowMessageBox.ps1 "'Your password will expire in %dayText%. Please press CTRL-ALT-DELETE (Or in AWS click View > Send CTRL-ALT-DELETE) and then click Change a Password.'" "'Password Expiration'" "'Warning'"


:diffdays
set start_date=%~1
set end_date=%~2
FOR /F "tokens=*" %%g IN ('powershell ^(New-TimeSpan -Start "%start_date%" -End "%end_date%" ^)^.Days') do (SET diff_day_of_year=%%g)
powershell ^(New-TimeSpan -Start "%start_date%" -End "%end_date%" ^)^.Days
exit /B
