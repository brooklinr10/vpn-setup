@echo off

rem ===== 1. Stop sing-box =====
taskkill /f /im sing-box.exe >nul 2>&1

rem ===== 2. Turn off Windows system proxy =====
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >nul

echo.
echo  VPN stopped.  System proxy turned off.
echo.
ping -n 3 127.0.0.1 >nul