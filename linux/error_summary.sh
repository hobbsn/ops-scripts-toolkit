#!/bin/bash
# Error Summary Script - Aggregate errors from multiple log files and generate alerts
# Author: System Admin
# Usage: ./error_summary.sh [-t time] [-e email] [-a alert]

VERSION="1.0"
TIME_PERIOD="24h"
ALERT_EMAIL=""
ALERT_THRESHOLD=10
SHOW_SUMMARY=0
LOG_DIRS="/var/log"
REPORT_FILE="/var/log/error_summary_report.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

declare -A ERROR_SUMMARY
# generate_summary 通过全局变量传回错误总数，return 只表示成功/失败
TOTAL_ERRORS=0
# 记录已提示过"时间过滤回退"的文件，避免重复输出
declare -A TIME_FILTER_NOTED

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$REPORT_FILE"
}

get_time_filter() {
    local period="$1"
    case "$period" in
        1h) echo "-1 hour" ;;
        6h) echo "-6 hours" ;;
        12h) echo "-12 hours" ;;
        24h|1d) echo "-1 day" ;;
        7d|1w) echo "-7 days" ;;
        30d|1m) echo "-30 days" ;;
        *) echo "-1 day" ;;
    esac
}

# 将时间窗参数（如 "-1 day"）换算为截止时刻的 epoch 秒
get_cutoff_epoch() {
    local num unit
    num="${1#-}"
    unit="${num#* }"
    num="${num%% *}"
    case "$unit" in
        hour|hours) echo $(( $(date +%s) - num * 3600 )) ;;
        week|weeks) echo $(( $(date +%s) - num * 604800 )) ;;
        day|days)   echo $(( $(date +%s) - num * 86400 )) ;;
        *)          echo $(( $(date +%s) - 86400 )) ;;
    esac
}

# 按时间窗过滤日志行：支持 syslog（Mon DD HH:MM:SS）与 ISO（YYYY-MM-DD）时间戳，
# 无法解析时间戳的文件回退为全文件并在输出中注明
filter_log_by_time() {
    local log_file="$1"
    local cutoff_epoch="$2"

    if ! head -5 "$log_file" | grep -qE '^[A-Z][a-z]{2} [ 0-9][0-9] [0-9]{2}:[0-9]{2}:[0-9]{2}|^[0-9]{4}[-/][0-9]{2}[-/][0-9]{2}'; then
        if [ -z "${TIME_FILTER_NOTED[$log_file]:-}" ]; then
            TIME_FILTER_NOTED[$log_file]=1
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $log_file: cannot parse timestamps, time filter skipped (scanning full file)" | tee -a "$REPORT_FILE" >&2
        fi
        cat "$log_file"
        return
    fi

    awk -v cutoff="$cutoff_epoch" -v now="$(date +%s)" -v year="$(date +%Y)" '
    BEGIN {
        split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", mn, " ")
        for (i = 1; i <= 12; i++) month[mn[i]] = i
    }
    {
        ep = ""
        if ($0 ~ /^[A-Z][a-z][a-z] [ 0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]/) {
            mo = month[substr($0, 1, 3)]
            dy = substr($0, 5, 2) + 0
            ep = mktime(year " " mo " " dy " " (substr($0, 8, 2) + 0) " " (substr($0, 11, 2) + 0) " " (substr($0, 14, 2) + 0))
            # 时间戳晚于当前时间说明跨了年，按上一年解析
            if (ep > now + 86400)
                ep = mktime((year - 1) " " mo " " dy " " (substr($0, 8, 2) + 0) " " (substr($0, 11, 2) + 0) " " (substr($0, 14, 2) + 0))
        } else if ($0 ~ /^[0-9][0-9][0-9][0-9][-\/][0-9][0-9][-\/][0-9][0-9]/) {
            ep = mktime(substr($0, 1, 4) " " substr($0, 6, 2) " " substr($0, 9, 2) " 00 00 00")
            if (substr($0, 11, 1) == " " || substr($0, 11, 1) == "T") {
                ep = mktime(substr($0, 1, 4) " " substr($0, 6, 2) " " substr($0, 9, 2) " " (substr($0, 12, 2) + 0) " " (substr($0, 15, 2) + 0) " " (substr($0, 18, 2) + 0))
            } else {
                # 仅到日期粒度时按整天处理，宁多勿漏
                ep += 86399
            }
        }
        # 时间戳解析失败的行保留，宁多勿漏
        if (ep == "" || ep <= 0 || ep >= cutoff) print
    }' "$log_file"
}

