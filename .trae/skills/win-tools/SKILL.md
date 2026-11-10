---
name: "win-tools"
description: "Windows 工具集：55 个 Linux 风格命令（ls/grep/find/top...）、系统一键优化、微信多开、Beyond Compare 试用重置。当用户在 Windows 上要用 Linux 命令或做系统优化时使用。"
---

# Windows 工具集

本 skill 提供 Windows 下的 Linux 风格命令工具（55 个）和系统优化脚本（自包含于 `scripts/` 目录）。

## 何时使用

- 用户想在 Windows PowerShell 用 Linux 风格命令（ls / grep / awk / top...）
- 用户要系统一键优化（隐私 / 性能）
- 用户要微信多开、Beyond Compare 试用重置

## 脚本清单

- `scripts/` 下 55 个 `*.ps1`：Linux 风格命令
- `scripts/install.ps1`：安装命令工具
- 3 个 bat：`Windows系统一键优化.bat` / `Window微信多开.bat` / `Window Beyond Compare重置试用.bat`

## 核心用法

```powershell
# 安装 Linux 风格命令
cd scripts
.\install.ps1
# 重启终端后即可使用: ls -la, df -h, grep, find, tree 等
```

## 命令分类

- 文件：ls / ll / cat / head / tail / more / less / touch / rm / cp / mv / mkdir / pwd / find / tree / which
- 文本：grep / awk / sort / uniq / cut / tr / wc / tee / xargs / basename / dirname / realpath
- 系统：df / du / free / uptime / ps / top / htop / kill / whoami / hostname / date / env / cal
- 网络：ip / netstat / ss / dig / nc / traceroute
- 压缩下载：zip / unzip / wget / curl
- 其他：history

## 注意事项

- 需 PowerShell 5+
- bat 脚本右键「以管理员身份运行」
- 一键优化会自动创建系统还原点
