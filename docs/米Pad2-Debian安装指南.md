# 小米平板 2（Mi Pad 2 / latte）安装 Debian 指南

> 机器代号 `latte`，Intel Atom x5-Z8500（Cherry Trail 平台），**无 microSD 卡槽**。
>
> **本文按「4GB RAM + 128GB eMMC」的魔改版写。** 原厂版本是 2GB + 16/64GB，
> 硬盘空间会明显紧张，其余步骤完全一致。
> 因为它是一台带完整 UEFI BIOS 的 x86_64 设备，装 Debian 的逻辑和给普通电脑装系统一样，
> 真正的难点是 Cherry Trail 的驱动很烂，需要装完后手动换社区维护的 `latte` 内核。

---

## 一、动手前先明确几件事

| 项目 | 情况 |
|---|---|
| 启动方式 | 标准 UEFI（百敖 BIOS），可从 U 盘引导 |
| 安全启动 | 默认开启，**必须关掉**才能引导第三方 U 盘 |
| 系统装在哪 | 只能装 eMMC（没有 SD 卡槽）。4+128 魔改版空间充裕，原厂 16GB 版则很紧张 |
| 性能预期 | Atom x5-Z8500 单核性能偏弱。4GB 内存能跑桌面，但还是轻量桌面更舒服；也有人纯当无头服务器用 |
| 变砖风险 | 很低。BIOS 和 fastboot 都还在，随时能刷回官方 MIUI / Win10 包 |

### 关于 4+128 魔改版

- 这是第三方改机版本（原厂只有 2+16 / 2+64），官方系统很早就停在 MIUI 9 / Android 5.1
- **128GB 空间完全够用**，可以放心装完整桌面 + 开发工具，不用像 16GB 版那样精打细算
- 社区里成功装上 Debian sid 的案例正是 4+128 版，参考价值最高
- 魔改版（以及刷过 Win10 的机器）分区表常被改过。但 UEFI 引导只认 ESP，
  **用「整个磁盘」自动分区并不致命**，详见 5.3 末尾的说明

**动手前先把原系统数据备份掉**，因为后面要删掉全部分区。

---

## 二、需要准备的硬件

1. **Type-C 扩展坞（带 PD 供电口）** —— 这是最关键的一件。
   米板 2 只有一个 Type-C 口，安装过程要几十分钟，边装边耗电会中途没电；而且安装需要键盘输入。
   注意：直接插一个「OTG 转接线 + U 盘 + 键盘」往往同时充不了电，**必须用带外接供电的扩展坞**。
2. **USB 键盘**（安装过程必须用，BIOS 里也好操作）
3. **U 盘**，≥8GB（16GB 更稳），建议 USB 2.0 的杂牌 U 盘反而兼容性更好
4. （可选）USB 鼠标，装完桌面后很好用

---

## 三、关闭安全启动（装系统的前提）

小米平板 2 用的是百敖（Byosoft）UEFI BIOS，菜单层级比较深。
安全启动不关掉，第三方 U 盘根本不会出现在启动列表里。

### 3.1 三种进 BIOS 的方式

**方式 A：接 USB 键盘按 F2（推荐）**
接好扩展坞和键盘，开机后**连续点按 `F2`**（不是长按）。

**方式 B：从系统里绕进去（手上没有键盘时）**
- Windows 10 版：设置 → 更新和安全 → 恢复 → 高级启动「立即重新启动」
  → 疑难解答 → 高级选项 → **UEFI 固件设置** → 重启
- MIUI 版：进入刷机 PE，桌面有个「引导配置」工具，勾选
  **「下次重启时进入 UEFI BIOS 设置界面」**，确定后重启即进 BIOS；
  PE 里还有「虚拟键盘」可以拿来操作

> 有些 Intel 平板可以「按住音量上 + 电源」进 Setup，米板 2 上不保证有效，接键盘最稳。

### 3.2 BIOS 里的操作路径

```
BIOS 主菜单
 └─ Device Manager
     └─ System Setup
         └─ Boot
             ├─ UEFI Secure Boot : Enable  →  改成 Disable
             └─ BOM Config       :        →  设为 Windows
```

1. 进入 `Device Manager`
2. 选 `System Setup`
3. 选 `Boot`
4. 选中 `UEFI Secure Boot`，回车，选 `Disable`
5. （如有）把 `BOM Config` 设为 `Windows`，对后续引导兼容性有帮助
6. 长按 `音量+` 返回上一级菜单
7. 选 **`Commit Changes and Exit`**，电源键确认 → 平板自动重启

