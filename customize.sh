#!/system/bin/sh
###############################################################
# 安装阶段（customize.sh）
###############################################################

MODDIR=$1
DATA_DIR=/data/adb/usb_auto_tether

chmod 0755 "$MODDIR" 2>/dev/null
chmod 0755 "$MODDIR/common" 2>/dev/null
for f in "$MODDIR"/*.sh "$MODDIR"/common/*.sh; do
  [ -f "$f" ] && chmod 0755 "$f"
done
chmod 0644 "$MODDIR/module.prop" "$MODDIR/config.sh" "$MODDIR/README.md" 2>/dev/null

mkdir -p "$DATA_DIR" 2>/dev/null
chmod 0755 "$DATA_DIR" 2>/dev/null

# 已有配置则保留（升级不丢配置），没有才生成
if [ ! -f "$DATA_DIR/config.sh" ]; then
  cp -f "$MODDIR/config.sh" "$DATA_DIR/config.sh" 2>/dev/null
  chmod 0644 "$DATA_DIR/config.sh" 2>/dev/null
fi
touch "$DATA_DIR/auto_tether.log" 2>/dev/null
chmod 0644 "$DATA_DIR/auto_tether.log" 2>/dev/null

ui_print "---------------------------------------------"
ui_print " USB 自动网络共享 已安装"
ui_print " 作者：酷安：坠欢啊"
ui_print " 二改 / 二次发布需本人同意"
ui_print " 首次插上数据线时会自动探测并记住可用的开启"
ui_print " 方式，之后每次插入都会自动开启共享。"
ui_print ""
ui_print " 配置：/data/adb/usb_auto_tether/config.sh"
ui_print " 日志：/data/adb/usb_auto_tether/auto_tether.log"
ui_print " 状态：在 Magisk 里点本模块的「动作」按钮"
ui_print " 或执行 sh $MODDIR/action.sh status"
ui_print ""
ui_print " 安装后请重启一次手机。"
ui_print "---------------------------------------------"
