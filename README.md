# QuarkPi-CA2 · fnOS 播放器测试样本（完整矩阵 · 含成功对照组）

用途：给社区/官方复现"fnOS 播放器对 10bit / HEVC 视频的黑屏与不支持"问题。
**全部文件都可自行复现**（生成命令见 `GEN-COMMANDS.txt`；素材为 Big Buck Bunny 4K，CC-BY）。

## 测试矩阵与实测结果

| 文件 | 编码 | 位深 | 分辨率 | 音轨 | fnOS 播放器实测 |
|---|---|---|---|---|---|
| `h264_8bit_1080p.mp4` | H.264 High | 8bit | 1920×1080 | AAC 2ch | ✅ **正常播放**（对照组）|
| `h264_8bit_4k.mp4` | H.264 High | 8bit | 3840×2160 | AC-3 6ch | ✅ **完美解码**（对照组）|
| `h264_10bit_1080p.mp4` | H.264 High10 | 10bit | 1920×1080 | AAC 2ch | ❌ 打不开 |
| `hevc_8bit_1080p.mp4` | HEVC Main | 8bit | 1920×1080 | AAC 2ch | ❌ 不支持格式 |
| `hevc_8bit_480p_noaudio.mp4` | HEVC Main | 8bit | 640×480 | 无 | ❌ 不支持格式 |
| `hevc_10bit_4k.mp4` | HEVC Main10 | 10bit | 3840×2160 | AC-3 6ch | ❌ 黑屏（进度条 20s）|
| `v_hdr_pq.mp4` | 同上 + HDR 标记（smpte2084/bt2020）| 10bit | 3840×2160 | AC-3 6ch | ❌ 黑屏 |
| `v_bt709.mp4` | 同上 + SDR 标记（bt709）| 10bit | 3840×2160 | AC-3 6ch | ❌ 黑屏 |
| `v_noaudio.mp4` | 同上，无音轨 | 10bit | 3840×2160 | 无 | ❌ 不支持格式 |
| `hevc_10bit_1080p.mp4` | HEVC Main10 | 10bit | 1920×1080 | AAC 2ch | ⏳ 未测（烦请帮测）|

**读法**：
- 8bit H.264 无论 1080p 还是 4K 都能播 ✅ ⇒ 播放器基本链路没问题；
- 只要换成 HEVC（8bit 或 10bit）就失败 ❌；10bit H.264 也失败 ❌
- 音轨（AC-3 6ch / AAC / 无）**不是**决定因素 ✅ —— 有音轨的 10bit 是"黑屏"，无音轨的变成"不支持格式"
- 色彩标记也不是决定因素 ✅（标 HDR 与标 SDR 都黑屏）

## 附属材料

| 文件 | 说明 |
|---|---|
| `fnos_decode_probe.sh` | 在 fnOS 上探测硬解链路（MPP / RGA / OpenCL / 设备节点）|
| `armbian_decode_probe.sh` | 在 Armbian 上做同样的探测，用于对照 |
| `board_dtb_compare.sh` | 对比主线 dtb 与厂商节点版 dtb 的差异 |
| `make-vmp-dts.py` | **厂商节点版 dtb 生成脚本**（把 MPP/NPU/GPU 节点并入主线 dtb）|
| `vmp.dtb` | 上述脚本产出的 dtb（fnOS `/boot` 现役，硬解三件套可用）|
| `GEN-COMMANDS.txt` | 本页所有样本的**逐条生成命令**（可复现）|

## 复现要点

```bash
# 源素材（CC-BY，Big Buck Bunny 4K）
curl -LO https://download.blender.org/demo/movies/BBB/bbb_sunflower_2160p_30fps_normal.mp4

# 10bit HEVC 4K 主样本
ffmpeg -ss 30 -t 20 -i bbb_sunflower_2160p_30fps_normal.mp4 -map 0:v:0 -map 0:a:0 \
  -vf format=yuv420p10le -c:v libx265 -preset medium -crf 20 -profile:v main10 \
  -c:a ac3 -ac 6 -b:a 448k -movflags +faststart hevc_10bit_4k.mp4

# 其余见 GEN-COMMANDS.txt（含成功对照组 h264_8bit_*）
```

## 硬件与系统背景

- 设备：正点原子 **QuarkPi-CA2**（RK3588S，eMMC 版）
- 系统：**fnOS v1.2.0604**，内核 `6.18.18.c1090-trim`
- 已装 Mali GPU 驱动插件；`/dev/mali0`、`/dev/rga`、`/dev/mpp_service` 均正常
- 把同一份 10bit 4K 文件交给 **fnOS 自带 ffmpeg** 命令行转码：4K HEVC Main10 → 1080p H.264 + AAC，
  20 秒素材约 4 秒完成（≈5× 实时）⇒ **底层编解码链路可用，问题在播放器/mediasrv 这一层**