> **BIOS 内部没有键盘也能操作：** 音量 +/− 移动光标，电源键确认，
> 长按音量 + 返回上一级。

### 3.3 怎么确认关成功了

重启后按 `F2` 进 BIOS → `Boot Manager`，正常情况下能看到 **`EFI USB Device`** 之类的条目。
如果只列出内建存储、看不到 U 盘，说明安全启动没关掉，或者 U 盘不是 UEFI 格式
（用 Rufus 以 GPT + UEFI 方式重写一遍）。

### 3.4 两个已知的坑

1. **关掉后一重启又自己变回 Enable。** 有人遇到过，可能是 BIOS 版本问题。
   重新进 BIOS 再关一次即可；反复出现的话先把 BIOS 升级到最新版再试。
2. **走过官方刷机流程 / 恢复出厂后，BIOS 会被重置。** 安全启动会回到 Enable，
   装系统前记得再确认一次。

---

## 四、制作 Debian 启动盘

- 镜像：**Debian 13（trixie）amd64 netinst ISO**（当前 stable 版本 13.7，2026-09-12 发布）
  - 下载页：https://www.debian.org/CD/netinst/
- 写盘工具：**Rufus**，分区类型选 **GPT**、目标系统选 **UEFI（非 CSM）**；
  或者直接用 **DD 模式**写入（兼容性最好）。
- 也可以偷懒用 **Ventoy**：把 ISO 直接拷进 U 盘即可，社区里有人就是这么装的。

---

## 五、从 U 盘启动并安装

### 5.1 引导

1. 插好 U 盘，开机按 `F2` 进 BIOS，选 `Boot Manager`（或 `Boot Maintenance Manager` → `Boot Options`）
2. 选择 **`EFI USB Device`** 回车
3. 进入 GRUB 菜单后按 `e` 编辑，在内核那行（`linux ...`）末尾**加上 `nomodeset`**，按 `F10` 启动
   - 不加 `nomodeset` 大概率黑屏

### 5.2 安装器里的选择

- **选「文本模式安装」（Text install）**，不要选图形化安装界面
  —— 这块板子跑图形安装器或 Live 桌面极容易卡死（包括 XFCE 的 Live 也进不去）
- 语言、时区、主机名随便填
- 网络：**WiFi 驱动基本是现成的**，能连就尽量连（后面要下载内核）
- root 密码、普通用户按习惯设

### 5.3 分区（最大的坑，重点看）

**强烈建议手动分区，只建两个分区：**

| 分区 | 大小 | 类型 |
|---|---|---|
| `/dev/mmcblk0p1` | 1 GB | EFI System Partition（挂到 `/boot/efi`，FAT32） |
| `/dev/mmcblk0p2` | 剩余全部 | ext4，挂到 `/` |

- **不要用 LVM、不要用全盘加密、不要单独建 swap 分区**（需要用 swap 就装完后加 swapfile）
- 安装器可能卡在这样一行不动：
  ```
  Running command ['partprobe', '/dev/mmcblk0'] with allowed return codes [0]
  ```
  这是 eMMC 在非 AHCI 模式下的已知问题。对策：
  1. 按 `Ctrl+Alt+F2`（或 `Alt+方向键`）切到另一个终端
  2. 执行 `killall partprobe`，或者手动 `partprobe /dev/mmcblk0` 回车
  3. 切回安装器终端继续
- 如果反复卡死，**换 Ubuntu 22.04 / 24.04 的安装器**（见第八节）

#### 已经用了「整个磁盘」自动分区，会有后遗症吗？

**结论：不会变砖。如果你本来就是要整机转 Linux，那连"损失"都谈不上。**

原厂那 13 个 `android_*` 分区对 Linux 用户是纯垃圾，自动分区一次清干净反而是好事。
（只有一种情况需要在意：如果你以后还想在同一个盘上保留 MIUI / Win10 双系统，
那就得手动分区给它们留位置，而且要先备份原分区表。）

为什么擦不坏：

- 米板2 的 UEFI BIOS 和 Intel CSE 都在**芯片固件里，不在 eMMC 上**。
  DNX 模式工作在 CSE Mask ROM 阶段，比 UEFI 还早 ——
  所以**无论怎么擦 eMMC，都还进得去 DNX**。
- 官方线刷流程本来就有「删除所有分区」这一步，之后由刷机包重建 GPT。

