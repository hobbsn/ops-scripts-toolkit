---
name: "linux-ops"
description: "Linux 运维脚本工具集：系统监控、备份恢复、安全审计、服务部署、性能调优、日志分析。当用户需要做 Linux 系统运维（监控/备份/审计/部署/调优/日志诊断）时使用。"
---

# Linux 运维脚本

本 skill 提供 14 个 Linux 运维脚本（自包含于 `scripts/` 目录），覆盖系统监控、备份恢复、安全审计、服务部署、性能调优和日志分析。

## 何时使用

- 用户要监控系统资源（CPU / 内存 / 磁盘 / 进程 / IO）
- 用户要备份文件或数据库、做全量/增量备份、恢复
- 用户要做安全审计（端口 / SUID / 权限 / SSH / sudo）
- 用户要部署服务、版本回滚、健康检查
- 用户要系统调优、分析日志、汇总错误告警

## 脚本清单与用法

| 脚本 | 功能 | 典型命令 |
|------|------|----------|
| system_monitor.sh | 实时系统监控 | `./system_monitor.sh -i 2 -t 80` |
| process_watchdog.sh | 进程守护重启 | `./process_watchdog.sh -c nginx -c mysql -i 30` |
| io_monitor.sh | 磁盘 IO 监控 | `./io_monitor.sh` |
| backup_manager.sh | 全量/增量备份 | `./backup_manager.sh -p /data -d /backup -t full` |
| db_backup.sh | 数据库备份 | `./db_backup.sh -t mysql -u root -p pw -d mydb` |
| security_audit.sh | 安全审计 | `sudo ./security_audit.sh -o report.log` |
| ssh_key_manage.sh | SSH 密钥管理 | `./ssh_key_manage.sh -a generate` |
| sudo_audit.sh | sudo 权限审计 | `./sudo_audit.sh` |
| port_scanner.sh | 端口扫描 | `./port_scanner.sh -t 192.168.1.100 -p 1-1000` |
| service_deploy.sh | 服务部署/回滚 | `./service_deploy.sh -n myapp -v 1.2.0 -a deploy -u <url>` |
| system_tuner.sh | 系统调优 | `./system_tuner.sh -p server -a apply` |
| log_analyzer.sh | 多类型日志分析 | `./log_analyzer.sh -l nginx -o report.html` |
| error_summary.sh | 错误汇总告警 | `./error_summary.sh -t 24h -e admin@example.com` |
| system_diagnostic.sh | 系统综合诊断 | `./system_diagnostic.sh` |

## 执行方式

- 脚本位于本 SKILL.md 同级 `scripts/` 目录
- 首次使用先 `chmod +x scripts/*.sh`
- 大部分脚本需 root 权限，用 `sudo` 执行
- 多数脚本支持 `-h` 查看详细帮助

## 定时任务参考

```bash
0 2 * * * /opt/scripts/backup_manager.sh -p /data -d /backup -t full
0 * * * * /opt/scripts/error_summary.sh -t 1h -e admin@example.com -a 50
0 3 * * 0 /opt/scripts/security_audit.sh -o /var/log/audit/$(date +\%Y\%m\%d).log
```

## 注意事项

- 依赖工具：mailx、iostat 等，缺失时脚本会提示
- 调优/部署脚本执行前会自动备份配置
- 生产环境建议先在测试环境验证