scan_auth_logs() {
    local time_filter="$1"
    local cutoff_epoch=$(get_cutoff_epoch "$time_filter")
    log "Scanning auth logs (last $TIME_PERIOD)..."
    
    local log_files=""
    [ -f /var/log/auth.log ] && log_files="$log_files /var/log/auth.log"
    [ -f /var/log/secure ] && log_files="$log_files /var/log/secure"
    
    if [ -z "$log_files" ]; then
        log "[INFO] No auth logs found"
        return
    fi
    
    local failed_logins=0
    local invalid_users=0
    local root_logins=0
    
    for log_file in $log_files; do
        local count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -c "Failed password" 2>/dev/null)
        failed_logins=$((failed_logins + ${count:-0}))
        
        count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -c "Invalid user" 2>/dev/null)
        invalid_users=$((invalid_users + ${count:-0}))
        
        count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -c "session opened for user root" 2>/dev/null)
        root_logins=$((root_logins + ${count:-0}))
    done
    
    ERROR_SUMMARY["Auth_Failed_Logins"]=$failed_logins
    ERROR_SUMMARY["Auth_Invalid_Users"]=$invalid_users
    ERROR_SUMMARY["Auth_Root_Logins"]=$root_logins
}

scan_system_logs() {
    local time_filter="$1"
    local cutoff_epoch=$(get_cutoff_epoch "$time_filter")
    log "Scanning system logs (last $TIME_PERIOD)..."
    
    local log_files=""
    [ -f /var/log/syslog ] && log_files="$log_files /var/log/syslog"
    [ -f /var/log/messages ] && log_files="$log_files /var/log/messages"
    
    if [ -z "$log_files" ]; then
        log "[INFO] No system logs found"
        return
    fi
    
    local errors=0
    local warnings=0
    local critical=0
    local oom=0
    
    for log_file in $log_files; do
        local count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -ci "error" 2>/dev/null)
        errors=$((errors + ${count:-0}))
        
        count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -ci "warn" 2>/dev/null)
        warnings=$((warnings + ${count:-0}))
        
        count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -ci "critical\|fatal\|panic" 2>/dev/null)
        critical=$((critical + ${count:-0}))
        
        count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -c "oom-killer\|Out of memory" 2>/dev/null)
        oom=$((oom + ${count:-0}))
    done
    
    ERROR_SUMMARY["System_Errors"]=$errors
    ERROR_SUMMARY["System_Warnings"]=$warnings
    ERROR_SUMMARY["System_Critical"]=$critical
    ERROR_SUMMARY["System_OOM"]=$oom
}

scan_kernel_logs() {
    local time_filter="$1"
    local cutoff_epoch=$(get_cutoff_epoch "$time_filter")
    log "Scanning kernel logs (last $TIME_PERIOD)..."
    
    local log_files=""
    [ -f /var/log/kern.log ] && log_files="$log_files /var/log/kern.log"
    [ -f /var/log/messages ] && log_files="$log_files /var/log/messages"
    
    if [ -z "$log_files" ]; then
        log "[INFO] No kernel logs found"
        return
    fi
    
    local segfaults=0
    local io_errors=0
    local hw_errors=0
    
    for log_file in $log_files; do
        local count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -c "segfault" 2>/dev/null)
        segfaults=$((segfaults + ${count:-0}))
        
        count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -ci "I/O error\|disk error" 2>/dev/null)
        io_errors=$((io_errors + ${count:-0}))
        
        count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -ci "hardware error\|machine check" 2>/dev/null)
        hw_errors=$((hw_errors + ${count:-0}))
    done
    
    ERROR_SUMMARY["Kernel_Segfaults"]=$segfaults
    ERROR_SUMMARY["Kernel_IO_Errors"]=$io_errors
    ERROR_SUMMARY["Kernel_HW_Errors"]=$hw_errors
}

