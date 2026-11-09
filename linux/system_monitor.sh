#!/bin/bash
# System Monitor Script - Real-time monitoring with alerts
# Author: System Admin
# Usage: ./system_monitor.sh [-i interval] [-a alert]

VERSION="1.0"
INTERVAL=5
ALERT_THRESHOLD=80
ALERT_EMAIL=""
LOG_FILE="/var/log/system_monitor.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

alert() {
    local msg="$1"
    log "[ALERT] $msg"
    if [ -n "$ALERT_EMAIL" ]; then
        echo "$msg" | mail -s "System Alert: $msg" "$ALERT_EMAIL"
    fi
}

get_cpu_usage() {
    # 两次采样/proc/stat取差值计算实时使用率（idle含iowait），避免取到开机以来均值
    local stat1 stat2
    stat1=$(awk '/^cpu / {t=0; for(i=2;i<=9;i++) t+=$i; print t, $5+$6}' /proc/stat)
    sleep 1
    stat2=$(awk '/^cpu / {t=0; for(i=2;i<=9;i++) t+=$i; print t, $5+$6}' /proc/stat)
    awk -v t1="${stat1%% *}" -v i1="${stat1##* }" -v t2="${stat2%% *}" -v i2="${stat2##* }" \
        'BEGIN {total=t2-t1; idle=i2-i1; if (total > 0) printf "%d\n", (total-idle)*100/total; else print 0}'
}

get_mem_usage() {
    # 兼容不同free输出格式
    free | awk '/Mem:/ {print int($3/$2 * 100)}'
}

get_disk_usage() {
    df -P / | awk '/\// {print $5}' | tr -d '%'
}

get_swap_usage() {
    # 检查swap是否存在，避免除零错误
    local swap_total=$(free | awk '/Swap:/ {print $2}')
    if [ -z "$swap_total" ] || [ "$swap_total" -eq 0 ]; then
        echo 0
    else
        free | awk '/Swap:/ {print int($3/$2 * 100)}'
    fi
}

get_load_avg() {
    cat /proc/loadavg | awk '{print $1, $2, $3}'
}

get_top_processes() {
    ps aux --sort=-%cpu | head -6 | tail -5
}

check_alerts() {
    local cpu=$(get_cpu_usage)
    local mem=$(get_mem_usage)
    local disk=$(get_disk_usage)
    
    # 确保变量有默认值，避免比较错误
    cpu=${cpu:-0}
    mem=${mem:-0}
    disk=${disk:-0}
    
    [ "$cpu" -gt "$ALERT_THRESHOLD" ] && alert "High CPU usage: ${cpu}%"
    [ "$mem" -gt "$ALERT_THRESHOLD" ] && alert "High Memory usage: ${mem}%"
    [ "$disk" -gt "$ALERT_THRESHOLD" ] && alert "High Disk usage: ${disk}%"
}

show_dashboard() {
    clear
    echo "=================================================="
    echo "       System Monitor v$VERSION"
    echo "=================================================="
    echo "Interval: ${INTERVAL}s | Alert: ${ALERT_THRESHOLD}%"
    echo "=================================================="
    echo ""
    
    local cpu=$(get_cpu_usage)
    local mem=$(get_mem_usage)
    local disk=$(get_disk_usage)
    local swap=$(get_swap_usage)
    local load=$(get_load_avg)
    
    # 默认值保护
    cpu=${cpu:-0}
    mem=${mem:-0}
    disk=${disk:-0}
    swap=${swap:-0}
    
    echo "--- CPU Usage ---"
    [ "$cpu" -ge "$ALERT_THRESHOLD" ] && echo -e "CPU: ${RED}${cpu}%${NC}" || echo -e "CPU: ${GREEN}${cpu}%${NC}"
    
    echo ""
    echo "--- Memory Usage ---"
    [ "$mem" -ge "$ALERT_THRESHOLD" ] && echo -e "RAM: ${RED}${mem}%${NC}" || echo -e "RAM: ${GREEN}${mem}%${NC}"
    [ "$swap" -ge "$ALERT_THRESHOLD" ] && echo -e "Swap: ${RED}${swap}%${NC}" || echo -e "Swap: ${GREEN}${swap}%${NC}"
    
    echo ""
    echo "--- Disk Usage (/) ---"
    [ "$disk" -ge "$ALERT_THRESHOLD" ] && echo -e "Disk: ${RED}${disk}%${NC}" || echo -e "Disk: ${GREEN}${disk}%${NC}"
    
    echo ""
    echo "--- Load Average ---"
    echo "1min: $(echo $load | awk '{print $1}') | 5min: $(echo $load | awk '{print $2}') | 15min: $(echo $load | awk '{print $3}')"
    
    echo ""
    echo "--- Top 5 CPU Processes ---"
    get_top_processes
    
    echo ""
    echo "=================================================="
    echo "Press Ctrl+C to exit"
}

while getopts "i:a:h" opt; do
    case $opt in
        i) INTERVAL="$OPTARG" ;;
        a) ALERT_THRESHOLD="$OPTARG" ;;
        h) echo "Usage: $0 [-i interval] [-a alert_threshold]"; exit 0 ;;
    esac
done

# 校验-i/-a参数必须为正整数，避免sleep失败导致循环空转
case "$INTERVAL" in
    ''|*[!0-9]*|0) echo "Error: interval must be a positive integer (got: $INTERVAL)" >&2; exit 1 ;;
esac
case "$ALERT_THRESHOLD" in
    ''|*[!0-9]*|0) echo "Error: alert threshold must be a positive integer (got: $ALERT_THRESHOLD)" >&2; exit 1 ;;
esac

echo "Starting System Monitor..."
log "System Monitor started - interval: ${INTERVAL}s, threshold: ${ALERT_THRESHOLD}%"

trap "echo 'Exiting...'; log 'System Monitor stopped'; exit" SIGINT SIGTERM

while true; do
    show_dashboard
    check_alerts
    sleep "$INTERVAL"
done