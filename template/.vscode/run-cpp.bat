@echo off
rem ============================================================
rem  Compile and run the given C/C++ source with MinGW-w64 g++.
rem  Usage: run-cpp.bat "C:\path\to\main.cpp"
rem  Bound to F5 through .vscode/tasks.json
rem ============================================================
setlocal

if "%~1"=="" (echo [ERROR] no source file specified & exit /b 1)

set "SRC=%~1"
set "EXE=%~dpn1.exe"

rem --- 1. Locate g++ -------------------------------------------------
rem  Prefer a known-good w64devkit install, then fall back to PATH.
rem  Edit the first line below if your toolchain lives elsewhere.
set "GXX="
if exist "C:\w64devkit\bin\g++.exe" set "GXX=C:\w64devkit\bin\g++.exe"
if not defined GXX (
  for %%i in (g++.exe) do (
    if not "%%~$PATH:i"=="" set "GXX=%%~$PATH:i"
  )
)
if not defined GXX (
  echo [ERROR] g++ not found.
  echo         Install MinGW-w64, or hard-code GXX in this file.
  exit /b 1
)

rem --- 2. Compile ----------------------------------------------------
rem  -O2                          match the judge's optimisation level
rem  -Wl,--stack=268435456        256 MB stack (deep recursion will not blow up)
rem  -static                      standalone exe, copies to any machine
echo [BUILD] %~nx1
"%GXX%" -std=c++17 -O2 -Wall -Wl,--stack=268435456 -static "%SRC%" -o "%EXE%"
if errorlevel 1 (
  echo.
  echo [BUILD FAILED] fix the errors above, then press F5 again.
  exit /b 1
)

rem --- 3. Run --------------------------------------------------------
echo [RUN] %~nx1
echo ========================================
"%EXE%"
echo ========================================
echo [DONE] exit code %ERRORLEVEL%
