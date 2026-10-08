#!/usr/bin/env bash
#
# mipad2-setup.sh — 小米平板2 (latte / Intel x5-Z8500) Debian 后置配置
#
# 用法（在平板上，除 --check 外都需要 root）：
#   sudo bash mipad2-setup.sh --check                  # 只看系统状态，不做任何改动
#   sudo bash mipad2-setup.sh --from-dir ./latte-files # 一键装本地已下载的 Release 文件
#   sudo bash mipad2-setup.sh --fix-grub               # 重装 GRUB 到 UEFI 兜底路径
#   sudo bash mipad2-setup.sh --phase1                 # 升级系统 + 装 latte 内核，然后重启
#   sudo bash mipad2-setup.sh --phase2 --desktop phosh # 收尾 + 装轻量桌面
#
# 设计成幂等的：重复跑不会把系统搞坏。
#
set -uo pipefail

usage() { sed -n '2,13p' "$0" | sed 's/^#\s\?//'; }

REPO="xiaomi-latte-dev/linux_latte"
GRUB=/etc/default/grub
DEB_DEFAULT_KERNEL="linux-image-amd64"
PHASE=""
DESKTOP="none"
FROM_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check)   PHASE="check" ;;
    --phase1)  PHASE="phase1" ;;
    --phase2)  PHASE="phase2" ;;
    --fix-grub) PHASE="fixgrub" ;;
    --from-dir) PHASE="fromdir"; FROM_DIR="${2:-}"
                [ -n "$FROM_DIR" ] || { echo "用法: --from-dir <放 Release 文件的目录>"; exit 2; }
                shift ;;
    --desktop) DESKTOP="${2:-none}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1（用 --help 看用法）"; exit 2 ;;
  esac
  shift
done

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  [ok] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  [!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m  [x] %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 硬件识别
step "硬件识别"
PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
BOARD="$(cat /sys/class/dmi/id/board_name   2>/dev/null || echo unknown)"
CPU="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //')"
KVER="$(uname -r)"
MEM="$(awk '/MemTotal/{printf "%.1f GB", $2/1048576}' /proc/meminfo)"
DISK="$(lsblk -dno SIZE /dev/mmcblk0 2>/dev/null || echo '未知')"
echo "  product_name : $PRODUCT"
echo "  board_name   : $BOARD"
echo "  CPU          : $CPU"
echo "  内存         : $MEM"
echo "  eMMC 容量    : $DISK"
echo "  当前内核     : $KVER"
echo "  发行版       : $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"

case "$PRODUCT$BOARD" in
  *[Ll]atte*|*MI*PAD*2*|*Mi*Pad*2*) ok "识别为小米平板2" ;;
  *) warn "没有认出 latte 标识，请自行确认机型" ;;
esac

step "网络状态"
ip -4 -o addr show | grep -v ' lo ' | awk '{print "  "$2": "$4}'
if ip route get 1.1.1.1 >/dev/null 2>&1; then
  ok "默认路由正常，能出网"
  GW=$(ip route | awk '/^default/{print $3; exit}')
  echo "  默认网关: $GW"
else
  warn "没有默认路由 —— 先用 nmtui 连上 WiFi 再来"
fi

