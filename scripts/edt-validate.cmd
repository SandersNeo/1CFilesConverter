@rem ----------------------------------------------------------
@rem This Source Code Form is subject to the terms of the
@rem Mozilla Public License, v.2.0. If a copy of the MPL
@rem was not distributed with this file, You can obtain one
@rem at http://mozilla.org/MPL/2.0/.
@rem ----------------------------------------------------------
@rem Codebase: https://github.com/ArKuznetsov/1CFilesConverter/
@rem ----------------------------------------------------------

@ECHO OFF

SETLOCAL ENABLEDELAYEDEXPANSION

IF not defined V8_ENCODING set V8_ENCODING=65001
chcp %V8_ENCODING% > nul

set CONVERT_VERSION=UNKNOWN
IF exist "%~dp0..\VERSION" FOR /F "usebackq tokens=* delims=" %%i IN ("%~dp0..\VERSION") DO set CONVERT_VERSION=%%i
echo 1C files converter v.%CONVERT_VERSION%
echo ======
echo [INFO] Validate 1C configuration, extension, external data processors ^& reports using 1C:EDT ^(using ring tool^)

set ERROR_CODE=0

IF exist "%cd%\.env" IF "%V8_SKIP_ENV%" neq "1" (
    FOR /F "usebackq tokens=*" %%a in ("%cd%\.env") DO (
        FOR /F "tokens=1* delims==" %%b IN ("%%a") DO ( 
            IF not defined %%b set "%%b=%%c"
        )
    )
)

IF not defined V8_VERSION set V8_VERSION=8.3.23.2040
IF not defined V8_TEMP set V8_TEMP=%TEMP%\1c

echo [INFO] Using 1C:Enterprise, version %V8_VERSION%
echo [INFO] Using temporary folder "%V8_TEMP%"

set LOCAL_TEMP=%V8_TEMP%\%~n0
IF "%VALIDATE_PATH%" equ "" (
    set VALIDATE_PATH=%LOCAL_TEMP%\tmp_edt
)
set WS_PATH=%LOCAL_TEMP%\edt_ws

set ARG=%1
IF defined ARG set ARG=%ARG:"=%
IF "%ARG%" neq "" set V8_SRC_PATH=%ARG%
set REPORT_FILE=%2
IF defined REPORT_FILE (
    set REPORT_FILE=%REPORT_FILE:"=%
    set REPORT_FILE_PATH=%~dp2
)
set EXT_NAME=%3
IF defined EXT_NAME set EXT_NAME=%EXT_NAME:"=%

IF not defined V8_SRC_PATH (
    echo [ERROR] Missed parameter 1 - "path to 1C configuration, extension, data processors or reports (binary (*.cf, *.cfe, *.epf, *.erf), 1C:Designer XML format or 1C:EDT format)"
    set ERROR_CODE=1
)
IF not defined REPORT_FILE (
    echo [ERROR] Missed parameter 2 - "path to validation report file"
    set ERROR_CODE=1
)
IF %ERROR_CODE% neq 0 (
    echo ======
    echo [ERROR] Input parameters error. Expected:
    echo     %%1 - path to 1C configuration, extension, data processors or reports ^(binary ^(*.cf, *.cfe, *.epf, *.erf^), 1C:Designer XML format or 1C:EDT project^)
    echo     %%2 - path to validation report file
    echo.
    goto finally
)

echo [INFO] Clear temporary files...
IF exist "%LOCAL_TEMP%" rd /S /Q "%LOCAL_TEMP%"
md "%LOCAL_TEMP%"
IF not exist "%REPORT_FILE_PATH%" md "%REPORT_FILE_PATH%"

echo [INFO] Prepare project for validation...

