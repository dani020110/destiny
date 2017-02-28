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

BUILD_START=$(date +"%s")

LGREEN='\033[1;32m'
GREEN='\033[0;32m'
WHITE='\033[1;37m'
PINK='\033[1;35m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NCOLOR='\033[0m'

export CROSS_COMPILE=/media/DATOS/desarrollo/kernel/toolchain/ubertc_kernel/aarch64-linux-android-4.9-kernel/bin/aarch64-linux-android-
#export CROSS_COMPILE=/media/DATOS/desarrollo/kernel/toolchain/linaro-4.9_aarch64-kernel/bin/aarch64-linux-gnu-

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
make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE -j$(grep -c ^processor /proc/cpuinfo)
echo ""

echo -e "${GREEN}Making the boot image${NCOLOR}"
../build_tools/bootimg mkimg --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" --base 0x81dfff00 --kernel arch/arm64/boot/Image.gz-dtb --ramdisk ../build_tools/ramdisks/e2306-ramdisk.cpio.gz --ramdisk_offset 0x82000000 --pagesize 2048 --tags_offset 0x81E00000 -o destiny-r3.img

BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))
echo -e "${LGREEN}Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds!${NCOLOR}"
