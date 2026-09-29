#!/system/bin/sh
###############################################################
# Magisk late_start service：启动 USB 自动共享守护进程
###############################################################

MODDIR=${0%/*}
DATA_DIR=/data/adb/usb_auto_tether

mkdir -p "$DATA_DIR" 2>/dev/null
chmod 0755 "$MODDIR/common" 2>/dev/null
chmod 0755 "$MODDIR/common/daemon.sh" "$MODDIR/common/functions.sh" 2>/dev/null

# 结束可能残留的旧进程
if [ -f "$DATA_DIR/daemon.pid" ]; then
  kill "$(cat "$DATA_DIR/daemon.pid" 2>/dev/null)" 2>/dev/null
  rm -f "$DATA_DIR/daemon.pid" 2>/dev/null
fi
for _p in /proc/[0-9]*; do
  grep -q "usb_auto_tether/common/daemon.sh" "$_p/cmdline" 2>/dev/null && kill "${_p#/proc/}" 2>/dev/null
done
sleep 1

# 启动守护进程
/system/bin/sh "$MODDIR/common/daemon.sh" >/dev/null 2>&1 &
echo $! > "$DATA_DIR/daemon.pid" 2>/dev/null

# 轻量看门狗：若守护进程意外退出则重新拉起
(
  while :; do
    sleep 120
    _alive=0
    for _p in /proc/[0-9]*; do
      if grep -q "usb_auto_tether/common/daemon.sh" "$_p/cmdline" 2>/dev/null; then
        _alive=1
        break
      fi
    done
    if [ "$_alive" = "0" ] && [ ! -f "$DATA_DIR/disable" ]; then
      /system/bin/sh "$MODDIR/common/daemon.sh" >/dev/null 2>&1 &
      echo $! > "$DATA_DIR/daemon.pid" 2>/dev/null
    fi
  done
) >/dev/null 2>&1 &