原厂 Android 布局是 13 个分区：`android_persistent`、`android_config`、`android_factory`、
`android_misc`、`android_metadata`、`android_bk1`、`android_bootloader`(ESP)、
`android_bootloader2`、`android_boot`、`android_recovery`、`android_system`、
`android_cache`、`android_data`。自动分区会把它们全部清掉并新建 GPT —— 这些你都不需要。

**唯一要留意的后遗症**：原来的 ESP（`android_bootloader`）没了，
Byosoft BIOS 的启动顺序里可能还留着指向它的旧条目，
表现为**开机直接进 BIOS，或者 Boot Manager 里挂着一个失效条目**。

装完系统后检查：

```bash
lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME
sudo efibootmgr -v
ls /boot/efi/EFI/
```

如果开机不直接进 Debian，补一个 UEFI 规范的默认启动文件即可：

```bash
sudo mkdir -p /boot/efi/EFI/BOOT
sudo cp /boot/efi/EFI/debian/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
```

**真想刷回 MIUI / Win10 也做得到**：

1. 关机，按住 `音量+` + `音量-` + `电源键`，直到出现黄色 `DNX FASTBOOT MODE`
2. 用 USB-C 线连到电脑（插主板后置 USB 2.0 口），装 Intel Android 驱动
3. 跑线刷包里的 `DNX_flash_all.bat` —— 它会重建 GPT 并刷回全部分区

这条路永远都在，所以这台机器属于「擦不坏」的类型。


### 5.4 软件选择

- **tasksel 里不要勾选任何桌面环境**（GNOME / KDE / XFCE 全都别勾）
- 保留 `standard system utilities` 和 `SSH server` 即可
- 装好后重启，拔掉 U 盘

#### 如果不小心勾了桌面环境

**不影响后面换内核和驱动**——内核/驱动和桌面是两层独立的东西，换 latte 内核只是装一个 deb 再刷 grub。

但会带来两个真实麻烦：

1. **重启后黑屏。** GNOME 用 Wayland，Wayland 需要 KMS，而你现在必须靠 `nomodeset` 启动，
   恰恰把 KMS 关了 → GDM 起不来。这不是装坏了。
   对策：GRUB 里按 `e`，在内核行加 `systemd.unit=multi-user.target` 走文本模式进系统；
   或者直接按 `Ctrl+Alt+F2` 切到文本终端。
2. **装的时候会很慢。** GNOME 那一整套包很多，在 Atom 上会拖比较久（4+128 版不用担心空间，
   原厂 16GB 版要留意 `df -h /`）。

**正确的处理顺序：先换内核，再换桌面。** 新内核起来之后一切就正常了，然后：

```bash
# 1. 先别让它起图形界面
sudo systemctl set-default multi-user.target

# 2. 卸掉重桌面
sudo apt purge -y task-desktop task-gnome-desktop gnome-core gnome-shell gdm3
sudo apt autoremove --purge -y

# 3. 装轻量的（二选一）
sudo apt install -y phosh-core    # 触屏友好
sudo apt install -y xfce4 lightdm # 传统桌面

# 4. 切回图形启动
sudo systemctl set-default graphical.target
```

不需要为了这个重装系统——重装反而要冒着再撞一次 `partprobe` 卡死的风险。


---

## 六、首次启动与驱动修复

### 6.1 先进得去系统

首次启动仍然要在 GRUB 里加 `nomodeset`（按 `e` 临时改）。
进去之后把它固化：

```bash
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet nomodeset"/' /etc/default/grub
sudo update-grub
```

然后升级一次：

```bash
sudo apt update && sudo apt full-upgrade -y
```

### 6.2 换上 latte 专用内核（关键一步）

社区维护的内核，6.14 起 Cherry Trail 的显卡、触屏、指示灯驱动才基本完善。

- 仓库：<https://github.com/xiaomi-latte-dev/linux_latte>（原 `Qs315490/linux_latte`）
- **Releases 里有编译好的 `.deb`，直接用最省事：**

```bash
# 下载 linux-image-*.deb 后
sudo dpkg -i linux-image-*.deb
sudo update-grub
```

- 想自己编译：

```bash
git clone https://github.com/xiaomi-latte-dev/linux_latte
cd linux_latte
make xiaomipad2_defconfig
make -j$(nproc) deb-pkg
```

- 重启时在 GRUB「高级选项」里选新内核启动，**确认能正常进系统后再**删掉官方内核：

```bash
sudo apt remove linux-image-amd64
```

- 新内核起来后，**把 `nomodeset` 从 grub 里去掉**（留着反而没显卡加速）：

```bash
sudo sed -i 's/ nomodeset//' /etc/default/grub && sudo update-grub
```

