#!/bin/bash
# 修复：接入私有网络后，云厂商内部服务全部不通
#
# 根因：tailscaled 启动时重建 iptables 规则，其中一条是
#   -A ts-input -s 100.64.0.0/10 ! -i tailscale0 -j DROP
# 云厂商的内部服务网段（元数据、内网镜像、监控、备份）使用 100.100.0.0/16，
# 正好落在 100.64.0.0/10 里面。请求能出去，回包源地址是 100.100.x.x、
# 从主网卡进来，被这条 DROP 直接丢掉 —— 表现为「内部服务全都不通」。
#
# 修法：在 ts-input 链最前面插入放行规则，按接口判断而不是按网段。
# 由 systemd drop-in 的 ExecStartPost 调用，保证每次 tailscaled 启动后自动补。

set -uo pipefail

MAIN_IF="${MAIN_IF:-eth0}"          # 主网卡名，用 `ip route get 1.1.1.1` 确认
CIDR="${PRIVATE_CIDR:-100.64.0.0/10}"
LOG_TAG="${LOG_TAG:-network-rule-fix}"

# tailscaled 启动后规则要过一会儿才建好，最多等 30 秒
for i in $(seq 1 30); do
  if ! iptables -L ts-input -n >/dev/null 2>&1; then
    sleep 1
    continue
  fi
  if iptables -C ts-input -i "$MAIN_IF" -s "$CIDR" -j ACCEPT 2>/dev/null; then
    logger -t "$LOG_TAG" "rule already present"
    exit 0
  fi
  if iptables -I ts-input 1 -i "$MAIN_IF" -s "$CIDR" -j ACCEPT 2>/dev/null; then
    logger -t "$LOG_TAG" "inserted ACCEPT for $MAIN_IF $CIDR (attempt $i)"
    exit 0
  fi
  sleep 1
done

logger -t "$LOG_TAG" "FAILED to insert rule after 30s"
exit 1
