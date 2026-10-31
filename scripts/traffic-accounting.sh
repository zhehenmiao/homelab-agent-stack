#!/bin/bash
# 统计「真实公网出流量」，用于判断是否吃掉月度流量包
#
# 为什么不能看网卡总量：
#   网卡计数包含内网、回环、云厂商内网备份等一切流量，比真实计费量大一个数量级。
#   这里单独建一条链 TRAFFIC_PUB，内网段打 RETURN 不计，剩下最后一条 RETURN
#   的计数器就是真正的公网出流量。
#
# 计数器是累积值（重启清零），所以每小时落一次快照，
# 日报用相邻两次的差值算这一小时用量。
#
# 附带做一件事：规则丢了自动补回来（幂等），防止重启后静默失效。

set -uo pipefail

CSV="${TRAFFIC_CSV:-/var/lib/traffic/pub-traffic.csv}"
mkdir -p "$(dirname "$CSV")"

ensure_chain() {
  if ! iptables -L TRAFFIC_PUB -n >/dev/null 2>&1; then
    iptables -N TRAFFIC_PUB
    iptables -A OUTPUT -j TRAFFIC_PUB
    iptables -A TRAFFIC_PUB -d 100.64.0.0/10 -j RETURN   # 私有网络
    iptables -A TRAFFIC_PUB -d 172.16.0.0/12  -j RETURN   # 内网
    iptables -A TRAFFIC_PUB -d 10.0.0.0/8     -j RETURN   # 内网
    iptables -A TRAFFIC_PUB -d 127.0.0.0/8    -j RETURN   # 回环
    iptables -A TRAFFIC_PUB -j RETURN                     # 剩下的才是公网
    echo "TRAFFIC_PUB 链已重建" >&2
  fi
}

ensure_chain

# 取最后一条（公网）规则的精确字节数与包数
# 注意：-L 不加 --line-numbers 时没有 num 列，$1=pkts $2=bytes $3=target
read -r pkts bytes <<<"$(iptables -L TRAFFIC_PUB -n -v -x 2>/dev/null \
  | awk '$1 ~ /^[0-9]+$/ {p=$1; b=$2} END {print p, b}')"

[ -z "$bytes" ] && { echo "读不到计数器" >&2; exit 1; }

[ -f "$CSV" ] || echo "time,pub_out_bytes,pub_out_pkts" > "$CSV"
echo "$(date '+%Y-%m-%d %H:%M:%S'),$bytes,$pkts" >> "$CSV"

# 只留最近 60 天，防止无限增长（每小时一行 = 1440 行）
if [ "$(wc -l < "$CSV")" -gt 1440 ]; then
  head -1 "$CSV" > "$CSV.tmp"
  tail -1439 "$CSV" >> "$CSV.tmp"
  mv "$CSV.tmp" "$CSV"
fi
