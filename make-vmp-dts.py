#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成【fnOS 专用】厂商 MPP 节点版设备树源码（rk3588s-quarkpi-ca2-vmp.dts）。

背景
----
fnOS 用厂商内核驱动（rk_vcodec.ko = "Rockchip mpp service driver"），它只认「厂商式节点」
（rockchip,mpp-service / rkv-decoder-v2 / rkv-encoder-v2 / vpu-*-v2 ...），而主线 dtb 里是
「主线式节点」（rockchip,rk3588-vdec / rk3568-vpu-dec / rk3588-av1-vpu-dec ...）⇒ compatible 不匹配
⇒ 驱动不 probe ⇒ 无 /dev/mpp_service ⇒ fnOS 硬解不可用（ffmpeg 报 Failed to init MPP context: -1）。

关键约束（**实证**）
-------------------
厂商节点与主线节点**地址冲突**（不是简单的追加就行）：
    主线 video-codec@fdb50000 (vpu121)   ⇔  厂商 vepu@fdb50000
    主线 video-codec@fdba0000/4000/8000/c000 (vepu121_0..3) ⇔ 厂商 jpege-core@...
    主线 video-codec@fdc38000/fdc40000 (vdec0/vdec1)        ⇔ 厂商 rkvdec-core@...
    主线 sram@ff001000/codec-sram@0/@78000                  ⇔ 厂商 rkvdec-sram@0/@78000
⇒ 必须**先删掉主线那组，再引入厂商组**（只追加会留下重复地址，绑定结果不可预期）。

⚠️ 本产物**只能**投放到 fnOS 的 /boot/dtb/；**不要**用于 Armbian
（Armbian 靠主线 rkvdec/hantro/av1-vpu/rga/rocket 正常工作，替换会破坏它）。

用法
----
    python3 make-vmp-dts.py            # 生成 + 编译 + 自检（输出到 /opt/data/cache/scratch/vmp-out/）
