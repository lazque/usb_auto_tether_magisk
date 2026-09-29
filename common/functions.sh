#!/system/bin/sh
###############################################################
# USB 自动网络共享 —— 公共函数库
# 被 daemon.sh / action.sh 引用
###############################################################

DATA_DIR=/data/adb/usb_auto_tether
CONF_FILE=$DATA_DIR/config.sh
CACHE_FILE=$DATA_DIR/method.cache
LOG_FILE=$DATA_DIR/auto_tether.log
PID_FILE=$DATA_DIR/daemon.pid
DISABLE_FILE=$DATA_DIR/disable

# ---------------------- 默认配置 ----------------------
TETHER_ON_CHARGER_ONLY=1
REQUIRE_HOST=0
METHOD_ORDER="connectivity rndis ncm manual"
CONNECTIVITY_CODE=""
AUTO_SCAN=1
SCAN_CODES="33 34 35 32 36 31 30 37 38 39 40 41 42"
SETTLE_DELAY=2
POLL_INTERVAL=2
RETRY_DELAY=10
MAX_ATTEMPTS=5
ENFORCE=0
KEEP_ADB=1
RESTORE_ON_UNPLUG=1
RESTORE_FUNC=mtp,adb
MANUAL_IP=192.168.42.129
MANUAL_PREFIX=24
LOG_MAX_KB=512
VERBOSE=1
METHOD=""
CONF_MTIME=0

# ---------------------- 工具 ----------------------

# 读 sysfs 单行内容
_r() {
  [ -r "$1" ] || return 1
  cat "$1" 2>/dev/null | tr -d '\r\n'
}

log() {
  _line="[$(date '+%m-%d %H:%M:%S')] $*"
  echo "$_line" >> "$LOG_FILE" 2>/dev/null
  # 注意：必须写全路径，否则会递归调用本函数
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

# 加载配置（会自动剔除 Windows 换行符，避免误改配置导致语法错误）
load_conf() {
  mkdir -p "$DATA_DIR" 2>/dev/null
  if [ ! -f "$CONF_FILE" ] && [ -f "$MODDIR/config.sh" ]; then
    cp -f "$MODDIR/config.sh" "$CONF_FILE" 2>/dev/null
    chmod 0644 "$CONF_FILE" 2>/dev/null
  fi
  if [ -f "$CONF_FILE" ]; then
    tr -d '\r' < "$CONF_FILE" > "$DATA_DIR/.conf.tmp" 2>/dev/null
    if [ -s "$DATA_DIR/.conf.tmp" ]; then
      . "$DATA_DIR/.conf.tmp" 2>/dev/null
      CONF_MTIME=$(_mtime "$CONF_FILE")
    fi
    rm -f "$DATA_DIR/.conf.tmp" 2>/dev/null
  fi
  [ -f "$CACHE_FILE" ] && . "$CACHE_FILE" 2>/dev/null
  return 0
}

# 配置文件修改时间（秒）
_mtime() {
  _t=$(stat -c %Y "$1" 2>/dev/null | tr -d '\r\n')
  case "$_t" in '' | *[!0-9]*) _t=0 ;; esac
  echo "$_t"
}

# ---------------------- 状态检测 ----------------------

# UDC 控制器状态：configured = 已被主机枚举（通常是电脑）
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

# USB 是否供电
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

# 端口类型：USB_SDP / USB_CDP / USB_DCP ...
get_port_type() {
  for f in /sys/class/power_supply/usb/real_type \
           /sys/class/power_supply/usb/usb_type \
           /sys/class/power_supply/USB/real_type \
           /sys/class/power_supply/usb/type; do
    v=$(_r "$f")
    [ -n "$v" ] && { echo "$v"; return 0; }
  done
  echo unknown
}

# 输出：host（已被电脑枚举） / charging（仅供电） / none（未插）
usb_state() {
  case "$(get_udc_state)" in
    *onfigured*) echo host; return 0 ;;
  esac
  case "$(get_ps_online)" in
    1 | true | yes) echo charging; return 0 ;;
  esac
  # 有些机型没有 udc/power_supply 节点，退而求其次看 sys.usb.state
  case "$(getprop sys.usb.state)" in
    *rndis* | *ncm*) echo host; return 0 ;;
  esac
  echo none
}

# 是否允许触发
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

# USB 当前功能是否已是 rndis / ncm
usb_func_is_tether() {
  _cfg="$(getprop sys.usb.config) $(getprop sys.usb.state)"
  case "$_cfg" in
    *rndis* | *ncm*) return 0 ;;
  esac
  return 1
}

