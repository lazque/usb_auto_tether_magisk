#!/system/bin/sh
###############################################################
# USB 自动网络共享 —— 用户配置
#
# 修改后无需重启手机，10 秒内守护进程会自动重新加载本文件。
# 本文件是 /data/adb/usb_auto_tether/config.sh 的模板，
# 模块安装后真正生效的是 /data/adb/usb_auto_tether/config.sh。
###############################################################

# ---------- 触发条件 ----------

# 1 = 只要检测到 USB 供电就尝试开启（含充电头，最省心，推荐）
# 0 = 只对"像电脑"的连接开启（充电器不动作）
TETHER_ON_CHARGER_ONLY=1

# 1 = 严格要求 USB 已被主机枚举（/sys/class/udc/*/state = configured）才触发
# 0 = 不严格，插上就试（推荐；部分机型充电模式下不会枚举）
REQUIRE_HOST=0

# ---------- 开启方式 ----------

# 依次尝试的方式，空格分隔。可选：connectivity rndis ncm manual
#   connectivity : 调用系统 ConnectivityManager.setUsbTethering()（最正规，会自动分配 IP + DHCP）
#   rndis / ncm  : 直接把 USB 功能切成 rndis/ncm（部分 ROM 会自动接管并开共享）
#   manual       : 兜底方案：切 rndis + 手动配 IP + 转发 + NAT（电脑需手动设静态 IP）
METHOD_ORDER="connectivity rndis ncm manual"

# connectivity 方式的事务码。留空 = 首次接入时自动扫描并记录。
# 扫描成功后会写入 /data/adb/usb_auto_tether/method.cache，之后不再扫描。
CONNECTIVITY_CODE=""

# 1 = 允许自动扫描事务码（仅在没有缓存时扫描一次，且只在 USB 已连接时扫描）
AUTO_SCAN=1

# 自动扫描时依次尝试的事务码（不同 Android 版本不同）
SCAN_CODES="33 34 35 32 36 31 30 37 38 39 40 41 42"

# ---------- 行为细节 ----------

# 检测到 USB 后等待几秒再操作（给系统切换 USB 模式的时间）
SETTLE_DELAY=2

# 轮询间隔（秒）
POLL_INTERVAL=2

# 两次尝试之间的最小间隔（秒）
RETRY_DELAY=10

# 每次插拔最多尝试几轮（0 = 不限）
MAX_ATTEMPTS=5

# 1 = 持续保持共享（被系统重置后无限重开）；0 = 最多试 MAX_ATTEMPTS 轮就放弃本轮
ENFORCE=0

# 1 = 原来开了 USB 调试就保留 adb（rndis,adb）
KEEP_ADB=1

# 1 = 拔掉 USB 后把 USB 功能还原为 RESTORE_FUNC（下次插入重新触发）
RESTORE_ON_UNPLUG=1
RESTORE_FUNC=mtp,adb

# manual 兜底方案的网段（电脑侧需要手动设置静态 IP 时使用）
MANUAL_IP=192.168.42.129
MANUAL_PREFIX=24

# ---------- 日志 ----------

# 日志超过该大小(KB)自动截断
LOG_MAX_KB=512

# 1 = 同时输出到 logcat（标签 USBTether），方便 adb logcat -s USBTether 观察
VERBOSE=1
