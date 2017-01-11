#!/bin/bash
TIMESTAMP=`date +"%d%m%Y"`
LGREEN='\033[1;32m'
GREEN='\033[0;32m'
WHITE='\033[1;37m'
PINK='\033[1;35m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'

export CROSS_COMPILE=/media/DATOS/desarrollo/kernel/toolchain/ubertc_kernel/aarch64-linux-android-4.9-kernel/bin/aarch64-linux-android-

echo -e "${WHITE}Cleaning up"
make mrproper
rm ../dtb.img
#To do: find a workaround for the .dtb's not being deleted
rm $(find -name '*.dtb')
echo ""

echo -e "${PINK}Compiling for tulip"
make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE kanuti-tulip_defconfig
echo ""

echo -e "${BLUE}Let's start the kernel compilation"
echo ""
time make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE -j$(grep -c ^processor /proc/cpuinfo)
echo ""

echo -e "${YELLOW}Making dtb.img"
echo ""
../dtbToolCM -2 -o ../dtb.img -s 2048 -p scripts/dtc/ arch/arm/boot/dts/
echo ""

echo -e "${LGREEN}Making the boot image"
../build_tools/mkbootimg --kernel arch/arm64/boot/Image --ramdisk ../ramdisk-e2306.cpio.gz --dt ../dtb.img --base 0x81dfff00 --ramdisk_offset 0x82000000 --tags_offset 0x81E00000 --pagesize 2048 --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" -o ../foykernel_$TIMESTAMP.img

echo -e "${GREEN}The kernel has been built successfully"
