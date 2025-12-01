#!/bin/bash

# ==========================================
# 主控制脚本 (Main Runner)
# 功能：依赖管理、配置生成、任务调度、日志整合
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
    if command -v apt-get &> /dev/null; then install_cmd="apt-get update && apt-get install -y";
    elif command -v yum &> /dev/null; then install_cmd="yum install -y";
    elif command -v dnf &> /dev/null; then install_cmd="dnf install -y";
    elif command -v apk &> /dev/null; then install_cmd="apk add --no-cache";
    else log "无法自动安装，请手动安装: ${missing_packages[*]}"; exit 1; fi

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

# --- 4. 配置文件生成与检查 ---
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

# --- 功能模块: 电费提醒 ---
[Electricity]
Enabled = true
Campus = "xha"
# xha = 西海岸

[Electricity.xha]
StudentID = "20230000"
Token = "YOUR_TOKEN_HERE"
# [照明警戒值, 空调警戒值]
RemindTime = [30.0, 30.0]
EOF
        log "配置文件已生成: $CONFIG_FILE"
        log "检测到第一次加载此脚本，将自动结束本脚本，请前往编辑配置文件"
        exit 0
    else
        log "加载配置文件: $CONFIG_FILE"
    fi
}

# 主函数

log "服务启动..."

check_and_install_dependencies
check_and_create_config

# 任务间隔 (秒)
INTERVAL_ELEC=1800  # 半小时
LAST_RUN_ELEC=0

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

    # 其他任务(预留)
    # TODO

    sleep 60
done