step "存储布局"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT /dev/mmcblk0 2>/dev/null || warn "读不到 mmcblk0"
[ -d /sys/firmware/efi ] && ok "以 UEFI 模式启动" || warn "不是 UEFI 模式启动"
if [ -f /boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
  ok "UEFI 兜底引导文件已就位"
else
  warn "缺 /boot/efi/EFI/BOOT/BOOTX64.EFI（固件不写 NVRAM 时靠它启动）"
fi

step "驱动现状"
for f in \
  "显卡(i915):lsmod | grep -q '^i915' && echo 已加载 || echo 未加载" \
  "WiFi(brcmfmac):lsmod | grep -q brcmfmac && echo 已加载 || echo 未加载" \
  "WiFi 固件:/lib/firmware/brcm"; do
  name="${f%%:*}"; cmd="${f#*:}"
  if [ "$name" = "WiFi 固件" ]; then
    if [ -e /lib/firmware/brcm/brcmfmac4356-pcie.txt ]; then ok "NVRAM 已就位"; else warn "缺 brcmfmac4356-pcie.txt"; fi
  else
    printf "  %s: %s\n" "$name" "$(eval "$cmd")"
  fi
done
echo "  grub 参数: $(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT' $GRUB 2>/dev/null || echo '读不到')"
echo "  已装内核:"; dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/{print "    "$2" "$3}'

[ "$PHASE" = "check" ] && { step "只做检查，未改动任何东西"; exit 0; }

[ "$(id -u)" -eq 0 ] || die "需要 root：sudo bash $0 $PHASE"

# ---------------------------------------------------------------- grub 工具
ensure_nomodeset() {
  if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=.*nomodeset' "$GRUB"; then
    ok "grub 里已有 nomodeset"
  else
    if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB"; then
      sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT=")([^"]*)"/\1\2 nomodeset"/' "$GRUB"
    else
      echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet nomodeset"' >> "$GRUB"
    fi
    update-grub >/dev/null 2>&1 && ok "已加上 nomodeset"
  fi
}

drop_nomodeset() {
  if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=.*nomodeset' "$GRUB"; then
    sed -i -E 's/ ?\bnomodeset\b//g' "$GRUB"
    update-grub >/dev/null 2>&1 && ok "已移除 nomodeset（latte 内核不需要它了）"
  else
    ok "grub 里本来就没有 nomodeset"
  fi
}

backup_grub() {
  cp -a "$GRUB" "$GRUB.bak.$(date +%Y%m%d%H%M%S)" && ok "已备份 $GRUB"
}

# ---------------------------------------------------------------- fix-grub
if [ "$PHASE" = "fixgrub" ]; then
  step "F1 当前引导状态"
  [ -d /sys/firmware/efi ] && ok "当前是 UEFI 模式启动" || warn "当前不是 UEFI 模式！先解决这个"
  ls -l /boot/efi/EFI/debian/grubx64.efi 2>/dev/null || warn "缺 /boot/efi/EFI/debian/grubx64.efi"
  ls -l /boot/efi/EFI/BOOT/BOOTX64.EFI  2>/dev/null || warn "缺 /boot/efi/EFI/BOOT/BOOTX64.EFI"

  step "F2 重装 GRUB（不写 NVRAM，强制装到兜底路径）"
  install -d /boot/efi/EFI/BOOT
  if grub-install --target=x86_64-efi --efi-directory=/boot/efi \
      --bootloader-id=debian --no-nvram --force-extra-removable; then
    ok "grub-install 成功"
  else
    warn "grub-install 报错，看上面输出；可能是 /boot/efi 没挂上"
  fi

  step "F3 重新生成引导配置"
  update-grub >/dev/null 2>&1 && ok "update-grub 完成" || warn "update-grub 失败"

  step "F4 结果"
  ls -l /boot/efi/EFI/debian/ /boot/efi/EFI/BOOT/ 2>/dev/null
  cat <<'EOF'

──────────────────────────────────────────────
 固件找不到 NVRAM 条目时会扫描 /EFI/BOOT/BOOTX64.EFI，
 所以上面这个文件存在就应该能开机。

 建议：sudo dpkg-reconfigure grub-efi-amd64
   Force extra installation to the removable media path? → 是
   Update NVRAM variables to automatically boot into Debian? → 否
 否则将来 grub 升级不会同步这份副本。
──────────────────────────────────────────────
EOF
  exit 0
fi

