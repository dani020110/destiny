#!/bin/bash
#
# Copyright © 2017, Daniel Vásquez "dani020110" <danielgusvt@yahoo.com>
#
# This software is licensed under the terms of the GNU General Public
# License version 2, as published by the Free Software Foundation, and
# may be copied, distributed, and modified under those terms.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#

# Colors
BCYAN='\033[1;36m'
LGREEN='\033[1;32m'
GREEN='\033[0;32m'
WHITE='\033[1;37m'
PINK='\033[1;35m'
BBLUE='\033[1;34m'
YELLOW='\033[1;33m'
NCOLOR='\033[0m'

# Release
export REL="6"

# Kernel-related files
BTOOLS=../build_tools
BOOTIMAGE=$BTOOLS/destiny-r$REL.img
WLANM=$BTOOLS/zipme/system/lib/modules/pronto/pronto_wlan.ko
RAMDISK=$BTOOLS/ramdisk.cpio.gz

clear && echo -e "${BCYAN}Hi $USER, you are building the destiny kernel!${NCOLOR}"

export CROSS_COMPILE=/media/DATOS/desarrollo/kernel/toolchain/ubertc_kernel/aarch64-linux-android-4.9-kernel/bin/aarch64-linux-android-

echo -e "${WHITE}Cleaning up${NCOLOR}"
make mrproper
rm dtb.img
rm $BOOTIMAGE
rm $BTOOLS/boot.img
#To do: find a workaround for the .dtb's not being deleted
rm $(find -name '*.dtb')
echo ""

set -e

BUILD_START=$(date +"%s")

echo -e "${PINK}Compiling for tulip${NCOLOR}"
make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE kanuti-tulip_defconfig
echo ""

echo -e "${BBLUE}Let's start the kernel compilation${NCOLOR}"
echo ""
make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE -j$(grep -c ^processor /proc/cpuinfo)
echo ""

echo -e "${YELLOW}Making dtb.img...${NCOLOR}"
echo ""
$BTOOLS/dtbToolCM -2 -o dtb.img -s 2048 -p scripts/dtc/ arch/arm/boot/dts/ && echo -e "${YELLOW}Done!${NCOLOR}"
echo ""

echo -e "${BBLUE}Would you like to pack the ramdisk? [y/ignore]${NCOLOR}"
read ans
if [ $ans = y -o $ans = Y -o $ans = yes -o $ans = Yes -o $ans = YES ]
then
cd $BTOOLS
rm ramdisk.cpio.gz
./mkbootfs ramdisk | gzip -n -f > ramdisk.cpio.gz && echo -e "${YELLOW}Done!${NCOLOR}"
echo ""
cd ../kernel
fi

echo -e "${GREEN}Making the boot image...${NCOLOR}"
#This way could boot in some variants
#$BTOOLS/bootimg mkimg --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" --base 0x81dfff00 --kernel arch/arm64/boot/Image.gz-dtb --ramdisk $RAMDISK --ramdisk_offset 0x82000000 --pagesize 2048 --tags_offset 0x81E00000 -o $BOOTIMAGE

$BTOOLS/mkbootimg --kernel arch/arm64/boot/Image --ramdisk $RAMDISK --dt dtb.img --base 0x81dfff00 --ramdisk_offset 0x82000000 --tags_offset 0x81E00000 --pagesize 2048 --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" -o $BOOTIMAGE && echo -e "${GREEN}Done!${NCOLOR}"

BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))
echo -e "${LGREEN}Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds! Image located in $(realpath $BOOTIMAGE)${NCOLOR}"

echo -e "${BBLUE}Would you like to pack the flashable zip now? [y/ignore]${NCOLOR}"
read ans
if [ $ans = y -o $ans = Y -o $ans = yes -o $ans = Yes -o $ans = YES ]
then
cp drivers/staging/prima/wlan.ko $WLANM
cd $BTOOLS
rm zipme/*.img
cp destiny-r$REL.img zipme/boot.img
sh packzip.sh
fi
