#!/usr/bin/env sh

KERNELSU_DIR=$(find $KERNEL_DIR -mindepth 0 -maxdepth 4 \( -iname "ksu" -o -iname "kernelsu" \) -type d ! -path "*/.git/*" | cut -c3-)
KERNELSU_GITMODULE=$(grep -i "KernelSU" $KERNEL_DIR/.gitmodules || true)

# Avoid dirty uname
touch $KERNEL_DIR/.scmversion

if [[ $KERNEL_VER == "4.14" ]]; then
    cp $WORKDIR/patches/strip_out_extraversion.patch $KERNEL_DIR/
    cd $KERNEL_DIR && patch -p1 < strip_out_extraversion.patch
    msg "4.14 detected! Removing openela tag..."

    cp $WORKDIR/patches/KernelSU/mapspoof.patch $KERNEL_DIR/
    cd $KERNEL_DIR && patch -p1 < mapspoof.patch
    msg "Adding support for map spoofing on Kernel..."
fi

msg "KernelSU"
if [[ $KSU_ENABLED == "true" ]] && [[ ! -z "$KERNELSU_DIR" ]]; then
    if [[ ! -z "$KERNELSU_GITMODULE" ]]; then
        cd $KERNEL_DIR && git submodule init && git submodule update
        msg "KernelSU submodule detected! Initializing..."
    fi    

    cd $KERNEL_DIR
    echo "CONFIG_KSU=y" >> $DEVICE_DEFCONFIG_FILE

    # Comment this out to allow kprobes fallback
    touch "$KERNEL_DIR/nohook"   

    if [[ ! -z "$KERNELSU_GITMODULE" ]]; then
        KSU_GIT_VERSION=$(cd KernelSU && git rev-list --count HEAD)
        KERNELSU_VERSION=$(($KSU_GIT_VERSION + 30000))
    else
        KERNELSU_VERSION=$(grep "KERNEL_SU_VERSION" "$KERNELSU_DIR/ksu.h" | cut -c26-)
    fi    

    msg "KernelSU Version: $KERNELSU_VERSION"
    sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"-$KERNEL_BRANCH-$KERNEL_NAME-xx\"/" $DEVICE_DEFCONFIG_FILE

elif [[ $KSU_ENABLED == "true" ]]; then
    cd $KERNEL_DIR && curl -LSs "https://raw.githubusercontent.com/$KERNELSU_REPO/main/kernel/setup.sh" | bash -s main

    cd $KERNEL_DIR/KernelSU || exit 1

	if [[ $KSU_MANAGER == "true" ]]; then
	    cd $WORKDIR/out/manager && wget -q https://nightly.link/tiann/KernelSU/workflows/build-manager/main/ksud-x86_64-unknown-linux-musl.zip
	    unzip ksud-x86_64-unknown-linux-musl.zip && mv x86_64-unknown-linux-musl/release/* .
	    rm -rf ksud-x86_64-unknown-linux-musl.zip x86_64-unknown-linux-musl
	    mv *.apk manager.apk && chmod +x ksud
	    MANAGER_SIGNATURE=$(./ksud get-sign manager.apk)
	    MANAGER_EXPECTED_SIZE=$(echo "$MANAGER_SIGNATURE" | grep 'size:' | sed 's/.*size: //; s/,.*//')
	    MANAGER_EXPECTED_HASH=$(echo "$MANAGER_SIGNATURE" | grep 'hash:' | sed 's/.*hash: //; s/,.*//')
            msg "Backporting latest KSU manager..."
	fi

    if [[ ! -z "$MANAGER_EXPECTED_SIZE" ]] && [[ ! -z "$MANAGER_EXPECTED_HASH" ]]; then
	cd $KERNEL_DIR/KernelSU
	sed -i "s/^KSU_EXPECTED_SIZE := .*/KSU_EXPECTED_SIZE := $MANAGER_EXPECTED_SIZE/" kernel/Makefile
	sed -i "s/^KSU_EXPECTED_HASH := .*/KSU_EXPECTED_HASH := $MANAGER_EXPECTED_HASH/" kernel/Makefile
	msg "KSU_EXPECTED_SIZE := $MANAGER_EXPECTED_SIZE"
        msg "KSU_EXPECTED_HASH := $MANAGER_EXPECTED_HASH" && cd $WORKDIR
    fi	

    cd "$KERNEL_DIR"
    # Comment this out to allow kprobes fallback
    touch "$KERNEL_DIR/nohook"

    if [[ ! -f "$KERNEL_DIR/nohook" ]]; then
    echo "CONFIG_KPROBES=y" >> $DEVICE_DEFCONFIG_FILE
	echo "CONFIG_HAVE_KPROBES=y" >> $DEVICE_DEFCONFIG_FILE
	echo "CONFIG_KPROBE_EVENTS=y" >> $DEVICE_DEFCONFIG_FILE
        msg "Hook patches not found! Using kprobes..."
    else
    	echo "CONFIG_KSU=y" >> $DEVICE_DEFCONFIG_FILE
    	echo "CONFIG_KPROBES=n" >> $DEVICE_DEFCONFIG_FILE # it will conflict with KSU hooks if it's on
    fi

    KSU_GIT_VERSION=$(cd KernelSU && git rev-list --count HEAD)
    KERNELSU_VERSION=$(($KSU_GIT_VERSION + 30000))
    msg "KernelSU Version: $KERNELSU_VERSION"
    sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"-$KERNEL_BRANCH-$KERNEL_NAME-xx\"/" $DEVICE_DEFCONFIG_FILE
fi
if [[ $KSU_ENABLED == "false" ]]; then
    echo "KernelSU Disabled"
    cd $KERNEL_DIR
    echo "CONFIG_KSU=n" >> $DEVICE_DEFCONFIG_FILE
    echo "CONFIG_KPROBES=n" >> $DEVICE_DEFCONFIG_FILE # just in case KSU is left on by default

    KERNELSU_VERSION="Disabled"
    sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"-$KERNEL_BRANCH-$KERNEL_NAME\"/" $DEVICE_DEFCONFIG_FILE
fi
