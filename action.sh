#!/system/bin/sh
###############################################################
# Magisk 模块「动作」按钮 / 手动调用
#
#   sh /data/adb/modules/usb_auto_tether/action.sh status   查看状态
#   sh /data/adb/modules/usb_auto_tether/action.sh on       立即开启一次
#   sh /data/adb/modules/usb_auto_tether/action.sh off      关闭并还原
#   sh /data/adb/modules/usb_auto_tether/action.sh test     逐个测试所有开启方式
#   sh /data/adb/modules/usb_auto_tether/action.sh log      查看日志尾部
###############################################################

MODDIR=${0%/*}
[ -f "$MODDIR/module.prop" ] || MODDIR=/data/adb/modules/usb_auto_tether
export MODDIR

. "$MODDIR/common/functions.sh"
load_conf

CMD=${1:-status}

case "$CMD" in
  on)
    echo "尝试开启 USB 网络共享…"
    try_enable && echo "结果：已开启（方式 $METHOD）" || echo "结果：失败，请查看日志"
    tether_active && echo "网卡：$(find_tether_iface)  状态：已分配 IP" || echo "网卡：$(find_tether_iface 2>/dev/null || echo 未找到)  状态：无 IP"
    ;;
  off)
    echo "关闭并还原 USB 功能…"
    disable_tether
    echo "完成"
    ;;
  test)
    echo "== 环境 =="
    echo "USB 状态     : $(usb_state)"
    echo "udc          : $(get_udc_state)"
    echo "usb online   : $(get_ps_online)"
    echo "port type    : $(get_port_type)"
    echo "sys.usb.config: $(getprop sys.usb.config)"
    echo "sys.usb.state : $(getprop sys.usb.state)"
    echo "已缓存事务码 : ${CONNECTIVITY_CODE:-无}"
    echo "== 逐个测试 =="
    for m in connectivity rndis ncm manual; do
      printf '%-14s' "$m:"
      case "$m" in
        connectivity) method_connectivity ;;
        rndis)        method_setfunc rndis ;;
        ncm)          method_setfunc ncm ;;
        manual)       method_manual ;;
      esac
      if [ $? -eq 0 ]; then echo "成功"; else echo "失败"; fi
      sleep 2
    done
    ;;
  log)
    echo "== 最近 40 行日志 =="
    tail -n 40 "$LOG_FILE" 2>/dev/null
    ;;
  *)
    echo "== USB 自动网络共享 =="
    echo "作者          : 酷安：坠欢啊（二改需本人同意）"
    echo "USB 状态      : $(usb_state)  （udc=$(get_udc_state) online=$(get_ps_online) type=$(get_port_type)）"
    echo "sys.usb.config: $(getprop sys.usb.config)"
    echo "sys.usb.state : $(getprop sys.usb.state)"
    echo "共享网卡      : $(find_tether_iface 2>/dev/null || echo 未找到)"
    if tether_active; then echo "共享状态      : 已开启"; else echo "共享状态      : 未开启"; fi
    echo "已缓存方式    : ${METHOD:-无}  事务码：${CONNECTIVITY_CODE:-无}"
    echo
    echo "最近日志："
    tail -n 15 "$LOG_FILE" 2>/dev/null
    echo
    echo "用法：sh $MODDIR/action.sh [status|on|off|test|log]"
    ;;
esac
