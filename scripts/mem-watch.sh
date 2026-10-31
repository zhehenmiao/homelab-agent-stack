#!/bin/bash
# 每小时采集一次关键进程内存，用来判断「涨上去会不会回落」
#
# 为什么不能只看 free -m：
#   Linux 的 used 包含可回收的 page cache，流水位高不代表有问题。
#   判断泄漏要看两个东西：可用量（available）和「RSS 是否贴着峰值不回落」。
#   后者只能靠时序数据 —— 所以这里每小时落一行 CSV。
#
# 输出：时间,可用MB,各服务RSS MB,swap MB,load1
# 只追加不轮转（一天 24 行，一年 9000 行，几百 KB）

set -uo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/mem-watch}"
OUT="$DATA_DIR/mem-history.csv"
ALERT_LOG="$DATA_DIR/mem-alert.log"
STATE="$DATA_DIR/mem-alert.state"
THRESH="${MEM_THRESH:-300}"        # 可用内存告警线（MB）
COOLDOWN="${ALERT_COOLDOWN:-21600}" # 同一场告急的静默期（秒），默认 6 小时
SERVICES="${SERVICES:-}"           # 空格分隔的服务名列表

mkdir -p "$DATA_DIR"

rss() {
  local svc="$1" pid
  pid=$(systemctl show "$svc" -p MainPID --value 2>/dev/null)
  if [ -n "$pid" ] && [ "$pid" != "0" ]; then
    awk '/^VmRSS/{print int($2/1024); exit}' "/proc/$pid/status" 2>/dev/null
  fi
}

[ -f "$OUT" ] || {
  printf 'time,avail_mb'
  for s in $SERVICES; do printf ',%s_mb' "$s"; done
  printf ',swap_mb,load1\n'
} > "$OUT"

avail=$(free -m | awk '/^Mem:/{print $7}')
swap=$(free -m | awk '/^Swap:/{print $3}')
load1=$(cut -d' ' -f1 /proc/loadavg)

row="$(date '+%Y-%m-%d %H:%M'),$avail"
for s in $SERVICES; do row="$row,$(rss "$s")"; done
row="$row,$swap,$load1"
echo "$row" >> "$OUT"

# 跌破告警线：落一行日志 + 发一次通知，同一场告急在静默期内不重复喊
if [ "$avail" -lt "$THRESH" ]; then
  last=0
  [ -f "$STATE" ] && last=$(cat "$STATE" 2>/dev/null || echo 0)
  now_s=$(date +%s)
  if [ $((now_s - last)) -ge "$COOLDOWN" ]; then
    msg="可用内存 ${avail}MB（告警线 ${THRESH}），swap ${swap}MB，1 分钟负载 ${load1}"
    printf '%s ALERT avail=%s swap=%s load=%s\n' "$(date '+%F %T')" "$avail" "$swap" "$load1" >> "$ALERT_LOG"
    # 替换成你自己的告警通道（webhook / 邮件 / 消息平台 CLI）
    "${ALERT_CMD:-true}" "$msg" || true
    echo "$now_s" > "$STATE"
  fi
elif [ -f "$STATE" ]; then
  printf '%s recovered avail=%sMB\n' "$(date '+%F %T')" "$avail" >> "$ALERT_LOG"
  rm -f "$STATE"
fi
