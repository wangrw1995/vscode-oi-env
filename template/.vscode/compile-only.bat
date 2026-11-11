@echo off
rem ============================================================
rem  Compile only (no run). Bound to Ctrl+Shift+B.
rem ============================================================
setlocal

if "%~1"=="" (echo [ERROR] no source file specified & exit /b 1)

rem --- Locate g++: prefer w64devkit, then fall back to PATH -----------
set "GXX="
if exist "C:\w64devkit\bin\g++.exe" set "GXX=C:\w64devkit\bin\g++.exe"
if not defined GXX (
  for %%i in (g++.exe) do (
    if not "%%~$PATH:i"=="" set "GXX=%%~$PATH:i"
  )
)
if not defined GXX (
  echo [ERROR] g++ not found.
  exit /b 1
)

echo [BUILD] %~nx1
"%GXX%" -std=c++17 -O2 -Wall -Wl,--stack=268435456 -static "%~1" -o "%~dpn1.exe"
if errorlevel 1 (
  echo.
  echo [BUILD FAILED]
  exit /b 1
)
echo [BUILD OK] %~dpn1.exe
