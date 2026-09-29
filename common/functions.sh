#!/system/bin/sh
###############################################################
# USB 自动网络共享 —— 公共函数库 (v2.1)
#
# 为什么不再用 "service call connectivity <码>"：
#   Android 13 起 IConnectivityManager 已移除 setUsbTethering，
#   那些事务码对应的是别的接口（例如 36 = setAirplaneMode），
#   盲扫会误开飞行模式。正确入口是 tethering 服务的 setUsbTethering。
###############################################################

DATA_DIR=/data/adb/usb_auto_tether
CONF_FILE=$DATA_DIR/config.sh
LOG_FILE=$DATA_DIR/auto_tether.log
PID_FILE=$DATA_DIR/daemon.pid
DISABLE_FILE=$DATA_DIR/disable
CACHE_FILE=$DATA_DIR/method.cache   # 旧版遗留，仅用于清理

# ---------------------- 默认配置 ----------------------
CONFIG_VERSION=0
TETHER_ON_CHARGER_ONLY=1
REQUIRE_HOST=0
METHOD_ORDER="tethering rndis ncm manual"
CALLER_PKG=com.android.shell
CALL_TIMEOUT=5
SETTLE_DELAY=2
POLL_INTERVAL=2
RETRY_DELAY=8
MAX_ATTEMPTS=3
ENFORCE=0
KEEP_ADB=1
RESTORE_ON_UNPLUG=0
RESTORE_FUNC=mtp,adb
MANUAL_IP=192.168.42.129
MANUAL_PREFIX=24
LEGACY_CALL=0
LEGACY_CALL_CODE=33
LOG_MAX_KB=512
VERBOSE=1
METHOD=""
CONF_MTIME=0
LAST_ERR=""
SNAP_AIR=""

# ---------------------- 工具 ----------------------

_r() {
  [ -r "$1" ] || return 1
  cat "$1" 2>/dev/null | tr -d '\r\n'
}

log() {
  echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null
  # 必须写全路径，否则会递归调用本函数
  if [ "$VERBOSE" = "1" ] && [ -x /system/bin/log ]; then
    /system/bin/log -t USBTether -p i "$*" 2>/dev/null
  fi
  return 0
}

log_rotate() {
  [ -f "$LOG_FILE" ] || return 0
  _sz=$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' \r\n')
  case "$_sz" in '' | *[!0-9]*) return 0 ;; esac
  if [ "$_sz" -gt $((LOG_MAX_KB * 1024)) ]; then
    tail -n 300 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv -f "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null
  fi
}

_mtime() {
  _t=$(stat -c %Y "$1" 2>/dev/null | tr -d '\r\n')
  case "$_t" in '' | *[!0-9]*) _t=0 ;; esac
  echo "$_t"
}

# 配置从旧版本升级：只改失效项，保留用户其它设置
_migrate_conf() {
  [ -f "$CONF_FILE" ] || return 0
  _ver=$(grep '^CONFIG_VERSION=' "$CONF_FILE" 2>/dev/null | tail -n1 | cut -d= -f2 | tr -d '\r\n ')
  [ "$_ver" = "2" ] && return 0
  cp -f "$CONF_FILE" "$CONF_FILE.bak" 2>/dev/null
  if grep -q '^METHOD_ORDER=' "$CONF_FILE" 2>/dev/null; then
    sed -i 's|^METHOD_ORDER=.*|METHOD_ORDER="tethering rndis ncm manual"|' "$CONF_FILE" 2>/dev/null
  fi
  grep -q '^CONFIG_VERSION=' "$CONF_FILE" 2>/dev/null || echo 'CONFIG_VERSION=2' >> "$CONF_FILE"
  grep -q '^CALLER_PKG=' "$CONF_FILE" 2>/dev/null || echo 'CALLER_PKG=com.android.shell' >> "$CONF_FILE"
  grep -q '^CALL_TIMEOUT=' "$CONF_FILE" 2>/dev/null || echo 'CALL_TIMEOUT=5' >> "$CONF_FILE"
  grep -q '^RESTORE_ON_UNPLUG=' "$CONF_FILE" 2>/dev/null || echo 'RESTORE_ON_UNPLUG=0' >> "$CONF_FILE"
  echo "[$(date '+%m-%d %H:%M:%S')] 配置已升级到 v2（原文件备份为 config.sh.bak）：不再使用已失效的 connectivity 事务码方式" >> "$LOG_FILE" 2>/dev/null
}

