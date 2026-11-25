# kernel_oneplus_sdm845-4.19 · SUSFS v2.4.0 + ReSukiSU

一加 6 / 6T（enchilada / fajita，SDM845）4.19 内核，在上游源码基础上加入 **SUSFS v2.4.0**（手动回移植）和 **ReSukiSU**（BakaSU）。

> English: OnePlus 6/6T (SDM845) 4.19.325 kernel with SUSFS v2.4.0 (hand-backported to 4.19) and ReSukiSU built in. Branch: `susfs240-resukisu`. The previous SUSFS v2.3.0 version is on branch `susfs230-resukisu`.

---

## 版本信息

| 项目       | 内容                                                                                                                |
| -------- | ----------------------------------------------------------------------------------------------------------------- |
| 设备       | OnePlus 6 (enchilada) / OnePlus 6T (fajita)                                                                       |
| 内核       | 4.19.325（非 GKI）                                                                                                   |
| 内核基线     | [EdwinMoq/android_kernel_oneplus_sdm845](https://github.com/EdwinMoq/android_kernel_oneplus_sdm845) @ `fd77fc2e3` |
| ReSukiSU | 固定在 `57b2db60`（v4.2.0-rc3 系列，内核驱动版本 35285），以 git 子模块引入，路径 `ReSukiSU/`                                           |
| SUSFS    | v2.4.0，内核侧来自 susfs4ksu 的 `gki-android12-5.10` 分支 `784ac9e`，手动回移植到 4.19（v2.3.0 基线为 `eb95da0`）                    |
| Hook 方式  | SUSFS Inline Hook（`CONFIG_KSU_SUSFS`）                                                                             |

`drivers/kernelsu` 是指向 `../ReSukiSU/kernel` 的软链接。

## 为什么要回移植

simonpunk 官方的 `kernel-4.19` 分支停留在 SUSFS v1.5.5，而当前 ReSukiSU 只跟进新版 SUSFS，两者对不上。2.x 官方只维护 GKI 分支，所以 4.19 上用 2.x 只能自己回移植。

v2.3.0 的回移植参考了 [fabiannabil1/susfs-4.19-nongki](https://github.com/fabiannabil1/susfs-4.19-nongki)（针对 LG V60 / lge_sm8250 的 4.19 参考移植）。它不是通用补丁，本仓库针对一加 SDM845 树重新核对并手动合并了冲突的部分。

## 从 v2.3.0 升级到 v2.4.0 做了什么

只移植了上游 `eb95da0` 到 `784ac9e` 之间的差量：

- **自包含文件**（`fs/susfs.c`、`include/linux/susfs.h`、`susfs_def.h`）：三方合并，无冲突。4.19 的适配只有两处：fsnotify 回调改用 `.handle_event`（4.19 的接口），`susfs_def.h` 增加 `<linux/cred.h>`。
- **priority_uid_filter**（`block/ioprio.c`、`kernel/sys.c`）：直接应用。
- **sus_path 按进程 uid 过滤**（`fs/namei.c`、`fs/readdir.c`）：手动合并，getdents 系列不再调用 `susfs_get_data_path`。
- **selinux_hide**（`security/selinux/` 下的 `hooks.c`、`selinuxfs.c`、`ss/status.c`、`ss/services.c`）：4.19 没有 `struct selinux_policy`，`services.c` 里新增的 `susfs_security_*` 函数以 4.19 原有的 `state->ss->policydb`、`policy_rwlock`、`hashtab_search` 为基础改写。
- 日志关闭时补了 `SUSFS_LOGI_RL` 的空定义，否则无法编译。
- ReSukiSU 要求的 hook 逐项核对过（`exec.c`、`open.c`、`read_write.c`、`stat.c`、`reboot.c`、`input.c`、`sys.c`），编译期的 hook 检查通过。

### 4.19 上的已知限制

沿用 v2.3.0 移植时的说明，未针对新版重新核对：

- 没有接入 module preinit hook（4.19 的 exec 重试流程不好安全展开，写错会导致 bootloop）。
- `struct kstat` 没有 `mnt_id`，相关代码已去掉。
- Open redirect 在 `do_filp_open()` 中实现。

## 验证情况

已验证（OnePlus 6T）：

- 完整编译并链接通过，生成 `Image.gz-dtb`。
- 可以开机，`getenforce` 为 Enforcing。
- 管理器授权后 `id` 为 uid=0，上下文 `u:r:ksu:s0`。
- dmesg 中驱动版本 35285，`v4.2.0-rc3-57b2db60`。
- `ksu_susfs show version` 返回 `v2.4.0`；`show enabled_features` 返回 SUS_PATH、SUS_MOUNT、SUS_KSTAT、SPOOF_UNAME、HIDE_KSU_SUSFS_SYMBOLS、SPOOF_CMDLINE_OR_BOOTCONFIG、OPEN_REDIRECT、SUS_MAP、PRIORITY_UID_FILTER。
- 没有 ksu / su 域被 SELinux 拒绝的记录。

已知现象：开机约 10 秒时 dmesg 有一条 `mm/memcontrol.c` 的 `mem_cgroup_update_lru_size` WARNING，发生在本次未改动的 mm 代码里，尚未确认与 SUSFS 无关。

**尚未验证**：SUSFS 各项隐藏功能的实际效果、Zygisk 等模块的运行情况、长时间使用的稳定性。只在 6T 上测试过，6（enchilada）没有测试。

## 编译

需要 clang 和 aarch64 binutils（我用的是 clang r563880 + `aarch64-linux-android-`）。

```
git clone --recurse-submodules -b susfs240-resukisu \
  https://github.com/qiao-q-bot/kernel_oneplus_sdm845-4.19.git
cd kernel_oneplus_sdm845-4.19
# 已有克隆的话：git submodule update --init

export ARCH=arm64
MK="O=out ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
CROSS_COMPILE=aarch64-linux-android- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
CLANG_TRIPLE=aarch64-linux-gnu-"

make $MK vendor/sdm845-perf_defconfig vendor/enchilada.config vendor/susfs.config
make -j$(nproc) $MK
```

**必须带上 `vendor/susfs.config`**。KernelSU 的 hook 方式是单选项，不带这个片段会落到默认的 tracepoint hook，它只支持 GKI 5.10+，在 4.19 上不能用。片段内容：

```
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
# CONFIG_KSU_SUSFS_ENABLE_LOG is not set
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER=y
```

产物：`out/arch/arm64/boot/Image.gz-dtb`（dtb 已追加在内核后面）。`ENABLE_LOG` 默认关闭，它会把 SUSFS 的操作写进内核日志。

## 刷入

> ⚠️ 需要已解锁 bootloader。刷机有风险，**先备份原厂 boot**，并先用 `fastboot boot` 试启动，确认能正常进系统之后再考虑刷写。

**方式一：AnyKernel3 刷机包。** 把 `Image.gz-dtb` 放进 AnyKernel3 目录打包，用 recovery 刷入。包内做了设备检查，只适用于 enchilada / fajita。

**方式二：magiskboot 重打包。**

1. 取得与当前系统版本一致的原厂 `boot.img`。
2. 用 magiskboot 解包，把解出来的 `kernel` 换成 `Image.gz-dtb`，删掉单独的 `kernel_dtb`（dtb 已在内核里），重新打包：

   ```
   magiskboot unpack -h boot.img
   rm -f kernel_dtb
   cp Image.gz-dtb kernel
   magiskboot repack boot.img boot_new.img
   ```

3. 临时启动，不改动分区：

   ```
   fastboot boot boot_new.img
   ```

4. 安装与内核同期的 ReSukiSU 管理器（内核驱动版本为 35285，管理器版本要匹配，不要随意升级）。

## 使用提示

- ReSukiSU 和官方 KernelSU 3.0 以后一样，自己不挂载模块，需要安装 metamodule（如 `meta-overlayfs`）。meta-overlayfs 依赖内核的 `CONFIG_OVERLAY_FS`，没有的话换 Magic Mount 类的 metamodule。
- 旧版 `susfs4ksu` 模块（v1.5.x）与内核里的 SUSFS 2.4.0 不匹配，不要安装。
- 不建议对 `/sdcard` 的子路径使用 `sus_path`，文件管理器类应用可能显示异常。
- `ksu_susfs add_sus_path` 只对 uid ≥ 10000 且处于 umounted 状态的进程生效。

## 致谢

- [simonpunk / susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)：SUSFS
- [ReSukiSU / BakaSU](https://github.com/ReSukiSU/ReSukiSU)：root 方案
- [fabiannabil1/susfs-4.19-nongki](https://github.com/fabiannabil1/susfs-4.19-nongki)：SUSFS v2.3.0 的 4.19 参考移植
- [EdwinMoq/android_kernel_oneplus_sdm845](https://github.com/EdwinMoq/android_kernel_oneplus_sdm845)：内核基线
- LineageOS、OnePlus 及各上游贡献者

## 许可与免责

内核部分遵循 GPL-2.0-only，ReSukiSU 及 SUSFS 各自的许可证请参考其仓库。本项目按现状提供，不对设备损坏、数据丢失或其他后果负责，使用风险自负。
