# GSI Media Keep Screen On

让安卓设备在**播放视频时不自动锁屏**、**空闲时正常自动锁屏**的 Magisk 模块。专为 Treble GSI（Phh AOSP/Lineage GSI）等「电源管理不尊重 `FLAG_KEEP_SCREEN_ON`」的系统而设计。

> 实测环境：MTK 平板 + LineageOS arm64 GSI（lineage_arm64_bvS，Phh Treble）+ Magisk root

## 问题描述

在 GSI 系统上，抖音等视频 App 播放时明明正确申请了屏幕常亮锁（`FLAG_KEEP_SCREEN_ON`，由 WindowManager 代替 App 持有 `SCREEN_BRIGHT_WAKE_LOCK`），但系统的电源管理服务（PowerManagerService）**无视该锁**，到达 `screen_off_timeout` 后照样息屏锁屏：

- 空闲 30 秒锁屏（正常设计）
- 播放视频 30 秒也锁屏（**不正常**，理论上持有常亮锁时应永不超时）

粗暴解法是把超时设为「永不」，但这牺牲了空闲时的自动锁屏。本模块实现两全其美。

## 诊断过程（可直接复用的取证命令）

### 1. 确认锁屏触发原因

```bash
adb shell "logcat -d -t 5000 | grep -iE 'PowerManagerService.*(Sleeping|Waking|Going to sleep)' | tail -20"
```

输出示例：

```
PowerManagerService: Going to sleep due to timeout (uid 1000)   # 超时锁屏
PowerManagerService: Waking up from Dozing (uid=1000, reason=WAKE_REASON_GESTURE, ...)
PowerManagerService: Going to sleep due to application (uid 10153)  # App主动锁屏（uid 10153=SystemUI，如双击锁屏手势，属正常）
```

`due to timeout` 说明是超时机制锁的屏，而非 App 崩溃或厂商行为。

### 2. 播放视频时抓取电源状态（关键证据）

```bash
adb shell dumpsys power | grep -E "WAKE_LOCK|Wakefulness|UserActivitySummary|HoldingDisplay"
```

播放视频时抓到的异常状态：

```
mWakeLockSummary=0x23                      # 0x2=SCREEN_BRIGHT 常亮锁确实被持有
SCREEN_BRIGHT_WAKE_LOCK 'WindowManager' ON_AFTER_RELEASE (ws=WorkSource{10196})  # 系统代抖音持有
mUserActivitySummary=0x4                   # 0x4=DREAM —— 但系统却判定要息屏！
mScreenOffTimeoutSetting=30000
```

**矛盾点**：AOSP 标准逻辑中，持有 `SCREEN_BRIGHT_WAKE_LOCK` 时 `mUserActivitySummary` 应为 `0x1 (BRIGHT)` 且永不超时；该 GSI 却计算为 `0x4 (DREAM)` → 判定为框架级 bug（或 Phh 电源补丁所致）。

### 3. 顺带排查项（排除法）

```bash
adb shell settings get global low_power                        # 省电模式会强制息屏
adb shell settings get global stay_on_while_plugged_in         # 插电常亮（7=全开）
adb shell settings get system screen_off_timeout               # 超时时间（毫秒）
adb shell dumpsys sensorservice | grep -i light                # 光线传感器（排查自动亮度时用）
```

## 解决方案

一个 5 秒轮询的 root 守护进程，动态切换系统超时值：

```
每5秒: dumpsys power 检测是否存在 SCREEN_BRIGHT_WAKE_LOCK
  ├─ 存在（有App要求常亮） → screen_off_timeout = 86400000 (24h, 等效永不)
  └─ 不存在               → screen_off_timeout = 用户设定的正常值 (默认60000, 可被用户修改自动采纳)
```

**优点**：
- 完全复用系统标准机制（App 只要规范申请常亮锁就生效），不侵入任何框架文件
- 用户在系统设置里手动改「自动锁屏时间」会被自动采纳（通过状态文件检测人为改动）
- 轮询开销可忽略（每 5 秒一次 dumpsys，毫秒级）

**缺点/已知限制**：
- 触发/恢复各有最多 5 秒延迟（轮询周期）
- 依赖 App 规范持有常亮锁；若 App 播放视频却不申请常亮锁（罕见），不会保活

## 安装

### 方式一：Magisk App 安装 zip

把打包好的 `MediaKeepScreenOn-v1.0.zip` 通过 Magisk App → 模块 → 从本地安装。

### 方式二：adb 手动部署（需 root）

```bash
adb push module.prop service.sh /data/local/tmp/
adb shell "su -c 'mkdir -p /data/adb/modules/media_keep_screen_on
  cp /data/local/tmp/module.prop /data/adb/modules/media_keep_screen_on/
  cp /data/local/tmp/service.sh /data/adb/modules/media_keep_screen_on/
  chmod 755 /data/adb/modules/media_keep_screen_on/service.sh'"
adb reboot   # 或立即启动: adb shell "su -c 'setsid sh /data/adb/modules/media_keep_screen_on/service.sh &'
```

## 验证

```bash
# 1. 守护进程存活
adb shell "ps -A | grep media_keep_screen_on"

# 2. 空闲时超时值（应为你的正常值）
adb shell settings get system screen_off_timeout

# 3. 播放视频 ≥5 秒后再查，应变为 86400000
adb shell settings get system screen_off_timeout

# 4. 停止播放 ≥5 秒后应恢复
```

## 打包

```bash
cd module && zip -r ../MediaKeepScreenOn-v1.0.zip module.prop service.sh
```

Magisk 模块 zip 要求 `module.prop`、`service.sh` 位于 zip 根目录。

## 踩坑记录（Windows adb 调试环境）

| 坑 | 解法 |
|---|---|
| Git Bash 把 `/data/local/tmp` 转成 Windows 路径 | 命令前加 `MSYS_NO_PATHCONV=1` |
| `pkill -f media_keep_screen_on` 会匹配到 su 自己的命令行并自杀 | 用 `ps -A` + `kill <pid>` |
| Write 工具生成的脚本带 CRLF，sh 执行报错 | 推送后 `sed -i 's/\r$//' file` |
| adb server 被沙箱反复杀死，偶发 `device offline` | `adb kill-server` 后重试；必要时重插 USB 并解锁屏幕 |
| 并行调用多条 adb 命令导致 daemon 抢端口冲突 | adb 调用串行执行 |

## 目录结构

```
├── README.md                        # 本文档
├── module/
│   ├── module.prop                  # Magisk 模块描述
│   └── service.sh                   # 核心守护脚本
├── MediaKeepScreenOn-v1.0.zip       # 可直接用 Magisk 安装的成品包
└── package.sh                       # 打包脚本
```

## License

MIT
