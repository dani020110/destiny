#!/bin/bash
TIMESTAMP=`date +"%d%m%Y"`
LGREEN='\033[1;32m'
GREEN='\033[0;32m'
WHITE='\033[1;37m'
PINK='\033[1;35m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NCOLOR='\033[0m'

export CROSS_COMPILE=/media/DATOS/desarrollo/kernel/toolchain/ubertc_kernel/aarch64-linux-android-4.9-kernel/bin/aarch64-linux-android-

echo -e "${WHITE}Cleaning up${NCOLOR}"
make mrproper
rm *.img
#To do: find a workaround for the .dtb's not being deleted
rm $(find -name '*.dtb')
echo ""

echo -e "${PINK}Compiling for tulip${NCOLOR}"
make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE kanuti-tulip_defconfig
echo ""

echo -e "${BLUE}Let's start the kernel compilation${NCOLOR}"
echo ""
time make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE -j$(grep -c ^processor /proc/cpuinfo)
echo ""

#echo -e "${LGREEN}Making the boot image for all the variants${NCOLOR}"
../build_tools/bootimg mkimg --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" --base 0x81dfff00 --kernel arch/arm64/boot/Image.gz-dtb --ramdisk ../build_tools/ramdisks/e2306-ramdisk.cpio.gz --ramdisk_offset 0x82000000 --pagesize 2048 --tags_offset 0x81E00000 -o foykernel_${TIMESTAMP}_e2306.img

../build_tools/bootimg mkimg --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" --base 0x81dfff00 --kernel arch/arm64/boot/Image.gz-dtb --ramdisk ../build_tools/ramdisks/e2303-ramdisk.cpio.gz --ramdisk_offset 0x82000000 --pagesize 2048 --tags_offset 0x81E00000 -o foykernel_${TIMESTAMP}_e2303.img

../build_tools/bootimg mkimg --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" --base 0x81dfff00 --kernel arch/arm64/boot/Image.gz-dtb --ramdisk ../build_tools/ramdisks/e2312-ramdisk.cpio.gz --ramdisk_offset 0x82000000 --pagesize 2048 --tags_offset 0x81E00000 -o foykernel_${TIMESTAMP}_e2312.img

../build_tools/bootimg mkimg --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" --base 0x81dfff00 --kernel arch/arm64/boot/Image.gz-dtb --ramdisk ../build_tools/ramdisks/e2312-ramdisk.cpio.gz --ramdisk_offset 0x82000000 --pagesize 2048 --tags_offset 0x81E00000 -o foykernel_${TIMESTAMP}_e2312.img

../build_tools/bootimg mkimg --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" --base 0x81dfff00 --kernel arch/arm64/boot/Image.gz-dtb --ramdisk ../build_tools/ramdisks/e2353-ramdisk.cpio.gz --ramdisk_offset 0x82000000 --pagesize 2048 --tags_offset 0x81E00000 -o foykernel_${TIMESTAMP}_e2353.img

echo -e "${GREEN}The kernel has been built successfully${NCOLOR}"