# 加载配置
load_conf() {
  mkdir -p "$DATA_DIR" 2>/dev/null
  if [ ! -f "$CONF_FILE" ] && [ -f "$MODDIR/config.sh" ]; then
    cp -f "$MODDIR/config.sh" "$CONF_FILE" 2>/dev/null
    chmod 0644 "$CONF_FILE" 2>/dev/null
  fi
  if [ -f "$CONF_FILE" ]; then
    _migrate_conf
    tr -d '\r' < "$CONF_FILE" > "$DATA_DIR/.conf.tmp" 2>/dev/null
    if [ -s "$DATA_DIR/.conf.tmp" ]; then
      . "$DATA_DIR/.conf.tmp" 2>/dev/null
      CONF_MTIME=$(_mtime "$CONF_FILE")
    fi
    rm -f "$DATA_DIR/.conf.tmp" 2>/dev/null
  fi
  # 双保险：即使配置文件没被改过来，内存里也强制剔除已失效的方式
  case "$METHOD_ORDER" in
    *connectivity* | *svccall*) METHOD_ORDER="tethering rndis ncm manual" ;;
  esac
  return 0
}

# 带超时执行命令：run_timeout <秒> <命令...>
run_timeout() {
  _lim=$1
  shift
  "$@" >> "$LOG_FILE" 2>&1 &
  _p=$!
  _n=0
  while [ "$_n" -lt "$_lim" ]; do
    [ -d "/proc/$_p" ] || return 0
    sleep 1
    _n=$((_n + 1))
  done
  kill "$_p" 2>/dev/null
  log "警告：命令超时（${_lim}s）已终止：$*"
  return 1
}

# service call 包装（带超时保护）
svc_call() {
  log "执行：service call $*"
  run_timeout "$CALL_TIMEOUT" service call "$@"
}

# ---------------------- 状态检测 ----------------------

get_udc_state() {
  for f in /sys/class/udc/*/state; do
    [ -r "$f" ] || continue
    v=$(_r "$f")
    [ -n "$v" ] && { echo "$v"; return 0; }
  done
  v=$(_r /sys/class/android_usb/android0/state)
  [ -n "$v" ] && { echo "$v"; return 0; }
  echo ""
}

get_ps_online() {
  for f in /sys/class/power_supply/usb/online \
           /sys/class/power_supply/USB/online \
           /sys/class/power_supply/usb/present; do
    v=$(_r "$f")
    [ -n "$v" ] && { echo "$v"; return 0; }
  done
  for f in /sys/class/power_supply/*/online; do
    case "$f" in *usb* | *USB*)
      v=$(_r "$f")
      [ -n "$v" ] && { echo "$v"; return 0; }
      ;;
    esac
  done
  echo ""
}

# 端口类型：优先 real_type（当前实际类型），否则只取 type 的第一个词
get_port_type() {
  for f in /sys/class/power_supply/usb/real_type \
           /sys/class/power_supply/USB/real_type; do
    v=$(_r "$f")
    [ -n "$v" ] && { echo "$v"; return 0; }
  done
  for f in /sys/class/power_supply/usb/usb_type /sys/class/power_supply/usb/type; do
    v=$(_r "$f")
    [ -z "$v" ] && continue
    case "$v" in
      *" "*) echo "${v%% *}" ;;
      *) echo "$v" ;;
    esac
    return 0
  done
  echo unknown
}

# host / charging / none
usb_state() {
  case "$(get_udc_state)" in
    *onfigured*) echo host; return 0 ;;
  esac
  case "$(get_ps_online)" in
    1 | true | yes) echo charging; return 0 ;;
  esac
  case "$(getprop sys.usb.state)" in
    *rndis* | *ncm*) echo host; return 0 ;;
  esac
  echo none
}

allow_trigger() {
  _st=$1
  [ "$_st" = "none" ] && return 1
  if [ "$_st" = "charging" ] && [ "$TETHER_ON_CHARGER_ONLY" != "1" ]; then
    return 1
  fi
  if [ "$REQUIRE_HOST" = "1" ] && [ "$_st" != "host" ]; then
    return 1
  fi
  return 0
}

usb_func_is_tether() {
  _cfg="$(getprop sys.usb.config) $(getprop sys.usb.state)"
  case "$_cfg" in
    *rndis* | *ncm*) return 0 ;;
  esac
  return 1
}

