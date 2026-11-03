# kernel_oneplus_sdm845-4.19 · SUSFS v2.3.0 + ReSukiSU

一加 6 / 6T（enchilada / fajita，SDM845）4.19 内核，在上游源码基础上加入 **SUSFS v2.3.0**（手动回移植）和 **ReSukiSU**（BakaSU）。

> English: OnePlus 6/6T (SDM845) 4.19.325 kernel with SUSFS v2.3.0 (hand-backported to 4.19) and ReSukiSU built in. Branch: `susfs230-resukisu`.

---

## 版本信息

| 项目 | 内容 |
|---|---|
| 设备 | OnePlus 6 (enchilada) / OnePlus 6T (fajita) |
| 内核 | 4.19.325（非 GKI） |
| 内核基线 | [EdwinMoq/android_kernel_oneplus_sdm845](https://github.com/EdwinMoq/android_kernel_oneplus_sdm845) @ `fd77fc2e3` |
| ReSukiSU | 固定在 `d5e9e025`（v4.2.0-rc3），以 git 子模块引入，路径 `ReSukiSU/` |
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

## 验证情况

已验证：

- 编译通过（`-Werror` 下无 ksu / susfs 相关警告），日志识别到 `SUSFS_VERSION: v2.3.0`。
- `Module.symvers` 与未打补丁的基线逐行一致，导出符号 CRC 没有变化，vendor 模块不会因为 KABI 变化拒载。
- 在 OnePlus 6T（A6013）上可以启动。
- 管理器显示"工作中 / Built-in"，内核驱动和管理器版本一致（35252），SUSFS 版本显示 v2.3.0，`su` 上下文为 `u:r:ksu:s0`。

**尚未验证**：SUSFS 各项隐藏功能的实际效果，以及 Zygisk 等模块的运行情况。只在 6T 上测试过，6（enchilada）没有测试。

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

然后把下面的 SUSFS 配置追加进 `out/.config`，再 `olddefconfig` 并编译：

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
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
```

```sh
cat susfs.fragment >> out/.config   # 上面的配置存成这个文件
make $MK olddefconfig
make -j$(nproc) $MK
```

产物：`out/arch/arm64/boot/Image.gz-dtb`（dtb 已追加在内核后面）。

> 正式使用时建议关掉 `CONFIG_KSU_SUSFS_ENABLE_LOG`，它会把 SUSFS 的操作写进内核日志。

## 刷入

> ⚠️ 需要已解锁 bootloader。刷机有风险，**先备份原厂 boot**，并先用 `fastboot boot` 试启动，确认能正常进系统之后再考虑刷写。

1. 取得与当前系统版本一致的原厂 `boot.img`。
2. 用 magiskboot 解包，把解出来的 `kernel` 换成 `Image.gz-dtb`，删掉单独的 `kernel_dtb`（dtb 已在内核里），重新打包：
   ```sh
   magiskboot unpack -h boot.img
   rm -f kernel_dtb
   cp Image.gz-dtb kernel
   magiskboot repack boot.img boot_new.img
   ```
3. 临时启动，不改动分区：
   ```sh
   fastboot boot boot_new.img
   ```
4. 安装与内核同期的 ReSukiSU 管理器（内核驱动版本为 35252，管理器版本要匹配，不要随意升级）。

## 使用提示

- ReSukiSU 和官方 KernelSU 3.0 以后一样，自己不挂载模块，需要安装 metamodule（如 `meta-overlayfs`）。meta-overlayfs 依赖内核的 `CONFIG_OVERLAY_FS`，没有的话换 Magic Mount 类的 metamodule。
- 旧版 `susfs4ksu` 模块（v1.5.x）与内核里的 SUSFS 2.3.0 不匹配，不要安装。SUSFS 可以在管理器内置的 SUSFS 页面管理。

## 致谢

- [simonpunk / susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)：SUSFS
- [ReSukiSU / BakaSU](https://github.com/ReSukiSU/ReSukiSU)：root 方案
- [fabiannabil1/susfs-4.19-nongki](https://github.com/fabiannabil1/susfs-4.19-nongki)：SUSFS v2.3.0 的 4.19 参考移植
- [EdwinMoq/android_kernel_oneplus_sdm845](https://github.com/EdwinMoq/android_kernel_oneplus_sdm845)：内核基线
- LineageOS、OnePlus 及各上游贡献者

## 许可与免责

内核部分遵循 GPL-2.0-only，ReSukiSU 及 SUSFS 各自的许可证请参考其仓库。本项目按现状提供，不对设备损坏、数据丢失或其他后果负责，使用风险自负。
