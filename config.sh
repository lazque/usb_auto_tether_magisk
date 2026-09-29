#!/system/bin/sh
###############################################################
# USB 自动网络共享 —— 用户配置 (v2.1)
#
# 修改后无需重启，10 秒内守护进程会自动重新加载。
# 实际生效的是 /data/adb/usb_auto_tether/config.sh（本文件是模板）
###############################################################

# 配置版本，请勿修改
CONFIG_VERSION=2

# ---------- 触发条件 ----------

# 1 = 只要检测到 USB 供电就尝试开启（含充电头，最省心，推荐）
# 0 = 只对"像电脑"的连接开启
TETHER_ON_CHARGER_ONLY=1

# 1 = 严格要求 USB 已被主机枚举（/sys/class/udc/*/state = configured）才触发
# 0 = 不严格，插上就试（推荐）
REQUIRE_HOST=0

# ---------- 开启方式 ----------
#
# 依次尝试，空格分隔。可选：
#   tethering : 调系统 Tethering 服务的 setUsbTethering()（Android 11+ 唯一正确入口，
#               自动选择 NCM 或 RNDIS，并触发系统分配 IP + DHCP + NAT）★推荐
#   rndis     : svc usb setFunctions rndis[,adb]
#   ncm       : svc usb setFunctions ncm[,adb]（Android 13+ 部分机型用 NCM）
#   manual    : 兜底：切 rndis + 手动配 IP + 转发 + NAT（电脑需手动设静态 IP）
#
# 注意：Android 13 起 ConnectivityManager.setUsbTethering 已被移除，
#      旧版那种 "service call connectivity <事务码>" 已彻底失效，本模块不再使用。
METHOD_ORDER="tethering rndis ncm manual"

# 调用 tethering 服务时使用的 callerPkg（shell 包名代表 root/shell 调用）
CALLER_PKG=com.android.shell

# 单次 service call 的超时保护（秒），防止个别机型阻塞
CALL_TIMEOUT=5

# ---------- 行为细节 ----------

# 检测到 USB 后等待几秒再操作
SETTLE_DELAY=2

# 轮询间隔（秒）
POLL_INTERVAL=2

# 两次尝试之间的最小间隔（秒）
RETRY_DELAY=8

# 每次插拔最多尝试几轮（0 = 不限）
MAX_ATTEMPTS=3

# 1 = 持续保持共享（被系统重置后无限重开）；0 = 最多试 MAX_ATTEMPTS 轮
ENFORCE=0

# 1 = 原来开了 USB 调试就保留 adb（rndis,adb）
KEEP_ADB=1

# 1 = 拔掉 USB 后把 USB 功能还原为 RESTORE_FUNC
# 0 = 不还原（推荐：让 rndis/ncm 成为默认 USB 配置，插上就自动共享）
RESTORE_ON_UNPLUG=0
RESTORE_FUNC=mtp,adb

# ---------- 兜底方案 manual ----------
MANUAL_IP=192.168.42.129
MANUAL_PREFIX=24

# ---------- 旧版本兼容（Android 10 及以下）----------
# 仅当 LEGACY_CALL=1 时使用；只调用 LEGACY_CALL_CODE 这一个事务码，绝不盲扫。
LEGACY_CALL=0
LEGACY_CALL_CODE=33

# ---------- 日志 ----------
LOG_MAX_KB=512
# 1 = 同时输出到 logcat（标签 USBTether）
VERBOSE=1
