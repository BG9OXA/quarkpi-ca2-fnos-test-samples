# QuarkPi-CA2 · fnOS 播放器测试样本 / fnOS player test samples

正点原子 **QuarkPi-CA2**（RK3588S）上 fnOS 播放器打不开 HEVC / 10bit 视频的复现素材。
分两部分：**板上实测过的原件**（原样收录，一个字节都没改）与**可从公开素材复现的重制件**。

Board: ALIENTEK QuarkPi-CA2 (RK3588S) · fnOS v1.2.0604 · kernel `6.18.18.c1090-trim`
Mali 插件已装；`/dev/mali0`、`/dev/rga`、`/dev/mpp_service` 均存在。

---

## A. 板上实测原件 `board-tested/` ★

**这些就是从板子上直接取回的文件**（md5 与板上逐条一致 ✓）。表中结果是在 fnOS 播放器上实际点开观察到的。

| 文件 | 规格 | fnOS 播放器实测 | md5 |
|---|---|---|---|
| `BBB_4K_45s.mp4` | H.264 High / 8bit / 3840×2160 / AC-3 / 45s / 6.0Mbps | ✅ **完美解码**（对照组）| `718cd9c5405ed31c30a904db4fe1b070` |
| `BBB_4K_HEVC10bit_20s.mp4` | HEVC Main10 / **10bit** / 3840×2160 / AC-3 / 20s | ❌ **黑屏**（进度条 20s，无画面）| `360d6279607467b5f397a081d749b08d` |
| `t_h264.mp4` | H.264 High / 8bit / 640×480 / 无音轨 / 5s | ✅ 正常播放 | `a708d16bfc30c78581662840c15b698e` |
| `t_h265.mp4` | HEVC Main / 8bit / 640×480 / 无音轨 / 5s | ❌ **不支持的音视频格式** | `321e3b66c729edb885ac5a218f5e27d7` |
| `t_vp8.webm` | VP8 / WebM / 640×480 / 5s | ❌ **文件格式无法识别** | `14f14c183385e6a40a72f4969ca39d9d` |
| `t_1920x1080.mp4` | H.264 Baseline / 8bit / 1920×1080 / 5s / 15.5Mbps | ✅ 正常播放 | `f2ef01063c8add76fe3d8bbf96ee533c` |
| `t_2560x1440.mp4` | H.264 Baseline / 8bit / 2560×1440 / 5s / 26.2Mbps | ✅ 正常播放 | `6f974e0f4a6c981a8b8d915f44309314` |
| `t_3840x2160.mp4` | H.264 Baseline / 8bit / 3840×2160 / 5s / 60.7Mbps | ✅ 正常播放 | `25e6757e2ff95bf36cc5d965fe13fb59` |
| `t_1080p_30s.mp4` | H.264 Baseline / 8bit / 1920×1080 / 30s / 15.5Mbps | ✅ 正常播放 | `26fe2045dba6d6778c51a4f4e3369d36` |
| `variants/v_hdr_pq.mp4` | 10bit HEVC 4K，另打 **HDR 标记**（smpte2084/bt2020）| ❌ 黑屏 | `8eba874c6ce988f54e1bf85f947c51b5` |
| `variants/v_bt709.mp4` | 10bit HEVC 4K，另打 **SDR 标记**（bt709）| ❌ 黑屏 | `b1937e888900fc776f5e5655dabe3c60` |
| `variants/v_noaudio.mp4` | 10bit HEVC 4K，**去掉音轨** | ❌ 不支持的音视频格式 | `81b54f468b78292b0a34b42ae33518da` |

**从原件能读出的边界：**
1. **8bit H.264 全部正常** ✅ —— 480p 到 4K、码率一路到 **60 Mbps** 都能放 ⇒ 主链路、硬件解码、码率都不是问题；
2. **换成 HEVC 就失败** ❌（10bit 4K → 黑屏；8bit 480p → "不支持的音视频格式"）；
3. **音轨不是决定因素** ✅ —— 有音轨=黑屏，去掉音轨=变成"不支持格式"；
4. **色彩标记也不是** ✅ —— 标 HDR 与标 SDR 表现一样（都黑屏）；
5. **VP8 / WebM 容器**：播放器报"文件格式无法识别" ❌（未进入解码）。

---

## B. 可复现重制件 `generated/`

为补齐矩阵（尤其是 1080p 行），这些用公开素材 Big Buck Bunny 4K（CC-BY）**按命令重制**，
生成命令见 `GEN-COMMANDS.txt`，可逐条复现。

| 文件 | 规格 | fnOS 播放器实测 | md5 |
|---|---|---|---|
| `h264_8bit_1080p.mp4` | H.264 High / 8bit / 1920×1080 / AAC 2ch | ⏳ 待确认 | `f0ef50f42edd2918f3bc67d76b6510d3` |
| `h264_10bit_1080p.mp4` | H.264 High10 / **10bit** / 1920×1080 / AAC 2ch | ⏳ 待确认 | `7e0630b07075e9ab2a109ed426f593c2` |
| `hevc_8bit_1080p.mp4` | HEVC Main / 8bit / 1920×1080 / AAC 2ch | ⏳ 待确认 | `ce8c3b85d9fc41f96b39d243ca97b442` |
| `hevc_10bit_1080p.mp4` | HEVC Main10 / 10bit / 1920×1080 / AAC 2ch | ⏳ 待确认 | `6f785fa9e05872022fc26d561a0f51eb` |

---

## C. 探测脚本与素材 `probe/`

| 文件 | 说明 |
|---|---|
| `fnos_decode_probe.sh` | 在 fnOS 上探测硬解链路（MPP / RGA / OpenCL / 设备节点）|
| `armbian_decode_probe.sh` | 在 Armbian 上做同样探测（用于对照）|
| `board_dtb_compare.sh` | 对比主线 dtb 与厂商节点版 dtb 的差异 |
| `make-vmp-dts.py` | **厂商节点版 dtb 生成脚本**（把 MPP/NPU/GPU 节点并入主线 dtb）|
| `vmp.dtb` | 上述脚本产出的 dtb（`b26f9d97faa65be9f5a70c7b9ba2628c`）|

---

## 复现命令（重制件）

```bash
# 源素材（CC-BY，Big Buck Bunny 4K）
curl -LO https://download.blender.org/demo/movies/BBB/bbb_sunflower_2160p_30fps_normal.mp4

# 全部重制命令见 GEN-COMMANDS.txt（含 1080p 各条与去音轨/色彩标记变体）
```

## 一个关键对照结论

把**同一份** 10bit 4K 文件交给 **fnOS 自带 ffmpeg 从命令行转码**是**成功**的
（4K HEVC Main10 → 1080p H.264 + AAC，20 秒素材约 4 秒，≈5× 实时），
同时 `/vol1/mediasrv.transcode/{video,media,thumb,subtitle}` 全程为空
⇒ **底层编解码链路可用，问题出在播放器 / mediasrv 这一层**。

> 板子与全部测试均为实机操作；文件取自板子自身，未做任何再编码（A 段）。
