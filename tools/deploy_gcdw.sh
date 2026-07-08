#!/bin/bash
#
# 一键部署脚本 - gcdw 服务更新部署
# 使用方法: sh deploy_gcdw.sh [选项]
#
# 选项:
#   --skip-backup    跳过备份步骤
#   --skip-confirm   跳过确认提示，直接执行
#   --no-log         部署完成后不跟踪日志
#   --jar-path       指定新jar包路径，默认 /tmp/gcdw.jar
#
# 流程: 备份 → 替换 → 重启 → 验证 → 日志
#

set -e

# ===== 配置区 =====
APP_DIR="/opt/app/your-app"               # 应用目录（修改为你的实际路径）
JAR_NAME="your-app.jar"                   # jar 文件名（修改为你的实际 jar 名）
SOURCE_JAR="/tmp/your-app.jar"            # 新 jar 包来源路径
MANAGE_SCRIPT="manage_jar.sh"           # 管理脚本名称
LOG_FILE="log.log"                      # 日志文件名
LOG_LINES=500                           # 日志跟踪行数
# ===== 配置区结束 =====

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 选项解析
SKIP_BACKUP=false
SKIP_CONFIRM=false
NO_LOG=false
CUSTOM_JAR_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-backup)   SKIP_BACKUP=true; shift ;;
        --skip-confirm)  SKIP_CONFIRM=true; shift ;;
        --no-log)        NO_LOG=true; shift ;;
        --jar-path)      CUSTOM_JAR_PATH="$2"; shift 2 ;;
        -h|--help)
            echo "使用方法: sh deploy_gcdw.sh [选项]"
            echo "选项:"
            echo "  --skip-backup    跳过备份步骤"
            echo "  --skip-confirm   跳过确认提示，直接执行"
            echo "  --no-log         部署完成后不跟踪日志"
            echo "  --jar-path PATH  指定新jar包路径，默认 /tmp/gcdw.jar"
            exit 0
            ;;
        *) echo "未知选项: $1"; exit 1 ;;
    esac
done

# 如果指定了自定义 jar 路径，使用它
if [[ -n "$CUSTOM_JAR_PATH" ]]; then
    SOURCE_JAR="$CUSTOM_JAR_PATH"
fi

# 辅助函数
timestamp() { date +%Y-%m-%d; }
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }


# ===== 步骤 0: 前置检查 =====
log_step "0. 前置检查"

# 检查新 jar 包是否存在
if [[ ! -f "$SOURCE_JAR" ]]; then
    log_error "新 jar 包不存在: $SOURCE_JAR"
    log_error "请先将新 jar 包上传到 $SOURCE_JAR"
    exit 1
fi
log_info "新 jar 包已就绪: $SOURCE_JAR ($(du -h "$SOURCE_JAR" | cut -f1))"

# 进入应用目录
cd "$APP_DIR" || { log_error "无法进入目录: $APP_DIR"; exit 1; }
log_info "当前目录: $(pwd)"

# 检查当前 jar 包
if [[ ! -f "$JAR_NAME" ]]; then
    log_warn "当前目录下不存在 $JAR_NAME，将直接部署新包"
fi

# ===== 步骤 1: 确认 =====
if [[ "$SKIP_CONFIRM" == false ]]; then
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}  即将执行 gcdw 服务部署${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo "  应用目录:  $APP_DIR"
    echo "  新 jar 包: $SOURCE_JAR"
    echo "  备份名称:  ${JAR_NAME}-$(timestamp)"
    echo "  管理脚本:  $MANAGE_SCRIPT"
    echo ""
    read -p "确认执行部署? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "部署已取消"
        exit 0
    fi
fi

echo ""
log_step "===== 开始部署 ====="
echo ""

# ===== 步骤 2: 备份当前 jar =====
if [[ "$SKIP_BACKUP" == false && -f "$JAR_NAME" ]]; then
    log_step "2. 备份当前 jar 包"
    BACKUP_NAME="${JAR_NAME}-$(timestamp)"
    cp "$JAR_NAME" "$BACKUP_NAME"
    log_info "已备份: $BACKUP_NAME ($(du -h "$BACKUP_NAME" | cut -f1))"
else
    if [[ "$SKIP_BACKUP" == true ]]; then
        log_warn "2. 跳过备份 (--skip-backup)"
    else
        log_warn "2. 无需备份 (当前无 $JAR_NAME)"
    fi
fi

# ===== 步骤 3: 替换 jar 包 =====
log_step "3. 替换 jar 包"
cp "$SOURCE_JAR" "./$JAR_NAME"
log_info "已替换: $JAR_NAME ($(du -h "$JAR_NAME" | cut -f1))"

# 清理 /tmp 下的源文件（可选）
# rm -f "$SOURCE_JAR"
# log_info "已清理源文件: $SOURCE_JAR"

# ===== 步骤 4: 重启服务 =====
log_step "4. 重启服务"
sudo sh "$MANAGE_SCRIPT" restart
log_info "服务重启完成"

# ===== 步骤 5: 验证服务 =====
log_step "5. 验证服务状态"
sleep 2

# 检查进程是否存在
if pgrep -f "$JAR_NAME" > /dev/null 2>&1; then
    PID=$(pgrep -f "$JAR_NAME")
    log_info "服务运行中, PID: $PID"
else
    log_error "服务未检测到进程，请检查日志!"
    # 显示最后 50 行日志辅助排查
    if [[ -f "$LOG_FILE" ]]; then
        echo ""
        echo -e "${RED}--- 最近日志 (最后50行) ---${NC}"
        tail -50 "$LOG_FILE"
    fi
    exit 1
fi

# ===== 步骤 6: 跟踪日志 =====
if [[ "$NO_LOG" == false && -f "$LOG_FILE" ]]; then
    echo ""
    log_step "6. 跟踪日志 (Ctrl+C 退出日志跟踪)"
    echo ""
    tail -${LOG_LINES}f "$LOG_FILE"
else
    log_info "部署完成! (--no-log 已跳过日志跟踪)"
fi

echo ""
log_info "===== 部署完成 ====="