# 找出 USB 共享网卡名
find_tether_iface() {
  for i in rndis0 ncm0 usb0 rndis1 usb1 usb2 eth1; do
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

# 网卡是否已拿到 IPv4
iface_has_ip() {
  [ -n "$1" ] || return 1
  ip -f inet addr show dev "$1" 2>/dev/null | grep -qE 'inet (addr:)?[0-9]{1,3}(\.[0-9]{1,3}){3}' && return 0
  ifconfig "$1" 2>/dev/null | grep -qE 'inet (addr:)?[0-9]{1,3}(\.[0-9]{1,3}){3}' && return 0
  return 1
}

# 共享是否已真正生效（USB 功能切换 + 网卡拿到 IP）
tether_active() {
  usb_func_is_tether || return 1
  _if=$(find_tether_iface) || return 1
  iface_has_ip "$_if"
}

# 等待共享生效，最多 n 秒
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

# ---------------------- 开启方式 ----------------------

# 方式一：调用 ConnectivityManager.setUsbTethering()
method_connectivity() {
  if [ -n "$CONNECTIVITY_CODE" ]; then
    _codes="$CONNECTIVITY_CODE"
  else
    [ "$AUTO_SCAN" = "1" ] || return 1
    _codes="$SCAN_CODES"
    log "未缓存事务码，开始自动扫描：$_codes"
  fi

  # 安全护栏：扫描过程中若误触发飞行模式则自动恢复
  _ap_before=$(settings get global airplane_mode_on 2>/dev/null | tr -d '\r\n')

  for _c in $_codes; do
    log "尝试 service call connectivity $_c i32 1 s16 com.android.shell"
    service call connectivity "$_c" i32 1 s16 com.android.shell >> "$LOG_FILE" 2>&1

    if [ -n "$CONNECTIVITY_CODE" ]; then
      # 已缓存的事务码：给足时间等待系统切换 USB 功能
      _ok=$(wait_tether_active 5 && echo yes)
    else
      # 扫描阶段：1 秒内 USB 功能没切成 rndis/ncm 就说明这个码不对，快速跳过
      sleep 1
      if usb_func_is_tether; then
        _ok=$(wait_tether_active 4 && echo yes)
      else
        _ok=""
        log "事务码 $_c 无反应，跳过"
      fi
    fi

    if [ "$_ok" = "yes" ]; then
      echo "CONNECTIVITY_CODE=$_c" > "$CACHE_FILE" 2>/dev/null
      echo "METHOD=connectivity" >> "$CACHE_FILE" 2>/dev/null
      chmod 0644 "$CACHE_FILE" 2>/dev/null
      CONNECTIVITY_CODE=$_c
      METHOD=connectivity
      log "成功：方式 connectivity 生效（事务码 $_c），网卡 $(find_tether_iface) 已分配 IP"
      return 0
    fi

    _ap=$(settings get global airplane_mode_on 2>/dev/null | tr -d '\r\n')
    if [ "$_ap" = "1" ] && [ "$_ap_before" != "1" ]; then
      settings put global airplane_mode_on 0 >/dev/null 2>&1
      am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false >/dev/null 2>&1
      log "提示：扫描过程中被误开的飞行模式已自动关闭"
    fi
  done
  return 1
}

# 方式二/三：直接切换 USB 功能（rndis / ncm）
method_setfunc() {
  _fn=$1
  _fn2=$_fn
  if [ "$KEEP_ADB" = "1" ]; then
    case "$(getprop sys.usb.config)$(getprop persist.sys.usb.config)" in
      *adb*) _fn2="$_fn,adb" ;;
    esac
  fi
  log "尝试 svc usb setFunctions $_fn2"
  if command -v svc >/dev/null 2>&1; then
    svc usb setFunctions "$_fn2" >> "$LOG_FILE" 2>&1
  elif [ -x /system/bin/cmd ]; then
    /system/bin/cmd usb setFunctions "$_fn2" >> "$LOG_FILE" 2>&1
  else
    setprop sys.usb.config "$_fn2" >> "$LOG_FILE" 2>&1
  fi
  if wait_tether_active 5; then
    METHOD=setfunc_$_fn
    log "成功：方式 $_fn 生效（$_fn2），网卡 $(find_tether_iface) 已分配 IP"
    return 0
  fi
  return 1
}

# 方式四：兜底 —— 切 rndis + 手动配 IP + 转发 + NAT
# 该方式下电脑侧需要手动设置静态 IP（见 README）
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

  _if=$(find_tether_iface) || { log "兜底失败：找不到 USB 网卡"; return 1; }
  log "兜底：使用网卡 $_if"

  ip link set "$_if" up >> "$LOG_FILE" 2>&1
  ip addr add "$MANUAL_IP/$MANUAL_PREFIX" dev "$_if" >> "$LOG_FILE" 2>&1

  # 上行接口：优先 wlan0，其次移动数据
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

  # 让 netd 认识这个接口（可选，失败不影响）
  ndc network interface add "$_if" >> "$LOG_FILE" 2>&1

  if iface_has_ip "$_if"; then
    METHOD=manual
    log "兜底生效：$_if=$MANUAL_IP/$MANUAL_PREFIX，上行=$_up（电脑需手动设静态 IP）"
    return 0
  fi
  log "兜底失败：$_if 未能配置 IP"
  return 1
}

# 依次尝试所有方式
try_enable() {
  _i=0
  for _m in $METHOD_ORDER; do
    _i=$((_i + 1))
    case "$_m" in
      connectivity) method_connectivity && return 0 ;;
      rndis)        method_setfunc rndis && return 0 ;;
      ncm)          method_setfunc ncm && return 0 ;;
      manual)       method_manual && return 0 ;;
      *)            log "未知方式：$_m" ;;
    esac
  done
  log "本轮所有方式均失败，稍后重试"
  return 1
}

# 关闭共享 / 还原 USB 功能
disable_tether() {
  if [ -n "$CONNECTIVITY_CODE" ]; then
    service call connectivity "$CONNECTIVITY_CODE" i32 0 s16 com.android.shell >> "$LOG_FILE" 2>&1
  fi
  if command -v svc >/dev/null 2>&1; then
    svc usb setFunctions "$RESTORE_FUNC" >> "$LOG_FILE" 2>&1
  else
    setprop sys.usb.config "$RESTORE_FUNC" >> "$LOG_FILE" 2>&1
  fi
  log "已还原 USB 功能为 $RESTORE_FUNC"
  return 0
}
