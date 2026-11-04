# kernel_oneplus_sdm845-4.19 · SUSFS v2.3.0 + ReSukiSU

一加 6 / 6T（enchilada / fajita，SDM845）4.19 内核，在上游源码基础上加入 **SUSFS v2.3.0**（手动回移植）和 **ReSukiSU**（BakaSU），并提供一键生成 **AnyKernel3 刷机包** 的脚本。

> English: OnePlus 6/6T (SDM845) 4.19.325 kernel with SUSFS v2.3.0 (hand-backported to 4.19) and ReSukiSU built in, plus a script that builds a flashable AnyKernel3 zip. Branch: `susfs230-resukisu`.

---

## 版本信息

| 项目 | 内容 |
|---|---|
| 设备 | OnePlus 6 (enchilada) / OnePlus 6T (fajita) |
| 内核 | 4.19.325（非 GKI） |
| 内核基线 | [EdwinMoq/android_kernel_oneplus_sdm845](https://github.com/EdwinMoq/android_kernel_oneplus_sdm845) @ `fd77fc2e3` |
| ReSukiSU | 固定在 `d5e9e025`（v4.2.0-rc3，驱动版本 35252），以 git 子模块引入，路径 `ReSukiSU/` |
| SUSFS | v2.3.0，内核侧由 susfs4ksu 的 `gki-android12-5.10` 分支（`eb95da0`）手动回移植到 4.19 |
| Hook 方式 | SUSFS Inline Hook（`CONFIG_KSU_SUSFS`） |

`drivers/kernelsu` 是指向 `../ReSukiSU/kernel` 的软链接。

## 为什么要回移植

simonpunk 官方的 `kernel-4.19` 分支停留在 SUSFS v1.5.5，而当前 ReSukiSU 只跟进新版 SUSFS，两者对不上。2.x 官方只维护 GKI 分支，所以 4.19 上用 2.3.0 只能自己回移植。

回移植参考了 [fabiannabil1/susfs-4.19-nongki](https://github.com/fabiannabil1/susfs-4.19-nongki)（针对 LG V60 / lge_sm8250 的 4.19 参考移植）。它不是通用补丁，本仓库针对一加 SDM845 树重新核对并手动合并了冲突的部分：

- `fs/Makefile`、`kernel/reboot.c`、`fs/proc/cmdline.c` 三处补丁无法直接应用，已按本树结构手动合并。
- 其余 23 个文件的 hunk 已逐个核对落点，确认落在对应函数内。

### 4.19 上的已知限制

沿用参考移植的说明：

- 没有接入 module preinit hook（4.19 的 exec 重试流程不好安全展开，写错会导致 bootloop）。ReSukiSU 因此不会启动 preinit，模块仍然从 `post-fs-data` 运行。
- `struct kstat` 没有 `mnt_id`，相关代码已去掉。
- Open redirect 在 `do_filp_open()` 中实现。
- 本构建**没有开启 KPM**（`CONFIG_KPM`）。

## 验证情况

已验证：

- 编译通过（无 ksu / susfs 相关警告），日志识别到 `SUSFS_VERSION: v2.3.0`。
- `Module.symvers` 与未打补丁的基线逐行一致，导出符号 CRC 没有变化，vendor 模块不会因为 KABI 变化拒载。
- 在 OnePlus 6T（A6013，Android 17）上可以启动；管理器显示"工作中 / Built-in"，内核驱动和管理器版本一致，SUSFS 版本显示 v2.3.0，`su` 上下文为 `u:r:ksu:s0`。
- 关闭 `CONFIG_KSU_SUSFS_ENABLE_LOG` 后，`dmesg` 中的 SUSFS 日志行明显减少。
- 内核 seccomp 正常：系统进程为 `Seccomp: 2`。

**尚未验证**：SUSFS 各项隐藏功能的实际效果、metamodule 与 Zygisk 等模块的运行情况。只在 6T 上测试过，6（enchilada）没有测试。

## 编译

需要 clang 和 aarch64 binutils（我用的是 clang r563880 + `aarch64-linux-android-`）。

```sh
git clone --recurse-submodules -b susfs230-resukisu \
  https://github.com/qiao-q-bot/kernel_oneplus_sdm845-4.19.git
cd kernel_oneplus_sdm845-4.19

export ARCH=arm64
MK="O=out ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
CROSS_COMPILE=aarch64-linux-android- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
CLANG_TRIPLE=aarch64-linux-gnu-"

make $MK vendor/sdm845-perf_defconfig vendor/enchilada.config
```

然后把下面的配置追加进 `out/.config`（存成 `susfs.fragment`），再 `olddefconfig` 并编译：

```
CONFIG_KSU=y
CONFIG_KSU_MULTI_MANAGER_SUPPORT=y
# CONFIG_KSU_MANUAL_HOOK is not set
# CONFIG_KSU_TRACEPOINT_HOOK is not set
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
```

```sh
cat susfs.fragment >> out/.config
make $MK olddefconfig
scripts/config --file out/.config -d KSU_SUSFS_ENABLE_LOG   # 见下方说明
make $MK olddefconfig
make -j$(nproc) $MK
```

产物：`out/arch/arm64/boot/Image.gz-dtb`（dtb 已追加在内核后面）。

> **关于 `CONFIG_KSU_SUSFS_ENABLE_LOG`**：它在 Kconfig 里默认是 `y`，只是在 fragment 里不写这一项，`olddefconfig` 会把它补成 `y`。所以要用 `scripts/config -d` 显式关掉，再执行 `grep ENABLE_LOG out/.config` 确认显示 `is not set`。这个选项会把 SUSFS 的操作写进内核日志，正式使用建议关闭；调试时可以打开。

之后不要再重新执行 `make ... vendor/sdm845-perf_defconfig`，那会把配置重置回默认值。

## 生成刷机包（AnyKernel3）

内核编译完成后，在源码根目录执行：

```sh
chmod +x ak3/build-zip.sh      # 只需要第一次
./ak3/build-zip.sh
```

脚本会下载 [AnyKernel3](https://github.com/osm0sis/AnyKernel3)，把 `ak3/anykernel.sh` 和刚编译出的 `Image.gz-dtb` 放进去，在源码根目录生成 `OP6-SUSFS230-ReSukiSU-<日期>.zip`，并打印 sha256。

可选环境变量：

| 变量 | 作用 | 默认值 |
|---|---|---|
| `OUT` | 内核编译输出目录 | `<源码根目录>/out` |
| `ZIP_NAME` | zip 文件名（不含 `.zip`） | `OP6-SUSFS230-ReSukiSU-<日期>` |

脚本每次都会拉取 AnyKernel3 的最新 `master`，并打印它的提交号，需要可复现的构建时请自行记录。

`ak3/anykernel.sh` 的要点：

- 只替换内核，保留当前 boot 里的 ramdisk；`BLOCK=boot`、`IS_SLOT_DEVICE=auto`，自动识别 A/B 槽位，刷入当前启用的槽位。
- 开启了设备检查（`do.devicecheck=1`），`device.name` 里写了 `enchilada`、`fajita`、`OnePlus6T`。AnyKernel3 用 `ro.product.device` 等属性去比对，**如果你的 ROM 报告的设备名不在这个列表里（用 `adb shell getprop ro.product.device` 查看），安装会中止**，改 `anykernel.sh` 里的 `device.name#` 即可。我只在 `ro.product.device` 为 `OnePlus6T` 的机器上验证过。

### 刷入刷机包

> ⚠️ 需要已解锁 bootloader。**先备份当前 boot**，建议先在备用机上测试。

备份当前 boot（需要 root，槽位用 `adb shell getprop ro.boot.slot_suffix` 查询）：

```sh
adb shell su -c "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_backup.img"
adb pull /sdcard/boot_backup.img
```

把 zip 传到手机，在 recovery 里安装，或使用 `adb sideload`。AnyKernel3 的 zip 没有签名，部分 recovery 会提示签名验证失败，需要选择继续安装。刷完重启，用下面的命令确认运行的是新内核（版本字符串里的提交哈希和编译时间会变）：

```sh
adb shell uname -a
```

出问题时，进 fastboot 刷回备份：

```sh
fastboot flash boot_a boot_backup.img    # 槽位要与备份时一致
```

## 手动打包 boot.img（不使用刷机包）

可以先用 `fastboot boot` 临时启动测试，不改动分区：

```sh
magiskboot unpack -h boot.img
rm -f kernel_dtb                 # dtb 已经追加在 Image.gz-dtb 里，不要重复
cp Image.gz-dtb kernel
magiskboot repack boot.img boot_new.img
fastboot boot boot_new.img
```

## 使用提示

- 管理器版本要和内核驱动匹配（驱动版本 35252），不要随意升级管理器。
- ReSukiSU 和官方 KernelSU 3.0 以后一样，自己不挂载模块，需要安装 metamodule（如 `meta-overlayfs`）。meta-overlayfs 依赖内核的 `CONFIG_OVERLAY_FS`（本构建已开启）。
- 旧版 `susfs4ksu` 模块（v1.x）与内核里的 SUSFS 2.3.0 不匹配，不要安装。SUSFS 可以在管理器内置的 SUSFS 页面管理。

## 致谢

- [simonpunk / susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)：SUSFS
- [ReSukiSU / BakaSU](https://github.com/ReSukiSU/ReSukiSU)：root 方案
- [fabiannabil1/susfs-4.19-nongki](https://github.com/fabiannabil1/susfs-4.19-nongki)：SUSFS v2.3.0 的 4.19 参考移植
- [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3)：刷机包模板
- [EdwinMoq/android_kernel_oneplus_sdm845](https://github.com/EdwinMoq/android_kernel_oneplus_sdm845)：内核基线
- LineageOS、OnePlus 及各上游贡献者

## 许可与免责

内核部分遵循 GPL-2.0-only，ReSukiSU 及 SUSFS 各自的许可证请参考其仓库。`ak3/anykernel.sh` 基于 AnyKernel3 模板，AnyKernel3 本身的许可证见其仓库。本项目按现状提供，不对设备损坏、数据丢失或其他后果负责，使用风险自负。