# ---------------------------------------------------------------- from-dir
# 一键安装「已下载好的 Release 关键文件」：校验 → 装内核/固件 → 装音频 UCM → 刷引导
if [ "$PHASE" = "fromdir" ]; then
  step "D1 检查目录：$FROM_DIR"
  [ -d "$FROM_DIR" ] || die "目录不存在：$FROM_DIR"
  cd "$FROM_DIR" || die "进不去 $FROM_DIR"
  echo "  $(pwd)"

  step "D2 校验下载文件"
  if [ -f SHA256SUMS.txt ]; then
    # 只校验目录里确实存在的文件 —— 有人可能只下 .deb，不下 ucm.zip
    SUMFILE="$(mktemp)"
    present=0; missing=0
    while read -r sum name; do
      f="${name#\*}"
      if [ -f "$f" ]; then
        printf '%s  %s\n' "$sum" "$f" >> "$SUMFILE"
        present=$((present + 1))
      else
        missing=$((missing + 1))
      fi
    done < SHA256SUMS.txt
    if [ "$present" -gt 0 ]; then
      if sha256sum -c "$SUMFILE"; then ok "校验通过（$present 个文件）"
      else rm -f "$SUMFILE"; die "校验失败：文件损坏或没下完，重新下载后再试"; fi
    else
      warn "SHA256SUMS.txt 里列出的文件，目录里一个都没有"
    fi
    [ "$missing" -gt 0 ] && warn "还有 $missing 个文件没下载，对应步骤会跳过"
    rm -f "$SUMFILE"
  else
    warn "目录里没有 SHA256SUMS.txt，跳过校验"
  fi

  step "D3 补 UEFI 兜底引导文件"
  if [ -f /boot/efi/EFI/debian/grubx64.efi ] && [ ! -f /boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
    mkdir -p /boot/efi/EFI/BOOT
    cp /boot/efi/EFI/debian/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI \
      && ok "已补上 /EFI/BOOT/BOOTX64.EFI（绕过固件不写 NVRAM）"
  elif [ -f /boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
    ok "兜底引导文件已在位"
  else
    warn "找不到 /boot/efi/EFI/debian/grubx64.efi —— 先按指南附录 A.5 处理"
  fi

  step "D4 安装内核与固件（.deb）"
  deb_found=0
  for f in *.deb; do
    [ -e "$f" ] || continue
    echo "  dpkg -i $f"
    dpkg -i "$f" || apt-get -y -f install || warn "$f 安装有报错，看一下上面的输出"
    deb_found=1
  done
  [ "$deb_found" = 1 ] && ok "已安装 .deb" || warn "目录里没有 .deb"

  step "D5 安装音频 UCM 配置"
  if [ -f latte-ucm.zip ]; then
    TMPU="$(mktemp -d)"; trap 'rm -rf "$TMPU"' EXIT
    if unzip -q -o latte-ucm.zip -d "$TMPU"; then
      cp -r "$TMPU"/latte-ucm/. /usr/share/alsa/ucm2/ && ok "UCM 已装入 /usr/share/alsa/ucm2/"
    else
      warn "解压 latte-ucm.zip 失败"
    fi
  elif [ -d latte-ucm ]; then
    cp -r latte-ucm/. /usr/share/alsa/ucm2/ && ok "UCM 已装入 /usr/share/alsa/ucm2/"
  else
    warn "没找到 latte-ucm.zip 或 latte-ucm/ 目录，跳过（音频可能没声音）"
  fi

  step "D6 刷新引导"
  update-grub >/dev/null 2>&1 && ok "grub 已更新" || warn "update-grub 失败"

  step "D7 结果"
  echo "  已装内核:"; dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/{print "    "$2" "$3}'
  echo "  grub 参数: $(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT' $GRUB 2>/dev/null)"

  cat <<'EOF'

──────────────────────────────────────────────
 装完了，接下来按顺序做：

   1) sudo reboot
   2) 在 GRUB「高级选项」里选新装的 6.14 内核启动
      （默认项可能还是发行版内核）
   3) 确认能正常进系统、显卡与触屏可用后，再删掉发行版内核
      并去掉 nomodeset：
        sudo bash mipad2-setup.sh --phase2

 起不来就在 GRUB 里按 e，把 nomodeset 加回去应急。
──────────────────────────────────────────────
EOF
  exit 0
fi

