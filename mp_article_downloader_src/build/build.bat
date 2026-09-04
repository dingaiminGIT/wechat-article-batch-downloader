@echo off
setlocal enabledelayedexpansion

set OUTPUT_DIR=%~dp0
if "%OUTPUT_DIR%" neq "" set OUTPUT_DIR=%OUTPUT_DIR:~0,-1%

if "%1" equ "" goto usage

goto %1

:windows
echo Building Windows x86_64...
set CGO_ENABLED=0
set GOOS=windows
set GOARCH=amd64
go build -trimpath -ldflags="-s -w" -o "%OUTPUT_DIR%\mp_article_batch_downloader_windows_x86_64.exe"
if exist mp_article_batch_downloader.exe (
    del mp_article_batch_downloader.exe
)
move /Y mp_article_batch_downloader_windows_x86_64.exe mp_article_batch_downloader.exe >nul 2>&1
echo Done: %OUTPUT_DIR%\mp_article_batch_downloader.exe
exit /b 0

:windows-sunnynet
echo Building Windows SunnyNet version...
echo This requires Docker on Windows:
echo   docker run --rm -v "%%cd%%:/workspace" -w /workspace golang:1.20 bash -c "...
echo Please run the Docker command manually from README.md
exit /b 1

:usage
echo Usage: build.bat [target]
echo   windows         - Windows x86_64
echo   windows-sunnynet - Windows SunnyNet ^(requires Docker^)
echo   all             - Build all targets
exit /b 1

:all
echo Building Windows...
call :windows
echo.
echo All done!
exit /b 0