### 6.3 WiFi（Broadcom BCM4356）

除了正常的 firmware，还需要一份 NVRAM 配置文件：

- 找到 `brcmfmac4356-pcie.txt`，拷贝到 `/lib/firmware/brcm/`
- 如果新版本 `linux-firmware` 导致网卡认不到，有人通过降级解决：
  从 <https://mirrors.tuna.tsinghua.edu.cn/ubuntu/pool/main/l/linux-firmware/>
  下载 `linux-firmware_1.173.18_all.deb` 安装

### 6.4 音频

Cherry Trail + RT5659 codec，需要仓库里 `fix_file` 目录中的补丁。
也可以在 XDA 帖里找现成的 `brcmfmac4356-pcie.txt` + 音频修复组合。

### 6.5 装桌面

4GB 内存虽然能跑 GNOME / KDE，但 Atom 的 CPU 带不动，**还是建议用轻量桌面**：

```bash
sudo apt install phosh-core      # 触屏友好，社区推荐
# 或者
sudo apt install xfce4 lxqt
```

> 触控优化很差，建议常备蓝牙 / USB 键鼠。

---

## 七、已知限制（心里先有数）

**6.16 内核下基本可用的：** 屏幕、触摸屏、3D 加速、WiFi、蓝牙、电池、亮度/重力/霍尔传感器
**部分可用：** 音频、摄像头（前摄 OV5693 在 6.14 下可用）、USB OTG
**不完善：** 后摄、部分传感器、耳机、电源管理（续航一般）

性能上，Atom x5-Z8500 的单核性能是主要瓶颈，4GB 内存够用；很多人最后还是选择只装基础系统当无头服务器用。

---

## 八、备选方案（如果 Debian 装不下去）

| 方案 | 说明 |
|---|---|
| **Ubuntu 22.04 / 24.04** | XDA 上多人反馈 24.04 开箱即用，只需 GRUB 加 `nomodeset`，屏幕、充电、WiFi 都正常，驱动比 Debian 省心。缺点：安装过程有概率卡在磁盘操作 |
| **deepin 23** | 有人成功运行并修好了 WiFi / 显卡 / 声卡，但触控体验一般 |
| **Arch Linux** | 有人装成功过，但安全启动会被自动重置，折腾成本高 |
| **postmarketOS** | 官方设备页已 archived，需要手动编译内核，不建议新手 |
| **Chrome OS / BlissOS** | 不推荐。Chrome OS 有能开机的版本但 Bug 一堆；BlissOS 驱动不完善、卡顿严重 |

---

## 九、参考资源

- postmarketOS 设备页（硬件支持矩阵最权威）：
  <https://wiki.postmarketos.org/wiki/Xiaomi_Pad_2_(xiaomi-latte)>
- latte 内核仓库：<https://github.com/xiaomi-latte-dev/linux_latte>
- 社区实战记录（Debian sid 全流程）：
  <https://community.wvbtech.com/d/4404>
- deepin 论坛驱动修复过程：
  <https://bbs.deepin.org.cn/post/276932>
- XDA 内核帖（含固件文件）：
  <https://xdaforums.com/t/xiaomi-mi-pad-2-linux-kernel-5-15.4533689/>

---

## 附录 A：安装过程卡住了怎么排错

### A.0 先记住这几个救命操作

**切虚拟终端**（文本模式安装器才有，所以别用图形安装器）：

| 组合键 | 内容 |
|---|---|
| `Ctrl+Alt+F1` | 安装器界面 |
| `Ctrl+Alt+F2` | shell（可以敲命令） |
| `Ctrl+Alt+F3` | 安装日志 |
| `Ctrl+Alt+F4` | 内核日志 syslog |

**卡住时先切到 F3 / F4**，就能看到它到底停在哪一步，比干等着有用。

**强制重启**：长按电源键 10 秒。
键盘还活着的话可以试 `Alt+SysRq+R E I S U B`（左手按住 Alt+SysRq，右手依次按 R E I S U B）。

### A.1 卡在进入安装器之前

| 现象 | 原因 | 对策 |
|---|---|---|
| 黑屏 / 花屏，机器在转但不显示 | 没加 `nomodeset` | GRUB 按 `e`，内核行末尾加 `nomodeset`，`F10` 启动 |
| 停在 `systemd` 某一行不动 | Cherry Trail 的 ACPI / 电源管理 | 先加 `nomodeset`；还不行再试 `acpi=off` 或 `intel_idle.max_cstate=2` |
| 选了 U 盘又弹回 BIOS | 安全启动又自动开了 | 重新进 BIOS 关掉，保存退出后马上继续装 |
| BIOS 里根本看不到 U 盘 | U 盘不是 UEFI 格式 | 用 Rufus 以 GPT + UEFI（非 CSM）重写 |