# ---------------------------------------------------------------- phase 1
if [ "$PHASE" = "phase1" ]; then
  step "P1-0 确保有 UEFI 兜底引导文件"
  if [ -f /boot/efi/EFI/debian/grubx64.efi ]; then
    if [ -f /boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
      ok "/EFI/BOOT/BOOTX64.EFI 已存在"
    else
      mkdir -p /boot/efi/EFI/BOOT
      cp /boot/efi/EFI/debian/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI \
        && ok "已补上 /EFI/BOOT/BOOTX64.EFI（绕过固件不写 NVRAM 的问题）"
    fi
  else
    warn "找不到 /boot/efi/EFI/debian/grubx64.efi —— GRUB 可能压根没装成"
    warn "先按指南附录 A.5 处理，再回来跑本脚本"
  fi

  step "P1-1 备份 grub 配置"
  backup_grub

  step "P1-2 升级系统"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update || die "apt update 失败，先检查网络"
  apt-get -y full-upgrade || warn "full-upgrade 有报错，继续"
  ok "升级完成"

  step "P1-3 确保 nomodeset（新内核启动前必须留着）"
  ensure_nomodeset

  step "P1-4 下载 latte 专用内核"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  API="https://api.github.com/repos/$REPO/releases/latest"
  curl -fsSL "$API" -o "$TMP/rel.json" || die "拉取 release 失败"
  TAG="$(grep -o '"tag_name": *"[^"]*"' "$TMP/rel.json" | head -1 | sed 's/.*: *"//; s/"$//')"
  ok "最新 release: $TAG"

  # 只取真正需要的：内核 / 头文件 / libc-dev 的 .deb，以及固件 .txt。
  # 必须排掉 -dbg（约 146 MB）、linux-upstream-* 与 .zst（约 229 MB）：
  # 平板的 /tmp 是 tmpfs（直接吃内存），下几百 MB 会把机器拖垮甚至 OOM。
  mapfile -t URLS < <(grep -o 'https://[^"]*' "$TMP/rel.json" \
    | grep -E '\.(deb|txt)$' \
    | grep -vE -- '-dbg|linux-upstream' | sort -u)
  [ "${#URLS[@]}" -gt 0 ] || die "release 里没找到可下载文件"
  echo "  发现 ${#URLS[@]} 个附件（已跳过 -dbg / .zst / linux-upstream 大包）"

  for u in "${URLS[@]}"; do
    f="$TMP/$(basename "$u")"
    printf "  下载 %s ... " "$(basename "$u")"
    if curl -fsSL "$u" -o "$f"; then echo "完成"; else echo "失败，跳过"; continue; fi
    case "$f" in
      *.deb) dpkg -i "$f" || apt-get -y -f install ;;
      *.txt) install -o root -g root -m 644 "$f" /lib/firmware/brcm/ && ok "固件 $(basename "$f") 已放入 /lib/firmware/brcm/" ;;
      *.zst) echo "  (arch 包，跳过)" ;;
    esac
  done

  step "P1-5 刷新引导"
  update-grub >/dev/null 2>&1 && ok "grub 已更新"

  step "P1-6 让下次启动走文本模式（避开 GDM/Wayland 黑屏）"
  if systemctl set-default multi-user.target >/dev/null 2>&1; then
    ok "已设为 multi-user.target，重启后直接进文本控制台"
    warn "等你换完桌面的 phase2 会自动切回 graphical.target"
  else
    warn "设置失败，重启后黑屏的话按 Ctrl+Alt+F2 切终端"
  fi

  cat <<'EOF'

──────────────────────────────────────────────
 Phase 1 完成。现在：

   1) sudo reboot
   2) 开机在 GRUB 里选「高级选项」→ 新装的 6.14 内核
      （不选的话默认项可能还是旧内核）
   3) 重启后是文本登录界面，这是正常的，用你的用户名密码登进去
   4) 然后跑：sudo bash mipad2-setup.sh --phase2 --desktop phosh
──────────────────────────────────────────────
EOF
  exit 0
fi

