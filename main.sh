#!/bin/bash

# ==========================================
# 主控脚本
# ==========================================

# --- 1. 路径定义 ---
BASE_DIR=$(cd $(dirname $0); pwd)
SRC_DIR="$BASE_DIR/src"
CONFIG_FILE="$BASE_DIR/config.toml"
LOG_FILE="$BASE_DIR/service.log"

# 日志
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

trap "log '服务停止'; exit" SIGTERM SIGINT

# 依赖检查和安装
check_and_install_dependencies() {
    local dependencies=("curl" "jq" "bc")
    local missing_packages=()

    for pkg in "${dependencies[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            missing_packages+=("$pkg")
        fi
    done

    if [ ${#missing_packages[@]} -eq 0 ]; then
        log "环境检查通过: 依赖已就绪。"
        return 0
    fi

    log "检测到缺失依赖: ${missing_packages[*]}，尝试自动安装..."

    local install_cmd=""
    if command -v apt-get &> /dev/null; then
        install_cmd="apt-get update && apt-get install -y"
    elif command -v yum &> /dev/null; then
        install_cmd="yum install -y"
    elif command -v dnf &> /dev/null; then
        install_cmd="dnf install -y"
    elif command -v apk &> /dev/null; then
        install_cmd="apk add --no-cache"
    else
        log "无法自动安装，请手动安装: ${missing_packages[*]}"
        exit 1
    fi

    if [ "$EUID" -ne 0 ] && command -v sudo &> /dev/null; then
        install_cmd="sudo $install_cmd"
    fi

    # 这里也将安装日志通过管道传递给 log 函数，保持日志格式统一
    eval "$install_cmd ${missing_packages[*]}" 2>&1 | while IFS= read -r line; do
        log "[依赖安装] $line"
    done

    # 二次检查
    for pkg in "${missing_packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            log "依赖 $pkg 安装失败，请检查网络或源。"
            exit 1
        fi
    done
    log "依赖安装完成。"
}

# 配置文件生成与检查
check_and_create_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "配置文件不存在，正在生成默认配置..."
        cat > "$CONFIG_FILE" << EOF
# ==========================================
# OUCShell配置文件
# ==========================================

[Global]
# 接收通知的邮箱
TargetEmail = "your_email@example.com"

[SMTP]
# 发件人邮箱服务器配置
Host = "smtp.qq.com"
Port = "465"
User = "your_smtp_email@qq.com"
Password = "your_smtp_auth_code"

# 电费提醒模块
[Electricity]
Enabled = true # 是否启用本模块
Campus = "xha" # 校区选择
# xha = 西海岸

[Electricity.xha]
StudentID = "XXX" # 学号
Token = "9f7c6e76979c4cb9dd3828f8cc44a5ef" # MD5(Sd1234) 居然加密这么简单吗?
# [照明警戒值, 空调警戒值]
RemindTime = [30.0, 30.0]

# 网费提醒模块
[Internet]
Enabled = true # 是否启用本模块
Campus = "xha" # 校区选择
# xha = 西海岸

[Internet.xha]
StudentID = "XXX" # 学号
# [最低余额, 触发天数]
# 触发天数: 离下个月1号还有几天时开始检测。
# e.g.
# 填 -1 表示忽略日期，只要余额低就提醒。
# 填 5 表示只有余额低 且 离月底少于5天时才提醒。
RemindTime = [10, -1]
EOF
        log "配置文件已生成: $CONFIG_FILE"
        log "检测到第一次运行，脚本将自动退出，请编辑配置文件后重新启动"
        exit 0
    else
        log "加载配置文件: $CONFIG_FILE"
    fi
}

# 主函数

log "服务启动..."

check_and_install_dependencies
check_and_create_config

# 电费提醒任务间隔 (秒)
INTERVAL_ELEC=7200  # 2小时
LAST_RUN_ELEC=0

# 网费提醒任务间隔 (秒)
INTERVAL_NET=43200  # 半天
LAST_RUN_NET=0

log "进入循环调度模式..."

while true; do
    CURRENT_TIME=$(date +%s)

    # 电费监控

    # 计算时间差
    TIME_DIFF=$((CURRENT_TIME - LAST_RUN_ELEC))

    if [ $TIME_DIFF -ge $INTERVAL_ELEC ]; then
        SCRIPT_PATH="$SRC_DIR/elec_monitor.sh"

        if [ -f "$SCRIPT_PATH" ]; then
            chmod +x "$SCRIPT_PATH"
            log "调度任务: 电费监控..."

            /bin/bash "$SCRIPT_PATH" "$CONFIG_FILE" 2>&1 | while IFS= read -r line; do
                log "[elec_monitor] $line"
            done

            log "任务结束: 电费监控"
        else
            log "警告: 找不到脚本 $SCRIPT_PATH"
        fi

        LAST_RUN_ELEC=$(date +%s)
    fi

    # 网费监控

    # 计算时间差
    TIME_DIFF=$((CURRENT_TIME - LAST_RUN_NET))

    if [ $TIME_DIFF -ge $INTERVAL_NET ]; then
        SCRIPT_PATH="$SRC_DIR/internet_monitor.sh"

        if [ -f "$SCRIPT_PATH" ]; then
            chmod +x "$SCRIPT_PATH"
            log "调度任务: 网费监控..."

            /bin/bash "$SCRIPT_PATH" "$CONFIG_FILE" 2>&1 | while IFS= read -r line; do
                log "[net_monitor] $line"
            done

            log "任务结束: 网费监控"
        else
            log "警告: 找不到脚本 $SCRIPT_PATH"
        fi

        LAST_RUN_NET=$(date +%s)
    fi

    # 其他任务(预留)
    # TODO

    sleep 60
done