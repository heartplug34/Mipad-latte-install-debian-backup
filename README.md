闲的没事干，折腾下MIpad2,安装的debian，跟workbuddy配合(ds4.1f)，这个仓库自用，如果能帮得到您的话就好QWQ

# 小米平板 2（Mi Pad 2 / latte）刷 Debian 记录

把 2015 年的小米平板 2 刷成能日常开机的 Debian 13（trixie），并把它跑通。
这里只记录**怎么刷、怎么开机**，以及**踩过的坑**。

> 关键文件（latte 专用内核、WiFi 固件）在 **[Releases](../../releases)** 里下载。
> 系统镜像等通用文件请自行从官方源下载，本仓库不重复托管 —— 见下方「需要准备的文件」。

---

## 一、这台机器的情况

| 项目 | 说明 |
|---|---|
| 机型 | 小米平板 2（代号 **latte**），2015 年 |
| SoC | Intel Atom x5-Z8500（Cherry Trail，4 核 Airmont @1.44 GHz） |
| 内存 / 存储 | 3.8 GB LPDDR3 / 32 或 64 GB eMMC（4+128 魔改版见下） |
| 固件 | 百敖（Byosoft）**UEFI BIOS**，可从 U 盘引导 |
| 装系统的难度 | 和给普通 x86 电脑装 Linux 基本一样 |
| 变砖风险 | 低。BIOS 与 fastboot 都在芯片固件里，随时能刷回官方包 |

**两个前提认知：**

1. **它是 x86_64 + UEFI**，不是 ARM 平板。所以用标准的 amd64 安装镜像即可。
2. **固件拒绝写入 NVRAM 中的 UEFI 启动变量**。这就是「装完了进不去系统」的根因 ——
   解决方式是在 ESP 里放一份**兜底引导文件** `EFI/BOOT/BOOTX64.EFI`（详见第四节）。

关于 4+128 魔改版：分区表常被改过，但 UEFI 引导只认 ESP，一般不影响安装。

---

## 二、需要准备的文件