IF exist "%V8_SRC_PATH%\DT-INF\" (
    set VALIDATE_PATH=%V8_SRC_PATH%
    goto validate
)
md "%VALIDATE_PATH%"
IF /i "%V8_SRC_PATH:~-3%" equ ".cf" (
    call %~dp0conf2edt.cmd "%V8_SRC_PATH%" "%VALIDATE_PATH%"
    goto validate
)
IF /i "%V8_SRC_PATH:~-4%" equ ".cfe" (
    call %~dp0ext2edt.cmd "%V8_SRC_PATH%" "%VALIDATE_PATH%" "%EXT_NAME%"
    goto validate
)
IF exist "%V8_SRC_PATH%\Configuration.xml" (
    FOR /F "delims=" %%t IN ('find /i "<objectBelonging>" "%V8_SRC_PATH%\Configuration.xml"') DO (
        call %~dp0ext2edt.cmd "%V8_SRC_PATH%" "%VALIDATE_PATH%"
        goto validate
    )
    call %~dp0conf2edt.cmd "%V8_SRC_PATH%" "%VALIDATE_PATH%"
    goto validate
)
IF /i "%V8_SRC_PATH:~0,2%" equ "/F" (
    call %~dp0conf2edt.cmd "%V8_SRC_PATH%" "%VALIDATE_PATH%"
    goto validate
)
IF /i "%V8_SRC_PATH:~0,2%" equ "/S" (
    call %~dp0conf2edt.cmd "%V8_SRC_PATH%" "%VALIDATE_PATH%"
    goto validate
)
IF exist "%V8_SRC_PATH%\1cv8.1cd" (
    call %~dp0conf2edt.cmd "%V8_SRC_PATH%" "%VALIDATE_PATH%"
    goto validate
)
FOR /F "delims=" %%f IN ('dir /b /a-d "%V8_SRC_PATH%\*.epf" "%V8_SRC_PATH%\*.erf" "%V8_SRC_PATH%\*.xml" "%V8_SRC_PATH%\ExternalDataProcessors\*.xml" "%V8_SRC_PATH%\ExternalReports\*.xml"') DO (
    call %~dp0dp2edt.cmd "%V8_SRC_PATH%" "%VALIDATE_PATH%"
    goto validate
)

echo [ERROR] Error cheking type of configuration "%BASE_CONFIG%"!
echo Infobase, configuration file ^(*.cf^), configuration extension file ^(*.cfe^), folder contains external data processors ^& reports in binary or XML format, 1C:Designer XML or 1C:EDT project expected.
set ERROR_CODE=1
goto finally

:validate

echo [INFO] Run validation in "%VALIDATE_PATH%"...

md "%WS_PATH%"

IF not defined RING_TOOL (
    FOR /F "usebackq tokens=1 delims=" %%i IN (`where ring`) DO (
        set RING_TOOL="%%i"
    )
)
IF not defined EDTCLI_TOOL (
    IF defined V8_EDT_VERSION (
        IF %V8_EDT_VERSION:~0,4% lss 2024 goto checktool
        set EDT_MASK="%PROGRAMW6432%\1C\1CE\components\1c-edt-%V8_EDT_VERSION%*"
    ) ELSE (
        set EDT_MASK="%PROGRAMW6432%\1C\1CE\components\1c-edt-*"
    )
    FOR /F "tokens=*" %%d IN ('"dir /B /S !EDT_MASK! | findstr /r /i ".*1c-edt-[0-9]*\.[0-9]*\.[0-9].*""') DO (
        IF exist "%%d\1cedtcli.exe" set EDTCLI_TOOL="%%d\1cedtcli.exe"
    )
)

:checktool

IF not defined RING_TOOL IF not defined EDTCLI_TOOL (
    echo [ERROR] Can't find "ring" or "edtcli" tool. Add path to "ring.bat" to "PATH" environment variable, or set "RING_TOOL" variable with full specified path to "ring.bat", or set "EDTCLI_TOOL" variable with full specified path to "1cedtcli.exe".
    set ERROR_CODE=1
    goto finally
)
IF defined EDTCLI_TOOL (
    echo [INFO] Start validate using "edt cli"
    call %EDTCLI_TOOL% -data "%WS_PATH%" -command validate --project-list "%VALIDATE_PATH%" --file "%REPORT_FILE%" 
) ELSE (
    echo [INFO] Start convalidate using "ring"
    call %RING_TOOL% edt@%V8_EDT_VERSION% workspace validate --project-list "%VALIDATE_PATH%" --workspace-location "%WS_PATH%" --file "%REPORT_FILE%"
)
set ERROR_CODE=%ERRORLEVEL%

:finally

echo [INFO] Clear temporary files...
IF exist "%LOCAL_TEMP%" rd /S /Q "%LOCAL_TEMP%"

exit /b %ERROR_CODE%
