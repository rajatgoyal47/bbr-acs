#!/usr/bin/env bash

# Copyright (c) 2021-2023, ARM Limited and Contributors. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# Neither the name of ARM nor the names of its contributors may be used
# to endorse or promote products derived from this software without specific
# prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

#
# This script uses the following environment variables from the variant
#
# VARIANT - build variant name
# TOP_DIR - workspace root directory
# CROSS_COMPILE - PATH to GCC including CROSS-COMPILE prefix
# PARALLELISM - number of cores to build across
# UEFI_BUILD_ENABLED - Flag to enable building UEFI
# UEFI_PATH - sub-directory containing UEFI code
# UEFI_BUILD_MODE - DEBUG or RELEASE
# UEFI_TOOLCHAIN - Toolchain supported by Linaro uefi-tools: GCC49, GCC48 or GCC47
# UEFI_PLATFORMS - List of platforms to build
# UEFI_PLAT_{platform name} - array of platform parameters:
#     - platname - the name of the platform used by the build
#     - makefile - the makefile to execute for this platform
#     - output - where to store the files in packaging phase
#     - defines - extra platform defines during the build
#     - binary - what to call the final output binary

TOP_DIR=`pwd`
UEFI_PATH=edk2
SCT_PATH=edk2-test
UEFI_TOOLCHAIN=GCC5
UEFI_BUILD_MODE=DEBUG
TARGET_ARCH=ARM

. $TOP_DIR/../../common/config/common_config.cfg
. $TOP_DIR/../../common/scripts/cross_toolchain-arm.sh

# Only build Full SystemReady IR
BUILD_PLAT=IR
BUILD_TYPE=F

BBR_DIR=$TOP_DIR/bbr-acs

echo "Target: $BUILD_PLAT"
echo "Build type: $BUILD_TYPE"

SBBR_TEST_DIR=$BBR_DIR/common/sct-tests/sbbr-tests

do_build()
{
    pushd $TOP_DIR/$SCT_PATH

    export EDK2_TOOLCHAIN=$UEFI_TOOLCHAIN
    export ${UEFI_TOOLCHAIN}_ARM_PREFIX=$CROSS_COMPILE
    local vars=
    export PACKAGES_PATH=$TOP_DIR/$UEFI_PATH
    export PYTHON_COMMAND=/usr/bin/python3
    export WORKSPACE=$TOP_DIR/$SCT_PATH/uefi-sct

    #Build base tools
    source $TOP_DIR/$UEFI_PATH/edksetup.sh
    make -C $TOP_DIR/$UEFI_PATH/BaseTools
    
    #Copy over extra files needed for SBBR tests
    cp -r $SBBR_TEST_DIR/SbbrBootServices          uefi-sct/SctPkg/TestCase/UEFI/EFI/BootServices/
    cp -r $SBBR_TEST_DIR/SbbrEfiSpecVerLvl         uefi-sct/SctPkg/TestCase/UEFI/EFI/Generic/
    cp -r $SBBR_TEST_DIR/SbbrRequiredUefiProtocols uefi-sct/SctPkg/TestCase/UEFI/EFI/Generic/
    cp -r $SBBR_TEST_DIR/SbbrSysEnvConfig          uefi-sct/SctPkg/TestCase/UEFI/EFI/Generic/
    cp -r $SBBR_TEST_DIR/SBBRRuntimeServices       uefi-sct/SctPkg/TestCase/UEFI/EFI/RuntimeServices/
    cp $SBBR_TEST_DIR/BBR_SCT_arm.dsc              uefi-sct/SctPkg/UEFI/
    cp $SBBR_TEST_DIR/build_bbr_arm.sh             uefi-sct/SctPkg/
    
    #Startup/runtime files.
    mkdir -p uefi-sct/SctPkg/BBR
    #EBBR
    cp $BBR_DIR/ebbr/config/EBBRStartup.nsh uefi-sct/SctPkg/BBR/
    cp $BBR_DIR/ebbr/config/EBBR-arm.seq uefi-sct/SctPkg/BBR/EBBR.seq
    cp $BBR_DIR/ebbr/config/EBBR_manual.seq uefi-sct/SctPkg/BBR/
    cp $BBR_DIR/ebbr/config/EfiCompliant_EBBR.ini uefi-sct/SctPkg/BBR/

    if git apply --check $BBR_DIR/common/patches/edk2-test-bbr-build.patch; then
        echo "Applying edk2-test BBR build patch..."
        git apply --ignore-whitespace --ignore-space-change $BBR_DIR/common/patches/edk2-test-bbr-build.patch
    else
        echo  "Error while applying edk2-test BBR build patch..."
    fi
    if git apply --check $BBR_DIR/common/patches/edk2-test-bbr.patch; then
        echo "Applying edk2-test BBR patch..."
        git apply --ignore-whitespace --ignore-space-change $BBR_DIR/common/patches/edk2-test-bbr.patch
    else
        echo  "Error while applying edk2-test BBR patch..."
    fi

    pushd uefi-sct
    ./SctPkg/build_bbr_arm.sh $TARGET_ARCH GCC $UEFI_BUILD_MODE
    popd
}

do_clean()
{
    pushd $TOP_DIR/$SCT_PATH/uefi-sct
    CROSS_COMPILE_DIR=$(dirname $CROSS_COMPILE)
    PATH="$PATH:$CROSS_COMPILE_DIR"
    source $TOP_DIR/$UEFI_PATH/edksetup.sh
    make -C $TOP_DIR/$UEFI_PATH/BaseTools clean
    rm -rf Build/bbrSct
    rm -rf ${TARGET_ARCH}_SCT

    popd

}

do_package ()
{
    echo "Packaging sct...";
    # Copy binaries to output folder
    pushd $TOP_DIR/$SCT_PATH/uefi-sct

    mkdir -p ${TARGET_ARCH}_SCT/SCT
    cp -r Build/bbrSct/${UEFI_BUILD_MODE}_${UEFI_TOOLCHAIN}/SctPackage${TARGET_ARCH}/${TARGET_ARCH}/* ${TARGET_ARCH}_SCT/SCT/

    #EBBR
    cp Build/bbrSct/${UEFI_BUILD_MODE}_${UEFI_TOOLCHAIN}/SctPackage${TARGET_ARCH}/EBBRStartup.nsh ${TARGET_ARCH}_SCT/SctStartup.nsh
    cp SctPkg/BBR/EfiCompliant_EBBR.ini ${TARGET_ARCH}_SCT/SCT/Dependency/EfiCompliantBBTest/EfiCompliant.ini
    cp SctPkg/BBR/EBBR_manual.seq ${TARGET_ARCH}_SCT/SCT/Sequence/EBBR_manual.seq

    pushd $TOP_DIR

}

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $DIR/framework.sh $BUILD_PLAT $BUILD_TYPE