"""

import os
import re
import shutil
import subprocess
import sys, hashlib, time

MAINLINE = "/opt/data/quarkpi/mainline/linux-6.18.y-main"
ROCK = MAINLINE + "/arch/arm64/boot/dts/rockchip"
VENDOR = "/opt/data/workspace/quarkpi-final/l618/arch/arm64/boot/dts/rockchip"
OUT = "/opt/data/cache/scratch/vmp-out"
DTC_ENV = "/opt/data/bin/dtb"

# 主线侧要删掉的冲突节点（标签来自实测 grep，见文件头）
DELETE_LABELS = [
    "vpu121",        # fdb50000  ⇔ 厂商 vepu@fdb50000
    "vepu121_0",     # fdba0000  ⇔ 厂商 jpege-core@fdba0000
    "vepu121_1",     # fdba4000
    "vepu121_2",     # fdba8000
    "vepu121_3",     # fdbac000
    "vdec0",         # fdc38000  ⇔ 厂商 rkvdec-core@fdc38000
    "vdec1",         # fdc40000
    "rknn_core_0",   # fdab0000  ⇔ 厂商 npu@fdab0000 (rk3588,rknpu)
    "rknn_core_1",   # fdac0000
    "rknn_core_2",   # fdad0000
    # 注意：av1d（fdc70000）由厂商 dtsi 自己 /delete-node/，这里不要再删（会报 label 不存在）
]
DELETE_PATHS = [     # 无标签的同址节点，按路径删
    "/sram@ff001000/codec-sram@0",
    "/sram@ff001000/codec-sram@78000",
]

# 引入的厂商 dtsi（按 Linux 惯例：VPU 组 + NPU 组 + GPU 组分别引入）
VENDOR_INCLUDES = ["rk3588s-vpu.dtsi", "rk3588s-npu.dtsi", "rk3588s-gpu.dtsi"]

# 主线基底缺、但厂商 dtsi 会引用的 OTP 单元（取自厂商 rk3588s-ip.dtsi:16-23）
VENDOR_OTP_CELLS = '''
/* 厂商 NPU 的 OPP 表（npu-opp-table）要读这两个 OTP 单元；主线基底里没有 ⇒ 从厂商 rk3588s-ip.dtsi 抄来 */
&otp {
	specification_serial_number: specification-serial-number@6 {
		reg = <0x06 0x1>;
		bits = <0 5>;
	};
	customer_demand: customer-demand@22 {
		reg = <0x22 0x1>;
		bits = <4 4>;
	};
};
'''

# 厂商 dtsi 里默认 disabled，需要板级开启
ENABLE = [
    # —— VPU/MPP 主体（fnOS 的 rk_vcodec 靠这组）——
    "mpp_srv", "vepu", "vdpu", "vdpu_mmu", "avsd",
    # —— JPEG 编解码 ——
    "jpegd", "jpegd_mmu", "jpege_ccu",
    "jpege0", "jpege0_mmu", "jpege1", "jpege1_mmu",
    "jpege2", "jpege2_mmu", "jpege3", "jpege3_mmu",
    # —— RKVENC / RKVDEC ——
    "rkvenc_ccu", "rkvenc0", "rkvenc0_mmu", "rkvenc1", "rkvenc1_mmu",
    "rkvdec_ccu", "rkvdec0", "rkvdec0_mmu", "rkvdec1", "rkvdec1_mmu",
    # —— AV1 ——
    "av1d", "av1d_mmu",
    # —— RGA / IEP ——
    "rga3_core0", "rga3_0_mmu", "rga3_core1", "rga3_1_mmu", "rga2", "iep", "iep_mmu",
    # —— NPU（fnOS 的 AI 引擎靠这组；厂商 compatible rockchip,rk3588-rknpu）——
    "rknpu_mmu",   # ← rknpu 单独处理（要带 supply ✓ 见下方）
]


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=600, **kw)


def main():
    os.makedirs(OUT, exist_ok=True)
    # 厂商 dtsi 复制到输出目录（作为 #include 搜索路径）
    for f in VENDOR_INCLUDES:
        src = os.path.join(VENDOR, f)
        if os.path.exists(src):
            shutil.copy(src, OUT)
        else:
            print(f"   ⚠️ 厂商 dtsi 不存在: {f}")

    src = open(f"{ROCK}/rk3588s-quarkpi-ca2.dts", encoding="utf-8", errors="replace").read()

    tail = ["", "/* ===================== fnOS 专用：厂商 MPP 节点组 ===================== */",
            "/* 先删掉与厂商节点同址的主线节点（否则重复地址，绑定结果不可预期） */"]
    tail += [f"/delete-node/ &{l};" for l in DELETE_LABELS]
    tail += [f"/delete-node/ &{{{p}}};" for p in DELETE_PATHS]
    tail += ["", "/* 再引入厂商节点组（含 /delete-node/ &av1d; 由厂商 dtsi 自己处理） */"]
    tail += [VENDOR_OTP_CELLS]
    tail += [f'#include "{f}"' for f in VENDOR_INCLUDES]
    tail += ["", "/* 厂商节点默认 disabled ⇒ 板级开启 */"]
    tail += [f'&{n} {{ status = "okay"; }};' for n in ENABLE]

    # 厂商 rk3588-vgnpu-supply.dtsi 的标准写法：
    # 厂商 npu-opp-table 的 opp-microvolt 要求 NPU 有稳压器，否则
    #   _opp_set_regulators: no regulator (rknpu) found ⇒ 探针中止 ✗
    # 我们的基底里 vdd_npu_s0 已注册且 enabled ✓（rk8602 @i2c2 0x42）但没人引用它 ⇒ 在此接上
    tail += [
        '&rknpu {',
        '\trknpu-supply = <&vdd_npu_s0>;',
        '\tmem-supply = <&vdd_npu_s0>;',
        '\tstatus = "okay";',
        '};',
    ]
    tail += [""]

    # —— GPU（fnOS 侧 rkgpu_bifrost_csf.ko 只认 compatible "rockchip,rk3588-mali-csf"）——
    # 病根：主线节点写的是 "rockchip,rk3588-mali","arm,mali-valhall-csf"，
    #       与 fnOS 的 /lib/modules/*/modules.alias 全不匹配 ⇒ 模块从不加载 ⇒ 无 /dev/mali0
    #       ⇒ fnOS 转码链里的 tonemap_opencl / scale_vulkan / libplacebo 全部不可用
    #       ⇒ 10bit（H.264 Hi10P 与 HEVC Main10）视频【打不开】，而 8bit 正常 ✓
    # 依据：fnOS 自带 dtb（rk3582-radxa-e52c.dtb）里的 gpu@fb000000 节点写法 ✓
    #       jjm2473 的 rk3588s-gpu.dtsi 已把 compatible/clocks/interrupt-names/OPP 全改好 ✓
    # ⚠️ 只允许放进本「fnOS 专用」dtb：Armbian 侧靠主线 panthor 驱动，换 compatible 会废掉 GPU ✗
    # 本板没有 vdd_gpu_mem_s0 ⇒ mem-supply 复用 vdd_gpu_s0（与 fnOS 官方 dtb 的做法一致 ✓）
    tail += [
        '&gpu {',
        '\tmali-supply = <&vdd_gpu_s0>;',
        '\tmem-supply = <&vdd_gpu_s0>;',
        '\tstatus = "okay";',
        '};',
        '',
        '/* rkvenc 稳压器（厂商 rk3588-vgnpu-supply.dtsi 标准写法）',
        ' * ⇒ 消掉 "no regulator (venc) found / failed to add venc devfreq" ✓',
        ' * 本板没有 vdd_vdenc_mem_s0 ⇒ 同样复用 vdd_vdenc_s0 ✓ */',
        '&rkvenc0 { venc-supply = <&vdd_vdenc_s0>; mem-supply = <&vdd_vdenc_s0>; status = "okay"; };',
        '&rkvenc1 { venc-supply = <&vdd_vdenc_s0>; mem-supply = <&vdd_vdenc_s0>; status = "okay"; };',
    ]
    tail += [""]

    dts = os.path.join(OUT, "rk3588s-quarkpi-ca2-vmp.dts")
    open(dts, "w", encoding="utf-8").write(src + "\n".join(tail))
    print(f"✓ 源码已生成: {dts}  ({os.path.getsize(dts)} 字节)")

    env = dict(os.environ)
    # ⚠️ 真因修正：libyaml 在解包目录的 usr/lib/x86_64-linux-gnu（与 env.sh 一致 ✓）
    env["LD_LIBRARY_PATH"] = "/opt/data/bin/dtc/usr/lib/x86_64-linux-gnu:" + env.get("LD_LIBRARY_PATH", "")
    DTC = f"{DTC_ENV}/dtc"

    pre = os.path.join(OUT, "vmp.dts.pre")
    c = sh(["cpp", "-nostdinc", f"-I{MAINLINE}/include", f"-I{MAINLINE}/arch/arm64/boot/dts",
            f"-I{ROCK}", f"-I{OUT}", "-undef", "-D__DTS__", "-x", "assembler-with-cpp",
            "-o", pre, dts], env=env)
    if c.returncode:
        print("✗ cpp 失败:\n" + c.stderr[:800]); return 1
    print(f"   cpp OK ⇒ {os.path.getsize(pre)} 字节")

    dtb = os.path.join(OUT, "vmp.dtb")
    old_md5 = hashlib.md5(open(dtb,"rb").read()).hexdigest() if os.path.exists(dtb) else None
    t0 = time.time()
    d = sh([DTC, "-@", "-I", "dts", "-O", "dtb", "-o", dtb, pre], env=env)
    if d.returncode != 0:
        print(f"✗ dtc 未成功执行（exit={d.returncode}）⇒ 产物不可信 ✗\n   stderr: {(d.stderr or d.stdout)[:500]}")
        return 1
    lines = [l for l in (d.stderr or "").splitlines() if l.strip()]
    errs = [l for l in lines if "Error" in l or "FATAL" in l]
    warns = [l for l in lines if "Warning" in l]
    print(f"   dtc exit={d.returncode}  错误 {len(errs)}  警告 {len(warns)}")
    for l in errs[:15]:
        print("     ✗ " + l[:160])
    for l in warns[:10]:
        print("     ⚠ " + l[:160])
    if os.path.exists(dtb):
        new_md5 = hashlib.md5(open(dtb,"rb").read()).hexdigest()
        fresh = os.path.getmtime(dtb) >= t0 - 1
        print(f"   ⇒ dtb {os.path.getsize(dtb)} 字节  md5={new_md5}")
        print(f"   断言：文件是本次新建={fresh} ✓  与旧版不同={new_md5!=old_md5} ✓  (旧 {old_md5})")
        if not fresh:
            print("✗ 产物没被更新 ⇒ 视为失败 ✗"); return 1
    return 0 if (d.returncode == 0 and not errs) else 1


if __name__ == "__main__":
    sys.exit(main())
