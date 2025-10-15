#!/bin/bash

TOP_DIR=$PWD
KERNEL_NAME="kernel-5.10"

KERNEL_DIR="$TOP_DIR/${KERNEL_NAME}"
KERNEL_OUT="$TOP_DIR/out/target/product/penangf/obj/KERNEL_OBJ"
KERNEL_BUILD_OUT="${KERNEL_OUT}/${KERNEL_NAME}"
MODULES_STAGING_DIR="${KERNEL_OUT}/staging"
KERNEL_DLKM="$TOP_DIR/vendor/mediatek/kernel_modules"
DTC_PATH="$TOP_DIR/prebuilts/build-tools/linux-x86/bin/dtc"
KERNEL_ZIMAGE_OUT="${KERNEL_BUILD_OUT}/arch/arm64/boot/Image.gz"

export CLANG_TRIPLE=
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export CROSS_COMPILE_ARM32=
export ARCH=arm64
export SUBARCH=
export MAKE_GOALS=all
export HOSTCC=clang
export HOSTCXX=clang++
export CC=clang
export LD=ld.lld
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export OBJSIZE=llvm-size
export STRIP=llvm-strip

export PATH="$TOP_DIR/prebuilts/build-tools/path/linux-x86:$TOP_DIR/prebuilts/clang/host/linux-x86/clang-r416183b/bin:$TOP_DIR/kernel/prebuilts/kernel-build-tools/linux-x86/bin:$PATH"


function git_clone() {
    local url=$1
    local branch=$2
    local dir=$3

    if [ ! -d "$dir" ]; then
      git clone --depth 1 -b "$branch" "$url" "$dir"
    fi
}

function setup_google_tools() {
  echo ">> Downloading toolchain"
  mkdir -p "$TOP_DIR/prebuilts/clang/host"
  cd "$TOP_DIR/prebuilts/clang/host"
  git_clone https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 aml_tz3_314012010 linux-x86
  cd "$TOP_DIR/prebuilts"
  git_clone https://android.googlesource.com/kernel/prebuilts/build-tools master build-tools
}

function download_kernel_src() {
  echo ">> Downloading kernel source..."
  cd "$TOP_DIR"
  git_clone https://github.com/moto-penangf/kernel-penangf main ${KERNEL_NAME}
}

function download_prebuilts() {
    echo ">> Downloading prebuilts"
    mkdir -p "$TOP_DIR/kernel/prebuilts"
    cd "$TOP_DIR/kernel/prebuilts"
    git_clone https://github.com/MotorolaMobilityLLC/kernel-prebuilts-kernel-build-tools.git android-14-release-uhas34.29 kernel-build-tools
}

function download_modules() {
    echo ">> Downloading kernel modules"
    mkdir -p "$KERNEL_DLKM"
    cd "$KERNEL_DLKM"

    declare -A MODULES=(
        [gpu]="vendor-mediatek-kernel_modules-gpu"
        [met_drv_v3]="vendor-mediatek-kernel_modules-met_drv_v3"
        [connectivity/gps]="vendor-mediatek-kernel_modules-connectivity-gps"
        [connectivity/common]="vendor-mediatek-kernel_modules-connectivity-common"
        [connectivity/fmradio]="vendor-mediatek-kernel_modules-connectivity-fmradio"
        [connectivity/connfem]="vendor-mediatek-kernel_modules-connectivity-connfem"
        [connectivity/wlan/adaptor]="vendor-mediatek-kernel_modules-connectivity-wlan-adaptor"
        [connectivity/wlan/core/gen4m]="vendor-mediatek-kernel_modules-connectivity-wlan-core-gen4m"
        [connectivity/bt/mt66xx]="vendor-mediatek-kernel_modules-connectivity-bt-mt66xx"
        [udc]="vendor-mediatek-kernel_modules-udc"
    )

    for path in "${!MODULES[@]}"; do
        local repo="${MODULES[$path]}"
        git_clone "https://github.com/MotorolaMobilityLLC/$repo.git" android-14-release-uhas34.29 "$path"
    done
}

function build_kernel() {
  echo ">> Building kernel manually..."
  mkdir -p "$KERNEL_OUT"

  python "$KERNEL_DIR/scripts/gen_build_config.py" \
    --kernel-defconfig penangf_defconfig \
    --kernel-defconfig-overlays "" \
    --kernel-build-config-overlays "" \
    -m user \
    -o "$KERNEL_OUT/build.config"

  cp "$KERNEL_DIR/arch/arm64/configs/penangf_defconfig" "$KERNEL_OUT/penangf.config"
  cd "$KERNEL_DIR"
  rm -f "$KERNEL_BUILD_OUT/.config"

  make O="$KERNEL_BUILD_OUT" LLVM=1 LLVM_IAS=1 gki_defconfig
  ./scripts/kconfig/merge_config.sh -m -O "$KERNEL_BUILD_OUT" \
    "$KERNEL_BUILD_OUT/.config" "$KERNEL_OUT/penangf.config"

  make O="$KERNEL_BUILD_OUT" LLVM=1 LLVM_IAS=1 olddefconfig
  make -j$(nproc) O="$KERNEL_BUILD_OUT" LLVM=1 LLVM_IAS=1 DTC="$DTC_PATH" all vmlinux
  make -j$(nproc) O="$KERNEL_BUILD_OUT" LLVM=1 LLVM_IAS=1 DTC="$DTC_PATH" \
    INSTALL_MOD_PATH="$MODULES_STAGING_DIR" modules_install
}

