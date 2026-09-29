#!/bin/bash
# 板端取证：① fnOS 的 dtb  vs  ophub(Armbian) 的 dtb 逐节点对比
#            ② 只读查看 eMMC 上的 Armbian 系统（ro,noload ⇒ 绝不写盘）
echo "══ ① dtc 可用性 ══"
command -v dtc || echo "  无 dtc ✗（无法反编译，退化用字符串对比）"
echo
echo "══ ② 两份 dtb 基本信息 ══"
for d in /boot/dtb/rockchip/rk3588s-quarkpi-ca2.dtb /tmp/ophub-quarkpi-ca2.dtb; do
  if [ -f "$d" ]; then
    echo "  ── $d ──"
    stat -c "     size: %s  mtime: %y" "$d"
    md5sum "$d" | awk '{print "     md5 :", $1}'
  else
    echo "  缺 $d ✗"
  fi
done
echo
echo "══ ③ 反编译对比：VPU / RGA 节点（关键 ✓）══"
if command -v dtc >/dev/null 2>&1; then
  for d in /boot/dtb/rockchip/rk3588s-quarkpi-ca2.dtb /tmp/ophub-quarkpi-ca2.dtb; do
    [ -f "$d" ] || continue
    echo "  ── $(basename $d) 的编解码相关节点 ──"
    dtc -I dtb -O dts -q "$d" 2>/dev/null | grep -nE '^	(video-codec|rga|mpp|rkvdec|rkvenc)' | head -20 | sed 's/^/     /'
    echo "     ── 这些节点的 compatible ──"
    dtc -I dtb -O dts -q "$d" 2>/dev/null | grep -E 'compatible = "(rockchip,(rkv-decoder-v2|rkv-encoder-v2|mpp_service|rk3588-vdec|rk3588-vpu121|rk3588-vepu121|rk3588-av1-vpu|rk3588-rga))' | sort | uniq -c | sed 's/^/     /'
  done
  echo
  echo "  ── 两份 dtb 的 VPU 段落逐行 diff（空 = 完全相同 ✓）──"
  for d in /boot/dtb/rockchip/rk3588s-quarkpi-ca2.dtb /tmp/ophub-quarkpi-ca2.dtb; do
    o=/tmp/$(basename $d).dts
    dtc -I dtb -O dts -q "$d" 2>/dev/null > "$o"
  done
  diff /tmp/rk3588s-quarkpi-ca2.dtb.dts /tmp/ophub-quarkpi-ca2.dtb.dts > /tmp/dtb.diff 2>&1
  echo "     全文件差异行数: $(wc -l < /tmp/dtb.diff)"
  echo "     ── 差异里与编解码相关的行 ──"
  grep -iE 'vdec|venc|vpu|av1|rga|mpp|iommu' /tmp/dtb.diff | head -20 | sed 's/^/     /' || echo "     （无 ✓ 说明编解码部分完全一致 ✓）"
else
  echo "  ── 无 dtc：用字符串对比（粗判 ✓）──"
  for d in /boot/dtb/rockchip/rk3588s-quarkpi-ca2.dtb /tmp/ophub-quarkpi-ca2.dtb; do
    [ -f "$d" ] || continue
    echo "     $(basename $d):"
    grep -aoE 'rkv-decoder-v2|rkv-encoder-v2|mpp_service|rk3588-vdec|rk3588-vpu121|rk3588-vepu121|rk3588-av1-vpu' "$d" | sort | uniq -c | sed 's/^/       /'
  done
fi
echo
echo "══ ④ 只读查看 eMMC 上的 Armbian（绝不写盘 ✓）══"
mkdir -p /mnt/emmc-ro
if mount -o ro,noload /dev/mmcblk0p1 /mnt/emmc-ro 2>/dev/null; then
  echo "  只读挂载 ✓"
  echo "  ── Armbian 内核版本 ──"; ls /mnt/emmc-ro/lib/modules/ 2>/dev/null | sed 's/^/     /'
  echo "  ── 有没有厂商 rk_vcodec 模块 ──"
  find /mnt/emmc-ro/lib/modules -maxdepth 5 -name '*vcodec*' 2>/dev/null | sed 's/^/     /' | head -8
  echo "  ── 编解码相关 .ko ──"
  find /mnt/emmc-ro/lib/modules -maxdepth 6 -name '*.ko*' 2>/dev/null | grep -iE 'vdec|vpu|rga|mpp|venc' | sed 's/^/     /' | head -10
  echo "  ── Armbian 的 dtb ──"
  ls -la /mnt/emmc-ro/boot/dtb/rockchip/rk3588s-quarkpi-ca2.dtb* 2>/dev/null | sed 's/^/     /'
  md5sum /mnt/emmc-ro/boot/dtb/rockchip/rk3588s-quarkpi-ca2.dtb 2>/dev/null | sed 's/^/     md5: /'
  echo "  ── extlinux 指向 ──"
  grep -iE 'fdt|label|linux ' /mnt/emmc-ro/boot/extlinux/extlinux.conf 2>/dev/null | sed 's/^/     /'
  echo "  ── Armbian 内核 config 里 MPP 相关（若带 config）──"
  for c in /mnt/emmc-ro/boot/config-*; do [ -f "$c" ] && grep -iE 'VIDEO_ROCKCHIP|RKVDEC|RKVENC|MPP' "$c" | head -10 | sed 's/^/     /'; done
  umount /mnt/emmc-ro && echo "  已卸载 ✓（全程只读 ✓）"
else
  echo "  挂载失败 ✗ ── 见下面分区表 ✓"
fi
echo
echo "══ ⑤ 分区表 ══"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null | sed 's/^/  /'
