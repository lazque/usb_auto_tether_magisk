#!/system/bin/sh
###############################################################
# 卸载时清理守护进程并还原 USB 功能
###############################################################

DATA_DIR=/data/adb/usb_auto_tether

if [ -f "$DATA_DIR/daemon.pid" ]; then
  kill "$(cat "$DATA_DIR/daemon.pid" 2>/dev/null)" 2>/dev/null
fi
for _p in /proc/[0-9]*; do
  grep -q "usb_auto_tether/common/daemon.sh" "$_p/cmdline" 2>/dev/null && kill "${_p#/proc/}" 2>/dev/null
done

# 还原 USB 功能
if command -v svc >/dev/null 2>&1; then
  svc usb setFunctions mtp,adb >/dev/null 2>&1
else
  setprop sys.usb.config mtp,adb >/dev/null 2>&1
fi

rm -rf "$DATA_DIR" 2>/dev/null
exit 0