scan_nginx_logs() {
    local time_filter="$1"
    local cutoff_epoch=$(get_cutoff_epoch "$time_filter")
    log "Scanning nginx logs (last $TIME_PERIOD)..."
    
    local log_files=""
    [ -f /var/log/nginx/error.log ] && log_files="$log_files /var/log/nginx/error.log"
    [ -f /var/log/nginx/access.log ] && log_files="$log_files /var/log/nginx/access.log"
    
    if [ -z "$log_files" ]; then
        log "[INFO] No nginx logs found"
        return
    fi
    
    local errors_4xx=0
    local errors_5xx=0
    
    for log_file in $log_files; do
        local count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -cE " 4[0-9]{2} " 2>/dev/null)
        errors_4xx=$((errors_4xx + ${count:-0}))
        
        count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -cE " 5[0-9]{2} " 2>/dev/null)
        errors_5xx=$((errors_5xx + ${count:-0}))
    done
    
    ERROR_SUMMARY["Nginx_4xx"]=$errors_4xx
    ERROR_SUMMARY["Nginx_5xx"]=$errors_5xx
}

scan_apache_logs() {
    local time_filter="$1"
    local cutoff_epoch=$(get_cutoff_epoch "$time_filter")
    log "Scanning apache logs (last $TIME_PERIOD)..."
    
    local log_files=""
    [ -f /var/log/apache2/error.log ] && log_files="$log_files /var/log/apache2/error.log"
    [ -f /var/log/httpd/error_log ] && log_files="$log_files /var/log/httpd/error_log"
    
    if [ -z "$log_files" ]; then
        log "[INFO] No apache logs found"
        return
    fi
    
    local errors=0
    for log_file in $log_files; do
        local count=$(filter_log_by_time "$log_file" "$cutoff_epoch" | grep -ci "error" 2>/dev/null)
        errors=$((errors + ${count:-0}))
    done
    
    ERROR_SUMMARY["Apache_Errors"]=$errors
}

scan_docker_logs() {
    local time_filter="$1"
    log "Scanning docker logs (last $TIME_PERIOD)..."
    
    if ! command -v docker >/dev/null 2>&1; then
        log "[INFO] Docker not installed"
        return
    fi
    
    local container_errors=0
    for container in $(docker ps -q 2>/dev/null); do
        local count=$(docker logs "$container" 2>&1 | grep -ci "error\|fatal")
        container_errors=$((container_errors + ${count:-0}))
    done
    
    ERROR_SUMMARY["Docker_Errors"]=$container_errors
}

scan_journal() {
    local time_filter="$1"
    log "Scanning systemd journal (last $TIME_PERIOD)..."
    
    if ! command -v journalctl >/dev/null 2>&1; then
        log "[INFO] journalctl not available"
        return
    fi
    
    # 时间窗映射要与 TIME_PERIOD 一致，6h/12h/7d/30d 不能一律缩成 1 小时/1 天
    local priority_filter=""
    case "$time_filter" in
        "-1 hour")   priority_filter="--since=-1hour" ;;
        "-6 hours")  priority_filter="--since=-6hour" ;;
        "-12 hours") priority_filter="--since=-12hour" ;;
        "-1 day")    priority_filter="--since=-1day" ;;
        "-7 days")   priority_filter="--since=-7day" ;;
        "-30 days")  priority_filter="--since=-30day" ;;
        *)           priority_filter="--since=-1day" ;;
    esac
    
    # 使用wc -l而不是grep -c ""，避免空匹配问题
    local emergency=$(journalctl $priority_filter -p 0 --no-pager 2>/dev/null | wc -l)
    local alert=$(journalctl $priority_filter -p 1 --no-pager 2>/dev/null | wc -l)
    local critical=$(journalctl $priority_filter -p 2 --no-pager 2>/dev/null | wc -l)
    local errors=$(journalctl $priority_filter -p 3 --no-pager 2>/dev/null | wc -l)
    
    ERROR_SUMMARY["Journal_Emergency"]=$emergency
    ERROR_SUMMARY["Journal_Alert"]=$alert
    ERROR_SUMMARY["Journal_Critical"]=$critical
    ERROR_SUMMARY["Journal_Errors"]=$errors
}

