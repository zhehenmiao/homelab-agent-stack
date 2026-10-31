#!/bin/bash
# 从「进程内部」触发自身重启的正确做法
#
# 为什么不能直接 systemctl restart 自己：
#   systemd 会先杀掉调用它的进程（连同它发出的重启命令），
#   命令执行到一半就断了。systemd-run 也一样，父进程一死子进程被清理。
#
# 解法：把重启动作投递到进程外部的执行器 —— 一次性 cron 任务。
# 本脚本由 cron 触发（独立于目标进程树），先摘掉自己的 cron 条目避免重复执行。

set -uo pipefail

SERVICE="${SERVICE:?需要设置 SERVICE}"
SELF_NAME="$(basename "$0")"
LOG="${LOG:-/var/log/bounce.log}"

# 先摘掉自己，避免下一分钟重复执行
crontab -l 2>/dev/null | grep -v "$SELF_NAME" | crontab - 2>/dev/null
sleep 2

/usr/bin/systemctl restart "$SERVICE"
echo "restart issued at $(date '+%F %T')" >> "$LOG"

# 重启后留一份快照，用于事后核对（重启有没有真的生效）
sleep 20
{
  echo "--- $(date '+%F %T') 重启后快照 ---"
  free -m | awk '/^Mem:/{printf "mem used %dM/%dM avail %dM\n", $3, $2, $7}'
  pid=$(systemctl show "$SERVICE" -p MainPID --value)
  if [ -n "$pid" ] && [ "$pid" != "0" ]; then
    ps -o rss= -p "$pid" 2>/dev/null | awk -v n="$SERVICE" '{printf "%s %.1fMB\n", n, $1/1024}'
  fi
} >> "$LOG"
