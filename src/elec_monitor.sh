#!/bin/bash

# ==========================================
# 电费提醒功能脚本
# ==========================================

CONFIG_PATH="$1"

# 检查参数
if [ -z "$CONFIG_PATH" ]; then
    echo "错误: 未传入配置文件路径。"
    exit 1
fi

if [ ! -f "$CONFIG_PATH" ]; then
    echo "错误: 配置文件不存在 ($CONFIG_PATH)"
    exit 1
fi

# 配置读取
get_val() {
    local section=$1
    local key=$2
    local safe_section=$(echo "$section" | sed 's/\./\\./g')

    sed -n "/^\[$safe_section\]/,/^\[/p" "$CONFIG_PATH" \
    | grep "^$key" \
    | head -n 1 \
    | awk -F'=' '{print $2}' \
    | tr -d ' "' \
    | sed 's/#.*//' \
    | tr -d '\r'
}

# 邮件发送函数
send_email() {
    local subject=$1
    local content=$2

    local smtp_host=$(get_val "SMTP" "Host")
    local smtp_port=$(get_val "SMTP" "Port")
    local smtp_user=$(get_val "SMTP" "User")
    local smtp_pass=$(get_val "SMTP" "Password")
    local target_email=$(get_val "Global" "TargetEmail")

    if [ -z "$smtp_user" ] || [ -z "$target_email" ]; then
        echo "错误: 邮箱配置不完整，跳过发送。"
        return
    fi

    echo "正在发送邮件到 $target_email ..."

    local curl_url="smtp://$smtp_host:$smtp_port"
    if [ "$smtp_port" == "465" ]; then
        curl_url="smtps://$smtp_host:$smtp_port"
    fi

    local mail_data="From: \"电费助手\" <$smtp_user>
To: <$target_email>
Subject: $subject
MIME-Version: 1.0
Content-Type: text/html; charset=utf-8

$content"

    echo "$mail_data" | curl --silent --ssl-reqd \
        --url "$curl_url" \
        --user "$smtp_user:$smtp_pass" \
        --mail-from "$smtp_user" \
        --mail-rcpt "$target_email" \
        --upload-file -
}

# 西海岸电费获取
check_xha() {
    local sno=$(get_val "Electricity.xha" "StudentID")
    local token=$(get_val "Electricity.xha" "Token")

    local thresholds_raw=$(get_val "Electricity.xha" "RemindTime" | tr -d '[]' | tr ',' ' ')

    local light_limit=$(echo $thresholds_raw | awk '{print $1}')
    local ac_limit=$(echo $thresholds_raw | awk '{print $2}')

    # 如果解析失败默认设为0
    light_limit=${light_limit:-0}
    ac_limit=${ac_limit:-0}

    if [ -z "$sno" ] || [ -z "$token" ]; then
        echo "错误: 学号或Token未配置，请修改 config.toml"
        return
    fi

    echo "查询西海岸校区... (学号: $sno)"

    local response=$(curl -s -X POST "http://10.128.13.25/hydxcas/getCadByNo" \
        -H "Token: $token" \
        -H "Content-Type: application/json" \
        -d "{\"sno\": \"$sno\"}")

    local errcode=$(echo "$response" | jq -r '.errcode')

    if [ "$errcode" != "0" ]; then
        echo "API 请求失败: $(echo "$response" | jq -r '.errmsg')"
        return
    fi

    # 解析数据
    local light_val=$(echo "$response" | jq -r '.value | fromjson | .eqptData[] | select(.categoryEnergyName == "照明与插座") | .buyElec')
    local ac_val=$(echo "$response" | jq -r '.value | fromjson | .eqptData[] | select(.categoryEnergyName == "空调末端") | .buyElec')

    light_val=${light_val:-0}
    ac_val=${ac_val:-0}

    echo "当前电量 -> 照明: $light_val, 空调: $ac_val"
    echo "警戒阈值 -> 照明: $light_limit, 空调: $ac_limit"

    local need_alert=0
    local msg="<h3>电费余额不足提醒</h3><ul>"

    # 使用 bc 进行比较，增加 2>/dev/null 屏蔽非数字报错
    if (( $(echo "$light_val < $light_limit" | bc -l 2>/dev/null) )); then
        need_alert=1
        msg="${msg}<li><strong>照明:</strong> ${light_val} 度 (低于 ${light_limit})</li>"
    fi

    if (( $(echo "$ac_val < $ac_limit" | bc -l 2>/dev/null) )); then
        need_alert=1
        msg="${msg}<li><strong>空调:</strong> ${ac_val} 度 (低于 ${ac_limit})</li>"
    fi

    msg="${msg}</ul><p>请及时充值！</p>"

    if [ $need_alert -eq 1 ]; then
        send_email "【紧急】宿舍电费余额不足" "$msg"
    else
        echo "电量充足，无需提醒。"
    fi
}

# 主函数部分

ENABLED=$(get_val "Electricity" "Enabled")
if [ "$ENABLED" != "true" ]; then
    echo "电费监控模块未启用。"
    exit 0
fi

CAMPUS=$(get_val "Electricity" "Campus")

case "$CAMPUS" in
    "xha")
        check_xha
        ;;
    *)
        echo "未知的校区配置: $CAMPUS"
        ;;
esac