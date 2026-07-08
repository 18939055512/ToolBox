#!/bin/bash
#
# 一键部署脚本 - 通用版
# 使用方法: sh deploy.sh <服务名> [选项]
#
# 新项目只需在下方 SERVICES 配置区加一行即可
#
# 选项:
#   --skip-backup    跳过备份步骤
#   --skip-confirm   跳过确认提示，直接执行
#   --no-log         部署完成后不跟踪日志
#   --jar-path PATH  指定新jar包路径（覆盖默认的 /tmp/<jar名>）
#
# 示例:
#   sh deploy.sh gcdw                       # 部署 gcdw
#   sh deploy.sh gcdw --skip-confirm        # 无确认直接部署
#   sh deploy.sh gcdw --jar-path /tmp/x.jar # 指定jar包
#

set -e

# ===== 服务配置区（加新项目只需在下面加一行） =====
# 格式: 服务名=应用目录|jar文件名|管理脚本|日志文件
# 管理脚本和日志文件默认都是 manage_jar.sh / log.log，可覆盖
SERVICES=(
    "gcdw=/data/wzb/gcdw|gcdw.jar|manage_jar.sh|log.log"
    # 加新项目示例（取消下面注释并修改即可）:
    # "java=/data/wzb/java|java.jar|manage_jar.sh|log.log"
    # "safe=/data/wzb/safe|safe.jar|manage_jar.sh|log.log"
)
LOG_LINES=500
# ===== 配置区结束 =====

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# 辅助函数
timestamp() { date +%Y-%m-%d; }
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# 查找服务配置
get_config() {
    local svc="$1"
    for entry in "${SERVICES[@]}"; do
        local name="${entry%%=*}"
        if [[ "$name" == "$svc" ]]; then
            echo "${entry#*=}"
            return 0
        fi
    done
    return 1
}

# 解析配置字段
parse_field() {
    echo "$1" | cut -d'|' -f"$2"
}

# ===== 参数解析 =====
SERVICE_NAME=""
SKIP_BACKUP=false; SKIP_CONFIRM=false; NO_LOG=false; CUSTOM_JAR_PATH=""

if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
    SERVICE_NAME="$1"; shift
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-backup)   SKIP_BACKUP=true; shift ;;
        --skip-confirm)  SKIP_CONFIRM=true; shift ;;
        --no-log)        NO_LOG=true; shift ;;
        --jar-path)      CUSTOM_JAR_PATH="$2"; shift 2 ;;
        -h|--help)
            echo "使用方法: sh deploy.sh <服务名> [选项]"
            echo ""
            echo "已配置的服务:"
            for entry in "${SERVICES[@]}"; do echo "  ${entry%%=*}"; done
            echo ""
            echo "选项:"
            echo "  --skip-backup    跳过备份"
            echo "  --skip-confirm   跳过确认"
            echo "  --no-log         不跟踪日志"
            echo "  --jar-path PATH  指定jar包路径"
            exit 0 ;;
        *) echo "未知选项: $1"; exit 1 ;;
    esac
done

# 校验服务名
if [[ -z "$SERVICE_NAME" ]]; then
    log_error "请指定服务名!"
    echo "已配置的服务:"; for entry in "${SERVICES[@]}"; do echo "  ${entry%%=*}"; done
    exit 1
fi

CONFIG=$(get_config "$SERVICE_NAME") || { log_error "未配置的服务: $SERVICE_NAME"; exit 1; }

APP_DIR=$(parse_field "$CONFIG" 1)
JAR_NAME=$(parse_field "$CONFIG" 2)
MANAGE_SCRIPT=$(parse_field "$CONFIG" 3)
LOG_FILE=$(parse_field "$CONFIG" 4)

SOURCE_JAR="${CUSTOM_JAR_PATH:-/tmp/${JAR_NAME}}"

# ===== 步骤 0: 前置检查 =====
log_step "0. 前置检查 - 服务: $SERVICE_NAME"

if [[ ! -f "$SOURCE_JAR" ]]; then
    log_error "新jar包不存在: $SOURCE_JAR"
    log_error "请先将新jar包上传到 $SOURCE_JAR"
    exit 1
fi
log_info "新jar包: $SOURCE_JAR ($(du -h "$SOURCE_JAR" | cut -f1))"

cd "$APP_DIR" || { log_error "无法进入: $APP_DIR"; exit 1; }
log_info "目录: $(pwd)"

[[ ! -f "$JAR_NAME" ]] && log_warn "当前无 $JAR_NAME，将直接部署新包"
[[ ! -f "$MANAGE_SCRIPT" ]] && { log_error "管理脚本不存在: $MANAGE_SCRIPT"; exit 1; }

# ===== 步骤 1: 确认 =====
if [[ "$SKIP_CONFIRM" == false ]]; then
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}  部署服务: $SERVICE_NAME${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo "  目录:  $APP_DIR"
    echo "  新包:  $SOURCE_JAR"
    echo "  备份:  ${JAR_NAME}-$(timestamp)"
    echo ""
    read -p "确认部署? [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { log_info "已取消"; exit 0; }
fi

echo ""; log_step "===== 开始部署: $SERVICE_NAME ====="; echo ""

# ===== 步骤 2: 备份 =====
if [[ "$SKIP_BACKUP" == false && -f "$JAR_NAME" ]]; then
    log_step "2. 备份"
    BACKUP_NAME="${JAR_NAME}-$(timestamp)"
    cp "$JAR_NAME" "$BACKUP_NAME"
    log_info "已备份: $BACKUP_NAME ($(du -h "$BACKUP_NAME" | cut -f1))"
else
    [[ "$SKIP_BACKUP" == true ]] && log_warn "2. 跳过备份" || log_warn "2. 无需备份"
fi

# ===== 步骤 3: 替换 =====
log_step "3. 替换jar包"
cp "$SOURCE_JAR" "./$JAR_NAME"
log_info "已替换: $JAR_NAME ($(du -h "$JAR_NAME" | cut -f1))"

# ===== 步骤 4: 重启 =====
log_step "4. 重启服务"
sudo sh "$MANAGE_SCRIPT" restart
log_info "重启完成"

# ===== 步骤 5: 验证 =====
log_step "5. 验证服务"
sleep 2

if pgrep -f "$JAR_NAME" > /dev/null 2>&1; then
    PID=$(pgrep -f "$JAR_NAME")
    log_info "服务运行中, PID: $PID"
else
    log_error "进程未检测到，请检查日志!"
    [[ -f "$LOG_FILE" ]] && tail -50 "$LOG_FILE"
    exit 1
fi

# ===== 步骤 6: 日志 =====
if [[ "$NO_LOG" == false && -f "$LOG_FILE" ]]; then
    echo ""; log_step "6. 跟踪日志 (Ctrl+C 退出)"; echo ""
    tail -${LOG_LINES}f "$LOG_FILE"
else
    log_info "部署完成!"
fi

echo ""; log_info "===== 部署完成: $SERVICE_NAME ====="