find_tether_iface() {
  for i in rndis0 ncm0 usb0 rndis1 ncm1 usb1 usb2; do
    [ -e "/sys/class/net/$i" ] && { echo "$i"; return 0; }
  done
  for p in /sys/class/net/*; do
    [ -e "$p" ] || continue
    _rl=$(readlink -f "$p" 2>/dev/null)
    [ -z "$_rl" ] && _rl=$(readlink "$p" 2>/dev/null)
    case "$_rl" in
      *usb* | *rndis* | *ncm*) basename "$p"; return 0 ;;
    esac
  done
  return 1
}

iface_has_ip() {
  [ -n "$1" ] || return 1
  ip -f inet addr show dev "$1" 2>/dev/null | grep -qE 'inet (addr:)?[0-9]{1,3}(\.[0-9]{1,3}){3}' && return 0
  ifconfig "$1" 2>/dev/null | grep -qE 'inet (addr:)?[0-9]{1,3}(\.[0-9]{1,3}){3}' && return 0
  return 1
}

# 共享是否真正生效：USB 功能已是 rndis/ncm 且网卡拿到 IPv4
tether_active() {
  usb_func_is_tether || return 1
  _if=$(find_tether_iface) || return 1
  iface_has_ip "$_if"
}

wait_tether_active() {
  _n=${1:-5}
  _i=0
  while [ "$_i" -lt "$_n" ]; do
    tether_active && return 0
    sleep 1
    _i=$((_i + 1))
  done
  tether_active
}

# 记录当前状态
snapshot() {
  SNAP_CFG="$(getprop sys.usb.config)"
  SNAP_STATE="$(getprop sys.usb.state)"
  SNAP_AIR=$(settings get global airplane_mode_on 2>/dev/null | tr -d '\r\n')
}

# 安全护栏：若尝试过程中被误开飞行模式则立刻还原
guard_airplane() {
  [ "$SNAP_AIR" = "1" ] && return 0
  _ap=$(settings get global airplane_mode_on 2>/dev/null | tr -d '\r\n')
  if [ "$_ap" = "1" ]; then
    settings put global airplane_mode_on 0 >/dev/null 2>&1
    run_timeout 5 am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false
    log "安全护栏：检测到飞行模式被意外打开，已自动关闭"
  fi
  return 0
}

# ---------------------- 开启方式 ----------------------

# 方式一：tethering 服务的 setUsbTethering（Android 11+ 官方入口）
#   ITetheringConnector 事务 3：
#   setUsbTethering(boolean enable, String callerPkg, String callingAttributionTag,
#                   IIntResultListener listener)
#   root 调用时权限校验走 uid==ROOT_UID 绕过分支，listener 传 null 是安全的
method_tethering() {
  svc_call tethering 3 i32 1 s16 "$CALLER_PKG" s16 "$CALLER_PKG" null
  if wait_tether_active 6; then
    METHOD=tethering
    log "成功：方式 tethering 生效，网卡 $(find_tether_iface) 已分配 IP"
    return 0
  fi
  log "tethering 未生效（可能 service 不支持 null 参数），改用 i32 0 写空 binder 重试"
  svc_call tethering 3 i32 1 s16 "$CALLER_PKG" s16 "$CALLER_PKG" i32 0
  if wait_tether_active 6; then
    METHOD=tethering
    log "成功：方式 tethering 生效（i32 0 空 binder），网卡 $(find_tether_iface) 已分配 IP"
    return 0
  fi
  LAST_ERR="tethering 调用后 USB 功能仍为 [$(getprop sys.usb.config)]"
  return 1
}

# 方式二/三：直接切换 USB 功能
method_setfunc() {
  _fn=$1
  _fn2=$_fn
  if [ "$KEEP_ADB" = "1" ]; then
    case "$(getprop sys.usb.config)$(getprop persist.sys.usb.config)" in
      *adb*) _fn2="$_fn,adb" ;;
    esac
  fi
  log "尝试：svc usb setFunctions $_fn2"
  if command -v svc >/dev/null 2>&1; then
    svc usb setFunctions "$_fn2" >> "$LOG_FILE" 2>&1
  elif [ -x /system/bin/cmd ]; then
    /system/bin/cmd usb setFunctions "$_fn2" >> "$LOG_FILE" 2>&1
  else
    setprop sys.usb.config "$_fn2" >> "$LOG_FILE" 2>&1
  fi
  if wait_tether_active 6; then
    METHOD=setfunc_$_fn
    log "成功：方式 $_fn 生效（$_fn2），网卡 $(find_tether_iface) 已分配 IP"
    return 0
  fi
  LAST_ERR="$_fn 切换后 USB 功能为 [$(getprop sys.usb.config)]，网卡未拿到 IP"
  return 1
}

# 兜底：切 rndis + 手动配 IP + 转发 + NAT（电脑侧需手动设静态 IP）
method_manual() {
  _fn=rndis
  if [ "$KEEP_ADB" = "1" ]; then
    case "$(getprop sys.usb.config)$(getprop persist.sys.usb.config)" in
      *adb*) _fn=rndis,adb ;;
    esac
  fi
  log "尝试兜底方案 manual：切 $_fn 并手动配置"
  if command -v svc >/dev/null 2>&1; then
    svc usb setFunctions "$_fn" >> "$LOG_FILE" 2>&1
  else
    setprop sys.usb.config "$_fn" >> "$LOG_FILE" 2>&1
  fi
  sleep 3

  _if=$(find_tether_iface) || { LAST_ERR="manual：找不到 USB 网卡"; log "$LAST_ERR"; return 1; }
  log "manual：使用网卡 $_if"

  ip link set "$_if" up >> "$LOG_FILE" 2>&1
  ip addr add "$MANUAL_IP/$MANUAL_PREFIX" dev "$_if" >> "$LOG_FILE" 2>&1

  _up=""
  for _u in wlan0 swlan0 rmnet_data0 rmnet0 ccmni0 eth0; do
    if iface_has_ip "$_u"; then _up=$_u; break; fi
  done
  [ -z "$_up" ] && _up=$(ip route 2>/dev/null | grep '^default' | head -n1 | sed 's/.*dev \([^ ]*\).*/\1/')

  echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null
  if [ -n "$_up" ] && command -v iptables >/dev/null 2>&1; then
    iptables -t nat -C POSTROUTING -o "$_up" -j MASQUERADE >> "$LOG_FILE" 2>&1 || \
      iptables -t nat -A POSTROUTING -o "$_up" -j MASQUERADE >> "$LOG_FILE" 2>&1
    iptables -C FORWARD -i "$_if" -o "$_up" -j ACCEPT >> "$LOG_FILE" 2>&1 || \
      iptables -A FORWARD -i "$_if" -o "$_up" -j ACCEPT >> "$LOG_FILE" 2>&1
    iptables -C FORWARD -i "$_up" -o "$_if" -m state --state RELATED,ESTABLISHED -j ACCEPT >> "$LOG_FILE" 2>&1 || \
      iptables -A FORWARD -i "$_up" -o "$_if" -m state --state RELATED,ESTABLISHED -j ACCEPT >> "$LOG_FILE" 2>&1
  fi
  ndc network interface add "$_if" >> "$LOG_FILE" 2>&1

  if iface_has_ip "$_if"; then
    METHOD=manual
    log "兜底生效：$_if=$MANUAL_IP/$MANUAL_PREFIX，上行=$_up（电脑需手动设静态 IP）"
    return 0
  fi
  LAST_ERR="manual：$_if 未能配置 IP"
  log "$LAST_ERR"
  return 1
}

