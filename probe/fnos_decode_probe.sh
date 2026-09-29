#!/bin/bash
# fnOS / RK3588S 硬解码能力探针  —— 全只读，不修改系统任何内容
# 用途：确认 fnOS 在 QuarkPi-CA2 上 4K 硬解是否可用（驱动/节点/MPP 库/ffmpeg 四层）
echo "═════════════════════════════════════════════════════"
echo " ① 系统与设备树"
echo "═════════════════════════════════════════════════════"
uname -a
echo -n "  model: "; cat /proc/device-tree/model 2>/dev/null | tr -d '\000'; echo
echo -n "  compatible: "; cat /proc/device-tree/compatible 2>/dev/null | tr '\000' ' '; echo

echo
echo "═════════════════════════════════════════════════════"
echo " ② 硬解设备节点（有这些才谈得上硬解）"
echo "═════════════════════════════════════════════════════"
for p in /dev/mpp_service /dev/rkvdec /dev/rkvdec0 /dev/rkvdec1 /dev/rkvenc /dev/vpu /dev/hevc-decoder /dev/rga; do
  if [ -e "$p" ]; then printf "  ✓ %-24s %s\n" "$p" "$(ls -l $p | awk '{print $1, $3, $4}')"
  else printf "  ✗ %-24s 不存在\n" "$p"; fi
done
echo "  ── video/dri 节点 ──"
ls -l /dev/video* /dev/dri/* /dev/dma_heap/* 2>/dev/null | head -12

echo
echo "═════════════════════════════════════════════════════"
echo " ③ 内核模块 / 内建驱动"
echo "═════════════════════════════════════════════════════"
echo "  ── /proc/modules 命中 ──"
grep -iE 'vdec|venc|rga|mpp|hantro|rknpu|rockchip' /proc/modules 2>/dev/null | awk '{printf "  %-28s %s\n", $1, $3}' | head -15 || true
echo "  （若为空 = 驱动直接编进内核 ✓ 看下面 dmesg 更准）"
echo "  ── 内核里已注册的 vdec/venc 平台驱动 ──"
ls /sys/bus/platform/drivers/ 2>/dev/null | grep -iE 'vdec|venc|vpu|rga|mpp|rockchip' | sed 's/^/  /'

echo
echo "═════════════════════════════════════════════════════"
echo " ④ dmesg 里的 VPU 痕迹（驱动 probe 证据）"
echo "═════════════════════════════════════════════════════"
dmesg 2>/dev/null | grep -iE 'rkvdec|rkvenc|vpu121|vdec|venc|mpp|rga' | head -20 | sed 's/^/  /'
echo "  （若无输出 ⇒ 驱动未 probe 或该内核未启用 ✓ 这是关键判据）"

echo
echo "═════════════════════════════════════════════════════"
echo " ⑤ 设备树节点状态（最权威 —— 看 okay/disabled）"
echo "═════════════════════════════════════════════════════"
for n in vpu121 vdec0 vdec1 av1d vepu121_0 vepu121_1 vepu121_2 vepu121_3 rga3_core0; do
  if [ -e /proc/device-tree/$n ]; then
    s=$(cat /proc/device-tree/$n/status 2>/dev/null | tr -d '\000')
    c=$(cat /proc/device-tree/$n/compatible 2>/dev/null | tr '\000' ' ')
    printf "  %-12s status=%-10s compatible=%s\n" "$n" "${s:-（未写=okay）}" "$c"
  else
    printf "  %-12s 节点不存在 ✗\n" "$n"
  fi
done

echo
echo "═════════════════════════════════════════════════════"
echo " ⑥ 用户态：ffmpeg 与 MPP 库（硬解要软件栈配合）"
echo "═════════════════════════════════════════════════════"
command -v ffmpeg ffprobe 2>/dev/null | sed 's/^/  /'
echo "  ── ffmpeg 版本 ──"
ffmpeg -hide_banner -version 2>/dev/null | head -2 | sed 's/^/  /'
echo "  ── hwaccels ──"
ffmpeg -hide_banner -hwaccels 2>/dev/null | tr '\n' ' ' | sed 's/^/  /'; echo
echo "  ── 解码器里有没有 rkmpp（关键 ✓）──"
ffmpeg -hide_banner -decoders 2>/dev/null | grep -iE 'rkmpp|mpp' | sed 's/^/  /' || echo "  ✗ 无 rkmpp 解码器"
echo "  ── hevc/h264 解码器 ──"
ffmpeg -hide_banner -decoders 2>/dev/null | grep -iE ' hevc | h264 ' | head -6 | sed 's/^/  /'
echo "  ── rkmpp 编码器 ──"
ffmpeg -hide_banner -encoders 2>/dev/null | grep -iE 'rkmpp|mpp' | sed 's/^/  /' || echo "  ✗ 无 rkmpp 编码器"
echo "  ── MPP 库文件 ──"
ls -l /usr/lib/aarch64-linux-gnu/librockchip_mpp* /usr/lib/librockchip_mpp* /usr/lib/aarch64-linux-gnu/libmpp* 2>/dev/null | sed 's/^/  /' || echo "  ✗ 未找到 librockchip_mpp"
echo "  ── 系统 ffmpeg 是否链 MPP ──"
for f in $(command -v ffmpeg 2>/dev/null) /usr/lib/aarch64-linux-gnu/libavcodec.so*; do
  [ -e "$f" ] || continue
  printf "    %s: " "$f"
  if ldd "$f" 2>/dev/null | grep -qi mpp; then echo "✓ 已链 MPP"; ldd "$f" 2>/dev/null | grep -i mpp | sed 's/^/       /'; else echo "（未链 MPP）"; fi
done

echo
echo "═════════════════════════════════════════════════════"
echo " ⑦ 测试片在位情况"
echo "═════════════════════════════════════════════════════"
ls -l /root/4k-test/ 2>/dev/null | sed 's/^/  /'

echo
echo "═════════════════════════════════════════════════════"
echo " ⑧ fnOS 媒体/转码相关进程与服务"
echo "═════════════════════════════════════════════════════"
ps -eo pid,comm 2>/dev/null | grep -iE 'trim|ffmpeg|video|media|dlna' | head -12 | sed 's/^/  /'
echo "  ── 监听端口（含媒体/转码服务）──"
ss -lntp 2>/dev/null | head -18 | sed 's/^/  /'

echo
echo "═════════════════════════════════════════════════════"
echo " 探针结束（全程只读 ✓）"
echo "═════════════════════════════════════════════════════"