### A.2 卡在安装器运行中

| 现象 | 原因 | 对策 |
|---|---|---|
| 卡在 `Running command ['partprobe', '/dev/mmcblk0']` | eMMC 不在 AHCI 模式下的已知问题 | 见 A.3 |
| 探测磁盘阶段长时间无响应 | 同上 | 同上 |
| 装软件包阶段死机 / 变得极慢 | 联网下载 + Atom 性能弱，16GB 版还可能是空间不足 | 断网安装，tasksel 只留 `standard system utilities`，装完再配源升级；顺手看一眼 `df -h /` |
| 中途直接关机黑屏 | 电量耗尽 | 必须用带 PD 供电的扩展坞，边装边充电 |
| 安装器莫名跳回第一步 | 内存不足 OOM | 别用图形安装器，别勾任何桌面环境 |

### A.3 `partprobe` 卡住的完整处理流程

1. 按 `Ctrl+Alt+F2` 切到 shell
2. 执行：
   ```bash
   killall partprobe
   # 或者手动跑一次
   partprobe /dev/mmcblk0
   ```
3. 按 `Ctrl+Alt+F1` 切回安装器，看是否继续往下走
4. 如果反复卡，退回分区那一步改成**手动分区**：
   - 只建两个分区：1GB 的 EFI System Partition（FAT32，挂 `/boot/efi`）+ 剩余全部 ext4 挂 `/`
   - **不要** LVM、**不要**加密、**不要**单独建 swap 分区（swap 用 swapfile）
5. 还不行就换 **Ubuntu 22.04 / 24.04 的安装器**——XDA 上多人反馈它做磁盘操作更稳（同样要 `nomodeset`）

### A.4 装完了进不去系统

| 现象 | 原因 | 对策 |
|---|---|---|
| `No bootable device` | ESP 没建对 | 重装，确认 EFI 分区是 FAT32 且挂到 `/boot/efi` |
| 开机直接进 BIOS | 同上，或安全启动又开了 | 先查安全启动，再查 ESP |
| GRUB 选完内核就黑屏 | 缺 `nomodeset` | GRUB 按 `e` 临时加，进系统后写进 `/etc/default/grub` |
| 停在 `grub>` 提示符 | GRUB 找不到配置文件 | 手动引导：<br>`set root=(hd0,gpt2)`<br>`configfile /boot/grub/grub.cfg` |
| 卡在 initramfs | 根分区没找到 | 多半分区表坏了，重装 |

### A.5 提示「GRUB 安装失败」

**先松口气**：GRUB 是安装流程的倒数第二步，报这个错说明**系统本体已经装完了**，
只是引导程序没装上。**不用重装。**

#### 最可能的原因（米板2 上尤其常见）

米板2 的 Byosoft 固件**支持 UEFI 引导，但拒绝写入 NVRAM 中的 UEFI 启动变量**。
Debian Wiki 专门记载过这类固件，典型报错长这样：

```
grub-install: warning: Cannot set EFI variable Boot0000.
grub-install: error: failed to register the EFI boot entry: Read-only file system.
```

也就是说 GRUB 的二进制其实**已经写进 ESP 了**，只是「告诉固件去哪找它」这一步失败。

#### 处理顺序

**第 1 步：安装器追问「是否装到可移动介质路径」时，选「是」**

报错后安装器通常会问：
`Force extra installation to the GRUB EFI removable media path?`
**选「是」** —— 它会改写 `/EFI/BOOT/BOOTX64.EFI`，
这是 UEFI 规范的默认兜底路径，固件在没有 NVRAM 条目时会自动找它。这一步通常就能解决。

**第 2 步：如果安装器只报错、没问你，选「继续」把安装跑完**，然后照下面手动修。

#### 手动修复（安装器里按 `Ctrl+Alt+F2` 切到 shell）

先诊断，看 GRUB 二进制到底写进去没有：

```bash
ls -l /target/boot/efi/EFI/debian/grubx64.efi
ls /target/boot/efi/EFI/
```

**情况一：文件存在** → 只是 NVRAM 没写成，补个兜底文件即可：

```bash
mkdir -p /target/boot/efi/EFI/BOOT
cp /target/boot/efi/EFI/debian/grubx64.efi /target/boot/efi/EFI/BOOT/BOOTX64.EFI
```

