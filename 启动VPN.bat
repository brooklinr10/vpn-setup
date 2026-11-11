@echo off
cd /d "%~dp0"

rem ===== 1. Stop any existing sing-box =====
taskkill /f /im sing-box.exe >nul 2>&1
ping -n 2 127.0.0.1 >nul

rem ===== 2. Start sing-box in a minimized window =====
start "VPN-Hysteria2" /min "%CD%\sing-box.exe" run -c "%CD%\hy2-client.json"

rem ===== 3. Wait a moment for sing-box to start listening =====
ping -n 3 127.0.0.1 >nul

rem ===== 4. Set Windows system proxy =====
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "127.0.0.1:1080" /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyOverride /t REG_SZ /d "<local>" /f >nul

echo.
echo  VPN started.  System proxy = 127.0.0.1:1080
echo  (A minimized window shows sing-box is running. Close it to disconnect.)
echo.
ping -n 4 127.0.0.1 >nul