#!/usr/bin/env bash
# 冒烟测试运行器
# 用法: bash tests/smoke_test.sh
# 覆盖: 脚本语法检查 / 帮助输出检查 / 批处理逻辑风格检查 / 关键功能回归(备份/增量/恢复、日志分析、恢复失败路径)

cd "$(dirname "$0")/.." || exit 1

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); printf '[PASS] %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[FAIL] %s\n' "$1"; }

# 去掉 ANSI 颜色码后再做文本断言
strip_ansi() { tr -d '\033' | sed 's/\[[0-9;]*m//g'; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------- 1. 语法检查: 所有 shell 脚本 ----------
for f in linux/*.sh linux/docker/*.sh; do
    if err=$(bash -n "$f" 2>&1); then
        ok "bash -n $f"
    else
        bad "bash -n $f: $err"
    fi
done

# ---------- 2. 帮助输出检查 ----------
# system_diagnostic.sh / docker_install.sh / docker_compose_deploy.sh 无 -h 选项, 跳过
declare -A HELP_FLAGS=(
    [linux/db_backup.sh]="-H"
)
for f in linux/*.sh linux/docker/*.sh; do
    case "$f" in
        linux/system_diagnostic.sh|linux/docker/docker_install.sh|linux/docker/docker_compose_deploy.sh) continue ;;
        linux/ssh_key_manage.sh)
            # 该脚本无 -h 帮助(被 hosts 参数占用), 无参调用时输出 Usage
            out=$(bash "$f" 2>&1)
            if printf '%s' "$out" | grep -qiE 'usage|用法'; then
                ok "help $f (无参)"
            else
                bad "help $f (无参)"
            fi
            continue ;;
    esac
    flag=${HELP_FLAGS[$f]:--h}
    out=$(bash "$f" "$flag" 2>&1)
    rc=$?
    if [ $rc -eq 0 ] && printf '%s' "$out" | grep -qiE 'usage|用法'; then
        ok "help $f $flag"
    else
        bad "help $f $flag (rc=$rc)"
    fi
done

# ---------- 3. 批处理逻辑风格检查 ----------
# if 条件后用 & 串联 set/goto 会导致命令无条件执行(历史 bug), 禁止出现
if grep -nE 'if .+& *(set|goto)' windows/*.bat > "$TMP/bat_lint.txt" 2>/dev/null; then
    bad "bat 逻辑风格: 发现 'if ... & set/goto' 写法:"
    sed 's/^/       /' "$TMP/bat_lint.txt"
else
    ok "bat 逻辑风格: 无 'if ... & set/goto' 写法"
fi

# ---------- 4. 功能回归: backup_manager.sh ----------
SRC="$TMP/src"
DST="$TMP/dst"
RST="$TMP/restore"
mkdir -p "$SRC" "$DST"
echo hello > "$SRC/a.txt"
echo world > "$SRC/b.txt"

out=$(bash linux/backup_manager.sh -s "$SRC" -d "$DST" -t full 2>/dev/null)
if [ $? -eq 0 ] && ls "$DST"/*.tar.gz >/dev/null 2>&1; then
    ok "backup_manager 全量备份"
else
    bad "backup_manager 全量备份: $out"
fi

out=$(bash linux/backup_manager.sh -s "$SRC" -d "$DST" -t incr 2>/dev/null)
if [ $? -eq 0 ] && ls "$DST"/*.snar >/dev/null 2>&1; then
    ok "backup_manager 增量备份(生成 .snar 基线快照)"
else
    bad "backup_manager 增量备份: $out"
fi

echo changed >> "$SRC/a.txt"
out=$(bash linux/backup_manager.sh -s "$SRC" -d "$DST" -t incr 2>/dev/null)
if [ $? -eq 0 ]; then
    ok "backup_manager 增量备份(变更后二次增量)"
else
    bad "backup_manager 二次增量: $out"
fi

out=$(bash linux/backup_manager.sh -l "$DST" 2>/dev/null)
if [ $? -eq 0 ] && printf '%s' "$out" | grep -q 'tar'; then
    ok "backup_manager 列表(-l)"
else
    bad "backup_manager 列表(-l): $out"
fi

full_archive=$(ls "$DST"/*_full_*.tar.gz 2>/dev/null | head -1)
out=$(bash linux/backup_manager.sh -r "$full_archive" -d "$RST" 2>/dev/null)
if [ $? -eq 0 ] && [ "$(cat "$RST/src/b.txt" 2>/dev/null)" = "world" ]; then
    ok "backup_manager 恢复(-r)"
else
    bad "backup_manager 恢复(-r): $out"
fi

# ---------- 5. 功能回归: log_analyzer.sh(双零统计 bug 修复验证) ----------
printf '2026-01-01 10:00:00 host app: ERROR boom\n2026-01-01 10:00:01 host app: ok\n' > "$TMP/app.log"
out=$(bash linux/log_analyzer.sh -l system -f "$TMP/app.log" -n 10 2>/dev/null)
rc=$?
out_clean=$(printf '%s' "$out" | strip_ansi)
if [ $rc -eq 0 ] && printf '%s' "$out_clean" | grep -qi 'total errors: 1'; then
    ok "log_analyzer 错误统计"
else
    bad "log_analyzer 错误统计 (rc=$rc): $out_clean"
fi

out=$(bash linux/log_analyzer.sh -l system -f "$TMP/not_exist.log" -n 10 2>/dev/null)
if [ $? -ne 0 ]; then
    ok "log_analyzer 不存在的文件报错退出"
else
    bad "log_analyzer 不存在的文件应报错退出"
fi

# ---------- 6. 功能回归: db_backup.sh 恢复失败路径(假成功 bug 修复验证) ----------
out=$(bash linux/db_backup.sh -t mysql -d testdb -r "$TMP/app.log" -y 2>/dev/null)
rc=$?
if [ $rc -ne 0 ] && printf '%s' "$out" | grep -qi 'unknown backup file format'; then
    ok "db_backup 恢复未知格式报错退出"
else
    bad "db_backup 恢复未知格式应报错退出 (rc=$rc): $out"
fi

# ---------- 结果汇总 ----------
echo
echo "=========================================="
printf '冒烟测试结果: %d 通过, %d 失败\n' "$PASS" "$FAIL"
echo "=========================================="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
