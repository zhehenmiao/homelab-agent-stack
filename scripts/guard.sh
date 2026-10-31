#!/bin/bash
# 第二层自愈：外部看门狗（由系统 cron 每 5 分钟调用）
#
# 为什么需要它：
#   如果调度器自己挂在被监控的进程里（cron ticker 住在 agent 进程内），
#   那个进程一挂，所有定时任务同时停摆 —— 包括负责报警的那个。
#   所以这一层必须跑在「不依赖被监控对象」的地方：系统 cron。
#
# 幂等：服务已经是 active 就什么都不做。
# 用 start 不用 restart —— 不会误杀正在正常运行的进程。

set -uo pipefail

SERVICE="${SERVICE:?需要设置 SERVICE，比如 myservice}"
LOG_TAG="${LOG_TAG:-service-guard}"

/usr/bin/systemctl is-active --quiet "$SERVICE" || {
  logger -t "$LOG_TAG" "$SERVICE 不是 active，尝试拉起"
  /usr/bin/systemctl start "$SERVICE"
  sleep 3
  if /usr/bin/systemctl is-active --quiet "$SERVICE"; then
    logger -t "$LOG_TAG" "已拉起成功"
  else
    logger -t "$LOG_TAG" "拉起失败，需人工介入"
    exit 1
  fi
}