| 文件 | 从哪来 |
|---|---|
| **Debian netinst ISO**（amd64） | <https://www.debian.org/CD/netinst/> — **自行下载，本仓库不提供镜像** |
| **写盘工具 Rufus** | <https://rufus.ie/> — 分区类型选 **GPT**、目标系统选 **UEFI（非 CSM）** |
| **latte 专用内核** `linux-image-6.14.0_*.deb` | **本仓库 Releases**（也可见上游 [linux_latte](https://github.com/xiaomi-latte-dev/linux_latte) releases） |
| **WiFi 固件** `firmware-brcm80211_*.deb` | **本仓库 Releases** |
| **杂项固件** `firmware-misc-nonfree_*.deb` | **本仓库 Releases** |
| **音频 UCM 配置** | 本仓库 [`ucm/`](ucm/) 目录（Cherry Trail + RT5659 用） |
| U 盘 | ≥ 4 GB |
| **USB 键盘** | **必需**。BIOS 操作和安装过程都要用（BIOS 里也能用音量键 + 电源键操作，但很别扭） |

> **为什么内核和固件要单独发？**
> Debian 自带的 amd64 内核在这台机器上显卡、触屏、指示灯都驱动不起来；
> 社区维护的 latte 内核从 **6.14** 起这些才基本完善。
> Broadcom BCM4356 的 WiFi 固件同理，缺了就是没有无线网。
> 这两个文件散落在论坛和上游 release 里，容易失效，所以在本仓库 Releases 做一份镜像。

**校验下载文件**（与 Releases 附带的 `SHA256SUMS.txt` 对照）：

```bash
sha256sum -c SHA256SUMS.txt
```

---

## 三、刷机流程

完整版见 **[docs/米Pad2-Debian安装指南.md](docs/米Pad2-Debian安装指南.md)**（含每一步的截图级细节和排错）。要点如下：

### 1. 关掉安全启动（前提）

进 BIOS 的三种方式：开机按 `F2`；Windows 下「疑难解答 → 高级选项 → UEFI 固件设置」；
MIUI 下进刷机 PE 用「引导配置」工具勾选下次进 BIOS。

BIOS 里把 **`UEFI Secure Boot` 改成 `Disable`**，保存退出。

> 两个已知坑：① 有时关掉后又自己变回 Enable，重进再关一次；
> ② 走过官方刷机流程或恢复出厂后 BIOS 会被重置，安全启动又回 Enable。

### 2. 制作启动盘

用 Rufus 以 **GPT + UEFI（非 CSM）** 方式写入 Debian netinst ISO。
如果 BIOS 里看不到 U 盘，基本就是这一步选错了模式。

### 3. 从 U 盘启动并安装

`F2` → `Boot Manager` → 选 `EFI USB Device`。

**分区是本机最大的坑**：建议手动分区，EFI 系统分区（ESP）给 512 MB 以上。
如果已经用了「整个磁盘」自动分区，也能用，但 ESP 偏小时后面放兜底引导文件要留意空间。

软件选择里**不要勾桌面环境**，先装基础系统 —— 装完再按需装轻量桌面（见第 5 节）。

### 4. 首次启动：换上 latte 专用内核（关键一步）

```bash
sudo dpkg -i linux-image-6.14.0_*.deb
sudo update-grub
```

重启时在 GRUB「高级选项」里选新内核，**确认能正常进系统之后**再删掉官方内核：

```bash
sudo apt remove linux-image-amd64
```

新内核起来后把 `nomodeset` 去掉（留着反而没有显卡加速）：

```bash
sudo sed -i 's/ nomodeset//' /etc/default/grub && sudo update-grub
```

### 5. 驱动与桌面

```bash
# WiFi（Broadcom BCM4356）
sudo dpkg -i firmware-brcm80211_*.deb firmware-misc-nonfree_*.deb

# 音频（Cherry Trail + RT5659）—— 把本仓库 ucm/ 里的文件对应拷进去
sudo cp -r ucm/* /usr/share/alsa/ucm2/

# 桌面：Atom 带不动 GNOME/KDE，建议轻量
sudo apt install phosh-core     # 触屏友好
# 或
sudo apt install xfce4 lxqt
```

### 6. 装完进不去系统？（最常见）

根因就是前面说的 **固件不写 NVRAM**，所以 BIOS 的启动项列表里没有 Debian。

最省事的解法 —— 在 ESP 里放一份 UEFI 规范的**默认兜底引导文件**：

```bash
# 在安装器的救援 shell，或已能进系统时执行
sudo mkdir -p /boot/efi/EFI/BOOT
sudo cp /boot/efi/EFI/debian/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
```

UEFI 规范要求固件在找不到启动变量时扫描 `\EFI\BOOT\BOOTX64.EFI`，
所以这份副本能被固件自动找到，通常这一步就能直接开机。

> 安装器里如果 GRUB 安装失败、或 `partprobe` 卡住、或装完是 `LEGACY` 而不是 `UEFI`，
> 都看指南的**附录 A**，里面有按顺序走的排错流程和手动 chroot 修法。

---

## 四、目录内容

| 路径 | 内容 |
|---|---|
| [`docs/米Pad2-Debian安装指南.md`](docs/米Pad2-Debian安装指南.md) | 完整安装指南：准备 → BIOS → 分区 → 内核 → 驱动 → 排错附录 → 重装清单 |
| [`scripts/mipad2-setup.sh`](scripts/mipad2-setup.sh) | 装完系统后的一键初始化脚本（换源、装基础工具、开 SSH 等） |
| [`ucm/`](ucm/) | Cherry Trail + RT5659 的 ALSA UCM 音频配置 |
| **Releases** | latte 专用内核、WiFi 固件、杂项固件 |

---

## 五、已知限制（心里先有数）

- **基本可用**：屏幕、触摸屏、3D 加速、WiFi、蓝牙、电池、亮度/重力/霍尔传感器
- **部分可用**：音频、摄像头（前摄 OV5693 在 6.14 下可用）、USB OTG
- **不完善**：后摄、部分传感器、耳机、电源管理（续航一般）
- **性能**：Atom x5-Z8500 单核是主要瓶颈，4 GB 内存够用；
  不少人最后只装基础系统当无头小服务器用。

---

## 六、参考与致谢

- latte 内核：<https://github.com/xiaomi-latte-dev/linux_latte>（原 `Qs315490/linux_latte`）
- postmarketOS wiki：<https://wiki.postmarketos.org/wiki/Xiaomi_Pad_2_(xiaomi_latte)>
- 相关讨论帖：<https://community.wvbtech.com/d/4404> ·
  <https://bbs.deepin.org.cn/post/276932> ·
  <https://xdaforums.com/t/xiaomi-mi-pad-2-linux-kernel-5-15.4533689/>

---

## 七、关于隐私

本仓库**不含任何设备内网 IP、密码或凭据**。
指南附录里出现的 `192.168.42.x` 是**安卓 USB 网络共享的标准网段**（文档示例），不是某一台设备的地址。
