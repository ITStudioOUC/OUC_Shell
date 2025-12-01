#!/bin/bash

# ==========================================
# 网费提醒功能脚本
# ==========================================

CONFIG_PATH="$1"

# 基础检查
if [ -z "$CONFIG_PATH" ] || [ ! -f "$CONFIG_PATH" ]; then
    echo "错误: 配置文件未找到 ($CONFIG_PATH)"
    exit 1
fi

# 读取配置
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
    if [ "$smtp_port" == "465" ]; then curl_url="smtps://$smtp_host:$smtp_port"; fi

    local mail_data="From: \"校园助手\" <$smtp_user>
To: <$target_email>
Subject: $subject
MIME-Version: 1.0
Content-Type: text/html; charset=utf-8

$content"

    echo "$mail_data" | curl --silent --ssl-reqd --url "$curl_url" --user "$smtp_user:$smtp_pass" --mail-from "$smtp_user" --mail-rcpt "$target_email" --upload-file -
}

# 兼容 macOS (BSD date) 与 Linux (GNU date) 计算距离下个月1号的天数
days_until_next_month() {
    local now_ts next_month_ts
    now_ts=$(date +%s)

    if date -v1d -v+1m +%s >/dev/null 2>&1; then
        # macOS/BSD date
        next_month_ts=$(date -v+1m -v1d +%s)
    else
        # GNU date
        next_month_ts=$(date -d "$(date +%Y-%m-01) +1 month" +%s)
    fi

    echo $(( (next_month_ts - now_ts) / 86400 ))
}

# 西海岸网费检查
check_xha_net() {
    local sno=$(get_val "Internet.xha" "StudentID")

    # 解析 RemindTime = [10, 5] -> money_limit=10, day_limit=5
    local config_raw=$(get_val "Internet.xha" "RemindTime" | tr -d '[]' | tr ',' ' ')
    local money_limit=$(echo $config_raw | awk '{print $1}')
    local day_limit=$(echo $config_raw | awk '{print $2}')

    # 默认值保护
    money_limit=${money_limit:-10}
    day_limit=${day_limit:--1}

    if [ -z "$sno" ]; then
        echo "错误: 未配置学号 (StudentID)"
        return
    fi

    echo "查询西海岸校区网费... (学号: $sno)"

    # 1. 发送请求
    local url="https://xha.ouc.edu.cn:802/eportal/portal/page/loadUserInfo?callback=dr1002&lang=zh-CN&program_index=ctshNw1713845951&page_index=V5fmKw1713845966&user_account=${sno}&wlan_user_ip=0.0.0.0&wlan_user_mac=000000000000&jsVersion=4.1&v=3015&lang=zh"

    local response=$(curl -k -s --http1.1 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "$url")

    # 2. 解析 JSONP
    # 返回格式: dr1002({ ... }); 需要去掉 dr1002( 和 );
    local json_body=$(echo "$response" | sed -E 's/^[^(]*\(//;s/\)[^)]*$//')

    # 检查 parsed JSON 是否有效
    local code=$(echo "$json_body" | jq -r '.code')
    if [ "$code" != "1" ]; then
        echo "API 请求失败或未登录: $(echo "$json_body" | jq -r '.msg')"
        return
    fi

    # 3. 提取余额
    # 原始值可能是 "0 元" 或 "12.50 元"
    local balance_str=$(echo "$json_body" | jq -r '.user_info.balance')
    # 只保留数字和小数点
    local balance_num=$(echo "$balance_str" | sed 's/[^0-9.]//g')

    # 提取已用流量用于展示
    local flow_str=$(echo "$json_body" | jq -r '.user_info.use_flow')

    balance_num=${balance_num:-0}
    echo "当前余额: ${balance_num} 元, 已用流量: ${flow_str}"

    # 4. 判断是否需要提醒
    local need_alert=0
    local reason=""

    # 只有当余额低于阈值才考虑发信
    if (( $(echo "$balance_num < $money_limit" | bc -l 2>/dev/null) )); then

        # 4.1 如果 day_limit 是 -1，不看日期，直接发
        if [ "$day_limit" == "-1" ]; then
            need_alert=1
            reason="余额低于 ${money_limit} 元"
        else
            # 4.2 如果配置了日期限制，检查是否接近月底
            # 计算距离下个月1号还有几天
            local diff_days
            diff_days=$(days_until_next_month)

            echo "距离月底结算还有: ${diff_days} 天 (配置阈值: ${day_limit} 天)"

            if [ "$diff_days" -le "$day_limit" ]; then
                need_alert=1
                reason="临近月底且余额低于 ${money_limit} 元"
            else
                echo "余额虽然不足，但未到提醒日期 (当前 ${diff_days} > 阈值 ${day_limit})，跳过。"
            fi
        fi
    fi

    # 5. 发送通知
    if [ $need_alert -eq 1 ]; then
        local msg="<h3>校园网费余额预警</h3>
        <ul>
            <li><strong>学号:</strong> ${sno}</li>
            <li><strong>当前余额:</strong> <span style='color:red'>${balance_num} 元</span></li>
            <li><strong>已用流量:</strong> ${flow_str}</li>
            <li><strong>警告原因:</strong> ${reason}</li>
        </ul>
        <p>请确认是否需要充值以避免下月断网。</p>"

        send_email "【提醒】校园网费余额不足 (${balance_num}元)" "$msg"
    fi
}

# 主函数
ENABLED=$(get_val "Internet" "Enabled")
if [ "$ENABLED" != "true" ]; then
    echo "网费监控模块未启用。"
    exit 0
fi

CAMPUS=$(get_val "Internet" "Campus")

case "$CAMPUS" in
    "xha")
        check_xha_net
        ;;
    *)
        echo "未知的校区配置: $CAMPUS"
        ;;
esac
