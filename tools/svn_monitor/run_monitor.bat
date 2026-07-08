@echo off
cd /d "%~dp0"
"C:\Users\Rh\.workbuddy\binaries\python\versions\3.13.12\pythonw.exe" "%~dp0svn_monitor.py" >> "%~dp0svn_monitor.log" 2>&1
