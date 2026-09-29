#!/system/bin/sh
###############################################################
# USB 自动网络共享 —— 手动操作 / 诊断
#
#   sh action.sh            查看状态（Magisk 里的「动作」按钮）
#   sh action.sh on         立即开启一次（依次尝试所有方式）
#   sh action.sh off        关闭共享并还原 USB 功能
#   sh action.sh test       只用 tethering 官方接口测试一次
#   sh action.sh diag       输出完整诊断信息（排障时用这个）
#   sh action.sh log        查看日志尾部
###############################################################

MODDIR=${0%/*}
[ -f "$MODDIR/module.prop" ] || MODDIR=/data/adb/modules/usb_auto_tether
CMD=${1:-status}

# 非 root 运行时自动提权（例如在 Termux 里执行）
if [ "$(id -u 2>/dev/null)" != "0" ]; then
  if command -v su >/dev/null 2>&1; then
    exec su -c "sh $MODDIR/action.sh $CMD"
  fi
fi

export MODDIR
. "$MODDIR/common/functions.sh"
load_conf

case "$CMD" in
  on)
    echo "尝试开启 USB 网络共享…"
    if try_enable; then
      echo "结果：已开启（方式 $METHOD）"
    else
      echo "结果：失败（${LAST_ERR:-未知原因}）"
    fi
    echo "网卡：$(find_tether_iface 2>/dev/null || echo 未找到)"
    echo "USB 功能：$(getprop sys.usb.config)"
    ;;
  off)
    echo "关闭共享并还原 USB 功能…"
    disable_tether
    echo "完成"
    ;;
  test)
    echo "== 环境 =="
    echo "Android       : $(getprop ro.build.version.release) (SDK $(getprop ro.build.version.sdk))"
    echo "USB 状态      : $(usb_state)   udc=$(get_udc_state) online=$(get_ps_online) type=$(get_port_type)"
    echo "sys.usb.config: $(getprop sys.usb.config)"
    echo "sys.usb.state : $(getprop sys.usb.state)"
    echo "共享网卡      : $(find_tether_iface 2>/dev/null || echo 未找到)"
    echo
    echo "== 调用 tethering 服务（官方入口）=="
    if method_tethering; then
      echo "成功：共享已生效，网卡 $(find_tether_iface)"
    else
      echo "失败：$LAST_ERR"
      echo "（若 tethering 服务不可用，可用 sh action.sh on 走全部方式）"
    fi
    echo
    echo "USB 功能现在是：$(getprop sys.usb.config)"
    ;;
  diag)
    echo "############ 诊断信息 ############"
    echo "== 设备 =="
    echo "brand/model : $(getprop ro.product.brand) $(getprop ro.product.model)"
    echo "系统        : $(getprop ro.build.version.release) SDK=$(getprop ro.build.version.sdk) $(getprop ro.build.version.incremental)"
    echo "HyperOS/MIUI: $(getprop ro.mi.os.version.incremental)$(getprop ro.miui.ui.version.name)"
    echo "内核        : $(uname -a)"
    echo
    echo "== USB 状态 =="
    echo "usb_state   : $(usb_state)"
    echo "udc         : $(get_udc_state)"
    echo "usb online  : $(get_ps_online)"
    echo "port type   : $(get_port_type)"
    echo "usb.config  : $(getprop sys.usb.config)"
    echo "usb.state   : $(getprop sys.usb.state)"
    echo "persist.cfg : $(getprop persist.sys.usb.config)"
    echo "飞行模式    : $(settings get global airplane_mode_on 2>/dev/null)"
    echo "网卡列表    : $(ls /sys/class/net 2>/dev/null | tr '\n' ' ')"
    echo "共享网卡    : $(find_tether_iface 2>/dev/null || echo 未找到)"
    echo
    echo "== 工具 =="
    echo "service : $([ -x /system/bin/service ] && echo 有 || echo 无)"
    echo "svc     : $([ -x /system/bin/svc ] && echo 有 || echo 无)"
    echo "cmd     : $([ -x /system/bin/cmd ] && echo 有 || echo 无)"
    echo "iptables: $(command -v iptables 2>/dev/null || echo 无)"
    echo
    echo "== 相关服务 =="
    service list 2>/dev/null | grep -iE "tether|connectivity|network_management" || echo "（无匹配）"
    echo
    echo "== cmd 支持的命令服务 =="
    cmd -l 2>/dev/null | grep -iE "tether|connect|usb" || echo "（无匹配）"
    echo
    echo "== 生效配置 =="
    grep -vE '^[[:space:]]*#' "$CONF_FILE" 2>/dev/null | grep -v '^$'
    echo
    echo "== 日志尾部 60 行 =="
    tail -n 60 "$LOG_FILE" 2>/dev/null
    echo "############ 诊断结束 ############"
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
    echo "最近使用方式  : ${METHOD:-无}"
    echo
    echo "最近日志："
    tail -n 12 "$LOG_FILE" 2>/dev/null
    echo
    echo "用法：sh $MODDIR/action.sh [status|on|off|test|diag|log]"
    ;;
esac
