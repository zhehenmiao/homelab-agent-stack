# scripts/

这里放脱敏后的运维脚本。

## 收录标准

```
✓ 有通用价值的（自愈、监控、巡检）
✓ 能讲清设计意图的
✗ 一次性脚本
✗ 带真实 IP / 域名 / token 的
```

## 脱敏规则

```
真实 IP        → <INTERNAL_IP> / <PUBLIC_IP>
域名           → <your-domain>
token / key    → 从环境变量读取，不写死
用户名         → $USER / <operator>
路径           → 保持真实（路径不敏感，且能体现结构）
```

## 待补

- [ ] `guard.sh` —— 第二层自愈：健康检查 + 强制重启
- [ ] `patrol.sh` —— 第三层巡检：端到端可用性
- [ ] `mem-watch.sh` —— 内存 RSS 时序采集
- [ ] `traffic.sh` —— 公网流量按链计费统计