generate_summary() {
    echo ""
    echo "==========================================" | tee -a "$REPORT_FILE"
    echo "       ERROR SUMMARY REPORT" | tee -a "$REPORT_FILE"
    echo "==========================================" | tee -a "$REPORT_FILE"
    echo "Hostname: $(hostname)" | tee -a "$REPORT_FILE"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$REPORT_FILE"
    echo "Time period: Last $TIME_PERIOD" | tee -a "$REPORT_FILE"
    echo "==========================================" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    
    local total_errors=0
    
    echo "--- Auth Logs ---" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Auth_Failed_Logins"]:-0}" -gt 0 ] && echo -e "${YELLOW}Failed logins:${NC} ${ERROR_SUMMARY["Auth_Failed_Logins"]}" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Auth_Invalid_Users"]:-0}" -gt 0 ] && echo -e "${RED}Invalid users:${NC} ${ERROR_SUMMARY["Auth_Invalid_Users"]}" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Auth_Root_Logins"]:-0}" -gt 0 ] && echo -e "${BLUE}Root logins:${NC} ${ERROR_SUMMARY["Auth_Root_Logins"]}" | tee -a "$REPORT_FILE"
    total_errors=$((total_errors + ${ERROR_SUMMARY["Auth_Failed_Logins"]:-0} + ${ERROR_SUMMARY["Auth_Invalid_Users"]:-0}))
    echo "" | tee -a "$REPORT_FILE"
    
    echo "--- System Logs ---" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["System_Errors"]:-0}" -gt 0 ] && echo -e "${RED}Errors:${NC} ${ERROR_SUMMARY["System_Errors"]}" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["System_Warnings"]:-0}" -gt 0 ] && echo -e "${YELLOW}Warnings:${NC} ${ERROR_SUMMARY["System_Warnings"]}" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["System_Critical"]:-0}" -gt 0 ] && echo -e "${RED}Critical:${NC} ${ERROR_SUMMARY["System_Critical"]}" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["System_OOM"]:-0}" -gt 0 ] && echo -e "${RED}OOM kills:${NC} ${ERROR_SUMMARY["System_OOM"]}" | tee -a "$REPORT_FILE"
    total_errors=$((total_errors + ${ERROR_SUMMARY["System_Errors"]:-0} + ${ERROR_SUMMARY["System_Critical"]:-0} + ${ERROR_SUMMARY["System_OOM"]:-0}))
    echo "" | tee -a "$REPORT_FILE"
    
    echo "--- Kernel Logs ---" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Kernel_Segfaults"]:-0}" -gt 0 ] && echo -e "${RED}Segfaults:${NC} ${ERROR_SUMMARY["Kernel_Segfaults"]}" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Kernel_IO_Errors"]:-0}" -gt 0 ] && echo -e "${RED}I/O Errors:${NC} ${ERROR_SUMMARY["Kernel_IO_Errors"]}" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Kernel_HW_Errors"]:-0}" -gt 0 ] && echo -e "${YELLOW}HW Errors:${NC} ${ERROR_SUMMARY["Kernel_HW_Errors"]}" | tee -a "$REPORT_FILE"
    total_errors=$((total_errors + ${ERROR_SUMMARY["Kernel_Segfaults"]:-0} + ${ERROR_SUMMARY["Kernel_IO_Errors"]:-0}))
    echo "" | tee -a "$REPORT_FILE"
    
    echo "--- Web Server Logs ---" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Nginx_4xx"]:-0}" -gt 0 ] && echo -e "${YELLOW}Nginx 4xx:${NC} ${ERROR_SUMMARY["Nginx_4xx"]}" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Nginx_5xx"]:-0}" -gt 0 ] && echo -e "${RED}Nginx 5xx:${NC} ${ERROR_SUMMARY["Nginx_5xx"]}" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Apache_Errors"]:-0}" -gt 0 ] && echo -e "${RED}Apache Errors:${NC} ${ERROR_SUMMARY["Apache_Errors"]}" | tee -a "$REPORT_FILE"
    total_errors=$((total_errors + ${ERROR_SUMMARY["Nginx_5xx"]:-0}))
    echo "" | tee -a "$REPORT_FILE"
    
    echo "--- Journal ---" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Journal_Emergency"]:-0}" -gt 0 ] && echo -e "${RED}Emergency:${NC} ${ERROR_SUMMARY["Journal_Emergency"]}" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Journal_Alert"]:-0}" -gt 0 ] && echo -e "${RED}Alert:${NC} ${ERROR_SUMMARY["Journal_Alert"]}" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Journal_Critical"]:-0}" -gt 0 ] && echo -e "${RED}Critical:${NC} ${ERROR_SUMMARY["Journal_Critical"]}" | tee -a "$REPORT_FILE"
    [ "${ERROR_SUMMARY["Journal_Errors"]:-0}" -gt 0 ] && echo -e "${RED}Errors:${NC} ${ERROR_SUMMARY["Journal_Errors"]}" | tee -a "$REPORT_FILE"
    total_errors=$((total_errors + ${ERROR_SUMMARY["Journal_Emergency"]:-0} + ${ERROR_SUMMARY["Journal_Alert"]:-0} + ${ERROR_SUMMARY["Journal_Critical"]:-0}))
    echo "" | tee -a "$REPORT_FILE"
    
    echo "==========================================" | tee -a "$REPORT_FILE"
    echo "TOTAL ERROR SCORE: $total_errors" | tee -a "$REPORT_FILE"
    echo "==========================================" | tee -a "$REPORT_FILE"
    
    if [ $total_errors -ge $ALERT_THRESHOLD ]; then
        echo -e "${RED}ALERT: Error count exceeds threshold ($ALERT_THRESHOLD)!${NC}" | tee -a "$REPORT_FILE"
    fi
    
    # 总数通过全局变量传回，return 只表示成功/失败（超过 255 的 return 值会被取模）
    TOTAL_ERRORS=$total_errors
    return 0
}

