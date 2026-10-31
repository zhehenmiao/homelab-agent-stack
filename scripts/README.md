# scripts/

五个运维脚本，全部脱敏自真实运行的版本。**关键设计决策写在脚本头注释里，不是事后编的。**

## 清单

| 脚本 | 作用 | 对应设计 | 实测 |
|---|---|---|---|
| `guard.sh` | 外部看门狗，服务挂了拉起 | 第二层自愈 | ✅ 幂等验证 |
| `bounce.sh` | 从进程内部触发的安全重启 | `pitfalls.md` 坑 2 | ⚠️ 只做语法与逻辑检查（会真重启服务） |
| `mem-watch.sh` | 内存时序采集 + 阈值告警 | `pitfalls.md` 坑 6 | ✅ 真实数据 |
| `network-rule-fix.sh` | 修复私有网络吞掉云厂商内部服务 | `pitfalls.md` 坑 1 | ✅ 幂等验证 |
| `traffic-accounting.sh` | 公网出流量精确计费 | `architecture.md` 成本账 | ✅ 真实计数器 |

## 部署方式

```bash
# 第二层自愈：每 5 分钟
*/5 * * * * SERVICE=myservice /opt/scripts/guard.sh

# 内存采集：每小时
0 * * * * DATA_DIR=/var/lib/mem-watch SERVICES="svc-a svc-b" /opt/scripts/mem-watch.sh

# 流量统计：每小时
5 * * * * TRAFFIC_CSV=/var/lib/traffic/pub.csv /opt/scripts/traffic-accounting.sh
```

**`bounce.sh` 不常驻**，只在需要重启时临时排进 cron：

```bash
echo "$(date -d '+1 min' '+%M %H') * * * SERVICE=myservice /opt/scripts/bounce.sh" | crontab -
```

## 可配置项（全部走环境变量）

```
guard.sh              SERVICE（必填）、LOG_TAG
bounce.sh             SERVICE（必填）、LOG
mem-watch.sh          DATA_DIR、SERVICES、MEM_THRESH（默认 300MB）、ALERT_COOLDOWN（默认 6h）、ALERT_CMD
network-rule-fix.sh   MAIN_IF（默认 eth0）、PRIVATE_CIDR（默认 100.64.0.0/10）
traffic-accounting.sh TRAFFIC_CSV
```

## 脱敏说明

```
服务名     → SERVICE 环境变量
数据路径   → DATA_DIR / TRAFFIC_CSV
告警通道   → ALERT_CMD，替换成自己的 webhook 或 CLI
真实 IP    → 一个都没有；只保留 RFC1918 网段和云厂商公开的元数据地址
```

## 共性

**这五个脚本都在解决同一类问题：让自动化流程「自己发现自己坏了」。**

```
guard.sh                进程没了 → 拉起来
bounce.sh               要重启自己 → 交给外部
mem-watch.sh            内存趋势 → 落数据 + 越线告警
network-rule-fix.sh     规则被重建覆盖 → 每次启动后补
traffic-accounting.sh   计数器被清零 → 幂等重建 + 快照差值
```

**没有一个是「跑一次就完事」的脚本** —— 全部设计成幂等、可重复执行、失败不静默。