**情况二：目录空的 / 不存在** → ESP 没挂对，chroot 进去重装：

```bash
mount /dev/mmcblk0p1 /target/boot/efi          # 先确认哪个分区是 ESP
mount -o rbind /dev /target/dev
mount -t proc proc /target/proc
mount -t sysfs sys /target/sys
mount -t efivarfs efivarfs /target/sys/firmware/efi/efivars
chroot /target
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=debian --removable
update-grub
exit
```

#### 进系统后的正规做法

```bash
sudo dpkg-reconfigure grub-efi-amd64
```

它会问两个问题，按这个选：

| 问题 | 选 |
|---|---|
| Force extra installation to the GRUB EFI removable media path? | **是** |
| Update NVRAM variables to automatically boot into Debian? | **否** |

或者直接命令行：

```bash
sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=debian --removable
sudo update-grub
```

#### 临时救急：手动从 BIOS 启动

重启进 BIOS → `Boot Manager` → 选硬盘上的 `\EFI\debian\grubx64.efi`，通常能直接进系统。

#### 还要排除一种情况：安装器是用 Legacy/CSM 模式启动的

在安装器 shell 里检查：

```bash
[ -d /sys/firmware/efi ] && echo UEFI || echo LEGACY
```

输出 `LEGACY` 的话，ESP 对 grub 不可见，必须**从 U 盘的 UEFI 项**重新启动安装器再装一遍。

### A.6 装完了但开不了机（没有 GRUB 引导）

系统已经装在 eMMC 上，只是固件里没有能引导它的条目。**不需要重装。**

#### 先试最省事的：进 BIOS 手动选引导文件

重启按 `F2` 进 BIOS → `Boot Manager`，找这几样：

- 有没有 `EFI Hard Drive` / `UEFI OS` / `debian` 之类的条目 → 直接选它
- 有没有「Boot from file」/ 浏览文件的功能 → 找到 `\EFI\debian\grubx64.efi` 选它

只要有一次能进系统，就立刻去把 SSH 开起来，剩下的远程修。

#### 正经修法：从 U 盘进救援模式

1. 插 U 盘，开机 `F2` → `Boot Manager` → `EFI USB Device`
2. 在安装器启动菜单选 **`Advanced options` → `Rescue mode`**
3. 选语言、键盘 → 它会扫描磁盘 → 选择根分区（一般是 **`/dev/mmcblk0p2`**）→ 挂载
4. 救援菜单里选 **`Force GRUB installation to the EFI removable media path`**
   （Debian 官方文档明确说明这个选项就是给「装完起不来」准备的）
5. 如果菜单里没有这一项，选 `Execute a shell in /dev/mmcblk0p2`，然后：
   ```bash
   grub-install --no-nvram --force-extra-removable
   update-grub
   exit
   ```
6. 重启

#### 如果救援模式自动挂载也失败，手动 chroot

在安装器/救援的 shell 里：

```bash
lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME        # 先确认哪个是 ESP、哪个是根

mount /dev/mmcblk0p2 /mnt
mount /dev/mmcblk0p1 /mnt/boot/efi
for d in dev proc sys; do mount --rbind /$d /mnt/$d; done
mount -t efivarfs efivarfs /mnt/sys/firmware/efi/efivars

chroot /mnt
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=debian --no-nvram --force-extra-removable
update-grub
exit

umount -R /mnt
reboot
```

#### 最快的一条野路子（Debian 官方文档也认可）

如果 ESP 里**已经有** `\EFI\debian\grubx64.efi`（说明 grub 二进制写成功了，只差兜底副本），
那么只需要复制一个文件：

```bash
mount /dev/mmcblk0p1 /mnt
ls /mnt/EFI/debian/          # 确认 grubx64.efi 在
mkdir -p /mnt/EFI/BOOT
cp /mnt/EFI/debian/grubx64.efi /mnt/EFI/BOOT/BOOTX64.EFI
umount /mnt
reboot
```

UEFI 规范要求固件在找不到 NVRAM 条目时扫描 `/EFI/BOOT/BOOTX64.EFI`，所以这个副本能直接启动。

#### 进系统后必做的一步（重要）

```bash
sudo dpkg-reconfigure grub-efi-amd64
```

两个问题这样选：

| 问题 | 选 |
|---|---|
| Force extra installation to the GRUB EFI removable media path? | **是** |
| Update NVRAM variables to automatically boot into Debian? | **否** |

