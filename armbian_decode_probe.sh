#!/bin/bash
# Armbian（eMMC，内线 6.18.54-ophub）硬解能力探针 —— 只读 ✓
# 与 fnOS 版的关键区别：Armbian 走【主线 V4L2】路径（无厂商 rk_vcodec ✓ 无 /dev/mpp_service ✓）
echo "═════════════════════════════════════════════════════"
echo " ① 系统身份"
echo "═════════════════════════════════════════════════════"
uname -a
head -6 /etc/armbian-release 2>/dev/null | sed 's/^/  /'
echo -n "  model: "; cat /proc/device-tree/model 2>/dev/null | tr -d '\000'; echo

echo
echo "═════════════════════════════════════════════════════"
echo " ② 【关键】主线的 V4L2 解码设备（有 = 驱动挂上了 ✓）"
echo "═════════════════════════════════════════════════════"
ls -l /dev/video* /dev/media* 2>/dev/null | sed 's/^/  /'
echo "  ── 每个 video 节点的名字（应看到 rockchip/rkvdec/hantro 字样 ✓）──"
for f in /sys/class/video4linux/video*/name; do
  [ -f "$f" ] || continue
  printf "  %-12s %s\n" "$(basename "$(dirname "$f")")" "$(cat "$f" 2>/dev/null)"
done
echo "  ── 解码设备的输出格式（M2M 解码器会列 H264/HEVC ✓）──"
command -v v4l2-ctl >/dev/null 2>&1 && for d in /dev/video*; do
  echo "    [$d]"; v4l2-ctl -d "$d" --list-formats-out 2>/dev/null | head -6 | sed 's/^/       /'
done || echo "    （无 v4l2-ctl ✓ 可后装 ✓）"

echo
echo "═════════════════════════════════════════════════════"
echo " ③ 驱动 probe 证据（dmesg）"
echo "═════════════════════════════════════════════════════"
dmesg 2>/dev/null | grep -iE 'rkvdec|hantro|vdec|venc|rga|mpp|vpu' | head -20 | sed 's/^/  /'
echo "  （有 rockchip-vdec/rkvdec probe 行 ⇒ 硬解驱动活了 ✓；fnOS 那边这里是空的 ✗）"

echo
echo "═════════════════════════════════════════════════════"
echo " ④ 已加载模块"
echo "═════════════════════════════════════════════════════"
lsmod 2>/dev/null | grep -iE 'vdec|hantro|rga|vpu|rockchip' | sed 's/^/  /' || echo "  （无 ✓）"

echo
echo "═════════════════════════════════════════════════════"
echo " ⑤ 设备树节点（用真实文件名 ✓ 带地址 ✓）"
echo "═════════════════════════════════════════════════════"
for d in /proc/device-tree/video-codec@*; do
  [ -e "$d" ] || continue
  printf "  %-26s status=%-8s compat=%s\n" "$(basename "$d")" \
    "$(cat "$d/status" 2>/dev/null | tr -d '\000')" \
    "$(cat "$d/compatible" 2>/dev/null | tr '\000' ' ')"
done
for d in /proc/device-tree/rga@*; do
  [ -e "$d" ] || continue
  printf "  %-26s status=%s\n" "$(basename "$d")" "$(cat "$d/status" 2>/dev/null | tr -d '\000')"
done

echo
echo "═════════════════════════════════════════════════════"
echo " ⑥ 用户态工具（Armbian 镜像里通常没装 ✓）"
echo "═════════════════════════════════════════════════════"
for b in ffmpeg ffprobe v4l2-ctl mpv gst-launch-1.0; do
  printf "  %-16s %s\n" "$b" "$(command -v $b 2>/dev/null || echo '无 ✗')"
done

echo
echo "═════════════════════════════════════════════════════"
echo " ⑦ 内线驱动是否编成模块（config ✓）"
echo "═════════════════════════════════════════════════════"
C=/boot/config-$(uname -r)
if [ -f "$C" ]; then
  grep -iE 'ROCKCHIP_(VDEC|VPU|VENC|RGA)|VIDEO_HANTRO' "$C" | sed 's/^/  /'
else
  echo "  （无 $C ✓）"
fi

echo
echo "═════════════════════════════════════════════════════"
echo " ⑧ 测试片在位情况"
echo "═════════════════════════════════════════════════════"
ls -l /root/4k-test/ 2>/dev/null | sed 's/^/  /' || echo "  （还没有 ✓ 等从容器 scp 过来 ✓）"

echo
echo "═════════════════════════════════════════════════════"
echo " 探针结束（全程只读 ✓）"
echo "═════════════════════════════════════════════════════"
