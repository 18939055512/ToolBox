@echo off
chcp 65001 >nul
echo ============================================
echo   SVN 代码监听器 - 安装
echo ============================================
echo.

:: 检查 Python
python --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 未找到 Python，请先安装 Python 3
    pause
    exit /b 1
)
echo [OK] Python 已安装: 
python --version

:: 获取脚本所在目录
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: 创建 Python 虚拟环境（可选，脚本无外部依赖）
echo [信息] 本脚本无外部 Python 依赖，使用系统 Python 即可

:: 测试运行一次
echo.
echo ============================================
echo   测试运行（将检查 SVN 项目）
echo ============================================
echo [信息] 请先编辑 svn_monitor_config.json 配置你的项目列表
echo         然后按任意键测试运行，或关闭窗口稍后手动运行
pause >nul

echo.
python "%SCRIPT_DIR%\svn_monitor.py"
echo.

echo ============================================
echo   安装 Windows 定时任务
echo ============================================
echo 现在将创建 Windows 计划任务，每小时自动检查一次
echo.

set /p SETUP="是否创建定时任务？(Y/N): "
if /I "%SETUP%"=="Y" (
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\setup_task.ps1"
) else (
    echo 已跳过。稍后可手动运行 setup_task.ps1 来创建定时任务。
)

echo.
echo 安装完成！按任意键退出...
pause >nul
