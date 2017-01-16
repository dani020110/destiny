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
export out=/media/DATOS/desarrollo/output/kernel

echo -e "${WHITE}Cleaning up${NCOLOR}"
make O=${out} mrproper
rm ${out}/*.img
#To do: find a workaround for the .dtb's not being deleted
rm $(find ${out} -name '*.dtb')
echo ""

echo -e "${PINK}Compiling for tulip${NCOLOR}"
make ARCH=arm64 O=${out} CROSS_COMPILE=$CROSS_COMPILE kanuti-tulip_defconfig
echo ""

echo -e "${BLUE}Let's start the kernel compilation${NCOLOR}"
echo ""
time make ARCH=arm64 O=${out} CROSS_COMPILE=$CROSS_COMPILE -j$(grep -c ^processor /proc/cpuinfo)
echo ""

echo -e "${YELLOW}Making dtb.img${NCOLOR}"
echo ""
../build_tools/dtbToolCM -2 -o ${out}/dtb.img -s 2048 -p ${out}/scripts/dtc/ ${out}/arch/arm64/boot/dts/
echo ""

echo -e "${LGREEN}Making the boot image for all the variants${NCOLOR}"
../build_tools/mkbootimg --kernel ${out}/arch/arm64/boot/Image --ramdisk ../build_tools/ramdisks/e2306-ramdisk.cpio.gz --dt ${out}/dtb.img --base 0x81dfff00 --ramdisk_offset 0x82000000 --tags_offset 0x81E00000 --pagesize 2048 --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" -o ${out}/foykernel_${TIMESTAMP}_e2306.img

#Don't build for the other variants yet
#../build_tools/mkbootimg --kernel ${out}/arch/arm64/boot/Image --ramdisk ../build_tools/ramdisks/ramdisk-e2303.cpio.gz --dt ${out}/dtb.img --base 0x81dfff00 --ramdisk_offset 0x82000000 --tags_offset 0x81E00000 --pagesize 2048 --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" -o ${out}/foykernel_${TIMESTAMP}_e2303.img

#../build_tools/mkbootimg --kernel ${out}/arch/arm64/boot/Image --ramdisk ../build_tools/ramdisks/ramdisk-e2312.cpio.gz --dt ${out}/dtb.img --base 0x81dfff00 --ramdisk_offset 0x82000000 --tags_offset 0x81E00000 --pagesize 2048 --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" -o ${out}/foykernel_${TIMESTAMP}_e2312.img

#../build_tools/mkbootimg --kernel ${out}/arch/arm64/boot/Image --ramdisk ../build_tools/ramdisks/ramdisk-e2333.cpio.gz --dt ${out}/dtb.img --base 0x81dfff00 --ramdisk_offset 0x82000000 --tags_offset 0x81E00000 --pagesize 2048 --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" -o ${out}/foykernel_${TIMESTAMP}_e2333.img

#../build_tools/mkbootimg --kernel ${out}/arch/arm64/boot/Image --ramdisk ../build_tools/ramdisks/ramdisk-e2353.cpio.gz --dt ${out}/dtb.img --base 0x81dfff00 --ramdisk_offset 0x82000000 --tags_offset 0x81E00000 --pagesize 2048 --cmdline "console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk" -o ${out}/foykernel_${TIMESTAMP}_e2353.img

echo -e "${GREEN}The kernel has been built successfully${NCOLOR}"