**别跳过这一步。** 如果不重新配置，将来 grub 升级时不会同步更新 removable media path 里的那份副本，
系统可能在某次升级后突然又起不来。



---

## 附录 B：换成 Arch 会怎样？

**结论：能用，而且 latte 内核的作者本人就在用 Arch；但这台机器上有几个 Arch 特有的硬坑，不建议现在换。**

### Arch 的优势

- latte 内核作者 Qs315490 本身就是 Arch 用户，release 里直接提供
  `linux-upstream-*-x86_64.pkg.tar.zst`，**驱动跟进最快的就是 Arch**
- 滚动更新，主线的 Cherry Trail 修复拿到最快
- 没有预装桌面的负担

### Arch 在这台机器上的坑

| 坑 | 说明 | 绕法 |
|---|---|---|
| **Archiso 可能根本起不来** | 同款 x5-Z8500 的 Kangaroo Mini-Computer 有明确记录：UEFI 认到 U 盘、进了引导菜单，一按键就冻死。而 Debian / Ubuntu / Mint 的 live ISO 全部正常 —— 差别在于 Arch 用 systemd-boot | 改用 GRUB 引导的 Arch 介质；或先用 Debian live 启动再 `arch-chroot` 安装 |
| **systemd-boot 不兼容** | 同上，`bootctl` 在这类固件上不工作 | 用 GRUB |
| **genfstab 的 UUID 引导失败** | 生成后按 UUID 挂载会起不来 | 手动改成 `/dev/mmcblk0p1` |
| **设备名只有 `mmcblk0`** | 没有 `/dev/sda` / `/dev/sdb` | 别照抄普通 PC 的教程 |
| **触屏有 Arch 特有的卡死** | 触摸事件响应极慢、卡死当前程序甚至整个界面（内核作者本人标注为 arch 特有） | `modprobe -r i2c-hid-acpi && modprobe i2c-hid-acpi`，或重载 `hid_multitouch` |
| **安全启动会被重置回 Enable** | 有人装 Arch 时遇到 | 进 BIOS 再关一次 |
| **GNOME 下要关 Wayland 才有硬件加速** | 与前文 nomodeset 问题同源 | 用 Xorg 会话，或直接换轻量桌面 |

### 换系统的真实成本

Debian 和 Arch **不能互相就地转换**，想换必须重装 ——
意味着要再赌一次 `partprobe` 卡死，以及重新走一遍本文档第五、六节。

### 建议

- **没有非 Arch 不可的理由 → 留在 Debian。** 这台机器上 Debian 的优势是实的：
  社区最详细的实战记录是 Debian 的，内核作者同时提供 `.deb`，而且你已经装到这一步了
- **就是想要 Arch → 别用官方 ISO 直装**，走这条路（已被 x5-Z8500 用户验证可行）：
  Debian / Ubuntu live U 盘启动 → 挂载目标分区 → `arch-chroot` 安装 → 引导用 GRUB
- **128GB 空间足够双系统**：可以先让 Debian 跑起来，之后在剩余空间划一个分区装 Arch，
  用 GRUB 统一引导。两条路都留着，不用二选一

---

# 附录 C：重装避坑清单（第二次装必读）

> 本节是在「第一次装完，系统能起来但 WiFi 用不了、SSH 没有、桌面黑屏」之后总结的。
> **第二次装，照着这张表勾选，装完即可直接用。**
> 第一次踩过的坑按严重程度排列如下。

## C.1 第一次装的四个坑

| # | 现象 | 根因 | 重装时的对策 |
|---|---|---|---|
| 1 | WiFi 起不来 | `/lib/firmware/brcm/brcmfmac4356-pcie.bin` 缺失（`dmesg` 报 `Direct firmware load ... failed with error -2`）。安装时没启用 non-free firmware 仓库 | 软件源步骤选 **Enable non-free firmware = Yes** |
| 2 | 没有 `dhclient` / `nmcli` / `killall` / `iw` | 装系统时软件选择太精简 | 软件选择勾 **standard system utilities** |
| 3 | 装完无法远程登录 | 没装 openssh-server | 软件选择勾 **SSH server** |
| 4 | 图形界面黑屏 | 装了 GNOME（Wayland）+ 无 `nomodeset` / 显卡驱动不匹配 | 软件选择**一律不勾桌面**，装完再手动装轻量桌面 |

外加一个偶发问题：