# 旧版兼容（默认关闭，仅 Android 10 及以下可用；只调一个指定事务码，不盲扫）
method_legacy() {
  [ "$LEGACY_CALL" = "1" ] || return 1
  log "尝试旧版兼容方式：service call connectivity $LEGACY_CALL_CODE i32 1"
  svc_call connectivity "$LEGACY_CALL_CODE" i32 1 s16 "$CALLER_PKG"
  if wait_tether_active 5; then
    METHOD=legacy
    log "成功：旧版方式生效"
    return 0
  fi
  return 1
}

try_enable() {
  snapshot
  for _m in $METHOD_ORDER; do
    case "$_m" in
      tethering) method_tethering && { guard_airplane; return 0; } ;;
      rndis)     method_setfunc rndis && { guard_airplane; return 0; } ;;
      ncm)       method_setfunc ncm && { guard_airplane; return 0; } ;;
      manual)    method_manual && { guard_airplane; return 0; } ;;
      legacy)    method_legacy && { guard_airplane; return 0; } ;;
      connectivity | svccall)
        log "跳过已失效的方式：$_m（Android 13 起 setUsbTethering 已从 IConnectivityManager 移除）"
        ;;
      *) log "未知方式：$_m" ;;
    esac
    guard_airplane
  done
  log "本轮全部方式失败，最后错误：${LAST_ERR:-未知}"
  return 1
}

# 关闭共享 / 还原 USB 功能
disable_tether() {
  run_timeout "$CALL_TIMEOUT" service call tethering 3 i32 0 s16 "$CALLER_PKG" s16 "$CALLER_PKG" null
  if command -v svc >/dev/null 2>&1; then
    svc usb setFunctions "$RESTORE_FUNC" >> "$LOG_FILE" 2>&1
  else
    setprop sys.usb.config "$RESTORE_FUNC" >> "$LOG_FILE" 2>&1
  fi
  log "已请求关闭共享，USB 功能还原为 $RESTORE_FUNC"
  return 0
}
