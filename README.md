# USB 自动网络共享 (Auto USB Tethering) v2.1

> **作者：酷安：坠欢啊**
> 二次修改、二次发布、搬运转载前，请先征得本人同意。

插入 USB 数据线后，自动开启「USB 网络共享」。适用于小米澎湃 OS / HyperOS / MIUI，Android 11 ~ 17，
兼容 Magisk / KernelSU / APatch。

---

## 一、安装

1. Magisk / KernelSU / APatch App → 「模块」→「从本地安装」→ 选择本 zip
2. 重启手机
3. 插上数据线，稍等 3～8 秒，电脑上会出现新的网络连接（Android 会分配 `192.168.42.x` 段）

模块 ID 为 `usb_auto_tether`，覆盖安装即可，配置会保留（旧配置自动升级，原文件备份为 `config.sh.bak`）。

---

## 二、v2.1 修了什么（重要）

**v2.0 会导致手机莫名开启飞行模式，已修复。** 原因：

- Android 13 起，`IConnectivityManager.setUsbTethering` 已被 Google 移除，`service call connectivity <事务码>`
  这条路彻底失效；
- v2.0 为了兼容不同版本，去"盲扫"事务码（30~45）。而这些码现在对应的是**其它接口**——
  例如 **`36` 就是 `setAirplaneMode`**，所以扫到它就会把飞行模式打开；
- 而飞行模式一开一关又会重置 USB 功能（回到 `adb`），导致共享怎么也起不来。

v2.1 的做法：

- **彻底删除盲扫**，只调用唯一正确的官方入口：

  ```sh
  service call tethering 3 i32 1 s16 com.android.shell s16 com.android.shell null
  ```

  这是 `ITetheringConnector.setUsbTethering(boolean, callerPkg, attrTag, listener)`，
  即系统「USB 网络共享」开关按钮用的同一条通道（`tethering` 服务的第 3 个事务）。
  root 调用时权限校验走 `uid == ROOT_UID` 的绕过分支，`listener` 传 `null` 是安全的。
- 它内部执行 `UsbManager.setCurrentFunctions(NCM 或 RNDIS)`——**自动按机型选择 NCM / RNDIS**，
  这解决了部分新机型（NCM 机型）用 `rndis` 永远不生效的问题；
- USB 功能切到 rndis/ncm 且被主机枚举后，系统 `Tethering` 会收到 `ACTION_USB_STATE` 广播，
  **自动**分配 IP、启动 DHCP 与 NAT——不需要再手动配网络。

---

## 三、开启方式与顺序

配置项 `METHOD_ORDER`，默认依次尝试：

| 方式 | 说明 |
|------|------|
| `tethering` | 官方入口，自动 NCM/RNDIS，会自动分 IP + DHCP + NAT。**首选** |
| `rndis` / `ncm` | `svc usb setFunctions rndis\|ncm[,adb]`，某些 ROM 会自动接管 |
| `manual` | 兜底：切 rndis + 手动配 IP + 开转发 + NAT。**电脑需手动设静态 IP** |

每种方式都会**真实校验**：USB 功能是否已是 rndis/ncm **且** 网卡是否拿到 IPv4，成功即停止并记录。

---

## 四、配置

配置文件：`/data/adb/usb_auto_tether/config.sh`（模块内的 `config.sh` 只是模板）
改完**不用重启**，10 秒内自动热加载。

```sh
TETHER_ON_CHARGER_ONLY=1   # 1=插充电头也尝试开启（推荐）；0=只对"像电脑"的连接开启
REQUIRE_HOST=0             # 1=必须被电脑枚举才触发；0=插上就试
METHOD_ORDER="tethering rndis ncm manual"
CALLER_PKG=com.android.shell
RESTORE_ON_UNPLUG=0        # 1=拔线后还原为 mtp,adb；0=保持 rndis/ncm 为默认（推荐）
KEEP_ADB=1                 # 保留 USB 调试（rndis,adb）
MAX_ATTEMPTS=3             # 每次插拔最多尝试轮数，0=不限
ENFORCE=0                  # 1=被系统重置后无限重开
```

临时停用：`touch /data/adb/usb_auto_tether/disable`（删除即恢复）

---

## 五、排障

```sh
# 一键诊断（排障首选，可把输出发给我）
sh /data/adb/modules/usb_auto_tether/action.sh diag

# 只用官方接口测一次
sh /data/adb/modules/usb_auto_tether/action.sh test

# 依次尝试所有方式
sh /data/adb/modules/usb_auto_tether/action.sh on

# 看状态 / 日志
sh /data/adb/modules/usb_auto_tether/action.sh
cat /data/adb/usb_auto_tether/auto_tether.log
adb logcat -s USBTether
```

**Q：插上还是没反应？**
跑 `action.sh diag`，重点看：`sys.usb.config` 是否变成 `rndis,adb` 或 `ncm,adb`。
若一直停在 `adb`，说明 `tethering` 服务调用被 ROM 拦了，看日志里 `service call` 的输出。

**Q：USB 功能切了 rndis/ncm，但电脑拿不到 IP？**
说明系统没启动 Tethering（IP 服务未拉起），此时会走 `manual` 兜底，电脑需手动设置：

```
IP：192.168.42.2   掩码：255.255.255.0   网关：192.168.42.129   DNS：114.114.114.114
```

**Q：为什么不用 `service call connectivity 33/34` 了？**
因为 Android 13 起该方法已从系统里删除，网上 33/34 的说法只适用于 Android 12 及以前。

**Q：开了共享后 adb 断了？**
正常，部分机型 USB 共享与 adb 不能共存。保持 `KEEP_ADB=1` 可缓解，否则改用 `adb tcpip 5555`。

---

## 六、卸载

Magisk 里移除模块即可，`uninstall.sh` 会杀掉守护进程并还原 USB 功能为 `mtp,adb`。

---

## 七、目录结构

```
/data/adb/modules/usb_auto_tether/
├── module.prop
├── service.sh          开机启动守护进程 + 看门狗
├── action.sh           状态 / 开关 / 测试 / diag 诊断
├── uninstall.sh
├── config.sh           配置模板
├── common/functions.sh 检测与开启的核心逻辑
└── common/daemon.sh    主循环
/data/adb/usb_auto_tether/
├── config.sh           实际生效的配置（旧版会备份为 config.sh.bak）
├── auto_tether.log     日志
└── disable             存在时暂停
```