# ---------------------------------------------------------------- phase 2
if [ "$PHASE" = "phase2" ]; then
  step "P2-1 确认当前跑的是新内核"
  echo "  uname -r = $(uname -r)"
  if dpkg -l "$DEB_DEFAULT_KERNEL" >/dev/null 2>&1 && [ "$(uname -r)" = "$(dpkg -l "$DEB_DEFAULT_KERNEL" | awk '/^ii/{print $3}' | sed 's/.*-//')" ]; then
    warn "看起来还在跑发行版自带内核，先重启并在 GRUB 里选新内核"
  else
    ok "当前不是发行版自带内核，继续"
  fi

  step "P2-2 去掉 nomodeset"
  backup_grub
  drop_nomodeset

  step "P2-3 WiFi 固件补齐"
  if [ -e /lib/firmware/brcm/brcmfmac4356-pcie.txt ]; then
    ok "NVRAM 已在位"
  else
    warn "缺 brcmfmac4356-pcie.txt，需要从内核 release 或 XDA 帖里取"
  fi

  step "P2-4 卸载发行版内核（保留正在跑的）"
  RUNNING_IMG="linux-image-$(uname -r)"
  if dpkg -l "$DEB_DEFAULT_KERNEL" >/dev/null 2>&1; then
    if [ "$RUNNING_IMG" != "$DEB_DEFAULT_KERNEL" ]; then
      apt-get -y purge "$DEB_DEFAULT_KERNEL" && ok "已移除 $DEB_DEFAULT_KERNEL"
    else
      warn "正在跑的就是它，先别删"
    fi
  else
    ok "本来就没装 $DEB_DEFAULT_KERNEL"
  fi

  step "P2-5 桌面环境"
  export DEBIAN_FRONTEND=noninteractive

  if [ "$DESKTOP" != "none" ]; then
    echo "  先检查有没有装 GNOME / KDE 这类重桌面..."
    HEAVY=""
    for p in task-desktop task-gnome-desktop gnome-core gnome-shell gdm3 \
             task-kde-desktop kde-plasma-desktop sddm gnome-shell-extension-common; do
      dpkg -l "$p" 2>/dev/null | grep -q '^ii' && HEAVY="$HEAVY $p"
    done
    if [ -n "$HEAVY" ]; then
      warn "发现:$HEAVY"
      echo "  正在卸载：Atom 的 CPU 带不动 GNOME，换轻量桌面更顺"
      apt-get -y purge $HEAVY >/dev/null 2>&1 || warn "purge 有报错，继续"
      apt-get -y autoremove --purge >/dev/null 2>&1 || true
      ok "重桌面已移除"
    else
      ok "没有装重桌面，不用清理"
    fi
  fi

  case "$DESKTOP" in
    phosh) apt-get -y install phosh-core && ok "phosh-core 装好" ;;
    xfce)  apt-get -y install xfce4 lightdm && ok "xfce4 装好" ;;
    lxqt)  apt-get -y install lxqt && ok "lxqt 装好" ;;
    none)  ok "跳过桌面（--desktop 没指定）" ;;
    *)     warn "不认识的桌面: $DESKTOP" ;;
  esac

  step "P2-6 收尾"
  apt-get -y autoremove --purge >/dev/null 2>&1 || true
  if [ "$DESKTOP" != "none" ]; then
    if systemctl set-default graphical.target >/dev/null 2>&1; then
      ok "已切回 graphical.target，重启后进图形界面"
    else
      warn "切 graphical.target 失败，手动执行：sudo systemctl set-default graphical.target"
    fi
  else
    ok "保持文本模式（没装桌面）"
  fi
  ok "清理完成"
  cat <<'EOF'

──────────────────────────────────────────────
 Phase 2 完成。建议再重启一次验证：
   sudo reboot
 起不来就在 GRUB 里按 e，把 nomodeset 加回去应急：
   linux ... nomodeset
──────────────────────────────────────────────
EOF
  exit 0
fi

die "必须指定 --check / --phase1 / --phase2 之一"