send_email_alert() {
    local total_errors="$1"
    local subject="$2"
    
    if [ -z "$ALERT_EMAIL" ]; then
        return
    fi
    
    if command -v mail >/dev/null 2>&1; then
        cat "$REPORT_FILE" | mail -s "$subject" "$ALERT_EMAIL"
        log "Alert email sent to: $ALERT_EMAIL"
    elif command -v sendmail >/dev/null 2>&1; then
        # printf 才能输出邮件头与正文之间的空行，echo 不解释 \n
        printf "Subject: %s\n\n%s\n" "$subject" "$(cat "$REPORT_FILE")" | sendmail "$ALERT_EMAIL"
        log "Alert email sent to: $ALERT_EMAIL"
    else
        log "[WARNING] No mail command available to send alert"
    fi
}

while getopts "t:e:a:sh" opt; do
    case $opt in
        t) TIME_PERIOD="$OPTARG" ;;
        e) ALERT_EMAIL="$OPTARG" ;;
        a) ALERT_THRESHOLD="$OPTARG" ;;
        s) SHOW_SUMMARY=1 ;;
        h) echo "Usage: $0 [-t 1h|6h|12h|24h|7d|30d] [-e email] [-a alert_threshold]"; exit 0 ;;
    esac
done

echo "==========================================" | tee "$REPORT_FILE"
echo "Error Summary Script v$VERSION" | tee -a "$REPORT_FILE"
echo "==========================================" | tee -a "$REPORT_FILE"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$REPORT_FILE"
echo "Time period: Last $TIME_PERIOD" | tee -a "$REPORT_FILE"
echo "Alert threshold: $ALERT_THRESHOLD errors" | tee -a "$REPORT_FILE"
[ -n "$ALERT_EMAIL" ] && echo "Alert email: $ALERT_EMAIL" | tee -a "$REPORT_FILE"
echo "==========================================" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

time_filter=$(get_time_filter "$TIME_PERIOD")

scan_auth_logs "$time_filter"
scan_system_logs "$time_filter"
scan_kernel_logs "$time_filter"
scan_nginx_logs "$time_filter"
scan_apache_logs "$time_filter"
scan_docker_logs "$time_filter"
scan_journal "$time_filter"

# -s 的输出动作放到扫描完成后，否则 ERROR_SUMMARY 恒为空
if [ "$SHOW_SUMMARY" = "1" ]; then
    for key in "${!ERROR_SUMMARY[@]}"; do echo "$key=${ERROR_SUMMARY[$key]}"; done | sort
    exit 0
fi

generate_summary
total_errors=$TOTAL_ERRORS

if [ $total_errors -ge $ALERT_THRESHOLD ] && [ -n "$ALERT_EMAIL" ]; then
    send_email_alert $total_errors "ERROR ALERT: $total_errors errors detected on $(hostname)"
fi

echo ""
echo "Report saved to: $REPORT_FILE"