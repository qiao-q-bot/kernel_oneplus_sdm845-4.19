### AnyKernel3 Ramdisk Mod Script
## SUSFS v2.3.0 + ReSukiSU kernel for OnePlus 6/6T (SDM845, 4.19)

### AnyKernel setup
# global properties
properties() { '
kernel.string=OnePlus 6/6T 4.19 SUSFS v2.3.0 + ReSukiSU
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=enchilada
device.name2=fajita
device.name3=OnePlus6T
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
dump_boot;
write_boot;
## end boot install
