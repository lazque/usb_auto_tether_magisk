# USB 自动网络共享 (Auto USB Tethering)

> **作者：酷安：坠欢啊**
> 二次修改、二次发布、搬运转载前，请先征得本人同意。

插入 USB 数据线后，自动开启「USB 网络共享」。适用于小米澎湃 OS / HyperOS / MIUI，Android 10 ~ 17，
兼容 Magisk / KernelSU / APatch。

---

## 一、安装

1. Magisk / KernelSU / APatch App → 「模块」→「从本地安装」→ 选择本 zip
2. 重启手机
3. 插上数据线，稍等 2～5 秒，电脑上就会出现新的网络连接（Android 通常会分配 `192.168.42.x` 段）

> 模块 ID 为 `usb_auto_tether`，如果你之前装过 v1.0，本包会作为升级覆盖安装，配置会保留。

---

## 二、它是怎么工作的

开机后启动一个常驻守护进程，每 2 秒检查一次 USB 状态：

- **检测接入**：读 `/sys/class/udc/*/state`（是否被主机枚举）、`/sys/class/power_supply/usb/online`（是否供电）、端口类型
- **开启共享**：按 `METHOD_ORDER` 依次尝试，**每种方式都会做真实校验**（USB 功能是否切到 rndis/ncm + 网卡是否拿到 IPv4），成功即停止并把方式记入缓存，下次开机直接使用
- **拔线处理**：默认还原 USB 功能为 `mtp,adb`，下次插入重新触发

### 四种开启方式

| 方式 | 说明 |
|------|------|
| `connectivity` | 调用系统 `ConnectivityManager.setUsbTethering()`，最正规：会自动切 rndis/ncm、分配 IP、起 DHCP。**事务码因 Android 版本而异，模块会自动扫描并缓存** |
| `rndis` / `ncm` | 直接把 USB 功能切成 rndis 或 ncm。部分 ROM（含部分澎湃 OS 版本）会自动接管并开启共享 |
| `manual` | 兜底：切 rndis + 手动配 IP + 开转发 + NAT。此方式下**电脑需要手动设静态 IP**（见第五节） |

---

## 三、配置

配置文件：`/data/adb/usb_auto_tether/config.sh`（模块内的 `config.sh` 只是模板）
改完**不用重启**，10 秒内守护进程自动热加载。

常用项：

```sh
TETHER_ON_CHARGER_ONLY=1   # 1=插充电头也尝试开启（推荐）；0=只对"像电脑"的连接开启
REQUIRE_HOST=0             # 1=必须被电脑枚举才触发；0=插上就试
METHOD_ORDER="connectivity rndis ncm manual"
CONNECTIVITY_CODE=""       # 留空=自动扫描；手动指定后可跳过扫描
AUTO_SCAN=1                # 允许自动扫描事务码
KEEP_ADB=1                 # 保留 USB 调试（rndis,adb）
RESTORE_ON_UNPLUG=1        # 拔线后还原为 mtp,adb
MAX_ATTEMPTS=5             # 每次插拔最多尝试轮数，0=不限
ENFORCE=0                  # 1=被系统重置后无限重开
```

临时停用（不用卸载）：

```sh
touch /data/adb/usb_auto_tether/disable      # 暂停
rm    /data/adb/usb_auto_tether/disable      # 恢复
```

---

## 四、调试

```sh
# 看状态（也可以在 Magisk 里点模块的「动作」按钮）
sh /data/adb/modules/usb_auto_tether/action.sh status

# 立即开启一次
sh /data/adb/modules/usb_auto_tether/action.sh on

# 逐个测试四种方式，看哪个能成功
sh /data/adb/modules/usb_auto_tether/action.sh test

# 看日志
sh /data/adb/modules/usb_auto_tether/action.sh log
# 或
cat /data/adb/usb_auto_tether/auto_tether.log
# 或 logcat
adb logcat -s USBTether
```

---

## 五、常见问题

**Q：插上没反应？**
按上面「test」跑一遍，把 `auto_tether.log` 里的内容看一下。绝大多数情况是 `connectivity` 的事务码没扫到，
可以在日志里搜 `service call connectivity`，找到成功的那一条，把事务码填进 `CONNECTIVITY_CODE=`。

**Q：USB 功能切了 rndis，但电脑拿不到 IP / 上不了网？**
说明系统没有真正启动 Tethering，模块会继续往下走 `manual` 兜底。此时电脑需要手动设置：

```
IP      ：192.168.42.2
掩码    ：255.255.255.0
网关    ：192.168.42.129
DNS     ：114.114.114.114（或 8.8.8.8）
```

**Q：电脑提示"未识别的设备" / RNDIS 驱动？**
Windows 需要在设备管理器里手动更新驱动，选择「Microsoft USB RNDIS 适配器」或安装小米/谷歌的 USB 驱动。

**Q：开了共享后 adb 断了？**
正常，很多机型 USB 共享与 adb 不能共存。若想保留 adb，确保 `KEEP_ADB=1`（会用 `rndis,adb`）；
仍不行就改用 adb over Wi-Fi（`adb tcpip 5555`）。

**Q：会不会很耗电？**
守护进程只是每 2 秒读几个 sysfs 节点，开销可以忽略。

---

## 六、卸载

Magisk 里直接移除模块即可，`uninstall.sh` 会杀掉守护进程并把 USB 功能还原为 `mtp,adb`。

---

## 七、目录结构

```
/data/adb/modules/usb_auto_tether/
├── module.prop
├── service.sh          开机启动守护进程 + 看门狗
├── action.sh           手动状态/开关/测试
├── uninstall.sh
├── config.sh           配置模板
├── NOTICE              作者与二次分发声明
├── common/functions.sh 检测与开启的核心逻辑
└── common/daemon.sh    主循环
/data/adb/usb_auto_tether/
├── config.sh           实际生效的配置
├── auto_tether.log     日志
├── method.cache        探测到的可用方式（删掉可重新探测）
└── disable             存在时暂停
```
