@echo off
title Liquid Glass Messaging Server
cd /d "%~dp0Server"
echo ========================================================
echo    Liquid Glass High-Performance Messaging Server
echo ========================================================
echo.
echo Configuration is loaded from the private Server/.env file.
echo.
echo Starting Node.js server...
echo ========================================================
call npm run start:local
pause