function build_external_module() {
  local path=$1
  local extra_args=("${@:2}")

  echo ">> Building external module: $path"
  mkdir -p "$KERNEL_OUT/$path"

  make -j$(nproc) -C "$KERNEL_DIR" \
    M="$TOP_DIR/$path" \
    KERNEL_SRC="$KERNEL_DIR" \
    O="$KERNEL_BUILD_OUT" \
    LLVM=1 LLVM_IAS=1 \
    DEPMOD=depmod \
    DTC="$DTC_PATH" \
    AUTOCONF_H="$KERNEL_BUILD_OUT/include/generated/autoconf.h" \
    "${extra_args[@]}"

  if [ $? -eq 0 ]; then
    make -j$(nproc) -C "$KERNEL_DIR" \
      M="$TOP_DIR/$path" \
      KERNEL_SRC="$KERNEL_DIR" \
      O="$KERNEL_BUILD_OUT" \
      LLVM=1 LLVM_IAS=1 \
      DEPMOD=depmod \
      DTC="$DTC_PATH" \
      INSTALL_MOD_PATH="$MODULES_STAGING_DIR" \
      AUTOCONF_H="$KERNEL_BUILD_OUT/include/generated/autoconf.h" \
      "${extra_args[@]}" \
      modules_install
  fi
}

###########################################################

echo "================================================"
echo "Penangf Kernel build script"
echo "================================================"

echo "Building kernel in $TOP_DIR"

setup_google_tools
download_kernel_src
download_prebuilts
download_modules
build_kernel

echo ">> Building core connectivity module"
build_external_module "vendor/mediatek/kernel_modules/connectivity/common"

mkdir -p "$TOP_DIR/ETC/wmt_drv.ko_intermediates/LINKED"
cp "$TOP_DIR/vendor/mediatek/kernel_modules/connectivity/common/Module.symvers" \
   "$TOP_DIR/ETC/wmt_drv.ko_intermediates/LINKED/"

echo ">> Building met_drv_v3 module"
build_external_module "vendor/mediatek/kernel_modules/met_drv_v3"

echo ">> Building GPU module"
build_external_module "vendor/mediatek/kernel_modules/gpu/platform/mt6768"

echo ">> Building FM Radio module with WMT dependencies"
build_external_module "vendor/mediatek/kernel_modules/connectivity/fmradio" \
  KBUILD_EXTRA_SYMBOLS="$TOP_DIR/vendor/mediatek/kernel_modules/connectivity/common/Module.symvers"

echo ">> Building GPS module with WMT dependencies"
build_external_module "vendor/mediatek/kernel_modules/connectivity/gps/gps_stp" \
  KBUILD_EXTRA_SYMBOLS="$TOP_DIR/vendor/mediatek/kernel_modules/connectivity/common/Module.symvers"

echo ">> Building ConnFEM module"
build_external_module "vendor/mediatek/kernel_modules/connectivity/connfem"
cp "$TOP_DIR/vendor/mediatek/kernel_modules/connectivity/connfem/Module.symvers" \
   "$TOP_DIR/ETC/connfem.ko_intermediates/LINKED/"

echo ">> Building WLAN adaptor"
build_external_module "vendor/mediatek/kernel_modules/connectivity/wlan/adaptor" \
  KBUILD_EXTRA_SYMBOLS="$TOP_DIR/vendor/mediatek/kernel_modules/connectivity/common/Module.symvers" \
  CONNAC_VER=1_0 \
  MODULE_NAME=wmt_chrdev_wifi

cp "$TOP_DIR/vendor/mediatek/kernel_modules/connectivity/wlan/adaptor/Module.symvers" \
   "$TOP_DIR/ETC/wmt_chrdev_wifi.ko_intermediates/LINKED/"

echo ">> Building WLAN core"
build_external_module "vendor/mediatek/kernel_modules/connectivity/wlan/core/gen4m" \
  KBUILD_EXTRA_SYMBOLS="$TOP_DIR/vendor/mediatek/kernel_modules/connectivity/wlan/adaptor/Module.symvers $TOP_DIR/vendor/mediatek/kernel_modules/connectivity/common/Module.symvers $TOP_DIR/vendor/mediatek/kernel_modules/connectivity/connfem/Module.symvers" \
  CONFIG_MTK_COMBO_WIFI_HIF=axi \
  MODULE_NAME=wlan_drv_gen4m \
  MTK_COMBO_CHIP=CONNAC \
  WLAN_CHIP_ID=6768 \
  MTK_ANDROID_WMT=y \
  WIFI_ENABLE_GCOV= \
  WIFI_IP_SET=1 \
  MTK_ANDROID_EMI=y \
  MTK_WLAN_SERVICE=yes

echo ">> Building Bluetooth module"
build_external_module "vendor/mediatek/kernel_modules/connectivity/bt/mt66xx/wmt" \
  KBUILD_EXTRA_SYMBOLS="$TOP_DIR/vendor/mediatek/kernel_modules/connectivity/common/Module.symvers" \
  BT_PLATFORM=connac1x \
  "LOG_TAG=[BT_Drv][wmt]" \
  BT_ENABLE_LOW_POWER_DEBUG=y

echo ">> Building UDC module"
build_external_module "vendor/mediatek/kernel_modules/udc"

echo "================================================"
echo "Kernel build complete"
echo "Kernel located at $KERNEL_ZIMAGE_OUT"
echo "Modules located at $MODULES_STAGING_DIR"
echo "================================================"
