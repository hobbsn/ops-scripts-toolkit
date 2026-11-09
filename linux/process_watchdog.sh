#!/bin/bash
# Process Watchdog - Monitor and restart critical processes
# Author: System Admin
# Usage: ./process_watchdog.sh -c process_name -c process2 [-e email]

VERSION="1.0"
CONFIG_FILE="/etc/watchdog.conf"
LOG_FILE="/var/log/watchdog.log"
CHECK_INTERVAL=30
ALERT_EMAIL=""
MAX_RESTARTS=5
RESTART_WINDOW=3600
SELF_NAME="${0##*/}"
declare -a PROCESSES
declare -A START_CMDS
declare -A RESTART_COUNT
declare -A RESTART_WINDOW_START

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
        echo "$msg" | mail -s "Watchdog Alert: $msg" "$ALERT_EMAIL"
    fi
}

# 支持 "进程名|启动命令" 形式，启动命令存入 START_CMDS 供重启使用
add_process() {
    local entry="$1"
    local name="${entry%%|*}"
    local start_cmd=""

    if [[ "$entry" == *"|"* ]]; then
        start_cmd="${entry#*|}"
    fi

    PROCESSES+=("$name")
    [ -n "$start_cmd" ] && START_CMDS["$name"]="$start_cmd"
}

# 获取目标进程 PID 列表，排除守护脚本自身/父进程，防止把守护自己当成目标进程
get_process_pids() {
    local proc="$1"
    local pids pid cmdline

    # 先精确匹配进程名，避免 "java" 匹配到 "javac"；失败再回退到子串匹配
    pids=$(pgrep -x "$proc" 2>/dev/null)
    if [ -z "$pids" ]; then
        pids=$(pgrep -f "$proc" 2>/dev/null)
    fi
    if [ -z "$pids" ]; then
        pids=$(pidof "$proc" 2>/dev/null)
    fi

    for pid in $pids; do
        [ "$pid" = "$$" ] && continue
        [ "$pid" = "$PPID" ] && continue
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
        [ -z "$cmdline" ] && cmdline=$(ps -p "$pid" -o args= 2>/dev/null)
        case "$cmdline" in
            *"$SELF_NAME"*) continue ;;
        esac
        echo "$pid"
    done
}

is_process_running() {
    local proc="$1"
    # 多种检测方式，提高兼容性
    if [ -n "$(get_process_pids "$proc")" ]; then
        return 0
    fi
    systemctl is-active --quiet "$proc" 2>/dev/null && return 0
    return 1
}

restart_process() {
    local proc="$1"
    local start_cmd="${START_CMDS[$proc]:-}"
    local pid
    log "Attempting to restart: $proc"
    
    # 方式1: systemctl
    if systemctl list-unit-files 2>/dev/null | grep -q "$proc"; then
        systemctl restart "$proc" 2>/dev/null
        if [ $? -eq 0 ]; then
            log "Successfully restarted via systemctl: $proc"
            return 0
        fi
    fi
    
    # 方式2: service命令
    if command -v service >/dev/null 2>&1; then
        service "$proc" restart 2>/dev/null
        if [ $? -eq 0 ]; then
            log "Successfully restarted via service: $proc"
            return 0
        fi
    fi
    
    # 方式3: 使用配置的启动命令直接拉起
    if [ -z "$start_cmd" ]; then
        alert "无法重启：缺少启动命令（请配置 进程名|启动命令）: $proc"
        return 1
    fi

    # 只杀目标进程的 PID（排除守护自身），避免 pkill -f 按正则误杀
    for pid in $(get_process_pids "$proc"); do
        kill "$pid" 2>/dev/null
    done
    sleep 1
    nohup bash -c "$start_cmd" > /dev/null 2>&1 &
    sleep 2
    
    if is_process_running "$proc"; then
        log "Successfully started: $proc"
        return 0
    else
        alert "Failed to restart: $proc"
        return 1
    fi
}

# 窗口内重启次数计数，超过 MAX_RESTARTS 告警退出，避免进程崩溃后无限拉起
check_restart_limit() {
    local proc="$1"
    local now=$(date +%s)
    local count=${RESTART_COUNT[$proc]:-0}
    local window_start=${RESTART_WINDOW_START[$proc]:-0}

    # 窗口过期则重新计数
    if [ $((now - window_start)) -ge "$RESTART_WINDOW" ]; then
        count=0
        window_start=$now
    fi
    count=$((count + 1))
    RESTART_COUNT[$proc]=$count
    RESTART_WINDOW_START[$proc]=$window_start

    if [ "$count" -gt "$MAX_RESTARTS" ]; then
        alert "[LIMIT] 重启次数超限：$proc 在 ${RESTART_WINDOW}s 内重启 ${count} 次（上限 $MAX_RESTARTS），守护退出"
        return 1
    fi
    return 0
}

monitor_processes() {
    local proc
    for proc in "${PROCESSES[@]}"; do
        if is_process_running "$proc"; then
            log "[OK] $proc is running"
        else
            alert "[DOWN] $proc is NOT running!"
            if ! check_restart_limit "$proc"; then
                exit 1
            fi
            restart_process "$proc"
        fi
    done
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            if [[ "$line" =~ ^process= ]]; then
                add_process "${line#*=}"
            elif [[ "$line" =~ ^interval= ]]; then
                CHECK_INTERVAL="${line#*=}"
            elif [[ "$line" =~ ^email= ]]; then
                ALERT_EMAIL="${line#*=}"
            elif [[ "$line" =~ ^max_restarts= ]]; then
                MAX_RESTARTS="${line#*=}"
            fi
        done < "$CONFIG_FILE"
    fi
}

show_status() {
    echo "=========================================="
    echo "       Process Watchdog v$VERSION"
    echo "=========================================="
    echo "Check Interval: ${CHECK_INTERVAL}s"
    [ -n "$ALERT_EMAIL" ] && echo "Alert Email: $ALERT_EMAIL"
    echo "Monitored Processes:"
    for proc in "${PROCESSES[@]}"; do
        if is_process_running "$proc"; then
            echo -e "  ${GREEN}[RUNNING]${NC} $proc"
        else
            echo -e "  ${RED}[DOWN]${NC} $proc"
        fi
    done
    echo "=========================================="
}

while getopts "c:i:e:lsh" opt; do
    case $opt in
        c) add_process "$OPTARG" ;;
        i) CHECK_INTERVAL="$OPTARG" ;;
        e) ALERT_EMAIL="$OPTARG" ;;
        l) load_config ;;
        s) show_status; exit 0 ;;
        h) echo "Usage: $0 [-c process[|start_cmd]] [-i interval] [-e email] [-l load_config] [-s status]"; exit 0 ;;
    esac
done

if [ ${#PROCESSES[@]} -eq 0 ]; then
    echo "No processes to monitor. Use -c or -l to load config."
    exit 1
fi

log "Watchdog started - monitoring: ${PROCESSES[*]}"
trap "log 'Watchdog stopped'; exit" SIGINT SIGTERM

while true; do
    monitor_processes
    sleep "$CHECK_INTERVAL"
done