| 现象 | 说明 | 对策 |
|---|---|---|
| 启动时掉进 `(initramfs)`，报 `UUID=xxx does not exist` | Cherry Trail eMMC 上电时序问题，偶发认不到根分区 | 直接输 `exit` 重试，或重启一次；稳定后加 `rootdelay=10` |

## C.2 重装操作清单（逐步勾选）

### 准备
- [ ] Type-C 扩展坞（带 PD 供电）+ USB 键盘
- [ ] U 盘（≥8GB），烧好 Debian 12 netinst（含 non-free firmware 的版本更好）
- [ ] 平板电量 ≥ 50%，最好一直插着供电

### 启动与安装
- [ ] 关安全启动（BIOS → Security → Secure Boot = Disabled）
- [ ] U 盘启动，选 **Install**（不是 graphical install 也行，文字版更稳）

### 关键选择点（★ 是绝对不能选错的）

| 步骤 | 必须怎么选 |
|---|---|
| 主机名 | `mipad2` |
| 域名 | 留空 |
| root 密码 | 设一个记得住的，后面还要用 |
| 普通用户 | 可建可 *跳过*（建了也行） |
| 分区 | **使用整个磁盘 → 所有文件在一个分区**（整机装 Linux，自动分区无损失）<br>⚠️ 卡在 `partprobe` 就等 2 分钟，或 `Ctrl+Alt+F2` 进 shell `partprobe; exit` |
| ★ 软件源 | 选国内镜像（清华 TUNA / 阿里）<br>**★ Enable non-free firmware → Yes** |
| ★ 软件选择 | `[x] SSH server`<br>`[x] standard system utilities`<br>`[ ]` 其他**全部不勾**（尤其不勾任何桌面） |
| ★ GRUB 安装位置 | 装到主引导记录（MBR/主分区）即可<br>**★ 追问 "Force GRUB installation to the EFI removable media path?" → 选 `是 / Yes`**<br>这是绕开本机固件不写 NVRAM 的关键 |
| 完成安装 | 拔 U 盘，重启 |

> 如果 GRUB 那步**没有**出现 removable path 的追问，且装完起不来，就按附录 A.6
> 手动把 `grubx64.efi` 拷成 `/boot/efi/EFI/BOOT/BOOTX64.EFI`。

### 装完首次启动后，在平板上执行

```bash
su -
# 1. 确认 WiFi 固件在
ls /lib/firmware/brcm/ | grep 4356          # 应有 brcmfmac4356-pcie.bin / .txt

# 2. 开 SSH
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl enable --now ssh
ss -tlnp | grep :22                          # 应看到 LISTEN

# 3. 看 IP
ip a | grep inet
```

拿到 **IP + root 密码**，即可从局域网另一台机器 SSH 接管，后续全部远程完成。

## C.3 接管后的操作顺序（重要：顺序不能反）

```
① 先联网（WiFi 通了才能 apt）
② apt full-upgrade
③ 装 latte 专用内核（.deb）—— 修显卡 / 触屏 / WiFi / 蓝牙
④ 从 GitHub release 取 WiFi 蓝牙固件（brcmfmac4356-pcie.* / BCM4356A2.hcd）
⑤ 从 GRUB 参数里去掉 nomodeset
⑥ 卸载 linux-image-amd64（防止新内核被覆盖）
⑦ 最后装轻量桌面（XFCE / LXQt）
```

**顺序不能反的原因**：桌面必须等新内核上了再装。若先装桌面（尤其 GNOME），
在 `nomodeset` 状态下会黑屏；而 `nomodeset` 又要等新内核才能在显卡上正常工作。
详见本文档第六节与附录 A.6。

## C.4 备选：USB 网络共享（重装前的救急法）

如果不想重装、只想把现有系统救活，可用手机 USB 共享网络让平板临时上网：

```bash
# 1. 手机开「USB 网络共享」，插到平板
# 2. 平板上找 USB 网卡（通常是 enp0s20u1 / usb0 / enx...）
ip link
# 3. 拉起来
ip link set enp0s20u1 up
# 4. 安卓 USB 共享的 IPv4 网段通常是 192.168.42.x
ip addr add 192.168.42.100/24 dev enp0s20u1
ip route add default via 192.168.42.129
# 5. 测试
ping -c 3 192.168.42.129
# 6. 通了就装固件
apt update && apt install -y firmware-brcm80211 firmware-misc-nonfree wpasupplicant isc-dhcp-client
```

> 注意：USB 共享只给 IPv6 地址是常见现象，此时 IPv4 需要**手动**配。
> 判断链路是否真的通，看 `/sys/class/net/<网卡>/carrier` 是否为 `1`。

