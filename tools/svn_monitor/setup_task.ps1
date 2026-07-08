# SVN 代码监听器 - Windows 计划任务设置脚本
# 右键选择 "使用 PowerShell 运行" 或管理员身份运行

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonExe = (Get-Command python -ErrorAction Stop).Source
$pythonDir = Split-Path -Parent $pythonExe
$pythonwExe = Join-Path $pythonDir "pythonw.exe"  # 无控制台窗口版

$monitorScript = Join-Path $scriptDir "svn_monitor.py"
$configFile = Join-Path $scriptDir "svn_monitor_config.json"
$taskName = "SVN_Monitor"
$logFile = Join-Path $scriptDir "svn_monitor.log"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Windows 计划任务 - SVN 监听器" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# 检查文件
if (-not (Test-Path $monitorScript)) {
    Write-Host "[错误] 未找到 svn_monitor.py: $monitorScript" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $configFile)) {
    Write-Host "[警告] 未找到配置文件: $configFile" -ForegroundColor Yellow
    Write-Host "        请先编辑 svn_monitor_config.json 配置你的项目列表！" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "[信息] Python 路径:  $pythonwExe" -ForegroundColor Gray
if (-not (Test-Path $pythonwExe)) {
    Write-Host "[警告] 未找到 pythonw.exe，将使用 python.exe（会有短暂控制台闪烁）" -ForegroundColor Yellow
    $pythonwExe = $pythonExe
}
Write-Host "[信息] 脚本路径:    $monitorScript" -ForegroundColor Gray
Write-Host "[信息] 配置文件:    $configFile" -ForegroundColor Gray
Write-Host "[信息] 日志文件:    $logFile" -ForegroundColor Gray
Write-Host ""

# 删除旧任务（如果存在）
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "[操作] 删除旧的计划任务..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# 创建计划任务操作（无控制台窗口运行）
$action = New-ScheduledTaskAction `
    -Execute $pythonwExe `
    -Argument "`"$monitorScript`"" `
    -WorkingDirectory $scriptDir

# 触发器：每 1 小时重复执行
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Hours 1)

# 主体：以当前用户身份运行，仅在登录时运行（确保弹窗可见）
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

# 设置
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -Compatibility Win8

# 注册任务
try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "SVN 代码提交监听器 - 每小时检查一次项目代码变动" `
        -Force

    Write-Host "" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  计划任务创建成功！" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  任务名称: $taskName"
    Write-Host "  执行频率: 每 1 小时"
    Write-Host "  日志文件: $logFile"
    Write-Host ""
    Write-Host "  管理命令:" -ForegroundColor Cyan
    Write-Host "    查看任务: schtasks /query /tn `"$taskName`" /v" -ForegroundColor Gray
    Write-Host "    立即运行: schtasks /run /tn `"$taskName`"" -ForegroundColor Gray
    Write-Host "    禁用任务: schtasks /change /tn `"$taskName`" /disable" -ForegroundColor Gray
    Write-Host "    启用任务: schtasks /change /tn `"$taskName`" /enable" -ForegroundColor Gray
    Write-Host "    删除任务: schtasks /delete /tn `"$taskName`" /f" -ForegroundColor Gray
    Write-Host ""

    # 立即运行一次测试
    $runNow = Read-Host "是否立即手动运行一次测试？(Y/N)"
    if ($runNow -eq "Y" -or $runNow -eq "y") {
        Write-Host "[操作] 正在启动脚本（弹窗测试）..." -ForegroundColor Yellow
        & $pythonwExe $monitorScript 2>&1 | Out-File -FilePath $logFile -Encoding UTF8 -Append
        Write-Host "[完成] 请查看日志: $logFile" -ForegroundColor Green
        if (Test-Path $logFile) {
            Write-Host ""
            Write-Host "--- 最近日志 ---" -ForegroundColor DarkGray
            Get-Content $logFile -Tail 20
        }
    }
}
catch {
    Write-Host "" -ForegroundColor Red
    Write-Host "[错误] 计划任务创建失败: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "可能的解决方案:" -ForegroundColor Yellow
    Write-Host "  1. 右键此脚本 -> 以管理员身份运行" -ForegroundColor Yellow
    Write-Host "  2. 手动创建: 打开 taskschd.msc 手动创建任务" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "按任意键退出..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
