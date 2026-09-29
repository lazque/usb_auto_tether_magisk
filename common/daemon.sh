#!/system/bin/sh
###############################################################
# USB 自动网络共享 —— 守护进程
#
# 开机后常驻：检测到 USB 接入 -> 自动开启 USB 网络共享
# 拔掉 USB -> 可选还原为 mtp,adb
#
# 日志：/data/adb/usb_auto_tether/auto_tether.log
# 配置：/data/adb/usb_auto_tether/config.sh
# 暂停：新建空文件 /data/adb/usb_auto_tether/disable
###############################################################

SELF=$0
DN=${SELF%/*}
MODDIR=${DN%/*}
[ -f "$MODDIR/module.prop" ] || MODDIR=$(cd "$DN/.." 2>/dev/null && pwd)
if [ ! -f "$MODDIR/module.prop" ]; then
  for _c in /data/adb/modules/usb_auto_tether /data/adb/modules_update/usb_auto_tether; do
    if [ -f "$_c/module.prop" ]; then MODDIR=$_c; break; fi
  done
fi
export MODDIR

. "$MODDIR/common/functions.sh"

mkdir -p "$DATA_DIR" 2>/dev/null
load_conf

log "=========================================================="
log "守护进程启动 | $(getprop ro.product.brand) $(getprop ro.product.model) | Android $(getprop ro.build.version.release) (SDK $(getprop ro.build.version.sdk))"
log "模块目录：$MODDIR"
log "配置：ORDER=[$METHOD_ORDER] CODE=[$CONNECTIVITY_CODE] SCAN=$AUTO_SCAN CHARGER=$TETHER_ON_CHARGER_ONLY REQUIRE_HOST=$REQUIRE_HOST ENFORCE=$ENFORCE KEEP_ADB=$KEEP_ADB RESTORE=$RESTORE_ON_UNPLUG"
log "探测：udc=[$(get_udc_state)] usb_online=[$(get_ps_online)] type=[$(get_port_type)] usb.config=[$(getprop sys.usb.config)] usb.state=[$(getprop sys.usb.state)]"
log "=========================================================="

# 开机先等一会儿，避开 boot 阶段 USB 状态抖动
sleep 5

_session=""
_attempts=0
_last_try=0
_cycles=0
_paused=""

while :; do
  _cycles=$((_cycles + 1))
  [ $((_cycles % 30)) -eq 0 ] && log_rotate

  # 配置文件被改过 -> 热重载
  if [ -f "$CONF_FILE" ]; then
    _mt=$(_mtime "$CONF_FILE")
    if [ "$_mt" != "$CONF_MTIME" ] && [ "$_mt" != "0" ]; then
      load_conf
      log "配置已重新加载：ORDER=[$METHOD_ORDER] CODE=[$CONNECTIVITY_CODE] CHARGER=$TETHER_ON_CHARGER_ONLY"
    fi
  fi

  # 暂停开关
  if [ -f "$DISABLE_FILE" ]; then
    if [ "$_paused" != "1" ]; then
      log "检测到 $DISABLE_FILE，暂停自动共享（删除该文件后自动恢复）"
      _paused=1
    fi
    sleep 10
    continue
  fi
  if [ "$_paused" = "1" ]; then
    log "disable 文件已删除，恢复自动共享"
    _paused=""
    _session=""
    _attempts=0
  fi

  _st=$(usb_state)

  if [ "$_st" = "none" ]; then
    if [ -n "$_session" ]; then
      log "USB 已断开（上次状态=$_session）"
      if [ "$RESTORE_ON_UNPLUG" = "1" ]; then
        sleep 1
        disable_tether
      fi
      _session=""
      _attempts=0
    fi
    sleep "$POLL_INTERVAL"
    continue
  fi

  if ! allow_trigger "$_st"; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  # 新的一次连接
  if [ -z "$_session" ]; then
    _session="$_st"
    log "检测到 USB 接入：状态=$_st 端口=$(get_port_type) udc=$(get_udc_state)"
    sleep "$SETTLE_DELAY"
    _attempts=0
    _last_try=0
  fi

  if tether_active; then
    _attempts=0
    sleep "$POLL_INTERVAL"
    continue
  fi

  _cap=$MAX_ATTEMPTS
  [ "$ENFORCE" = "1" ] && _cap=999999
  [ "$MAX_ATTEMPTS" = "0" ] && _cap=999999

  _now=$(date +%s 2>/dev/null | tr -d '\r\n')
  case "$_now" in '' | *[!0-9]*) _now=0 ;; esac

  if [ "$_attempts" -lt "$_cap" ] && [ $((_now - _last_try)) -ge "$RETRY_DELAY" ]; then
    _attempts=$((_attempts + 1))
    _last_try=$_now
    log "----- 第 $_attempts 轮尝试（状态=$_st）-----"
    try_enable
  fi

  sleep "$POLL_INTERVAL"
done
